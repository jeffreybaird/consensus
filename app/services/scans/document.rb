# frozen_string_literal: true

module Scans
  # The scan's report as the plain hash the gem's document service builds —
  # the same structure the gem's own CLI prints as JSON. Routes serialize it;
  # they never touch the gem's internals themselves.
  class Document
    def self.call(...) = new.call(...)

    def call(scan)
      Biometry::Services::Report::Document.new.call(**Report.call(scan).to_h)
    end
  end
end
