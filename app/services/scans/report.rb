# frozen_string_literal: true

module Scans
  # One saved scan → the gem's composed report. No dating inputs are collected
  # in this app, so the dating derivations all refuse; the growth rows are the
  # content. All clinical computation happens in the gem, recomputed on every
  # call — nothing is cached or stored.
  class Report
    def self.call(...) = new.call(...)

    def call(scan)
      BIOMETRY.report(
        scans: [scan.to_biometry_scan],
        ga: scan.ga,
        at: scan.scanned_on,
        sex: scan.sex_sym,
        stratum: scan.stratum_sym
      )
    end
  end
end
