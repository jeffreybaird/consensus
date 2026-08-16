# frozen_string_literal: true

source "https://rubygems.org"

# One source of truth for the Ruby version: .ruby-version (the Dockerfile's
# RUBY_VERSION ARG and CI's ruby-version-file read the same file).
ruby file: ".ruby-version"

gem "sinatra", "~> 4.1", require: "sinatra/base" # modular app, no classic DSL
gem "puma", "~> 6.6"                             # app server (config/puma.rb)
gem "rackup", "~> 2.2"                           # `run App` entrypoint (config.ru)
gem "sequel", "~> 5.90"                          # ORM + migrations
gem "sqlite3", "~> 2.6"                          # the only DB backend
gem "rake", "~> 13.2"                            # `rake db:migrate` (the deploy gate)
gem "dry-monads", "~> 1.8", require: "dry/monads" # Success/Failure Results
gem "faraday", "~> 2.13"                         # HTTP client for service wrappers

group :development, :test do
  gem "rspec", "~> 3.13"
  gem "rack-test", "~> 2.2", require: "rack/test"
  gem "factory_bot", "~> 6.5"
  gem "dotenv", "~> 3.1"
end

group :test do
  gem "capybara", "~> 3.40"
end
