# frozen_string_literal: true

require "sequel"
Sequel.extension :migration

namespace :db do
  desc "Run pending migrations"
  task :migrate do
    require_relative "config/database"
    Sequel::Migrator.run(DB, "db/migrate")
    puts "migrated: #{DB.opts[:database]}"
  end

  desc "Roll back the last migration"
  task :rollback do
    require_relative "config/database"
    current = Sequel::Migrator.new(DB, "db/migrate").current
    Sequel::Migrator.run(DB, "db/migrate", target: [current - 1, 0].max)
  end
end

begin
  require "rspec/core/rake_task"
  RSpec::Core::RakeTask.new(:spec)
  task default: :spec
rescue LoadError
  # rspec is a dev/test gem; absent in production images. That's fine.
end
