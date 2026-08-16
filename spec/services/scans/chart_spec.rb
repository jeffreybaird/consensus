# frozen_string_literal: true

require "spec_helper"

RSpec.describe Scans::Chart do
  # `gem_chart`, `paired_weight` and friends come from BiometryChartHelpers:
  # the gem asked directly, from the scan's stored columns and the catalog's
  # published formula pairing. Nothing clinical is typed in this spec; every
  # expected number, centile and citation comes back out of BIOMETRY.
  def charts(result) = charts_of(result)

  def payloads(result) = payloads_of(result)

  describe ".call" do
    context "with a complete scan" do
      let(:scan) { create(:scan) }

      it "returns a Success for every chart the gem serves" do
        results = BIOMETRY.charts.keys.map { |id| described_class.call(scan, standard: id) }

        expect(results).to all(be_success)
      end

      it "draws the same centile curves the gem draws" do
        BIOMETRY.charts.each_key do |id|
          expect(payloads(described_class.call(scan, standard: id)).map { |chart| chart[:series] })
            .to eq(payloads(gem_chart(scan, id)).map { |chart| chart[:series] })
        end
      end

      it "describes the same chart, from the same source" do
        BIOMETRY.charts.each_key do |id|
          mine = payloads(described_class.call(scan, standard: id))
          theirs = payloads(gem_chart(scan, id))

          expect(mine.map { |chart| chart[:chart] }).to eq(theirs.map { |chart| chart[:chart] })
          expect(mine.map { |chart| chart[:source] }).to eq(theirs.map { |chart| chart[:source] })
        end
      end

      it "plots a point on every chart" do
        BIOMETRY.charts.each_key do |id|
          expect(payloads(described_class.call(scan, standard: id)).map { |chart| chart[:point] })
            .to all(be_a(Hash))
        end
      end

      it "plots the same point the gem plots for that chart's paired formula" do
        BIOMETRY.charts.each_key do |id|
          expect(payloads(described_class.call(scan, standard: id)).map { |chart| chart[:point] })
            .to eq(payloads(gem_chart(scan, id)).map { |chart| chart[:point] })
        end
      end

      it "reads a point whose percentile differs between the two Hadlock readings" do
        percentile = lambda do |id|
          described_class.call(scan, standard: id).value!.point[:percentile][:value]
        end

        expect(percentile.call(:hadlock_1991_equation))
          .not_to eq(percentile.call(:hadlock_1991_table))
      end

      it "carries the standard's known issues through untouched" do
        BIOMETRY.charts.each_key do |id|
          expect(charts(described_class.call(scan, standard: id)).map(&:known_issues))
            .to eq(charts(gem_chart(scan, id)).map(&:known_issues))
        end
      end
    end

    context "when the scan names no stratum" do
      let(:scan) { create(:scan, stratum: nil) }

      it "returns one chart per stratum the stratified standard publishes" do
        result = described_class.call(scan, standard: :nichd)

        expect(result.value!).to be_an(Array)
        expect(charts(result).map { |chart| chart.chart[:stratum] })
          .to eq(charts(gem_chart(scan, :nichd)).map { |chart| chart.chart[:stratum] })
      end

      it "returns a single chart for an unstratified standard" do
        expect(described_class.call(scan, standard: :who).value!).to be_a(Biometry::ChartSeries)
      end
    end

    context "when the scan names a stratum" do
      let(:scan) { create(:scan, stratum: Scans::Options.strata.first.to_s) }

      it "reads only that stratum's chart" do
        chart = described_class.call(scan, standard: :nichd).value!

        expect(chart).to be_a(Biometry::ChartSeries)
        expect(chart.chart[:stratum]).to eq(Scans::Options.strata.first)
      end
    end

    context "when the scan names a sex" do
      let(:scan) { create(:scan, sex: "female") }

      it "reads the sexed chart rather than the combined one" do
        chart = described_class.call(scan, standard: :who).value!

        expect(chart.chart[:stratum]).to eq(:female)
      end

      it "matches the gem asked the same way" do
        expect(described_class.call(scan, standard: :who).value!.to_h)
          .to eq(gem_chart(scan, :who).value!.to_h)
      end

      it "draws different curves than the same scan read without a sex" do
        unsexed = BIOMETRY.chart_series(standard: :who, sex: nil, stratum: nil)

        expect(described_class.call(scan, standard: :who).value!.to_h[:series])
          .not_to eq(unsexed.value!.to_h[:series])
      end
    end

    context "with a scan whose measurements the paired formulas cannot read" do
      let(:scan) { create(:scan, :partial) }

      it "has no readable weight to plot" do
        expect(BIOMETRY.charts.keys.map { |id| paired_weight(scan, id) }).to all(be_nil)
      end

      it "still draws the curves for every standard" do
        results = BIOMETRY.charts.keys.map { |id| described_class.call(scan, standard: id) }

        expect(results).to all(be_success)
        expect(results.flat_map { |result| charts(result).map { |chart| chart.series.length } })
          .to all(be_positive)
      end

      it "draws them without a point rather than refusing the chart" do
        BIOMETRY.charts.each_key do |id|
          expect(payloads(described_class.call(scan, standard: id)).map { |chart| chart[:point] })
            .to all(be_nil)
        end
      end

      it "draws the same curves as the gem asked for without a point" do
        BIOMETRY.charts.each_key do |id|
          expect(payloads(described_class.call(scan, standard: id)))
            .to eq(payloads(gem_chart(scan, id, with_point: false)))
        end
      end
    end

    context "with a readable scan earlier than some standards cover" do
      let(:scan) { create(:scan, ga_days: 70) }

      it "is a gestation whose weight reads but which some charts refuse" do
        expect(BIOMETRY.charts.keys.map { |id| paired_weight(scan, id) }).to all(be_truthy)
        expect(BIOMETRY.charts.keys.map { |id| described_class.call(scan, standard: id).success? })
          .to include(true).and include(false)
      end

      it "returns the gem's refusal untouched for the standards that refuse" do
        BIOMETRY.charts.each_key do |id|
          expect(described_class.call(scan, standard: id).failure?)
            .to eq(gem_chart(scan, id).failure?)
        end
      end

      it "carries the refusing standard's own window in the failure" do
        refusals = BIOMETRY.charts.keys
                           .map { |id| described_class.call(scan, standard: id) }
                           .select(&:failure?)
                           .map(&:failure)

        expect(refusals).not_to be_empty
        expect(refusals).to eq(BIOMETRY.charts.keys.map { |id| gem_chart(scan, id) }
                                       .select(&:failure?).map(&:failure))
      end

      it "still draws the charts whose window covers it" do
        readable = BIOMETRY.charts.keys
                           .map { |id| described_class.call(scan, standard: id) }
                           .select(&:success?)

        expect(readable).not_to be_empty
        expect(readable.flat_map { |result| payloads(result).map { |chart| chart[:point] } })
          .to all(be_a(Hash))
      end
    end

    context "with a chart id the registry does not serve" do
      let(:scan) { create(:scan) }

      it "returns the gem's refusal rather than raising" do
        result = described_class.call(scan, standard: :banana)

        expect(result).to be_failure
        expect(result.failure).to eq(BIOMETRY.chart_series(standard: :banana).failure)
      end
    end
  end
end
