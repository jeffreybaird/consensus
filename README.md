# Notes (Sinatra + Sequel + SQLite)

A minimal, tested Sinatra app scaffolded by `push-button-deploy`. See `CLAUDE.md`
and `.claude/` for the conventions Claude Code follows in this repo.

```bash
bundle install
bundle exec rake db:migrate        # create db/development.sqlite3
bundle exec puma -C config/puma.rb  # http://localhost:4000
bundle exec rspec                   # run the suite
```

Layout:

- `app.rb` — the Sinatra app; thin routes only.
- `app/services/` — service objects (one `#call`, return a dry-monads Result).
- `app/models/` — Sequel models (persistence + invariants).
- `config/database.rb` — the SQLite connection (WAL mode; see `.claude/database.md`).
- `db/migrate/` — Sequel migrations (`rake db:migrate`).
- `spec/` — RSpec (Rack::Test + Capybara).

Deploys via the `push-button-deploy` pipeline: push to `main` → test → build →
migrate (gated) → zero-downtime blue/green swap. SQLite is replicated to object
storage by Litestream.
