# Security

## Reporting a vulnerability

Report suspected vulnerabilities privately to the maintainer
(jeffreybaird@hey.com) — do not open a public issue for a security problem.
Include steps to reproduce and the affected route or component. You'll get an
acknowledgement and a fix or mitigation timeline.

## Data-handling posture

**Consensus holds no real patient data.** Every `patient_ref` is a synthetic
label entered by a user, and that is a permanent property of the app, not a
temporary state. Because of it:

- `patient_ref` MAY appear in logs and telemetry today.
- All clinical values are recomputed on view from the `biometry` gem and are
  **never stored**. The database persists only the raw inputs a user typed
  (measurements, gestational age, optional synthetic labels).

## Application security baseline

- **Output escaping.** ERB is HTML-escaped by default (`set :erb,
  escape_html: true`, backed by `erubi`). Do not disable it per-template without
  a reviewed reason.
- **Sessions.** Signed with `SECRET_KEY_BASE` (`openssl rand -hex 64`), read via
  `ENV.fetch`. Never commit a real secret; dev/test load it from an untracked
  `.env` via `dotenv`, prod injects it over SSH at deploy time.
- **Input boundary.** Rack params can arrive as arrays or hashes; services coerce
  any non-String input to `nil` so a hostile param becomes an ordinary validation
  failure, never a 500 or an injection. Scan ids are matched against a strict
  canonical-decimal regex before use.
- **SQL.** All persistence goes through Sequel datasets and model methods — no
  string-interpolated SQL.
- **Secrets.** `ENV.fetch` only. No secrets in source, cloud-init, or metadata;
  deploy-time secrets travel over SSH (`.env`, `umask 077`, never committed).

## Infrastructure

- The droplet firewall keeps SSH closed to the world; the deploy pipeline
  punches a temporary `/32` hole for the runner and revokes it in an `always()`
  step. A Terraform apply wipes any leaked rule as drift.
- Infrastructure changes go through the Terraform roots in [`infra/`](infra/)
  only — never the DigitalOcean console.
- Dependency audit: run `bundler-audit` as part of pre-commit checks.

## Scope

This app has no authentication, authorization, users, accounts, payments, or
external HTTP services — those modules were deliberately removed (see
[`CLAUDE.md`](CLAUDE.md)). The `biometry` gem is an in-process path dependency,
not a network service. If any of these are added, the corresponding `.claude/`
rules (authentication, authorization policies, idempotency, webhook signature
verification) apply in full from the first line.
