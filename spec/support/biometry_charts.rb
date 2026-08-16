# frozen_string_literal: true

# The gem's own chart answer for a saved scan, composed from the scan's stored
# columns and the catalog's published formula pairing — never from the app's
# converters or services. Specs that assert what a chart shows compare against
# this, so nothing clinical is typed into an example and a service or view that
# drops a measurement, a sex, a stratum or the point shows up as a difference
# rather than as a tautology.
module BiometryChartHelpers
  def biometry_scan(scan)
    measurements = { bpd: scan.bpd_mm, hc: scan.hc_mm, ac: scan.ac_mm, fl: scan.fl_mm }
                   .filter_map { |kind, mm| Biometry::Measurement.new(kind: kind, mm: mm) if mm }
    Biometry::Scan.new(date: scan.scanned_on, measurements: measurements)
  end

  def paired_formula(standard)
    BIOMETRY.catalog.growth_standards
            .find { |descriptor| descriptor.id == standard }
            &.paired_formula
  end

  # The weight the chart's own paired formula produces, or nil when that
  # formula refused this scan's measurements.
  def paired_weight(scan, standard)
    formula = paired_formula(standard)
    return nil unless formula

    weight = BIOMETRY.weights(biometry_scan(scan)).value![formula]
    weight&.success? ? weight.value! : nil
  end

  def gem_chart(scan, standard, with_point: true)
    estimate = with_point ? paired_weight(scan, standard) : nil
    point = estimate && { estimate: estimate, ga: Biometry::GestationalAge.new(days: scan.ga_days) }
    BIOMETRY.chart_series(
      standard: standard,
      sex: scan.sex&.to_sym,
      stratum: scan.stratum&.to_sym,
      point: point
    )
  end

  # A Success wraps one ChartSeries, or an array of them for a stratified
  # standard asked without a stratum. Both read the same way here.
  def charts_of(result) = Array(result.value!)

  def payloads_of(result) = charts_of(result).map(&:to_h)
end

RSpec.configure { |config| config.include BiometryChartHelpers }
