# frozen_string_literal: true

require "dry/monads"

module Notes
  # One object, one job, one #call. Returns a tagged Result the route branches on
  # — never a bare boolean/nil. See .claude/architecture-decisions.md.
  class Create
    include Dry::Monads[:result]

    def self.call(...) = new.call(...)

    def call(attrs)
      note = Note.new(body: attrs["body"].to_s.strip)
      return Failure([:validation, note.errors]) unless note.valid?

      note.save
      Success(note)
    rescue Sequel::DatabaseError => e
      Failure([:error, e.message])
    end
  end
end
