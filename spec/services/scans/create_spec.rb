# frozen_string_literal: true

require "spec_helper"

RSpec.describe Scans::Create do
  # The form posts strings; the service is what turns them into a Scan.
  let(:valid_params) do
    { "ga" => "32w0d",
      "bpd" => "81", "hc" => "296", "ac" => "279", "fl" => "61",
      "sex" => "female", "stratum" => "white",
      "patient_ref" => "demo-1", "scanned_on" => "2026-08-10" }
  end

  # Failure messages are read by field, tolerant of one message or many.
  def messages_for(result, pattern)
    result.failure.last
          .select { |field, _| field.to_s.match?(pattern) }
          .values.flatten.join(" ")
  end

  def error_fields(result) = result.failure.last.keys.map(&:to_s)

  # The stratification options are the gem's, never a list typed in a spec.
  def catalog_values(id)
    BIOMETRY.catalog.growth_standards
            .find { |standard| standard.id == id }
            .stratification[:values].map(&:to_s)
  end

  describe ".call" do
    context "with a complete scan" do
      it "returns Success with the saved scan" do
        result = described_class.call(valid_params)

        expect(result).to be_success
        expect(result.value!).to be_a(Scan)
        expect(result.value!.id).not_to be_nil
      end

      it "stores the gestational age as days" do
        expect(described_class.call(valid_params).value!.ga_days).to eq(224)
      end

      it "stores the measurements as floating-point millimetres" do
        scan = described_class.call(valid_params).value!

        expect([scan.bpd_mm, scan.hc_mm, scan.ac_mm, scan.fl_mm])
          .to eq([81.0, 296.0, 279.0, 61.0])
        expect(scan.bpd_mm).to be_a(Float)
      end

      it "stores the scan date, chart options and label as entered" do
        scan = described_class.call(valid_params).value!

        expect(scan.scanned_on).to eq(Date.new(2026, 8, 10))
        expect(scan.sex.to_s).to eq("female")
        expect(scan.stratum.to_s).to eq("white")
        expect(scan.patient_ref).to eq("demo-1")
      end

      it "persists exactly one scan" do
        described_class.call(valid_params)

        expect(Scan.count).to eq(1)
      end
    end

    describe "gestational age parsing" do
      { "0w0d" => 0, "46w6d" => 328, "32w0d" => 224, "32w" => 224 }.each do |text, days|
        it "reads #{text.inspect} as #{days} days" do
          result = described_class.call(valid_params.merge("ga" => text))

          expect(result).to be_success
          expect(result.value!.ga_days).to eq(days)
        end
      end

      ["32w7d", "47w0d", "banana", ""].each do |text|
        context "when the gestational age reads #{text.inspect}" do
          let(:result) { described_class.call(valid_params.merge("ga" => text)) }

          it "returns a tagged validation Failure naming the expected format" do
            expect(result).to be_failure
            expect(result.failure.first).to eq(:validation)
            expect(messages_for(result, /ga/)).to match(/\d+w\d+d/)
          end

          it "persists nothing" do
            result

            expect(Scan.count).to eq(0)
          end
        end
      end
    end

    describe "the scan date" do
      it "defaults to today when left blank" do
        result = described_class.call(valid_params.merge("scanned_on" => ""))

        expect(result).to be_success
        expect(result.value!.scanned_on).to eq(Date.today)
      end

      it "fails naming the ISO date format when it is malformed" do
        result = described_class.call(valid_params.merge("scanned_on" => "10-08-2026"))

        expect(result).to be_failure
        expect(result.failure.first).to eq(:validation)
        expect(messages_for(result, /scanned_on|date/)).to match(/ISO/i)
        expect(Scan.count).to eq(0)
      end
    end

    describe "the measurements" do
      it "leaves a blank measurement null rather than zero" do
        result = described_class.call(valid_params.merge("hc" => "", "fl" => "   "))

        expect(result).to be_success
        expect(result.value!.hc_mm).to be_nil
        expect(result.value!.fl_mm).to be_nil
      end

      it "saves a scan with no measurements at all" do
        params = valid_params.merge("bpd" => "", "hc" => "", "ac" => "", "fl" => "")

        result = described_class.call(params)

        expect(result).to be_success
        expect(Scan.count).to eq(1)
      end

      it "fails on the offending field when a measurement is not a number" do
        result = described_class.call(valid_params.merge("bpd" => "abc"))

        expect(result).to be_failure
        expect(result.failure.first).to eq(:validation)
        expect(error_fields(result)).to include(a_string_matching(/bpd/))
        expect(Scan.count).to eq(0)
      end
    end

    describe "the chart options" do
      it "accepts every sex the WHO standard stratifies by, apart from combined" do
        (catalog_values(:who) - ["combined"]).each do |sex|
          DB.transaction(rollback: :always, savepoint: true) do
            expect(described_class.call(valid_params.merge("sex" => sex))).to be_success
          end
        end
      end

      it "accepts every stratum the NICHD standard stratifies by" do
        catalog_values(:nichd).each do |stratum|
          DB.transaction(rollback: :always, savepoint: true) do
            expect(described_class.call(valid_params.merge("stratum" => stratum))).to be_success
          end
        end
      end

      it "treats a blank sex and stratum as unspecified" do
        result = described_class.call(valid_params.merge("sex" => "", "stratum" => ""))

        expect(result).to be_success
        expect(result.value!.sex).to be_nil
        expect(result.value!.stratum).to be_nil
      end

      it "rejects an unknown sex, naming the sexes WHO offers" do
        result = described_class.call(valid_params.merge("sex" => "purple"))
        message = messages_for(result, /sex/)

        expect(result).to be_failure
        expect(result.failure.first).to eq(:validation)
        (catalog_values(:who) - ["combined"]).each { |sex| expect(message).to include(sex) }
        expect(message).not_to include("combined")
        expect(Scan.count).to eq(0)
      end

      it "rejects an unknown stratum, naming the strata NICHD offers" do
        result = described_class.call(valid_params.merge("stratum" => "martian"))
        message = messages_for(result, /stratum/)

        expect(result).to be_failure
        expect(result.failure.first).to eq(:validation)
        catalog_values(:nichd).each { |stratum| expect(message).to include(stratum) }
        expect(Scan.count).to eq(0)
      end
    end
  end
end
