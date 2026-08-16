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
  end
end
