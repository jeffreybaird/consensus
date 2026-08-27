# Contributing to Consensus

Read [`CLAUDE.md`](CLAUDE.md) first — it is the full rulebook, and this file is
the human-facing summary. Detail patterns live per-area under
[`.claude/`](.claude/). When a rule here and a rule in `CLAUDE.md` seem to
conflict, `CLAUDE.md` wins.

## Getting set up

See the [README](README.md#run-it-locally). In short:

```bash
bundle install
cp .env.example .env      # then set SECRET_KEY_BASE (openssl rand -hex 64)
bundle exec rake db:migrate
bundle exec rspec
bundle exec puma -C config/puma.rb   # http://localhost:4000
```

## The one rule that overrides convenience

**Every addition that adds behavior ships with a test that validates that
behavior.** No exceptions. A branch with no spec is an incomplete change.

## Tests are a contract

The suite is a ratchet — it only moves forward. See [`.claude/testing.md`](.claude/testing.md).

1. **Never modify an existing test to make it pass.** A previously-passing test
   that fails after your change means your change broke intended behavior. Fix
   the code, not the test. (Only exception: a deliberate, explicitly-stated
   behavior change.)
2. **Never weaken an assertion** to get to green.
3. **Never delete a test to resolve a failure** — flag it for discussion.
4. **Never change existing behavior to satisfy a new test** — add a new
   method/argument instead.
5. **Given a bug report**, write a failing spec for the expected behavior first,
   then fix the root cause. Don't take the shortest route around the error message.

### Spec ownership is enforced by a hook

Specs are owned by the `spec-writer` role. A `PreToolUse` hook
([`scripts/protect-tests.sh`](scripts/protect-tests.sh)) blocks any other agent
from writing to `spec/` — including redirects, in-place mutators, and inline
interpreters that target a spec path. If you need a spec changed and you are not
the spec-writer, **report the problem** rather than editing.

A `TaskCompleted` hook ([`scripts/gate.sh`](scripts/gate.sh)) runs the full
suite and blocks completion while it is red.

### Test layout & conventions

```
spec/requests/    Rack::Test against real routes
spec/features/    Capybara flows
spec/services/    service objects in isolation
spec/factories/   FactoryBot definitions
spec/support/     shared config + gem fixtures
```

- Each example runs in a transaction rolled back at the end (fast, isolated,
  single-writer-safe). Set up in [`spec/spec_helper.rb`](spec/spec_helper.rb).
- **Select by `data-testid`, never by CSS class.** A CSS class is a styling
  decision; using it as a selector couples tests to the stylesheet.
- The test DB is disposable and recreated from migrations before every run.

## Where code goes

Skinny routes; domain logic below them. See
[`.claude/separation-of-concerns.md`](.claude/separation-of-concerns.md).

| It is…                                              | It goes in…                          |
|-----------------------------------------------------|--------------------------------------|
| param parsing + one call + render                   | a route in `app.rb`                  |
| trivial CRUD / a query                              | a Sequel model method or dataset     |
| multi-model work, real side effects, or reused logic| a service object (`app/services/`)   |
| persistence + invariants                            | the Sequel model                     |
| a display name / number formatting                  | a helper or `Standards::Names`       |
| anything clinical                                   | **the gem** — never this app         |

A service object does **one** thing and exposes a single `#call`. If its
description needs an "and", split it. Don't manufacture a one-line service for a
trivial save.

## Failure handling

Expected, recoverable outcomes are **values**, not exceptions:

```ruby
Success(scan)
Failure([:validation, errors])
Failure([:not_found])
```

Use a tagged `dry-monads` Result when an operation has several distinct failure
modes or a future API must map them to HTTP. For simpler cases, `model.errors`
(with `raise_on_save_failure = false`) or a domain exception rescued at the
boundary is fine — just be consistent within a context, and **never** return a
bare boolean/`nil` where the caller must know *why* it failed. `raise` is for the
exceptional, not for control flow. Full taxonomy:
[`.claude/architecture-decisions.md`](.claude/architecture-decisions.md).

## Clinical rules (non-negotiable)

These are inherited from the gem and enforced here. A violation is a bug, not a
style nit.

- **No classification labels** — no SGA/LGA/IUGR/macrosomia/normal/abnormal, no
  threshold lines, no shaded zones. Anywhere.
- **Every number is cited** — surface the gem's provenance; a bare number is
  incomplete.
- **Refusals are content** — render the reason where the reading would be, never
  a blank row or empty chart. Use `Scans::Reason`.
- **No clinical constant in this app** — if the UI seems to need one, the gem is
  missing it. Stop and say so.

## Accessibility (WCAG 2.1 AA)

Every UI change must comply — a11y violations are bugs. Highlights (full list in
[`CLAUDE.md`](CLAUDE.md), audit with `/a11y-audit`):

- Semantic HTML over ARIA: a navigation is `<a href>`, a state change is a
  `<form method="post">` with a real `<button>` — never a click handler on a
  `<div>`/`<span>`.
- Keyboard-navigable, visible focus indicators (never remove an outline without
  a replacement).
- `aria-label` on icon-only controls; `aria-current="page"` on the active nav link.
- Contrast ≥ 4.5:1 (text); never convey info by color alone.
- Every `<img>` has `alt`; every input has a linked `<label for>`.
- Respect `prefers-reduced-motion`; touch targets ≥ 44×44 CSS px.

## Data honesty

This app holds **no real patient data** — every `patient_ref` is synthetic, which
is why it MAY appear in logs. If real data ever enters the system, that allowance
is revoked: redact `patient_ref` everywhere (grep for it) and apply the no-PII
rule in [`.claude/observability.md`](.claude/observability.md). See also
[SECURITY.md](SECURITY.md).

## Git workflow

Trunk-based. Work off `main`, short-lived branches, rebase frequently, **no merge
commits**. `main` is always releasable — every push to `main` deploys.

**Before every commit**, the checks must pass:

```bash
bundle exec rspec
# plus rubocop and bundler-audit where configured
```

No commit if checks fail.

**Atomic commits.** Each does one thing, contains only related changes, leaves
the tree in a working state, and is independently reviewable. Don't mix a refactor
with a behavior change; no "WIP"/"misc" commits.

**Message format:** `feat:`, `fix:`, `refactor:`, `test:` — and be specific.

```
feat: render a refusal reason in each chart panel
fix:  reject non-canonical scan ids (08, 0x10) with an honest 404
```

## Changing the vendored gem

`vendor/biometry` is a vendored copy of the private `../biometry` gem — the build
has no access to the source repo. After any gem change, re-sync and commit:

```bash
bin/vendor-biometry
```

Never edit `vendor/biometry` in place; the next sync overwrites it.

## Infrastructure

No infrastructure change outside [`infra/`](infra/). The Terraform roots own the
droplet, DNS, and state bucket — clicking it in the DigitalOcean console makes the
next `terraform apply` fight you. Secrets come from `ENV.fetch` (dev/test via
`dotenv`, prod via the deploy `.env` shipped over SSH) — never in source.
