# frozen_string_literal: true

# A saved scan. Measurements are millimetres, exactly as the gem's
# Biometry::Measurement takes them; nothing here is a clinical claim about
# which formula can read which set — traits only vary what was recorded.
FactoryBot.define do
  factory :scan do
    bpd_mm     { 81.0 }
    hc_mm      { 296.0 }
    ac_mm      { 279.0 }
    fl_mm      { 61.0 }
    ga_days    { 224 }
    scanned_on { Date.today }

    # Only one measurement was recorded. Some formulas will refuse this scan;
    # which ones is the gem's business, not the factory's.
    trait :partial do
      hc_mm { nil }
      ac_mm { nil }
      fl_mm { nil }
    end

    trait :labelled do
      sequence(:patient_ref) { |n| "REF-#{n}" }
    end
  end
end
