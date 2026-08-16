# frozen_string_literal: true

module Scans
  # Every chart panel for one scan: the scan is weighed once and each chart in
  # the registry is drawn with the estimate its own formula produced. Panels
  # follow the order given (the report's row order), falling back to the
  # registry's; a chart the gem refuses keeps its entry as a Failure.
  class Charts
    def self.call(...) = new.call(...)

    def call(scan, order: nil)
      weights = BIOMETRY.weights(scan.to_biometry_scan)
      ordered(order).to_h do |standard|
        [standard, Chart.call(scan, standard: standard, weights: weights)]
      end
    end

    private

    def ordered(order)
      known = BIOMETRY.charts.keys
      preferred = Array(order).select { |standard| known.include?(standard) }
      preferred + (known - preferred)
    end
  end
end
