# frozen_string_literal: true

module Scans
  # One saved scan + one chart id → the gem's chart-series payload, plotted
  # with the estimate that chart's own formula produces. The gem's Result is
  # returned untouched: a refusal is content the panel renders, not an error.
  #
  # When the paired weight itself refused (missing measurements), the curves
  # are still asked for, without a point — a chart with no point beside a
  # stated reason reads honestly; a missing chart reads as never consulted.
  class Chart
    def self.call(...) = new.call(...)

    def call(scan, standard:)
      BIOMETRY.chart_series(
        standard: standard,
        sex: scan.sex_sym,
        stratum: scan.stratum_sym,
        point: point_for(scan, standard)
      )
    end

    private

    def point_for(scan, standard)
      entry = BIOMETRY.charts[standard]
      return nil unless entry

      weight = BIOMETRY.weights(scan.to_biometry_scan).value![entry[:formula]]
      return nil unless weight&.success?

      { estimate: weight.value!, ga: scan.ga }
    end
  end
end
