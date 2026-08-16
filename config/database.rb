# frozen_string_literal: true

require "sequel"

# DATABASE_PATH is set by the deploy stack (an on-volume file, e.g.
# /data/app.sqlite3). In dev/test it defaults to a per-environment file.
db_path = ENV.fetch("DATABASE_PATH") do
  env = ENV.fetch("RACK_ENV", "development")
  File.expand_path("../db/#{env}.sqlite3", __dir__)
end

# The single global connection. SQLite is one file, one writer at a time — see
# .claude/database.md before doing anything write-heavy.
DB = Sequel.connect(adapter: "sqlite", database: db_path)

# WAL: readers don't block the single writer, and it's what Litestream replicates.
# busy_timeout: wait (don't instantly error) when another write holds the lock.
DB.run "PRAGMA journal_mode=WAL"
DB.run "PRAGMA busy_timeout=5000"
DB.run "PRAGMA foreign_keys=ON"

# App-wide model plugins (models are defined after this file loads).
Sequel::Model.plugin :timestamps, update_on_create: true
Sequel::Model.plugin :validation_helpers
