# frozen_string_literal: true

# Boot order: Bundler -> DB (+ Sequel plugins) -> app code -> the Sinatra app.
require "bundler/setup"
Bundler.require(:default, ENV.fetch("RACK_ENV", "development").to_sym)

require_relative "database"

require_relative "../app/current"
Dir[File.expand_path("../app/models/**/*.rb", __dir__)].sort.each   { |f| require f }
Dir[File.expand_path("../app/services/**/*.rb", __dir__)].sort.each { |f| require f }
Dir[File.expand_path("../app/policies/**/*.rb", __dir__)].sort.each { |f| require f }

require_relative "../app"
