# frozen_string_literal: true

module Scans
  # Turns the gem's Failure tuples into the sentences the page prints. Every
  # number and name comes from the failure payload — nothing clinical is
  # decided or invented here, and a refusal is content, not an error.
  module Reason
    module_function

    def call(failure)
      tag, details = failure
      case tag
      when :out_of_range then out_of_range(details)
      when :insufficient_data then insufficient_data(details)
      when :formula_chart_mismatch then mismatch(details)
      else fallback(tag, details)
      end
    end

    def out_of_range(details)
      from, to = details[:valid_range]
      "#{Standards::Names.standard(details[:standard])} covers #{from}–#{to} weeks; " \
        "this scan is at #{details[:ga_weeks]} weeks."
    end

    def insufficient_data(details)
      required = details.fetch(:required, [])
      missing = required - details.fetch(:given, [])
      "This chart's formula needs #{kinds(required)}; " \
        "this scan has no #{kinds(missing)}."
    end

    def mismatch(details)
      "#{Standards::Names.standard(details[:chart])} pairs with the " \
        "#{Standards::Names.formula(details[:expected])} formula, " \
        "not #{Standards::Names.formula(details[:given])}."
    end

    def fallback(tag, details)
      detail = details.is_a?(Hash) ? details.map { |k, v| "#{k}: #{v}" }.join(", ") : details
      "Could not be read (#{tag.to_s.tr('_', ' ')}#{detail ? " — #{detail}" : ''})."
    end

    def kinds(list) = Array(list).map { |kind| kind.to_s.upcase }.join(", ")
  end
end
