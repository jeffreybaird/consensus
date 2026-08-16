# frozen_string_literal: true

require "factory_bot"

FactoryBot.definition_file_paths = [File.expand_path("../factories", __dir__)]

# Sequel::Model persists with #save, not ActiveRecord's #save!.
FactoryBot.define { to_create(&:save) }

FactoryBot.find_definitions
