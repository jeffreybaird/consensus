# frozen_string_literal: true

# Persistence + invariants for one saved ultrasound scan. All clinical
# computation happens in the biometry gem; this model only holds what was
# entered and converts it to the gem's value objects on demand.
class Scan < Sequel::Model
  MEASUREMENTS = { bpd: :bpd_mm, hc: :hc_mm, ac: :ac_mm, fl: :fl_mm }.freeze

  dataset_module do
    def recent = order(Sequel.desc(:created_at), Sequel.desc(:id))
  end

  def validate
    super
    validates_presence %i[ga_days scanned_on]
    validates_includes 0..350, :ga_days if ga_days
    MEASUREMENTS.each_value do |column|
      value = public_send(column)
      errors.add(column, "must be positive") if value && value <= 0
    end
  end

  def ga = Biometry::GestationalAge.new(days: ga_days)

  def ga_text = ga.to_s

  def to_biometry_scan
    measurements = MEASUREMENTS.filter_map do |kind, column|
      value = public_send(column)
      Biometry::Measurement.new(kind: kind, mm: value) if value
    end
    Biometry::Scan.new(date: scanned_on, measurements: measurements)
  end

  def sex_sym = sex&.to_sym

  def stratum_sym = stratum&.to_sym
end
