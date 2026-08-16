# frozen_string_literal: true

Sequel.migration do
  change do
    create_table(:scans) do
      primary_key :id
      # Millimetres, nullable: a scan records what was measured. The gem
      # refuses per-chart when a formula's inputs are missing, and that
      # refusal is page content, not a validation error here.
      Float :bpd_mm
      Float :hc_mm
      Float :ac_mm
      Float :fl_mm
      Integer :ga_days, null: false
      Date :scanned_on, null: false
      String :sex
      String :stratum
      # Synthetic label only — this app holds no real patient data (CLAUDE.md
      # "Data honesty"). May appear in logs under that standing rule.
      String :patient_ref
      DateTime :created_at
      DateTime :updated_at

      index :created_at
    end
  end
end
