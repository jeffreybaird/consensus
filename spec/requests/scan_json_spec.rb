# frozen_string_literal: true

require "spec_helper"

# The machine-readable report. Nothing clinical is typed here: the body is
# compared against the document the gem builds for the same saved scan, so a
# route that dropped a study, a refusal or a citation shows up as a difference
# rather than as a tautology. Only the envelope around that document — the
# saved scan this reading belongs to — is pinned literally, because it is this
# app's contract, not the gem's.
RSpec.describe "Scan report as JSON", type: :request do
  def body = JSON.parse(last_response.body)

  # The gem's own answer for this scan, round-tripped through JSON so symbols,
  # dates and floats are compared the way a consumer receives them.
  def gem_document(scan)
    JSON.parse(
      JSON.generate(Biometry::Services::Report::Document.new.call(**Scans::Report.call(scan).to_h))
    )
  end

  describe "GET /scans/:id.json" do
    context "with a complete scan" do
      let(:scan) do
        create(:scan, :labelled,
               sex: Scans::Options.sexes.first.to_s,
               stratum: Scans::Options.strata.first.to_s)
      end

      before { get "/scans/#{scan.id}.json" }

      it "responds ok" do
        expect(last_response).to be_ok
      end

      it "serves it as JSON" do
        expect(last_response.headers["Content-Type"]).to include("application/json")
      end

      it "parses" do
        expect { body }.not_to raise_error
      end

      it "carries the saved scan and its report, and nothing else" do
        expect(body.keys).to contain_exactly("scan", "report")
      end

      it "names the scan the reading was computed from" do
        expect(body["scan"]).to eq(
          "id" => scan.id,
          "ga" => scan.ga_text,
          "scanned_on" => scan.scanned_on.iso8601,
          "patient_ref" => scan.patient_ref,
          "sex" => scan.sex,
          "stratum" => scan.stratum
        )
      end

      it "is the gem's report document, unaltered" do
        expect(body["report"]).to eq(gem_document(scan))
      end

      it "cites every source the gem cites" do
        expect(body["report"]["sources"]).to eq(gem_document(scan)["sources"])
        expect(body["report"]["sources"]).not_to be_empty
      end

      it "never labels the reading" do
        expect(last_response.body).not_to match(/\b(SGA|LGA|IUGR|FGR|macrosomia|abnormal)\b/i)
      end
    end

    context "with a scan carrying no patient reference, sex or stratum" do
      let(:scan) { create(:scan) }

      before { get "/scans/#{scan.id}.json" }

      it "responds ok" do
        expect(last_response).to be_ok
      end

      it "reports the absent fields as null rather than omitting them" do
        expect(body["scan"].keys)
          .to include("patient_ref", "sex", "stratum")
        expect(body["scan"].values_at("patient_ref", "sex", "stratum")).to all(be_nil)
      end

      it "is the gem's report document, unaltered" do
        expect(body["report"]).to eq(gem_document(scan))
      end
    end

    context "with a scan whose measurements the formulas cannot read" do
      let(:scan) { create(:scan, :partial) }

      before { get "/scans/#{scan.id}.json" }

      it "responds ok" do
        expect(last_response).to be_ok
      end

      it "carries the refusals the gem carries, rather than dropping the rows" do
        expect(body["report"]).to eq(gem_document(scan))
      end

      it "still reports a row for every reading the gem reports" do
        rows = body["report"]["studies"].flat_map { |study| study["growth"] }

        expect(rows.size).to eq(Scans::Report.call(scan).studies.flat_map(&:growth).size)
      end

      it "never labels the reading" do
        expect(last_response.body).not_to match(/\b(SGA|LGA|IUGR|FGR|macrosomia|abnormal)\b/i)
      end
    end

    context "with a scan earlier than some standards cover" do
      let(:scan) { create(:scan, ga_days: 70) }

      before { get "/scans/#{scan.id}.json" }

      it "is a gestation some standards read and others refuse" do
        results = Scans::Report.call(scan).studies.flat_map(&:growth).map { |row| row[:report].success? }

        expect(results).to include(true).and include(false)
      end

      it "is the gem's report document, unaltered" do
        expect(body["report"]).to eq(gem_document(scan))
      end
    end

    context "when the scan does not exist" do
      it "responds 404" do
        get "/scans/999999.json"

        expect(last_response.status).to eq(404)
      end
    end
  end
end
