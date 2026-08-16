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
end
