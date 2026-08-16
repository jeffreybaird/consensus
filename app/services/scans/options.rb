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

    def stratification(id)
      BIOMETRY.catalog.growth_standards
              .find { |standard| standard.id == id }
              .stratification[:values].map(&:to_sym)
    end
  end
end
