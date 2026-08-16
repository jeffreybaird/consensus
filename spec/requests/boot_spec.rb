# frozen_string_literal: true

require "spec_helper"

# The gem boundary, asserted once: BIOMETRY is the whole door to clinical
# computation, loaded at boot and shared — frozen — by every request.
RSpec.describe "Boot", type: :request do
  describe "BIOMETRY" do
    it "is a Biometry::Context" do
      expect(BIOMETRY).to be_a(Biometry::Context)
    end

    it "is frozen, so every request and thread may share it" do
      expect(BIOMETRY).to be_frozen
    end

    it "offers a chart for every growth standard the catalog names" do
      expect(BIOMETRY.charts.keys)
        .to match_array(BIOMETRY.catalog.growth_standards.map(&:id))
    end
  end

  describe "GET /up" do
    it "reports ok once the process can reach the database" do
      get "/up"

      expect(last_response).to be_ok
    end
  end
end
