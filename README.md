# Consensus

**The web UI for the [`biometry`](vendor/biometry) gem — fetal biometry from ultrasound measurements.**

A user enters a scan's measurements (BPD, HC, AC, FL, in millimetres) and a
gestational age; Consensus shows the estimated fetal weight and where it falls
on each competing growth standard — both Hadlock 1991 readings,
INTERGROWTH-21st, WHO and NICHD — side by side, with server-rendered SVG growth
charts.

**The disagreement between standards is the product, not a caveat on it.** The
app renders numbers, percentile curves and citations. Interpreting them is a
clinician's job.

---

## What this app does (and deliberately does not)

Consensus is a thin, honest presentation layer over one clinical library. Every
clinical number comes from the `biometry` gem; the app stores what a user typed
and recomputes everything else on view — nothing clinical is ever cached or
persisted.

Four clinical rules, inherited from the gem and enforced here:

- **No classification labels, ever.** No SGA, LGA, IUGR, macrosomia,
  abnormal/normal, threshold lines, or shaded "danger" zones — not in views,
  not in JSON, not in charts.
- **Every number is cited.** A weight or percentile shown without its standard
  and paper citation is incomplete. The gem carries provenance on every value;
  the UI surfaces it.
- **Refusals are content.** When a chart cannot answer (missing measurement, GA
  outside its window), the reason is rendered where the reading would have been
  — never a silently absent row or an empty chart.
- **No clinical constants in this app.** Every clinical number comes from the
  gem. If the UI seems to need one, the gem is missing it.

**No real patient data lives here.** Every `patient_ref` is a synthetic label
and always will be. (That allowance is what lets `patient_ref` appear in logs —
see [`.claude/observability.md`](.claude/observability.md).)

---

## Stack

| Layer            | Choice                                                              |
|------------------|--------------------------------------------------------------------|
| Language         | Ruby 3.3+ (pinned in [`.ruby-version`](.ruby-version))             |
| Web framework    | **Modular** Sinatra (`class App < Sinatra::Base`), served by Puma   |
| ORM              | Sequel                                                              |
| Database         | SQLite (WAL mode, single writer), replicated by Litestream in prod  |
| Views            | ERB (`erubi`, HTML-escaped) — no Hotwire/Turbo/Stimulus            |
| Client JS        | one vanilla module ([`public/js/theme.js`](public/js/theme.js))   |
| Results          | `dry-monads` (`Success`/`Failure`)                                  |
| Clinical compute | the `biometry` gem, loaded once at boot into a frozen `Context`     |
| Tests            | RSpec + Rack::Test + Capybara                                       |
| Deploy           | Docker + Puma on a DigitalOcean droplet (Caddy TLS, blue/green)     |

This is a lean stack on purpose. Sinatra gives routing and little else; most of
the structure here is convention, not framework. When something isn't built in,
the answer is "plain Ruby + an explicit `require`", not a Rails-ism.

---

## Run it locally

Prerequisites: Ruby matching [`.ruby-version`](.ruby-version) (3.3.6) and
Bundler. No external services — SQLite is a file, and `biometry` is vendored
in-process.

```bash
# 1. Install gems (biometry is vendored at vendor/biometry — no extra step)
bundle install

# 2. Environment: copy the example and set a dev secret
cp .env.example .env
# then edit .env — generate a secret with: openssl rand -hex 64

# 3. Create the SQLite database from migrations
bundle exec rake db:migrate        # writes db/development.sqlite3

# 4. Run the app
bundle exec puma -C config/puma.rb  # http://localhost:4000
```

Open <http://localhost:4000>, enter a scan, and read the standards side by side.

### Common tasks

```bash
bundle exec rspec                    # run the full suite
bundle exec rspec spec/requests      # one directory
bundle exec rake db:migrate          # apply pending migrations
bundle exec rake db:rollback         # undo the last migration
curl localhost:4000/up               # liveness/readiness probe -> {"status":"ok"}
```

### Environment variables

Loaded from `.env` in dev/test via `dotenv`; injected over SSH at deploy time in
prod (never committed). See [`.env.example`](.env.example).

| Var               | Purpose                                              | Default (dev)              |
|-------------------|------------------------------------------------------|----------------------------|
| `RACK_ENV`        | environment                                          | `development`              |
| `PORT`            | Puma bind port                                       | `4000`                     |
| `DATABASE_PATH`   | SQLite file path                                     | `db/<env>.sqlite3`         |
| `SECRET_KEY_BASE` | session secret (`openssl rand -hex 64`)              | random per-boot if unset   |
| `PUMA_MAX_THREADS`| Puma thread ceiling (keep modest — single writer)    | `5`                        |

---

## Routes

| Method | Path                          | Renders                                                      |
|--------|-------------------------------|-------------------------------------------------------------|
| `GET`  | `/`                           | new-scan form + recent saved scans (paginated, 25/page)     |
| `POST` | `/scans`                      | create a scan → redirect to it, or re-render form with 422  |
| `GET`  | `/scans/:id`                  | the report: every standard side by side + SVG charts        |
| `GET`  | `/scans/:id.json`             | the report as JSON (same document the gem's CLI prints)     |
| `GET`  | `/scans/:id/charts/:standard` | one standard's growth chart, standalone                     |
| `GET`  | `/standards`                  | read-only catalog: standards, formulas, citations           |
| `GET`  | `/up`                         | liveness/readiness (`200` once the DB is reachable)         |

Unknown ids and non-canonical ids (`01`, `0x10`, `08`) get an honest `404` —
JSON body on the `.json` route, HTML page elsewhere.

---

## Code organization

```
app.rb                     # the Sinatra app — thin routes + presentation helpers only
config/
  environment.rb           # boot order: Bundler -> DB -> BIOMETRY -> app code -> App
  database.rb              # the single global DB (SQLite, WAL, busy_timeout)
  puma.rb                  # server config
app/
  current.rb               # request-scoped Current (the DATA boundary, not auth)
  models/scan.rb           # Sequel model: persistence + invariants + gem conversion
  services/
    scans/                 # one job per object, single #call
      create.rb            #   form params -> saved Scan (dry-monads Result)
      report.rb            #   scan -> the gem's composed report
      charts.rb            #   scan -> every chart panel, in report row order
      chart.rb             #   scan + one standard -> that chart's series payload
      document.rb          #   scan -> the gem's plain-hash JSON document
      options.rb           #   sex/stratum option lists, derived from the catalog
      reason.rb            #   the gem's Failure tuples -> sentences the page prints
    standards/names.rb     # display names for the gem's ids (presentation only)
  policies/                # authorization policy objects (none yet; the seam exists)
  clients/                 # external-service client classes (none — nothing external)
views/                     # ERB: layout, scans/*, standards/*
public/                    # app.css + theme.js (the only client JS)
db/migrate/                # Sequel migrations (rake db:migrate is the deploy gate)
spec/                      # RSpec: requests, features, services, factories, support
vendor/biometry/           # the vendored gem (bin/vendor-biometry re-syncs it)
deploy/                    # compose, Caddy, Litestream, blue/green swap scripts
infra/                     # Terraform roots (droplet, DNS, state bucket)
.claude/                   # per-area conventions Claude Code follows
```

The boot chain (`config/environment.rb`) is deliberate: `BIOMETRY =
Biometry.load` runs **once at boot** into a frozen, thread-safe `Context` shared
across every request. It raises before anything serves if the gem's reference
data is malformed.

For a deeper tour — the request lifecycle, the gem boundary, the SQLite
single-writer constraint — see [`ARCHITECTURE.md`](ARCHITECTURE.md).

---

## Architecture principles (the short version)

1. **Skinny routes.** A route parses params, calls one service, and renders.
   Business rules and SQL never live in a route block.
2. **Domain logic in service objects.** One object, one job, one `#call`,
   returning a value the caller can branch on — a tagged `dry-monads` Result
   where there are several failure modes.
3. **The gem is the only door to clinical computation.** Services call
   `BIOMETRY`; routes and views never require gem internals.
4. **Respect the single writer.** SQLite serializes writes and locks the whole
   file. No high-frequency row-by-row writes; keep write transactions short.
   Reads scale with caching and indexing, not replicas.
5. **Every behavior change ships with a test.** The suite is a ratchet — see
   [CONTRIBUTING.md](CONTRIBUTING.md) and [`.claude/testing.md`](.claude/testing.md).

Full detail lives in [`CLAUDE.md`](CLAUDE.md) and the per-area files under
[`.claude/`](.claude/).

---

## Testing

```bash
bundle exec rspec
```

The suite uses an isolated, disposable SQLite test DB, recreated from migrations
before every run (see [`spec/spec_helper.rb`](spec/spec_helper.rb)). Each example
runs inside a transaction rolled back at the end — fast, isolated, and safe under
SQLite's single writer.

- **`spec/requests/`** — Rack::Test against real routes (create, report, JSON, 404s).
- **`spec/features/`** — Capybara flows (browsing the catalog).
- **`spec/services/`** — service objects in isolation.
- **`spec/support/`** — FactoryBot config and shared gem fixtures.

Selectors are `data-testid`, never CSS classes. Specs are owned by the
`spec-writer` role and protected by a hook — see [CONTRIBUTING.md](CONTRIBUTING.md).

---

## Deployment

`main` is always releasable. The pipeline
([`.github/workflows/deploy.yml`](.github/workflows/deploy.yml)) runs on push to
`main`:

```
test (gate) -> build + push image -> migrate (gated) -> blue/green swap
```

Red tests block the deploy entirely. Migrations run as a one-off against the new
image **before** any traffic is served — a bad migration can never serve a
half-updated DB. The swap is health-checked; Caddy holds requests through the
window, so there is no downtime. SQLite is replicated to object storage by
Litestream.

Infrastructure (droplet, DNS, state bucket) is owned by the Terraform roots in
[`infra/`](infra/) — never click it in the DO console. See
[`.claude/deployment.md`](.claude/deployment.md).

---

## Documentation map

| File                          | What it covers                                            |
|-------------------------------|-----------------------------------------------------------|
| [README.md](README.md)        | this file — orientation, running locally, layout          |
| [ARCHITECTURE.md](ARCHITECTURE.md) | deep code tour: lifecycle, the gem boundary, data model |
| [CONTRIBUTING.md](CONTRIBUTING.md) | how to work in the repo: workflow, tests, style, commits |
| [SECURITY.md](SECURITY.md)    | data-handling posture, reporting, the no-PII allowance     |
| [CLAUDE.md](CLAUDE.md)        | the full rulebook Claude Code follows                      |
| [`.claude/`](.claude/)        | per-area conventions (database, testing, deployment, …)   |
```