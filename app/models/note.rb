# frozen_string_literal: true

# Persistence + invariants for a note. Business orchestration belongs in a
# service object (app/services/notes/), not here.
class Note < Sequel::Model
  dataset_module do
    def recent = order(Sequel.desc(:created_at))
  end

  def validate
    super
    validates_presence :body
    validates_max_length 10_000, :body, allow_nil: false
  end
end
