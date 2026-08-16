# frozen_string_literal: true

module Standards
  # Display names for the gem's identifiers. The gem deliberately returns ids
  # and citations, never labels (../rei_calc/docs/LIBRARY.md) — these are this
  # app's labels, presentation only, keyed by the catalog's ids. An unknown id
  # falls back to a readable spelling rather than raising: a new chart in the
  # gem must not take the page down.
  module Names
    STANDARDS = {
      intergrowth21: "INTERGROWTH-21st",
      hadlock_1991: "Hadlock 1991",
      hadlock_1991_equation: "Hadlock 1991 (equation)",
      hadlock_1991_table: "Hadlock 1991 (table)",
      who: "WHO",
      nichd: "NICHD",
      naegele: "Naegele",
      ivf_transfer: "IVF transfer",
      acog: "ACOG"
    }.freeze

    FORMULAS = {
      intergrowth: "INTERGROWTH (AC+HC)",
      hadlock_ac_fl: "Hadlock AC+FL",
      hadlock_bpd_ac_fl: "Hadlock BPD+AC+FL",
      hadlock_hc_ac_fl: "Hadlock HC+AC+FL",
      hadlock_bpd_hc_ac_fl: "Hadlock BPD+HC+AC+FL"
    }.freeze

    module_function

    def standard(id) = STANDARDS.fetch(id.to_sym) { fallback(id) }

    def formula(id) = FORMULAS.fetch(id.to_sym) { fallback(id) }

    def fallback(id) = id.to_s.tr("_", " ")
  end
end
