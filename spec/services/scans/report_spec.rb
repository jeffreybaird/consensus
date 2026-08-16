# frozen_string_literal: true

require "spec_helper"

RSpec.describe Scans::Report do
  # The gem's own answer, composed here from the scan's stored values rather
  # than from the model's converter — so a service that drops a measurement,
  # a date or a chart option shows up as a difference rather than as a
  # tautology. Nothing clinical is typed in this spec; every expected number
  # comes back out of BIOMETRY.
  def gem_report(scan, sex: scan.sex&.to_sym, stratum: scan.stratum&.to_sym)
    measurements = { bpd: scan.bpd_mm, hc: scan.hc_mm, ac: scan.ac_mm, fl: scan.fl_mm }
                   .filter_map { |kind, mm| Biometry::Measurement.new(kind: kind, mm: mm) if mm }
    BIOMETRY.report(
      scans: [Biometry::Scan.new(date: scan.scanned_on, measurements: measurements)],
      ga: Biometry::GestationalAge.new(days: scan.ga_days),
      at: scan.scanned_on,
      sex: sex,
      stratum: stratum
    )
  end

  def rows(report) = report.studies.flat_map(&:growth)

  def weights(report) = rows(report).map { |row| row[:weight].value_or(nil)&.value }

  def percentiles(report) = rows(report).map { |row| row[:report].value_or(nil)&.value }

  describe ".call" do
    context "with a complete scan" do
      let(:scan) { create(:scan) }
      let(:result) { described_class.call(scan) }
      let(:expected) { gem_report(scan) }

      it "returns the gem's report value" do
        expect(result).to be_a(Biometry::Report)
      end

      it "reads it at the scan's gestational age" do
        expect(result.ga.days).to eq(scan.ga_days)
      end

      it "reads the same growth standards, in the same order" do
        expect(rows(result).map { |row| row[:standard] })
          .to eq(rows(expected).map { |row| row[:standard] })
      end

      it "agrees row for row on which readings are readable" do
        expect(rows(result).map { |row| row[:report].success? })
          .to eq(rows(expected).map { |row| row[:report].success? })
      end

      it "carries the same estimated weights" do
        expect(weights(result)).to eq(weights(expected))
      end

      it "carries the same percentiles" do
        expect(percentiles(result)).to eq(percentiles(expected))
      end

      it "cites every row" do
        expect(rows(result)).to all(include(citation: a_string_matching(/\S/)))
      end

      it "reads a row for every standard the gem serves" do
        expect(rows(result).map { |row| row[:standard] }.uniq)
          .to match_array(BIOMETRY.catalog.growth_standards.map(&:id))
      end
    end

    context "when no dating inputs were collected" do
      let(:scan) { create(:scan) }

      # This app never asks for an LMP or a transfer date, so every dating
      # derivation refuses. That is the expected state, not a bug.
      it "returns a refusal for every dating derivation" do
        result = described_class.call(scan)

        expect(result.dating.values).to all(be_failure)
      end

      it "still has something to report from the growth rows" do
        expect(described_class.call(scan)).to be_reportable
      end
    end

    context "when the scan names a sex" do
      let(:scan) { create(:scan, sex: "female") }

      it "reads the sexed chart rather than the combined one" do
        who = rows(described_class.call(scan)).find { |row| row[:standard] == :who }

        expect(who[:report].value!.source.stratum).to eq(:female)
      end

      it "matches the gem asked the same way" do
        expect(percentiles(described_class.call(scan))).to eq(percentiles(gem_report(scan)))
      end

      it "differs from the same scan read without a sex" do
        unsexed = gem_report(scan, sex: nil)
        who_of = ->(report) { rows(report).find { |row| row[:standard] == :who } }

        expect(who_of[described_class.call(scan)][:report].value!.value)
          .not_to eq(who_of[unsexed][:report].value!.value)
      end
    end

    context "when the scan names a stratum" do
      let(:scan) { create(:scan, stratum: Scans::Options.strata.first.to_s) }

      it "reads only that stratum's chart" do
        nichd = rows(described_class.call(scan)).select { |row| row[:standard] == :nichd }

        expect(nichd.size).to eq(1)
        expect(nichd.first[:report].value!.source.stratum).to eq(Scans::Options.strata.first)
      end
    end

    context "when the scan names no stratum" do
      let(:scan) { create(:scan, stratum: nil) }

      it "reads every stratum the standard publishes" do
        nichd = rows(described_class.call(scan)).select { |row| row[:standard] == :nichd }

        expect(nichd.map { |row| row[:report].value!.source.stratum })
          .to match_array(Scans::Options.strata)
      end
    end

    context "with a scan the standards cannot read" do
      let(:scan) { create(:scan, :partial) }
      let(:result) { described_class.call(scan) }

      it "still returns a row for every standard" do
        expect(rows(result).map { |row| row[:standard] }.uniq)
          .to match_array(BIOMETRY.catalog.growth_standards.map(&:id))
      end

      it "returns a refusal on every row rather than dropping it" do
        expect(rows(result).map { |row| row[:report] }).to all(be_failure)
      end

      it "agrees with the gem about every refusal" do
        expect(rows(result).map { |row| row[:report].failure })
          .to eq(rows(gem_report(scan)).map { |row| row[:report].failure })
      end
    end

    context "with a scan earlier than some standards cover" do
      let(:scan) { create(:scan, ga_days: 70) }
      let(:result) { described_class.call(scan) }

      it "agrees with the gem about which standards can read it" do
        expect(rows(result).map { |row| [row[:standard], row[:report].success?] })
          .to eq(rows(gem_report(scan)).map { |row| [row[:standard], row[:report].success?] })
      end

      it "refuses some rows and reads others" do
        readable = rows(result).map { |row| row[:report].success? }

        expect(readable).to include(true).and include(false)
      end
    end
  end
end
