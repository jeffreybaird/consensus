# Testing

Load this file when writing tests, setting up test infrastructure, or reviewing
test coverage. Generic Ruby template for **modular Sinatra + Sequel + SQLite**.

> **Baseline:** Ruby 3.3+ · RSpec · Rack::Test (request specs drive `App`) ·
> Capybara with the rack-test driver (feature/E2E) · FactoryBot · data-testid
> selectors. There is **no** WebMock/VCR: the only dependency is the in-process
> `biometry` gem, so the suite makes no external HTTP calls to stub.

Maturity tags: **[stable]** = mature, safe to rely on · **[active]** =
maintained, evolving · **[optional]** = adopt only if the need exists.

Loose gem pins below use `~>` — pin to the minor you adopt, let patch float.
The Sinatra base class is always `App` (a fixed name), booted by `run App` in
`config.ru`.

---

## 1. Tests Are a Contract, Not an Obstacle

Existing tests describe **intended behavior**. They are specifications, not
suggestions. These rules are absolute:

1. **Never modify an existing test to make it pass.** A previously-passing test
   that fails after your change means your change broke intended behavior. Fix
   the code, not the test. Only exception: a deliberate, explicitly-stated
   behavior change.
2. **Never weaken an assertion** to pass a failing test.
3. **Never delete a test to resolve a failure** — flag it for discussion.
4. **Never change existing function behavior to satisfy a new test** — add a new
   method/parameter instead.
5. **A new feature that breaks existing tests** carries the burden of proof —
   integrate without breaking existing behavior.
6. **If you believe a test is genuinely wrong**, flag it with a comment and ask
   before changing.
7. **Given a bug report**, write a failing test for the expected behavior first,
   then fix the code.
8. **Find the root cause** — don't take the shortest route around an error
   message.

The suite is a ratchet: it only moves forward.

---

## 1a. Who Writes Tests — Agent Roles (hook-enforced)

The contract above is not just discipline; it is enforced by hooks (see
`.claude/settings.json`), the same setup as the biometry gem's repo:

- **`spec-writer`** (`.claude/agents/spec-writer.md`) **owns every file under
  `spec/`.** It decomposes a requirement into failing unit / integration /
  acceptance specs *before* implementation, matching the conventions already in
  the suite, asserting on observable behavior only — never internal call order
  or private names. It reports the files written and an ordering plan of
  slices.
- **`implementer`** implements one slice against pre-written failing specs, one
  failure at a time, never touching a spec file or shared code outside its
  slice.
- **`test-runner`** runs the suite (or one spec) and reports failures verbatim —
  no interpretation, no fixes.
- **`reviewer`** reviews the finished diff after green: error paths, boundaries,
  consistency with the codebase — green tests are the floor, not the finding.
- **`Explore`** is the read-only search agent.

Enforcement:

- **`scripts/protect-tests.sh`** (PreToolUse hook): any agent other than
  `spec-writer` is blocked from writing/editing anything matching
  `spec/`, `_spec.rb` or `_test.rb`, including via shell redirection, `sed -i`,
  `cp`/`mv`, or inline interpreters (`ruby -e`, `python3 -c`). The main
  assistant is "everyone else": it delegates spec work to `spec-writer` and
  reports spec problems instead of editing them. Escape hatch for a human:
  `ALLOW_TEST_EDITS=1` in the environment.
- **`scripts/gate.sh`** (TaskCompleted hook): a task cannot complete while
  `bundle exec rspec` is red. The last 20 lines of the failing run are echoed.

The workflow for any feature is therefore: `spec-writer` writes failing specs →
implementation makes them pass (directly or via `implementer` slices) →
`test-runner` confirms → `reviewer` reads the diff. A spec that seems wrong is
*flagged to spec-writer*, never edited around.

---

## 2. Test Layout

The real layout (this app has no models/policies/clients specs — the one model
is covered through its service and request specs, there are no policy objects,
and there are no external clients):

```
spec/
├── services/        # service objects: happy + error paths (Scans::*, Standards::*)
├── requests/        # full-stack route behavior, App via Rack::Test; fast
├── features/        # Capybara feature specs (rack-test driver); no JS
├── factories/       # FactoryBot definitions (scans.rb — the one factory)
├── support/         # shared config + gem fixtures
│   ├── factory_bot.rb
│   └── biometry_charts.rb
└── spec_helper.rb
```

There is no `rails_helper` — the whole harness lives in **`spec_helper.rb`**. It
migrates a **fresh** SQLite test database with `Sequel::Migrator` *before* the
app loads, then wraps every example in a transaction that is rolled back
afterward (Sequel's equivalent of Rails' transactional-fixtures). The
migrate-before-require order matters: a `Sequel::Model` introspects its table at
require-time, so the schema must already exist when `config/environment` loads
the models. See `.claude/database.md` for Sequel/SQLite/Litestream specifics.

```ruby
# spec/spec_helper.rb
ENV["RACK_ENV"] = "test"
# Isolated, disposable test DB — recreated from migrations before every run.
ENV["DATABASE_PATH"] ||= File.expand_path("../db/test.sqlite3", __dir__)
File.delete(ENV["DATABASE_PATH"]) if File.exist?(ENV["DATABASE_PATH"])

# Migrate BEFORE the app loads (models introspect their tables at require-time):
# connect, migrate, THEN load the models + app via config/environment.
require_relative "../config/database"
Sequel.extension :migration
Sequel::Migrator.run(DB, File.expand_path("../db/migrate", __dir__))

require_relative "../config/environment"   # BIOMETRY, models, services, App

require "rack/test"
require "capybara/rspec"
Capybara.app = App

Dir[File.expand_path("support/**/*.rb", __dir__)].sort.each { |f| require f }

module RequestHelpers
  include Rack::Test::Methods
  def app = App
end

RSpec.configure do |config|
  config.include FactoryBot::Syntax::Methods
  config.include RequestHelpers, type: :request
  config.include RequestHelpers, type: :feature

  # Every example runs inside a transaction rolled back at the end — fast,
  # isolated, and safe against SQLite's single writer (one connection throughout).
  config.around(:each) do |example|
    DB.transaction(rollback: :always, savepoint: true) { example.run }
  end

  config.order = :random
  config.expect_with(:rspec) { |c| c.syntax = :expect }
end
```

`savepoint: true` turns a transaction opened by the code-under-test into a
savepoint, so its COMMIT/ROLLBACK nests inside the example's outer transaction
instead of ending it. This app has **no** `sign_in`/login helper — it has no
authentication; a request spec just drives the route directly.

The transaction-per-example strategy shares **one** SQLite connection across the
spec and the in-process request, so both see the same uncommitted data. A
real-browser `:js` spec would run the app in a separate thread with its own
connection and could not see that transaction — but there are no `:js` specs
here (no client JS beyond the theme toggle).

---

## 3. Default Tool Ladder

Escalate only when the rung below cannot cover the case. Reserve the browser for
genuine JavaScript behavior (there is no Turbo/Stimulus here — just small
vanilla JS in `public/js/`); it is slow and flaky compared to request specs.

| Scenario                                              | Tool                              | Maturity   |
|-------------------------------------------------------|-----------------------------------|------------|
| Model validation / dataset / association              | model spec                        | [stable]   |
| Business logic, authorization, tenant isolation       | service spec (unit)               | [stable]   |
| One route, full stack, no JS                          | request spec (Rack::Test)         | [stable]   |
| Multi-page flow, server-rendered, no JS               | feature spec (Capybara rack-test) | [stable]   |
| JS interaction, real browser                          | feature spec (Capybara `:js`)     | [active]   |
| CSS / visual rendering verification                   | feature spec (Capybara `:js`)     | [active]   |

Ladder: **model + service unit specs → request specs (Rack::Test, full stack,
fast) → feature specs (Capybara rack-test for server-rendered flows; the real
browser only for JavaScript).**

Feature specs default to Capybara's **rack-test** driver (in-process, no JS).
Tag the browser ones `:js` to switch to Selenium/Cuprite, and **exclude `:js`
from the fast dev run**:

```ruby
# .rspec or CI: fast loop skips the browser
# bundle exec rspec --tag ~js
```

```ruby
# spec/support/capybara.rb
require "capybara/rspec"

Capybara.app               = App                        # mount the modular app
Capybara.default_driver    = :rack_test                 # no JS — fast, in-process
Capybara.javascript_driver = :selenium_chrome_headless  # only for :js specs
Capybara.default_selector  = :css

RSpec.configure do |config|
  config.include Capybara::DSL, type: :feature
end
```

Capybara: [github.com/teamcapybara/capybara](https://github.com/teamcapybara/capybara) — `[stable]`.

---

## 4. Factories (FactoryBot)

Use [`factory_bot`](https://github.com/thoughtbot/factory_bot) (`~> 6.5`) —
`[stable]`. There is no `factory_bot_rails`, so wire definition loading yourself
(shown below) and `include FactoryBot::Syntax::Methods` (done in `spec_helper`).
This app persists exactly one entity — the saved `Scan` — so there is exactly
**one** factory. Vary what was recorded with **traits**, not new factories.

`build` vs `create`: prefer **`build`** (in-memory, no DB) for unit specs that
don't need persistence; use **`create`** only when the record must exist in the
DB (request/feature specs). `build_stubbed` is the fastest when you need a record
with an id but no DB write.

```ruby
# spec/support/factory_bot.rb
require "factory_bot"
FactoryBot.definition_file_paths = [File.expand_path("../factories", __dir__)]

# Sequel::Model persists with #save, not ActiveRecord's #save!.
FactoryBot.define { to_create(&:save) }

FactoryBot.find_definitions
```

```ruby
# spec/factories/scans.rb — the only factory. Measurements are millimetres,
# exactly as Biometry::Measurement takes them; traits only vary what was
# recorded, never make a clinical claim about which formula can read the set.
FactoryBot.define do
  factory :scan do
    bpd_mm     { 81.0 }
    hc_mm      { 296.0 }
    ac_mm      { 279.0 }
    fl_mm      { 61.0 }
    ga_days    { 224 }
    scanned_on { Date.today }

    # Only one measurement recorded — some formulas will refuse this scan;
    # which ones is the gem's business, not the factory's.
    trait :partial do
      hc_mm { nil }
      ac_mm { nil }
      fl_mm { nil }
    end

    trait :labelled do
      sequence(:patient_ref) { |n| "REF-#{n}" }
    end
  end
end
```

FactoryBot instantiates `Sequel::Model` subclasses like any other object:
`build` calls `.new`, `create` runs the `to_create(&:save)` hook above.

---

## 5. External Services — Not Applicable Here

This app has **no external services** to stub. Its only dependency for clinical
computation is the `biometry` gem, which is a vendored, in-process path
dependency (`require`, not a network hop) — so there is no Faraday client, no
`app/clients/`, no WebMock, and no VCR in the suite, and none belong here. The
gem is exercised directly through the service and request specs.

The moment a real external HTTP dependency is ever added (it isn't planned), the
rule returns in full: wrap it in a Faraday client class, block all real outbound
HTTP in the suite (WebMock), replay recorded interactions where useful (VCR), and
never record a secret into a cassette. Until then, this section is a placeholder,
not a description of anything in the repo.

---

## 6. Test Selectors — `data-testid` Mandatory

All interactive and conditionally-rendered elements get a `data-testid`
attribute. Tests target **these attributes, never CSS classes or DOM structure**
(classes change with styling; testids are a stable contract).

```erb
<%# ✅ CORRECT — test-stable selector %>
<button data-testid="delete-note-<%= note.id %>">Delete</button>
<div data-testid="empty-state" <%= "hidden" if notes.any? %>>No notes yet.</div>

<%# ❌ WRONG — fragile, breaks on restyle %>
<button class="btn btn-danger text-sm">Delete</button>
```

In Capybara, target the attribute directly:

```ruby
find('[data-testid="delete-note-1"]').click
expect(page).to have_css('[data-testid="empty-state"]')
```

A full feature spec (rack-test driver, no JS) drives the server-rendered flow
through those selectors:

```ruby
# spec/features/browsing_standards_spec.rb — no login: this app has no auth.
require "spec_helper"

RSpec.feature "Browsing the standards catalog", type: :feature do
  scenario "a user follows the navigation from a saved scan to the catalog" do
    scan = create(:scan)

    visit "/scans/#{scan.id}"
    find('a[href="/standards"]').click

    expect(page).to have_current_path("/standards")
    expect(page).to have_css('[data-testid="growth-standards"]')
    expect(page).to have_css('[data-testid="efw-formulas"]')
  end
end
```

Naming convention for `data-testid` values (use the real domain vocabulary):
- Containers: `growth-standards`, `efw-formulas`, `dating-methods`
- Items: `standard-{id}` (e.g. `standard-hadlock_1991_equation`), `scan-{id}`
- States: `empty-state`, `error-state`

---

## 7. Background-Job Testing

By default the template ships **no background-job system** — domain work runs
inline inside the service object during the request. Because SQLite allows **one
writer at a time**, keep those transactions short and never fan out parallel
writes (see `.claude/database.md`). There is no ActiveJob.

If you genuinely need durable async work, adopt **Sidekiq** (Redis); for light,
non-durable async a thread pool or `sucker_punch` is the small-scale option. Do
not pretend Solid Queue exists. When you do run jobs, assert three things:
**(a) it gets enqueued** with the right args (including account/tenant id),
**(b) idempotency** — running twice produces the same result with no duplicate
side effects, **(c) error handling** — a malformed payload or missing record
returns/raises as designed.

### Sidekiq — `[stable]`

Framework-agnostic. Use
[`Sidekiq::Testing`](https://github.com/sidekiq/sidekiq/wiki/Testing).

| Mode                      | Behavior                                              | Use for                          |
|---------------------------|-------------------------------------------------------|----------------------------------|
| `Sidekiq::Testing.fake!`  | Jobs pushed onto a `jobs` array, **not executed**     | Asserting enqueue without effects |
| `Sidekiq::Testing.inline!`| Jobs execute **synchronously** when enqueued          | Asserting full job effect end-to-end |

```ruby
require "sidekiq/testing"

it "enqueues the processor with the account id" do
  Sidekiq::Testing.fake! do
    Notes::Publish.call(account:, note:)
    expect(WebhookProcessorWorker.jobs.size).to eq(1)
    expect(WebhookProcessorWorker.jobs.last["args"]).to eq([account.id, note.id])
  end
end

it "is idempotent" do
  args = [account.id, asset.id]
  expect { WebhookProcessorWorker.new.perform(*args) }.not_to raise_error
  expect { WebhookProcessorWorker.new.perform(*args) }  # second run, same result
    .not_to change { MediaAsset.with_pk!(asset.id).provider_status }
end

it "raises on a missing record" do
  expect { WebhookProcessorWorker.new.perform(0, 0) }
    .to raise_error(Sequel::NoMatchingRow)
end
```

---

## 8. Required Coverage

For every new feature, ALL applicable categories below are required before it is
considered complete.

### Models / data objects (`Scan`)
- Valid attrs → valid
- Missing required fields → invalid with the expected error (`validation_helpers`
  `validates_presence` on `ga_days`/`scanned_on`)
- Out-of-range / non-positive values → invalid (`ga_days` in `0..350`, each
  measurement `> 0`)
- Each **dataset method** returns the right set — `recent` ordering, and `page`
  clamped (`per` to `1..100`, page number to `1..10_000`)

> This app has no unique constraints and no soft delete on `Scan`. If a model
> ever grows either, add the matching checks (a `validates_unique` /
> `Sequel::UniqueConstraintViolation` case; a soft-delete dataset that excludes
> `deleted_at`-set rows by default, with a `with_deleted` variant).

### Services / business logic
- Happy path — returns `Success(...)`
- **Every error path** — each `Failure([:tag, ...])` return (e.g. the create
  service's `[:validation, errors]` and `[:error, message]`)
- Edge cases (empty, nil, boundary values; hostile Rack params — an array/hash
  where a String is expected must degrade to a validation failure, never a 500)

> Authorization and tenant-isolation categories do **not** apply here — this app
> has no accounts, users, or policy objects. If it ever grows them, they become
> required (an authorized actor succeeds, an unauthorized one is denied; an actor
> in account A can never read or mutate account B's rows — the highest-value
> category once tenancy exists).

A service spec exercising the happy path and an error path:

```ruby
# spec/services/scans/create_spec.rb
require "spec_helper"

RSpec.describe Scans::Create do
  describe ".call" do
    it "creates a scan from valid form params (happy path)" do
      result = described_class.call(
        "ga" => "32w0d", "bpd" => "81", "hc" => "296", "ac" => "279", "fl" => "61"
      )

      expect(result).to be_success
      expect(result.value!).to be_a(Scan)
      expect(Scan.count).to eq(1)
    end

    it "returns a tagged Failure on an unparseable GA (nothing persisted)" do
      result = described_class.call("ga" => "not-a-ga")

      expect(result).to be_failure
      expect(result.failure.first).to eq(:validation)
      expect(result.failure.last).to have_key(:ga)
      expect(Scan.count).to eq(0)
    end

    it "treats a hostile array param as unsupplied, not a 500" do
      result = described_class.call("ga" => "32w0d", "bpd" => ["1"])

      expect(result).to be_failure   # bpd degrades to a validation failure
    end
  end
end
```

### Request specs (every route)
- Each route's success response (status + body/redirect)
- Validation errors re-rendered (the `POST /scans` form re-renders with `422`)
- Not-found paths — unknown and non-canonical ids (`01`, `0x10`, `08`) → honest
  `404` (JSON body on `.json`, HTML page elsewhere)

```ruby
# spec/requests/scans_spec.rb
require "spec_helper"

RSpec.describe "Scans", type: :request do   # drives App via Rack::Test (def app = App)
  describe "POST /scans" do
    it "creates a scan and redirects to its report" do
      post "/scans", "ga" => "32w0d", "bpd" => "81", "hc" => "296",
                     "ac" => "279", "fl" => "61"

      expect(last_response.status).to eq(302)
      follow_redirect!
      expect(last_response.status).to eq(200)
    end

    it "re-renders the form with 422 on invalid input" do
      post "/scans", "ga" => ""

      expect(last_response.status).to eq(422)
    end
  end

  describe "GET /scans/:id" do
    it "404s a non-canonical id" do
      get "/scans/08"
      expect(last_response.status).to eq(404)
    end
  end
end
```

### Feature specs (server-rendered flows)
- Capybara rack-test driver, no JS (there is no client JS beyond the theme
  toggle, so there are no `:js` specs)
- Drive a real multi-page flow through `data-testid` selectors — e.g. save a
  scan, read its report, navigate to the catalog

### Job specs (only if Sidekiq is ever adopted)
- Happy-path processing, idempotency (run twice → same result), error handling
  (malformed payload, missing record). None apply today — the app ships no jobs.

## 9. CI Gates

All must pass before merge/deploy. Run the fast suite locally before every
commit.

```bash
bundle exec rspec --tag ~js               # fast: unit + request + rack-test feature specs
bundle exec rspec --tag js                # browser specs (separate CI job; needs Chrome)
bundle exec rubocop                       # style + lint (add rubocop-sequel, rubocop-rspec)
bundle exec bundler-audit check --update  # dependency CVE scan
bundle exec erb_lint --lint-all           # ERB lint (optional)
```

| Gate           | Gem / tool                                                              | Scope     | Maturity   |
|----------------|-------------------------------------------------------------------------|-----------|------------|
| Tests          | [rspec](https://rspec.info/) `~> 3.13`                                   | Sinatra   | [stable]   |
| Rack integration | [rack-test](https://github.com/rack/rack-test) `~> 2.2`               | Sinatra   | [stable]   |
| Feature / E2E  | [capybara](https://github.com/teamcapybara/capybara) `~> 3.40`          | Sinatra   | [stable]   |
| Factories      | [factory_bot](https://github.com/thoughtbot/factory_bot) `~> 6.5`       | Sinatra   | [stable]   |
| Lint/style     | [rubocop](https://github.com/rubocop/rubocop) `~> 1.65`                 | Sinatra   | [stable]   |
| CVE audit      | [bundler-audit](https://github.com/rubysec/bundler-audit) `~> 0.9`      | Sinatra   | [stable]   |
| ERB lint       | [erb_lint](https://github.com/Shopify/erb_lint) `~> 0.5`                | template  | [optional] |

Notes:
- **Brakeman is Rails-aware** — it follows Rails routing/views and cannot map a
  modular Sinatra/Rack app, so its value here is limited. Rely on `rubocop`
  (with `rubocop-sequel` + `rubocop-rspec`), `bundler-audit`, and review;
  reach for Semgrep as an optional static analyzer if you need one.
- The test DB is disposable: `spec_helper` migrates it fresh each run, so no
  seeding gate is required.
- Run the suite, lint, and CVE gates green before any deploy. In production the
  schema is applied by a one-off `rake db:migrate` gate before traffic switches
  (see `.claude/deployment.md` and `.claude/database.md`). `main` is always
  releasable.

<!-- BEGIN MANAGED AGENT WORKFLOW -->
Shared native agent workflow version 2.0.0 applies to every behavior
change. This section supersedes legacy workflow, role-assignment, and blanket
test-edit approval instructions only. Preserve domain, privacy, coverage,
static-analysis, deployment, and project constraints. Follow [.docs/agent-workflow.md](.docs/agent-workflow.md) for role ownership,
red → accepted tests → implementation → green → independent review.
Accepted tests are a contract: only the test writer changes them when the
expected behavior changes, with renewed review. Never weaken tests to pass.
The orchestrator coordinates the pipeline. This hook restricts only direct source
and test edits; other files, tools and commands retain ordinary native permissions.
Do not use alternate editing routes to evade the source/test ownership workflow.
<!-- END MANAGED AGENT WORKFLOW -->
