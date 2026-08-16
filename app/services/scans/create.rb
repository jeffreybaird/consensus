# frozen_string_literal: true

require "dry/monads"

module Scans
  # Parses the new-scan form into a saved Scan. One object, one job, one #call,
  # returning a tagged Result the route branches on.
  #
  # Sex and stratum options come from the gem's catalog, never from a list
  # typed here: what WHO and NICHD stratify by is their manifests' business.
  class Create
    include Dry::Monads[:result]

    GA_FORMAT = /\A(\d{1,2})w(?:([0-6])d)?\z/
    GA_MESSAGE = "reads as weeks and days, like 32w0d (0w0d to 46w6d)"
    MAX_WEEKS = 46

    def self.call(...) = new.call(...)

    def call(params)
      errors = {}
      attrs = parsed(params, errors)
      return Failure([:validation, errors]) if errors.any?

      scan = Scan.new(attrs)
      return Failure([:validation, scan.errors.to_h]) unless scan.valid?

      scan.save
      Success(scan)
    rescue Sequel::DatabaseError => e
      Failure([:error, e.message])
    end

    private

    def parsed(params, errors)
      { ga_days: ga_days(text(params["ga"]), errors),
        scanned_on: scanned_on(text(params["scanned_on"]), errors),
        patient_ref: presence(text(params["patient_ref"])),
        sex: option(:sex, text(params["sex"]), sexes, errors),
        stratum: option(:stratum, text(params["stratum"]), strata, errors) }
        .merge(measurements(params, errors))
    end

    # The boundary: Rack params can arrive as arrays or hashes (`bpd[]=1`).
    # Anything that is not a String is treated as unsupplied and falls into
    # the same validation failure the field already produces — never a 500.
    def text(value) = value.is_a?(String) ? value : nil

    def ga_days(text, errors)
      match = GA_FORMAT.match(text.to_s.strip)
      return errors[:ga] = GA_MESSAGE unless match

      weeks = Integer(match[1], 10)
      return errors[:ga] = GA_MESSAGE if weeks > MAX_WEEKS

      (weeks * 7) + Integer(match[2] || "0", 10)
    end

    def scanned_on(text, errors)
      return Date.today if blank?(text)

      Date.iso8601(text.strip)
    rescue Date::Error
      errors[:scanned_on] = "reads as an ISO date, like 2026-08-16"
      nil
    end

    def measurements(params, errors)
      Scan::MEASUREMENTS.to_h do |kind, column|
        [column, measurement(kind, text(params[kind.to_s]), errors)]
      end
    end

    def measurement(kind, text, errors)
      return nil if blank?(text)

      Float(text.strip)
    rescue ArgumentError
      errors[kind] = "must be a number in millimetres"
      nil
    end

    def option(field, value, available, errors)
      return nil if blank?(value)

      choice = value.to_sym
      return choice.to_s if available.include?(choice)

      errors[field] = "must be one of: #{available.join(', ')}"
      nil
    end

    def sexes = Options.sexes

    def strata = Options.strata

    def presence(text) = blank?(text) ? nil : text.strip

    def blank?(text) = text.nil? || text.strip.empty?
  end
end
