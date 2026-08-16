# frozen_string_literal: true

require "sinatra/base"
require "securerandom"

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

  get "/scans/:id" do
    @scan = Scan[params[:id]] or halt 404
    erb :"scans/show"
  end
end
