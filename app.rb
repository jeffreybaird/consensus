# frozen_string_literal: true

require "sinatra/base"
require "securerandom"
require "json"

# The application. Routes stay thin: parse params, call a service object, render.
# Business rules and SQL live in app/services and app/models — never here.
class App < Sinatra::Base
  configure do
    set :root, __dir__
    set :erb, escape_html: true
    set :sessions, secret: ENV.fetch("SECRET_KEY_BASE") { SecureRandom.hex(64) }
    enable :logging
    set :show_exceptions, false if ENV["RACK_ENV"] == "production"
  end

  # Current is the request-scoped data boundary (NOT authorization). Reset it
  # around every request so nothing leaks between them.
  before do
    Current.reset!
    Current.request_id = env["HTTP_X_REQUEST_ID"] || SecureRandom.uuid
  end
  after { Current.reset! }

  # Liveness/readiness: 200 once the process can reach the DB.
  get "/up" do
    DB.test_connection
    content_type :json
    '{"status":"ok"}'
  end

  PAGE_SIZE = 25

  # The form's option lists come from the gem's catalog via Scans::Options —
  # the same source the create service validates against.
  def scan_index_locals
    @scans = Scan.recent.limit(PAGE_SIZE).all
    @sex_options = Scans::Options.sexes
    @stratum_options = Scans::Options.strata
  end

  get "/" do
    scan_index_locals
    erb :"scans/index"
  end

  post "/scans" do
    result = Scans::Create.call(params)
    if result.success?
      redirect "/scans/#{result.value!.id}"
    else
      @errors = result.failure.last
      scan_index_locals
      status 422
      erb :"scans/index"
    end
  end

  # The report as data: the same document the gem's CLI prints as --json,
  # wrapped in an envelope naming the saved scan it was computed from.
  get "/scans/:id.json" do
    scan = Scan[params[:id]] or halt 404
    content_type :json
    document = Biometry::Services::Report::Document.new.call(**Scans::Report.call(scan).to_h)
    JSON.generate(
      scan: { id: scan.id, ga: scan.ga_text, scanned_on: scan.scanned_on.iso8601,
              patient_ref: scan.patient_ref, sex: scan.sex, stratum: scan.stratum },
      report: document
    )
  end

  get "/standards" do
    @catalog = BIOMETRY.catalog
    erb :"standards/index"
  end

  get "/scans/:id" do
    @scan = Scan[params[:id]] or halt 404
    @report = Scans::Report.call(@scan)
    @charts = BIOMETRY.charts.keys.to_h { |id| [id, Scans::Chart.call(@scan, standard: id)] }
    erb :"scans/show"
  end

  get "/scans/:id/charts/:standard" do
    @scan = Scan[params[:id]] or halt 404
    @standard = params[:standard].to_sym
    halt 404 unless BIOMETRY.charts.key?(@standard)
    @result = Scans::Chart.call(@scan, standard: @standard)
    erb :"scans/chart"
  end

  helpers do
    # Display helpers only — no clinical decision lives here.
    def ordinal(number)
      value = number.round
      suffix = if (11..13).cover?(value % 100) then "th"
               else { 1 => "st", 2 => "nd", 3 => "rd" }.fetch(value % 10, "th")
               end
      "#{value}#{suffix}"
    end

    def grams(value) = value.round.to_s.gsub(/(\d)(?=(\d{3})+\z)/, '\1,')

    def standard_name(symbol) = Standards::Names.standard(symbol)

    # ---- SVG chart geometry: pure presentation arithmetic, no clinical value.

    CHART_W = 640
    CHART_H = 400
    CHART_MARGIN = { left: 48, right: 56, top: 16, bottom: 36 }.freeze

    def chart_view(chart)
      from, to = chart.chart[:valid_ga_weeks]
      top = (chart_max_grams(chart) / 500.0).ceil * 500
      plot_w = CHART_W - CHART_MARGIN[:left] - CHART_MARGIN[:right]
      plot_h = CHART_H - CHART_MARGIN[:top] - CHART_MARGIN[:bottom]
      { from: from, to: to, y_top: top,
        x: ->(ga) { (CHART_MARGIN[:left] + (((ga - from).to_f / (to - from)) * plot_w)).round(1) },
        y: ->(g) { (CHART_H - CHART_MARGIN[:bottom] - ((g.to_f / top) * plot_h)).round(1) } }
    end

    def chart_max_grams(chart)
      curve_max = chart.series.flat_map { |s| s.points.map { |p| p[:grams] } }.max
      [curve_max, chart.point&.dig(:efw_g)].compact.max
    end

    def polyline_points(series, view)
      series.points.map { |p| "#{view[:x].call(p[:ga_weeks])},#{view[:y].call(p[:grams])}" }
            .join(" ")
    end

    # Curve order → the ordinal centile tokens, highest centile lightest,
    # symmetric reuse when a standard publishes more than five columns.
    def centile_class(chart, series)
      ordered = chart.series.map(&:centile).sort.reverse
      index = ordered.index(series.centile)
      step = ordered.length < 2 ? 3 : 1 + ((index * 4.0) / (ordered.length - 1)).round
      "centile-#{step}"
    end

    def chart_label(chart)
      block = chart.chart
      label = "#{Standards::Names.standard(block[:standard])} growth chart, " \
              "centiles #{chart.series.map(&:centile).join(', ')}, " \
              "#{block[:valid_ga_weeks].join('–')} weeks"
      point = chart.point
      return label unless point

      "#{label}; this scan: #{grams(point[:efw_g])} g, " \
        "#{ordinal(point[:percentile][:value])} percentile at #{point[:ga_weeks]} weeks"
    end

    def ga_axis_label(chart)
      case chart.chart[:ga_units]
      when :exact_weeks then "weeks (exact)"
      when :completed_weeks then "completed weeks"
      else "weeks as published"
      end
    end
  end
end
