# Frontend Map

> Filled in for Consensus, 2026-08-16. When routes, ERB views, JS modules, or
> layouts change, update this file **in the same commit**.

Quick-reference for everything user-facing: which route calls which service,
renders which view, and hangs which `data-testid` hooks.

## Stack

- **Server:** modular Sinatra (`App` in `app.rb`), ERB views under `views/`,
  escape_html on. No Hotwire/Turbo/Stimulus.
- **CSS:** one hand-written token layer, `public/css/app.css` — the "Reading
  room" design system (`.claude/design-system.md`). Light default;
  `[data-theme="dark"]` opts in, `@media print` always forces light.
- **JS:** one vanilla module, `public/js/theme.js` (theme toggle persistence).
  Nothing else; charts are server-rendered SVG.
- **Domain:** the `biometry` gem via the boot-time `BIOMETRY` context; app
  services under `app/services/scans/` + `app/services/standards/names.rb`.

## Layout

`views/layout.erb` — head (css + deferred theme.js), `.site-header` (brand →
`/`, nav → `/standards`, `[data-theme-toggle]` button), `<main>` yield. One
layout; print styles hide nav/forms/buttons.

## Route → Service → View

| Route | Service(s) | View | Notes |
|---|---|---|---|
| `GET /up` | — | (json inline) | health |
| `GET /` | `Scan.recent`, `Scans::Options` | `scans/index.erb` | list + new-scan form; 422 re-render target |
| `POST /scans` | `Scans::Create` | redirect `/scans/:id` or `scans/index.erb` @422 | errors → `@errors` |
| `GET /scans/:id` | `Scans::Report`, `Scans::Chart` (per chart id) | `scans/show.erb` | readouts, growth table, chart panels, sources |
| `GET /scans/:id.json` | `Scans::Report` + gem `Report::Document` | (json inline) | envelope `{scan:, report:}` |
| `GET /scans/:id/charts/:standard` | `Scans::Chart` | `scans/chart.erb` | full-size panel; 404 unknown standard |
| `GET /standards` | `BIOMETRY.catalog` | `standards/index.erb` | citations, formulas, known issues |

Anything else → 404.

## Views / partials

| File | Renders |
|---|---|
| `scans/index.erb` | form (`new-scan-form`), errors, recent list, empty state |
| `scans/show.erb` | header readouts, `_growth_table`, chart panels, sources |
| `scans/_growth_table.erb` | one row per chart reading; refusal rows in place |
| `scans/_chart_panel.erb` | one standard's chart(s) or its refusal sentence |
| `scans/_chart.erb` | one ChartSeries → SVG + caption + known-issues details |
| `scans/chart.erb` | per-standard page wrapping `_chart_panel` |
| `standards/index.erb` | catalog: standards, formulas, dating, redating policy |

SVG geometry helpers live in `app.rb`'s `helpers do` block (`chart_view`,
`polyline_points`, `centile_class`, `chart_label`, `ga_axis_label`) — pure
presentation arithmetic; no clinical value is computed there.

## data-testid hooks (canonical list — tests target only these)

- `new-scan-form`, `form-errors`, `empty-state`, `scan-list`, `scan-{id}`
- `scan-ga`, `measurements`
- `growth-table`, `growth-row-{standard}` (`growth-row-nichd-{stratum}` when
  the four-chart spread renders), `refusal`
- `charts`, `chart-{standard}`, `chart-nichd-{stratum}`, `chart-point`,
  `chart-refusal`
- `sources`
- `growth-standards`, `standard-{id}`, `efw-formulas`, `formula-{id}`,
  `formula-{id}-requires`, `dating-methods`, `redating-policy`

## Rules carried from CLAUDE.md

No classification label may be rendered anywhere; every clinical number keeps
its citation on the same surface; refusals render in place. Authorization is
plain-Ruby policy objects in `app/policies/` — this app currently has none.
