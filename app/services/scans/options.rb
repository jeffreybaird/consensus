# frozen_string_literal: true

module Scans
  # The chart options a scan can carry, derived from the gem's catalog — what
  # WHO and NICHD stratify by is their manifests' business, and this is the
  # one place the app reads it. Both the create service and the form render
  # from here, so the options cannot drift apart.
  module Options
    module_function

    # WHO's sexed charts, minus the combined one a nil sex already means.
    def sexes = stratification(:who) - [:combined]

    def strata = stratification(:nichd)

    # A standard the gem's loader pruned yields no options rather than a
    # crash: the app still boots and says less, which is the honest state.
    def stratification(id)
      standard = BIOMETRY.catalog.growth_standards.find { |each| each.id == id }
      return [] unless standard

      standard.stratification[:values].map(&:to_sym)
    end
  end
end
