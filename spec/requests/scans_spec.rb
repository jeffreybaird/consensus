# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Scans", type: :request do
  describe "GET /" do
    context "when no scans have been saved" do
      it "responds ok" do
        get "/"

        expect(last_response).to be_ok
      end

      it "shows the empty state" do
        get "/"

        expect(last_response.body).to include('data-testid="empty-state"')
      end

      it "offers the new-scan form" do
        get "/"

        expect(last_response.body).to include('data-testid="new-scan-form"')
      end
    end

    context "when scans have been saved" do
      # A GA that no form placeholder or example text on the page shares, so
      # "the list shows it" cannot pass by accident.
      let!(:scan) { create(:scan, :labelled, ga_days: 199) }

      it "lists them" do
        get "/"

        expect(last_response.body).to include('data-testid="scan-list"')
        expect(last_response.body).to include(%(data-testid="scan-#{scan.id}"))
      end

      it "shows each scan's gestational age" do
        get "/"

        expect(last_response.body).to include(scan.ga_text)
      end

      it "drops the empty state" do
        get "/"

        expect(last_response.body).not_to include('data-testid="empty-state"')
      end
    end
  end

  describe "POST /scans" do
    let(:valid_params) do
      { "ga" => "32w0d", "bpd" => "81", "hc" => "296", "ac" => "279", "fl" => "61",
        "scanned_on" => "2026-08-10" }
    end

    context "with valid measurements" do
      it "redirects to the saved scan" do
        post "/scans", valid_params
        saved = Scan.order(:id).last

        expect(last_response.status).to eq(302)
        expect(saved).not_to be_nil
        expect(last_response.headers["Location"]).to end_with("/scans/#{saved&.id}")
      end

      it "persists the scan" do
        expect { post "/scans", valid_params }.to change(Scan, :count).by(1)
      end
    end

    context "with an unreadable gestational age" do
      it "responds 422" do
        post "/scans", valid_params.merge("ga" => "banana")

        expect(last_response.status).to eq(422)
      end

      it "renders the errors" do
        post "/scans", valid_params.merge("ga" => "banana")

        expect(last_response.body).to include('data-testid="form-errors"')
      end

      it "persists nothing" do
        expect { post "/scans", valid_params.merge("ga" => "banana") }
          .not_to change(Scan, :count)
      end
    end
  end

  describe "GET /scans/:id" do
    it "shows the scan" do
      scan = create(:scan, ga_days: 199)

      get "/scans/#{scan.id}"

      expect(last_response).to be_ok
      expect(last_response.body).to include(scan.ga_text)
    end

    it "responds 404 for a scan that does not exist" do
      get "/scans/999999"

      expect(last_response.status).to eq(404)
    end

    # Everything below is checked against the report the gem returns for the
    # same scan — no window, weight, percentile or citation is typed into
    # this spec. Anything asserted as visible was first read out of BIOMETRY.
    def rendered = Capybara.string(last_response.body)

    def growth_rows = rendered.all('[data-testid^="growth-row-"]')

    def report_rows(scan) = Scans::Report.call(scan).studies.flat_map(&:growth)

    def row_for(standard) = rendered.find(%([data-testid^="growth-row-#{standard}"]))

    def refused?(row) = row.all('[data-testid="refusal"]').any?

    # Grouping, ordinal suffixes and which way a half rounds are the view's
    # business; the value underneath them is the gem's. The digits are what
    # is asserted, not the typography around them.
    def shows_number(text, value)
      plain = text.delete(",")

      expect(plain).to match(/(?<!\d)#{value.round}(?!\d)|(?<!\d)#{value.floor}(?!\d)/)
    end

    # The unstratified standards have one row each, so each can be read on
    # its own without depending on the order the rows are rendered in.
    def unstratified(rows) = rows.reject { |row| row[:standard] == :nichd }

    context "with a complete scan" do
      let(:scan) { create(:scan) }
      let(:rows) { report_rows(scan) }

      before { get "/scans/#{scan.id}" }

      describe "the readout header" do
        it "shows the gestational age" do
          expect(rendered.find('[data-testid="scan-ga"]').text).to include(scan.ga_text)
        end

        it "shows the date of the scan" do
          expect(last_response.body).to include(scan.scanned_on.iso8601)
        end

        it "shows every measurement recorded, with its value in millimetres" do
          text = rendered.find('[data-testid="measurements"]').text

          Scan::MEASUREMENTS.each do |kind, column|
            expect(text).to include(kind.to_s.upcase)
            shows_number(text, scan.public_send(column))
          end
          expect(text).to match(/mm/)
        end

        it "records no measurement as absent" do
          expect(rendered.find('[data-testid="measurements"]').text).not_to match(/not recorded/i)
        end
      end

      describe "the growth table" do
        it "is on the page" do
          expect(rendered.all('[data-testid="growth-table"]').size).to eq(1)
        end

        it "renders one row per reading the gem returns" do
          expect(growth_rows.size).to eq(rows.size)
        end

        it "gives every row its own test id" do
          ids = growth_rows.map { |row| row[:"data-testid"] }

          expect(ids.uniq.size).to eq(ids.size)
        end

        it "renders a row for every standard" do
          rows.map { |row| row[:standard] }.uniq.each do |standard|
            expect(rendered.all(%([data-testid^="growth-row-#{standard}"]))).not_to be_empty
          end
        end

        it "renders one row per stratum for the stratified standard" do
          nichd = rows.select { |row| row[:standard] == :nichd }
          table = rendered.find('[data-testid="growth-table"]').text

          expect(rendered.all('[data-testid^="growth-row-nichd"]').size).to eq(nichd.size)
          nichd.each { |row| expect(table).to match(/#{row[:report].value!.source.stratum}/i) }
        end

        it "refuses nothing" do
          expect(growth_rows.select { |row| refused?(row) }).to be_empty
        end

        it "shows each reading's weight in grams" do
          unstratified(rows).each do |row|
            text = row_for(row[:standard]).text

            shows_number(text, row[:weight].value!.value)
            expect(text).to match(/\bg\b/)
          end
        end

        it "shows each reading's percentile" do
          unstratified(rows).each do |row|
            shows_number(row_for(row[:standard]).text, row[:report].value!.value)
          end
        end

        it "names what kind of standard each reading came from" do
          unstratified(rows).each do |row|
            expect(row_for(row[:standard]).text).to match(/#{row[:report].value!.source.type}/i)
          end
        end

        it "names the measurements each formula used" do
          unstratified(rows).each do |row|
            text = row_for(row[:standard]).text

            row[:weight].value!.inputs.each { |kind| expect(text).to include(kind.to_s.upcase) }
          end
        end
      end

      it "cites every reading exactly once in the sources" do
        text = rendered.find('[data-testid="sources"]').text

        rows.map { |row| row[:citation] }.uniq.each do |citation|
          expect(text.scan(citation).size).to eq(1)
        end
      end

      it "never labels the reading" do
        expect(last_response.body).not_to match(/\b(SGA|LGA|IUGR|FGR|macrosomia|abnormal)\b/i)
      end
    end

    context "with a scan whose measurements the standards cannot read" do
      let(:scan) { create(:scan, :partial) }
      let(:rows) { report_rows(scan) }

      before { get "/scans/#{scan.id}" }

      it "shows the measurements that were not recorded as absent" do
        text = rendered.find('[data-testid="measurements"]').text
        absent = Scan::MEASUREMENTS.count { |_, column| scan.public_send(column).nil? }

        expect(text.scan(/not recorded/i).size).to eq(absent)
      end

      it "still renders a row for every reading" do
        expect(growth_rows.size).to eq(rows.size)
      end

      it "renders the refusal where the numbers would have been" do
        expect(growth_rows.reject { |row| refused?(row) }).to be_empty
      end

      it "gives the reason in the same words the reason formatter does" do
        rows.each do |row|
          expect(row_for(row[:standard]).find('[data-testid="refusal"]').text)
            .to include(Scans::Reason.call(row[:report].failure))
        end
      end

      it "shows no failure tag" do
        expect(last_response.body).not_to match(/insufficient_data/)
      end

      it "never labels the reading" do
        expect(last_response.body).not_to match(/\b(SGA|LGA|IUGR|FGR|macrosomia|abnormal)\b/i)
      end
    end

    context "with a scan earlier than some standards cover" do
      let(:scan) { create(:scan, ga_days: 70) }
      let(:rows) { report_rows(scan) }

      before { get "/scans/#{scan.id}" }

      it "is a gestation some standards read and others refuse" do
        expect(rows.map { |row| row[:report].success? }).to include(true).and include(false)
      end

      it "still renders a row for every reading" do
        expect(growth_rows.size).to eq(rows.size)
      end

      it "reads the rows the gem read and refuses the rows it refused" do
        rows.each do |row|
          expect(refused?(row_for(row[:standard]))).to eq(row[:report].failure?)
        end
      end

      it "names the window each refusing standard covers" do
        rows.select { |row| row[:report].failure? }.each do |row|
          window = row[:report].failure.last[:valid_range]
          text = row_for(row[:standard]).find('[data-testid="refusal"]').text

          expect(text).to include(window.first.to_s).and include(window.last.to_s)
        end
      end

      it "still shows the readable rows' weights" do
        rows.select { |row| row[:report].success? }.each do |row|
          shows_number(row_for(row[:standard]).text, row[:weight].value!.value)
        end
      end
    end
  end

  # Every expectation below is checked against the chart series the gem returns
  # for the same scan — curve counts, citations, refusal sentences and known
  # issues are read out of BIOMETRY inside the example, never typed here.
  describe "chart panels" do
    def rendered = Capybara.string(last_response.body)

    def panel(standard) = rendered.find(%([data-testid="chart-#{standard}"]))

    def stratum_panel(standard, stratum)
      rendered.find(%([data-testid="chart-#{standard}-#{stratum}"]))
    end

    def curves(node) = node.all("polyline, path", visible: :all)

    def svgs(node) = node.all("svg", visible: :all)

    def points(node) = node.all('[data-testid="chart-point"]', visible: :all)

    def refusals(node) = node.all('[data-testid="chart-refusal"]', visible: :all)

    # A stratified standard asked without a stratum draws one chart per
    # stratum, each in its own sub-panel; every other standard draws one.
    def drawn_panels(standard, result)
      charts = charts_of(result)
      return [panel(standard)] if charts.one?

      charts.map { |chart| stratum_panel(standard, chart.chart[:stratum]) }
    end

    def each_drawn_chart(scan)
      BIOMETRY.charts.each_key do |standard|
        result = gem_chart(scan, standard)
        next if result.failure?

        drawn_panels(standard, result).zip(charts_of(result)) { |node, chart| yield(node, chart, standard) }
      end
    end

    def dispersion_detail
      BIOMETRY.catalog.growth_standards
              .find { |descriptor| descriptor.id == :hadlock_1991_equation }
              .known_issues
              .find { |issue| issue[:id].to_s.include?("dispersion") }
              .fetch(:detail)
    end

    def polyline_geometry(standard)
      curves(panel(standard)).map { |curve| curve[:points] }
    end

    describe "GET /scans/:id with a complete scan" do
      let(:scan) { create(:scan) }

      before { get "/scans/#{scan.id}" }

      it "renders the charts section once" do
        expect(rendered.all('[data-testid="charts"]').size).to eq(1)
      end

      it "renders one panel per chart the gem serves" do
        BIOMETRY.charts.each_key do |standard|
          expect(rendered.all(%([data-testid="chart-#{standard}"]), visible: :all).size).to eq(1)
        end
      end

      it "gives the stratified standard one panel per stratum it publishes" do
        charts = charts_of(gem_chart(scan, :nichd))

        expect(charts.size).to be > 1
        charts.each do |chart|
          expect(svgs(stratum_panel(:nichd, chart.chart[:stratum])).size).to eq(1)
        end
      end

      it "draws an image-role svg for every chart" do
        each_drawn_chart(scan) do |node, _chart, _standard|
          expect(svgs(node).map { |svg| svg[:role] }).to include("img")
        end
      end

      it "names the standard in every chart's accessible label" do
        each_drawn_chart(scan) do |node, _chart, standard|
          labels = svgs(node).map { |svg| svg[:"aria-label"].to_s }

          expect(labels).to all(match(/\S/))
          expect(labels).to all(include(Standards::Names.standard(standard)))
        end
      end

      it "draws one curve per centile the gem publishes for that chart" do
        each_drawn_chart(scan) do |node, chart, _standard|
          expect(curves(node).size).to eq(chart.series.size)
        end
      end

      it "marks the plotted point on every chart" do
        each_drawn_chart(scan) do |node, chart, _standard|
          expect(chart.point).not_to be_nil
          expect(points(node).size).to eq(1)
        end
      end

      it "marks the point with a circle" do
        each_drawn_chart(scan) do |node, _chart, _standard|
          expect(node.all('[data-testid="chart-point"] circle, circle[data-testid="chart-point"]',
                          visible: :all)).not_to be_empty
        end
      end

      it "captions every panel with the chart's citation" do
        each_drawn_chart(scan) do |node, chart, _standard|
          expect(node.text).to include(chart.source[:citation])
        end
      end

      it "refuses nothing" do
        section = rendered.find('[data-testid="charts"]')

        expect(section.all('[data-testid="chart-refusal"]', visible: :all)).to be_empty
      end

      it "discloses the contested dispersion in both Hadlock panels" do
        sentence = dispersion_detail.split(". ").first

        %i[hadlock_1991_equation hadlock_1991_table].each do |standard|
          disclosures = panel(standard).all("details", visible: :all)

          expect(disclosures).not_to be_empty
          expect(disclosures.map { |node| node.text(:all) }.join(" ")).to include(sentence)
        end
      end

      it "draws the two Hadlock readings as different curves" do
        expect(polyline_geometry(:hadlock_1991_equation))
          .not_to eq(polyline_geometry(:hadlock_1991_table))
      end

      it "never labels the reading" do
        expect(last_response.body).not_to match(/\b(SGA|LGA|IUGR|FGR|macrosomia|abnormal)\b/i)
      end
    end

    describe "GET /scans/:id with a scan whose measurements the formulas cannot read" do
      let(:scan) { create(:scan, :partial) }

      before { get "/scans/#{scan.id}" }

      it "still draws every standard's curves" do
        each_drawn_chart(scan) do |node, chart, _standard|
          expect(curves(node).size).to eq(chart.series.size)
        end
      end

      it "plots no point on the charts it draws" do
        drawn = 0

        each_drawn_chart(scan) do |node, _chart, _standard|
          drawn += 1
          expect(points(node)).to be_empty
        end
        expect(drawn).to eq(BIOMETRY.charts.keys.sum { |id| charts_of(gem_chart(scan, id)).size })
      end
    end

    describe "GET /scans/:id with a scan earlier than some standards cover" do
      let(:scan) { create(:scan, ga_days: 70) }

      before { get "/scans/#{scan.id}" }

      def refusing = BIOMETRY.charts.keys.select { |id| gem_chart(scan, id).failure? }

      def drawing = BIOMETRY.charts.keys.select { |id| gem_chart(scan, id).success? }

      it "is a gestation some charts draw and others refuse" do
        expect(refusing).not_to be_empty
        expect(drawing).not_to be_empty
      end

      it "keeps a panel for every standard" do
        BIOMETRY.charts.each_key do |standard|
          expect(rendered.all(%([data-testid="chart-#{standard}"]), visible: :all).size).to eq(1)
        end
      end

      it "gives the reason in the refusing standard's own panel" do
        refusing.each do |standard|
          expect(refusals(panel(standard)).map(&:text).join(" "))
            .to include(Scans::Reason.call(gem_chart(scan, standard).failure))
        end
      end

      it "draws no curves for a standard that refused" do
        refusing.each do |standard|
          expect(curves(panel(standard))).to be_empty
          expect(svgs(panel(standard))).to be_empty
        end
      end

      it "still draws the standards whose window covers it" do
        drawing.each do |standard|
          expect(refusals(panel(standard))).to be_empty
          expect(curves(panel(standard)).size).to eq(gem_chart(scan, standard).value!.series.size)
        end
      end

      it "shows no failure tag" do
        expect(rendered.find('[data-testid="charts"]').text).not_to match(/out_of_range/)
      end

      it "never labels the reading" do
        expect(last_response.body).not_to match(/\b(SGA|LGA|IUGR|FGR|macrosomia|abnormal)\b/i)
      end
    end

    describe "GET /scans/:id/charts/:standard" do
      let(:scan) { create(:scan) }

      it "responds ok for every chart the gem serves" do
        BIOMETRY.charts.each_key do |standard|
          get "/scans/#{scan.id}/charts/#{standard}"

          expect(last_response).to be_ok
        end
      end

      it "renders that standard's panel" do
        BIOMETRY.charts.each_key do |standard|
          get "/scans/#{scan.id}/charts/#{standard}"

          expect(rendered.all(%([data-testid="chart-#{standard}"]), visible: :all).size).to eq(1)
        end
      end

      it "draws the same curves the panel on the scan page draws" do
        BIOMETRY.charts.each_key do |standard|
          get "/scans/#{scan.id}/charts/#{standard}"
          result = gem_chart(scan, standard)

          drawn_panels(standard, result).zip(charts_of(result)) do |node, chart|
            expect(curves(node).size).to eq(chart.series.size)
          end
        end
      end

      it "cites the standard on its own page" do
        BIOMETRY.charts.each_key do |standard|
          get "/scans/#{scan.id}/charts/#{standard}"

          expect(last_response.body).to include(charts_of(gem_chart(scan, standard)).first.source[:citation])
        end
      end

      it "never labels the reading" do
        BIOMETRY.charts.each_key do |standard|
          get "/scans/#{scan.id}/charts/#{standard}"

          expect(last_response).to be_ok
          expect(last_response.body).not_to match(/\b(SGA|LGA|IUGR|FGR|macrosomia|abnormal)\b/i)
        end
      end

      it "responds 404 for a standard the registry does not serve" do
        served = BIOMETRY.charts.keys.first
        get "/scans/#{scan.id}/charts/#{served}"
        control = last_response.status

        get "/scans/#{scan.id}/charts/banana"

        expect(control).to eq(200)
        expect(last_response.status).to eq(404)
      end

      it "responds 404 for a scan that does not exist" do
        served = BIOMETRY.charts.keys.first
        get "/scans/#{scan.id}/charts/#{served}"
        control = last_response.status

        get "/scans/999999/charts/#{served}"

        expect(control).to eq(200)
        expect(last_response.status).to eq(404)
      end
    end
  end

  # A stored label is data, never markup. The label below is the only place in
  # the suite where a saved value could reach the browser as a tag, so both
  # pages that print it are checked — and checked to still render their own
  # structure, because a template escaped twice renders its markup as text.
  describe "a scan whose label contains markup" do
    let(:markup) { "<script>alert(1)</script><b>x" }
    let(:scan) { create(:scan, patient_ref: markup) }

    context "on the scan page" do
      before { get "/scans/#{scan.id}" }

      it "responds ok" do
        expect(last_response).to be_ok
      end

      it "renders the label as text, not as a tag" do
        expect(last_response.body).not_to include("<script>alert(1)")
        expect(last_response.body).not_to include("<b>x")
      end

      it "shows the label escaped" do
        expect(last_response.body).to include("&lt;script&gt;")
      end

      it "still renders the page's own structure" do
        expect(Capybara.string(last_response.body)
                       .all('[data-testid="growth-table"]', visible: :all).size).to eq(1)
      end

      it "still renders the partials' markup as markup" do
        rendered = Capybara.string(last_response.body)

        expect(rendered.all('[data-testid="charts"]', visible: :all).size).to eq(1)
        expect(rendered.all('[data-testid^="growth-row-"]', visible: :all)).not_to be_empty
      end
    end

    context "on the scan list" do
      before do
        scan
        get "/"
      end

      it "responds ok" do
        expect(last_response).to be_ok
      end

      it "renders the label as text, not as a tag" do
        expect(last_response.body).not_to include("<script>alert(1)")
        expect(last_response.body).not_to include("<b>x")
      end

      it "shows the label escaped" do
        expect(last_response.body).to include("&lt;script&gt;")
      end

      it "still renders the list" do
        expect(last_response.body).to include('data-testid="scan-list"')
        expect(last_response.body).to include(%(data-testid="scan-#{scan.id}"))
      end
    end
  end

  # Rack turns `bpd[]=1` into an Array. That is not a crash: a field that did
  # not arrive as text counts as unsupplied, and the request lands on the same
  # success or validation failure a blank field does.
  describe "POST /scans with array parameters" do
    context "when the measurements, sex and date arrive as arrays" do
      let(:params) do
        { "ga" => "32w0d", "bpd" => ["1"], "sex" => ["male"], "scanned_on" => ["x"] }
      end

      it "does not fail" do
        post "/scans", params

        expect(last_response.status).not_to eq(500)
      end

      it "saves the scan, treating the array fields as unsupplied" do
        post "/scans", params
        saved = Scan.order(:id).last

        expect(last_response.status).to eq(302)
        expect(last_response.headers["Location"]).to end_with("/scans/#{saved&.id}")
      end

      it "records nothing for the fields that did not arrive as text" do
        post "/scans", params
        saved = Scan.order(:id).last

        expect(saved.bpd_mm).to be_nil
        expect(saved.sex).to be_nil
        expect(saved.scanned_on).to eq(Date.today)
      end
    end

    context "when the gestational age arrives as an array" do
      let(:params) { { "ga" => ["32w0d"] } }

      it "does not fail" do
        post "/scans", params

        expect(last_response.status).not_to eq(500)
      end

      it "responds 422" do
        post "/scans", params

        expect(last_response.status).to eq(422)
      end

      it "renders the errors" do
        post "/scans", params

        expect(last_response.body).to include('data-testid="form-errors"')
      end

      it "says how a gestational age reads, in the service's own words" do
        message = Scans::Create.call(params).failure.last[:ga]

        post "/scans", params

        expect(message).not_to be_nil
        expect(last_response.body).to include(message)
      end

      it "persists nothing" do
        expect { post "/scans", params }.not_to change(Scan, :count)
      end
    end
  end

  # A 404 is a page a person landed on, not an empty response: it says so and
  # offers the way back.
  describe "a request for a scan that cannot be found" do
    def bad_ids = ["999999", "abc", "1.0"]

    before { create(:scan) }

    it "responds 404 for an unknown id, a non-numeric id and a decimal id" do
      bad_ids.each do |id|
        get "/scans/#{id}"

        expect(last_response.status).to eq(404)
      end
    end

    it "answers with a page rather than an empty body" do
      bad_ids.each do |id|
        get "/scans/#{id}"

        expect(last_response.body).not_to be_empty
        expect(last_response.body).to match(/not found/i)
      end
    end

    it "offers the way back to the scans" do
      bad_ids.each do |id|
        get "/scans/#{id}"

        expect(Capybara.string(last_response.body).all('a[href="/"]', visible: :all))
          .not_to be_empty
      end
    end

    it "answers an unknown path the same way" do
      get "/nothing-here"

      expect(last_response.status).to eq(404)
      expect(last_response.body).to match(/not found/i)
    end

    it "still serves a scan that does exist" do
      scan = Scan.order(:id).last

      get "/scans/#{scan.id}"

      expect(last_response).to be_ok
    end

    # One scan has one address. A padded, hexadecimal or space-wrapped spelling
    # of the same number is a different string and is not that address — each
    # of these would otherwise be coerced to an existing id.
    context "when the id is a non-canonical spelling of a real id" do
      # "01" and " 1 " both coerce to 1; "0x10" would coerce to 16.
      def non_canonical_ids = ["01", "0x10", "%201%20"]

      it "serves the canonical spelling" do
        get "/scans/#{Scan.order(:id).last.id}"

        expect(last_response).to be_ok
      end

      it "responds 404 for every other spelling" do
        non_canonical_ids.each do |id|
          get "/scans/#{id}"

          expect(last_response.status).to eq(404)
        end
      end

      it "answers each with the not-found page rather than an empty body" do
        non_canonical_ids.each do |id|
          get "/scans/#{id}"

          expect(last_response.body).not_to be_empty
          expect(last_response.body).to match(/not found/i)
          expect(Capybara.string(last_response.body).all('a[href="/"]', visible: :all))
            .not_to be_empty
        end
      end

      it "renders no scan of its own" do
        non_canonical_ids.each do |id|
          get "/scans/#{id}"

          expect(last_response.body).not_to include('data-testid="growth-table"')
        end
      end
    end
  end
end
