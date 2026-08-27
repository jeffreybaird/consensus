# Architecture

A deeper tour of Consensus than the [README](README.md) — for a reviewer who
needs to understand *why* the code is shaped the way it is. Pair this with
[`CLAUDE.md`](CLAUDE.md) (the rulebook) and the per-area files in
[`.claude/`](.claude/).

## The one-sentence model

Consensus is a thin, honest **presentation layer** over one clinical library
[https://github.com/jeffreybaird/biometry](biometry). It persists what a user typed and recomputes every clinical value
on view.

## Boot order

`config.ru` requires `config/environment.rb`, which loads in a fixed order and
raises early if anything is wrong:

```
Bundler.setup / Bundler.require
  -> config/database.rb   # DB = Sequel.connect(...); WAL, busy_timeout, foreign_keys
  -> BIOMETRY = Biometry.load   # the gem: reference data read ONCE into a frozen Context
  -> app/current.rb
  -> app/models/**/*.rb   # Sequel models introspect their tables at require-time
  -> app/services/**/*.rb
  -> app/policies/**/*.rb
  -> app.rb               # class App < Sinatra::Base
config.ru: run App
```

Two ordering facts matter:

- **`BIOMETRY` loads before any model or route.** It's a frozen, thread-safe
  `Biometry::Context` shared across every request and Puma thread. If the gem's
  reference data is unverified or malformed, the process dies at boot — before
  it can serve a single wrong number.
- **Models load after the DB connects and migrates.** A `Sequel::Model`
  introspects its table at require-time, so the schema must already exist. In
  tests, `spec_helper.rb` migrates the disposable test DB *before* requiring the
  app for exactly this reason.

## Request lifecycle

```
Puma thread picks up a request
  before  -> Current.reset!; Current.request_id = X-Request-Id or a fresh uuid
  route   -> parse params -> call ONE service -> render ERB (or JSON)
  after   -> Current.reset!   # Puma reuses threads; leaking Current would cross requests
```

`Current` ([`app/current.rb`](app/current.rb)) is thread-local and is the
**data boundary** — who / which tenant — *not* authorization. This app has no
users or accounts, so today it carries only `request_id`, but the seam
(`user`, `account`) exists so scoping has a home when it's needed. Authorization,
when it arrives, is a separate concern living in `app/policies/`.

## The layers

### Routes — [`app.rb`](app.rb)

Thin by rule. A route:

1. parses params,
2. calls exactly one service (or a model dataset for trivial reads),
3. renders ERB or serializes JSON.

No business rules, no raw SQL, no gem internals. The only logic that lives in
`app.rb` is **presentation**: SVG chart geometry (pure arithmetic — pixel
coordinates, never clinical values), number formatting (`grams`, `ordinal`), and
the `scan_or_404` / canonical-id guard.

The canonical-id guard (`CANONICAL_ID = /\A(?:0|[1-9]\d*)\z/`) is a deliberate
detail: `Integer("01")` is octal `1` and `Integer("0x10")` is `16`, so a naive
parse would silently accept those and 404 `"08"`. The regex accepts exactly the
decimal digits with no leading zero, so ids behave consistently.

### Models — [`app/models/scan.rb`](app/models/scan.rb)

`Scan` is the only persisted entity. It holds **what was entered** (four
measurements in mm, `ga_days`, `scanned_on`, optional `patient_ref`, `sex`,
`stratum`) and converts on demand to the gem's value objects
(`to_biometry_scan`, `ga`). It owns its invariants (`validate`) and its
pagination contract (`page`, clamped 1–100 per page). It does **not** compute
anything clinical — that's the gem's job.

### Services — [`app/services/`](app/services/)

One object, one job, one `#call`. The `Scans::` family:

| Service     | Input → output                                                        |
|-------------|-----------------------------------------------------------------------|
| `Create`    | form params → saved `Scan`, as a tagged `dry-monads` Result           |
| `Report`    | scan → the gem's composed report (all standards)                      |
| `Charts`    | scan → every chart panel, in the report's row order                  |
| `Chart`     | scan + one standard → that chart's series payload                    |
| `Document`  | scan → the plain hash the gem's CLI prints as JSON                   |
| `Options`   | the sex/stratum option lists, derived from the gem's catalog          |
| `Reason`    | a gem `Failure` tuple → the sentence the page prints                  |

Two service patterns are worth calling out for a reviewer:

- **`Create` returns a Result, not an exception.** `Success(scan)` or
  `Failure([:validation, errors])` / `Failure([:error, message])`. The route
  branches on it. Rack params can arrive as arrays or hashes (`bpd[]=1`);
  `Create#text` coerces any non-String to `nil` so a hostile param becomes an
  ordinary validation failure, never a 500.
- **`Reason` makes refusals content.** The gem returns `Failure` tuples like
  `[:out_of_range, {...}]`; `Reason` turns each into a human sentence built
  *only* from the failure payload. Nothing clinical is decided or invented here.
  This is how "refusals are content" is implemented: a chart the gem refuses
  keeps its panel and states why, instead of vanishing.

### Display names — [`app/services/standards/names.rb`](app/services/standards/names.rb)

The gem deliberately returns **ids and citations, never labels**. `Standards::Names`
maps those ids to display strings (`:hadlock_1991 => "Hadlock 1991"`). An unknown
id falls back to a readable spelling rather than raising — a new chart in the gem
must never take the page down. This is the *only* place the app names a standard.

### Views — [`views/`](views/)

Server-rendered ERB, HTML-escaped (`set :erb, escape_html: true`, backed by
`erubi`). One layout, plus `scans/*` and `standards/*`. The single piece of
client JS is [`public/js/theme.js`](public/js/theme.js) (the theme toggle) — no
Turbo, no Stimulus, no build step.

## The gem boundary

`BIOMETRY` (a loaded `Biometry::Context`) is the **only** door to clinical
computation. The contract:

- Services call `BIOMETRY.report`, `.weights`, `.chart_series`, `.charts`,
  `.catalog`. Routes and views never require gem internals.
- The gem is **vendored** at `vendor/biometry` from the private `../biometry`
  repo, because the build has no access to the source repo. Re-sync with
  `bin/vendor-biometry` after any gem change and commit the result.
- Library API: `../biometry/docs/LIBRARY.md`. Chart-data contract:
  `../biometry/docs/CHART_DATA.md`.

Because the gem is an in-process path dependency, there is **no** Faraday client,
no WebMock, no wrapper class for it. It's a `require`, not a network hop.

## Data & the single-writer constraint

One SQLite file, one global `DB` ([`config/database.rb`](config/database.rb)),
one writer at a time — the write locks the whole file. Consequences baked into
the design:

- **WAL mode** lets readers run concurrently with the single writer, and it's
  what Litestream replicates.
- **`busy_timeout=5000`** makes a contender wait rather than instantly error,
  but the real fix for contention is *fewer, shorter* writes — never a longer
  timeout.
- **Puma threads stay modest** (`config/puma.rb`, max 5). More threads mainly
  means more lock contention here, not more throughput.
- The app's only mutation today is "save a scan" of synthetic data. Under that
  reality, two `.claude/architecture-decisions.md` rules are **consciously
  deferred**: there is no `audit_logs` table and no soft delete (there is no
  delete at all). The moment a second mutation, a destructive action, or real
  data arrives, both rules apply in full.

Migrations live in `db/migrate/` and are run by `rake db:migrate` — which is the
deploy gate. (Note the history: notes tables were created then dropped;
`002_create_scans.rb` is the live schema.)

## Failure & honesty conventions

- **Expected failures are values, not exceptions.** Tagged Results
  (`dry-monads`) where an operation has several distinct failure modes;
  `model.errors` for simple CRUD. Never a bare boolean/`nil` where the caller
  needs to know *why*.
- **A 404 always says so.** The `not_found` handler preserves a route's own body
  (the JSON 404) and otherwise renders the HTML not-found page. No silently
  empty responses.
- **No clinical constant is ever hard-coded here.** If the UI seems to need one,
  the gem is missing it — stop and say so.

## Deployment shape

Docker image (`Dockerfile`) + Puma, on a DigitalOcean droplet behind a shared
Caddy edge (TLS, per-app site file). Push to `main` runs
[`.github/workflows/deploy.yml`](.github/workflows/deploy.yml): test gate →
build/push image → **gated migration against the new image before traffic** →
health-checked blue/green swap. Litestream replicates the SQLite file to object
storage. The `deploy/` directory holds the compose files, Caddy templates,
Litestream config, and `swap.sh`. Full detail: [`.claude/deployment.md`](.claude/deployment.md).
