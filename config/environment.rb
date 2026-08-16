# frozen_string_literal: true

# Boot order: Bundler -> DB (+ Sequel plugins) -> app code -> the Sinatra app.
require "bundler/setup"
Bundler.require(:default, ENV.fetch("RACK_ENV", "development").to_sym)

require_relative "database"

# The gem boundary: read data/ once, at boot, into a frozen Context every
# request and thread shares. Raises here — before anything serves — if the
# gem's reference data is unverified or malformed. See ../rei_calc/docs/LIBRARY.md.
BIOMETRY = Biometry.load

require_relative "../app/current"
Dir[File.expand_path("../app/models/**/*.rb", __dir__)].sort.each   { |f| require f }
Dir[File.expand_path("../app/services/**/*.rb", __dir__)].sort.each { |f| require f }
Dir[File.expand_path("../app/policies/**/*.rb", __dir__)].sort.each { |f| require f }

require_relative "../app"
