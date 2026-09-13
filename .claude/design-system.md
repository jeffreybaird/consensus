# Design System

> Filled in for Consensus — the "Reading room" direction, 2026-08-16. Token
> values are validator-checked; change them only with a re-run of the dataviz
> palette validator against both surfaces.

This file is the authoritative reference for all frontend work on Consensus. Read it before writing any template, partial, view, or CSS. Follow conventions already established in the codebase — discover before building.

> **Baseline:** Plain CSS served as a static file from `public/css/` · CSS custom properties for tokens · ERB partials for reusable components · ERB templates rendered by modular Sinatra. Tokens are CSS variables — overridable per tenant. Tailwind is **optional** (a standalone CLI build step, below).

**Maturity tags:** **[core]** apply to every project · **[recommended]** strong default, skip only with reason · **[optional]** include only if the app needs it.

---

## Identity — "Reading room"

`Consensus` is the web UI for the biometry gem: it shows where one fetal weight
estimate falls on each of the competing growth standards, side by side, for
clinically-literate users exploring the disagreement between standards.

Aesthetic: **instrument dark** — the register of an ultrasound console or a PACS
reading room. Near-black surfaces, high-contrast readouts, charts as the hero of
every screen, measurements displayed like machine values (large numeral, small
unit). The user should feel they are reading a precise instrument, not a
marketing page. A **dark theme is available as an explicit toggle**; the
default UI is light (near-white surfaces, the same token structure), and print
always forces light regardless of the active toggle.

Tone: precise, cited, unhurried. Not alarming, not reassuring — this interface
never renders a verdict (see CLAUDE.md clinical rules), so nothing in the visual
language may imply one: **no red/green on clinical values, no shading of chart
regions, no "normal range" affordances.** Red belongs to form and system errors
only.

---

## Stack **[core]**

| Concern | Sinatra |
|---|---|
| CSS delivery | Hand-authored CSS in `public/css/app.css`, served as a **static file** by Sinatra (`public/` is the static root). No asset pipeline, no fingerprinting by default. |
| Optional utility framework | **Tailwind via the standalone CLI binary** — no Node toolchain. Input `src/tailwind.css`, output `public/css/app.css` ([tailwindcss.com/blog/standalone-cli](https://tailwindcss.com/blog/standalone-cli)). Include only if the app wants utilities. |
| Build command | None by default (author CSS directly). With optional Tailwind: `./bin/tailwindcss -i src/tailwind.css -o public/css/app.css --watch` (dev), run alongside Puma via a `Procfile.dev`. |
| Reusable component | **ERB partial** in `views/components/`, rendered through a small helper on `App`. No ViewComponent gem — plain ERB + Ruby. |
| Template engine | ERB (`.erb`), rendered by Tilt via Sinatra's `erb` helper; layout `views/layout.erb`. |
| Client interactivity | Small **vanilla JS** in `public/js/`, progressive enhancement. No Hotwire/Turbo/Stimulus. |
| Icon set | `<e.g., inline SVG partials in views/components/icons/ / a downloaded SVG sprite>` |

- The default is **plain CSS you write and commit** — the file in `public/css/` is what ships; there is no compile step to forget. Reach for the optional Tailwind CLI only when a project genuinely wants utility classes.
- The standalone Tailwind CLI bundles v4 by default; pin the version you download so you know which directive set (`@theme` vs `tailwind.config.js`) applies.
- Font sources: `<Google Fonts / self-hosted under public/fonts/ / system only>`. Custom font upload: `<supported / not supported>`.

---

## Codebase Conventions — Discover Before Building **[core]**

Before creating any file, partial, or template, read the existing codebase to understand:

- How routes map to services and views (thin `get "/notes" do … end` blocks in `app.rb` / `app/routes/*.rb`), where partials live (`views/components/`), how `views/layout.erb` and shared partials are structured.
- Where CSS is served from (`public/css/app.css`) and, if the optional Tailwind CLI is in use, where its input lives and how the watcher is run.
- How authentication and the current-tenant lookup work — the `Current` module (`Current.user`, `Current.account`), set in a `before` filter — since per-tenant theming reads from it.

Follow existing conventions exactly. Do not introduce new organizational patterns unless none exists for the type of thing you are building.

---

## Color & Token System **[core]**

All design values — colors, surfaces, accents, type scale, radii, spacing accents — are **CSS custom properties**. Use semantic token names in templates and component CSS. Never write hardcoded hex/rgb/raw color in a template, partial, or CSS rule.

### Where tokens live

Define tokens once in a **base layer** at the top of `public/css/app.css`, then reference them everywhere via `var(--token)`. This file is the single source of truth and is served directly — no build step required.

```css
/* public/css/app.css */

/* 1. Base token layer — single source of truth */
:root {
  --bg:            oklch(98% 0 0);
  --surface:       oklch(100% 0 0);
  --elevated:      oklch(96% 0 0);
  --text-primary:  oklch(20% 0 0);
  --text-secondary:oklch(45% 0 0);
  --text-muted:    oklch(60% 0 0);
  --border:        oklch(90% 0 0);
  --accent:        oklch(55% 0.2 250);
  --accent-text:   oklch(99% 0 0);
  --radius:        0.5rem;
}

/* 2. Component classes resolve to tokens — never raw color */
.card   { background: var(--surface); color: var(--text-primary);
          border: 1px solid var(--border); border-radius: var(--radius); }
```

If you opt into the **optional Tailwind CLI**, expose the same tokens to utilities instead of (or alongside) hand-written classes — the tokens stay the single switch point:

```css
/* src/tailwind.css — Tailwind v4 (CSS-first, no tailwind.config.js) */
@import "tailwindcss";
@theme {
  --color-bg:           var(--bg);
  --color-surface:      var(--surface);
  --color-text-primary: var(--text-primary);
  --color-accent:       var(--accent);
  --radius-md:          var(--radius);
}
```

```js
// Tailwind v3 alternative — tailwind.config.js
module.exports = {
  content: ["./views/**/*.erb", "./public/js/**/*.js"],
  theme: { extend: { colors: {
    bg: 'var(--bg)', surface: 'var(--surface)',
    'text-primary': 'var(--text-primary)', accent: 'var(--accent)',
  } } }
}
```

### Surface scale (light default / dark theme)

| Token | Purpose | Dark (toggle) | Light (default + print) |
|---|---|---|---|
| `bg` | Page background | `#0d0d0d` | `#f9f9f7` |
| `surface` | Cards, panels, chart surface | `#1a1a19` | `#fcfcfb` |
| `elevated` | Inputs, dropdowns | `#232321` | `#ffffff` |
| `overlay` | Modals, popovers | `#2c2c2a` | `#ffffff` |

### Text scale

| Token | Purpose | Dark | Light |
|---|---|---|---|
| `text-primary` | Main readable text, readout numerals | `#ffffff` | `#0b0b0b` |
| `text-secondary` | Supporting text, citations | `#c3c2b7` | `#52514e` |
| `text-muted` | Metadata, axis labels | `#898781` | `#898781` |
| `border` | Hairline rings, dividers | `rgba(255,255,255,0.10)` | `rgba(11,11,11,0.10)` |

### Accent — fixed (single brand)

| Token | Purpose | Dark | Light |
|---|---|---|---|
| `accent` | Interactive elements, links, focus | `#3987e5` | `#2a78d6` |
| `accent-hover` | Hover state | `#5598e7` | `#256abf` |
| `accent-text` | Text on accent backgrounds | `#0d0d0d` | `#ffffff` |
| `accent-subtle` | Tinted accent background | `rgba(57,135,229,0.15)` | `rgba(42,120,214,0.10)` |

### Status — app mechanics ONLY, never clinical values

| Token | Purpose | Dark | Light |
|---|---|---|---|
| `success` | "Scan saved" confirmation | `#0ca30c` | `#006300` (text) |
| `error` | Form/system errors, destructive confirm | `#d03b3b` | `#d03b3b` |

No `warning` token: this app has no warning states, and a yellow near clinical
data reads as a verdict. Status colors always pair with an icon + text — never
color alone — and are **never applied to a weight, percentile, curve or chart
region**. There is no token for "abnormal" and none may be added.

### Chart tokens (validated with the dataviz palette validator)

Standard identity — fixed assignment, used for table row markers and catalog
chips; wherever a standard's identity is colored, it is this hue, and the
assignment never re-flows when a chart is missing. Note the curves inside a
chart do NOT use these: every chart's centile curves are the one ordinal blue
ramp below (order, not identity — the panel heading and chip identify the
standard):

| Token | Standard | Dark | Light |
|---|---|---|---|
| `series-intergrowth21` | INTERGROWTH-21st | `#3987e5` | `#2a78d6` |
| `series-hadlock-eq` | Hadlock 1991 (equation) | `#d95926` | `#eb6834` |
| `series-hadlock-tab` | Hadlock 1991 (table) | `#199e70` | `#1baf7a` |
| `series-who` | WHO | `#c98500` | `#eda100` |
| `series-nichd` | NICHD | `#d55181` | `#e87ba4` |

Validated (adjacent pairs, both surfaces): CVD ΔE ≥ 8.4, normal-vision ≥ 19.3,
all ≥ 3:1 on the dark surface. On the light surface three slots sit below 3:1 —
the relief rule applies and is satisfied structurally: every colored marker
always sits beside its visible text label, and the growth table is always
present. Identity is never color-alone.

Centile curves within one chart are **ordered, not categorical** — one blue
ramp light→dark with direct labels (P3…P97) at the curve ends; the ramp step
carries the order, the label carries the identity:

| Token | Centile | Dark | Light |
|---|---|---|---|
| `centile-1` (lightest) | outermost high (e.g. P97) | `#b7d3f6` | `#86b6ef` |
| `centile-2` | | `#6da7ec` | `#5598e7` |
| `centile-3` (median, 2px) | P50 | `#3987e5` | `#2a78d6` |
| `centile-4` | | `#256abf` | `#1c5cab` |
| `centile-5` (darkest) | outermost low (e.g. P3) | `#184f95` | `#0d366b` |

Validated as ordinal ramps in both modes (monotone lightness, adjacent ΔL ≥
0.06, near-surface end ≥ 2:1). Charts with more published centiles (WHO's nine)
reuse steps symmetrically around P50 with direct labels doing the work.

Chart chrome: `gridline` `#2c2c2a` / `#e1e0d9` (hairline), `axis` `#383835` /
`#c3c2b7`. The plotted point is **`text-primary` ink with a 2px `surface` ring
and a fine crosshair** — maximum contrast, no hue, so the reader's point never
borrows a color that could read as a verdict.

```erb
<%# ✅ semantic token-backed class (defined in public/css/app.css) %>
<div class="card">…</div>

<%# ✅ same intent with optional Tailwind utilities resolving to the same tokens %>
<div class="bg-surface text-text-primary border border-border rounded-md">…</div>

<%# ❌ hardcoded color bypasses theming and per-tenant override %>
<div style="background:#1a1a1a;color:#fff;border-radius:12px">…</div>
```

Per-tenant brand overrides are documented in `.claude/theming.md` — the same `:root` variables are re-tinted at render time (a small `<style>` block driven by `Current.account`), so token-based components re-brand for free.

---

## Typography **[core]**

Define a small set of semantic font roles as CSS variables. Collapse roles you don't use.

| Role | Variable | Purpose |
|---|---|---|
| Body / UI | `--font-ui` | everything: nav, prose, labels, forms — `system-ui, -apple-system, "Segoe UI", sans-serif` |
| Mono | `--font-mono` | measurement readouts, GA strings, chart axis ticks — `ui-monospace, "SF Mono", Menlo, monospace` |

No display or serif face; the instrument register comes from the mono readouts
and the dark surfaces, not a typeface. Numeric columns (growth table, axis
ticks) set `font-variant-numeric: tabular-nums`. Readout values are large
(`1.5–2rem`) with the unit small (`0.75em`, `text-secondary`) beside them.

- Always declare **system fallbacks** in the variable default.
- Body: line-height 1.6, 1rem minimum; citations may drop to 0.875rem `text-secondary`, never below.
- For external fonts, put `dns-prefetch` + `preconnect` + `preload as="style"` in `views/layout.erb` before the stylesheet `<link>`; provide a `<noscript>` fallback. Self-hosting under `public/fonts/` avoids the extra origin entirely. Avoid render-blocking.

---

## Components **[core]**

### ERB partials (reusable UI)

Use an **ERB partial** for any UI element reused across views, or any element with non-trivial variants. Partials live in `views/components/` and are rendered through a thin helper registered on `App`, keeping call sites terse and the class/variant logic in one place. Pass data in as **locals** — never query or branch on request state inside the partial.

```ruby
# app/helpers/component_helpers.rb
module ComponentHelpers
  BUTTON_VARIANTS = {
    primary: "btn--primary",
    ghost:   "btn--ghost",
  }.freeze

  def button_component(label:, variant: :primary, type: "button", **attrs)
    erb :"components/button", layout: false, locals: {
      label:         label,
      type:          type,
      variant_class: BUTTON_VARIANTS.fetch(variant),
      attrs:         attrs,
    }
  end
end
```

```ruby
# app.rb
class App < Sinatra::Base
  helpers ComponentHelpers
  # …
end
```

```erb
<%# views/components/button.erb — pure presentation, no logic %>
<button type="<%= type %>" class="btn <%= variant_class %>"
  <%= attrs.map { |k, v| %(#{k}="#{Rack::Utils.escape_html(v.to_s)}") }.join(" ") %>>
  <%= label %>
</button>
```

```erb
<%# call site %>
<%= button_component(label: "Save changes", variant: :primary, type: "submit") %>
```

- Use a **plain partial** (`erb :"components/badge", layout: false, locals: { … }`) for simple, logic-free fragments.
- Promote to a **helper-backed partial** (as above) when there are variants, conditional classes, or attribute plumbing worth naming once.
- Every behavior-bearing component ships with a test — exercise it through a Capybara feature spec that renders a view using it, selecting by `data-testid`. See `.claude/testing.md`. Per CLAUDE.md, every addition that adds behavior ships with a test.

---

## Semantic HTML over ARIA **[core]**

Use the right element; let the browser supply roles, focus, and keyboard handling for free. Sinatra hands you plain HTML — write real elements.

```erb
<%# ✅ real interactive elements %>
<a href="/orders/<%= order.id %>">View order</a>
<button type="button" data-testid="edit-order" data-modal-open="edit">Edit</button>

<%# ✅ a destructive action is a real <form> + <button>, not a link %>
<form method="post" action="/orders/<%= order.id %>">
  <input type="hidden" name="_method" value="delete">
  <button type="submit">Delete</button>
</form>

<%# ❌ click handler on a non-interactive element — no keyboard, no role %>
<div data-modal-open="edit">Edit</div>
<span onclick="…">Delete</span>
```

- Never put a click handler on `<div>`/`<span>`. Use `<button>`, `<a href>`, or a real `<form>` submit.
- State-changing actions (delete, publish) go through `<form method="post">`; use a hidden `_method` field for `PATCH`/`PUT`/`DELETE` — `Rack::MethodOverride` (enabled on `App`) rewrites the verb. Never mutate state on a `GET`.
- Use `<nav>`, `<main>`, `<header>`, `<footer>` for landmarks. Active nav links get `aria-current="page"`.
- See MDN for `<button>` vs `<a>` semantics ([developer.mozilla.org/en-US/docs/Web/HTML/Element/button](https://developer.mozilla.org/en-US/docs/Web/HTML/Element/button)).

---

## Animation **[core]**

- **Only animate `transform` and `opacity`.** Never animate layout properties (width, height, margin, padding, top, left) — they trigger reflow.
- Asymmetric timing: enter slightly faster than exit.
- **Respect `prefers-reduced-motion: reduce` — non-negotiable for WCAG 2.1 AA.** Disable transitions/animations globally:

```css
@media (prefers-reduced-motion: reduce) {
  *, *::before, *::after {
    animation-duration: 0.01ms !important;
    animation-iteration-count: 1 !important;
    transition-duration: 0.01ms !important;
    scroll-behavior: auto !important;
  }
}
```

- Loading skeletons use a shimmer keyframe; their outer dimensions must match the loaded element.
- Drive show/hide from small vanilla JS in `public/js/` (a `data-*` hook wired on `DOMContentLoaded`) or, where possible, CSS-only `:target` / `<details>` — keep logic out of templates.

---

## Iconography **[core]**

- **Icon-only controls must have an accessible name** — `aria-label` on the `<button>`/`<a>`. Decorative icons get `aria-hidden="true"`.
- Default size `<e.g., 1.25rem (20px), class="icon">`; compact `<1rem, class="icon icon--sm">`; emphasis `<1.5rem, class="icon icon--lg">`.

```erb
<%# ✅ %><button type="button" aria-label="Close" data-modal-close><svg class="icon" aria-hidden="true">…</svg></button>
<%# ❌ %><button type="button"><svg class="icon">…</svg></button>
```

---

## Contrast & Forms **[core]**

- Text ≥ **4.5:1**, large text ≥ 3:1, UI boundaries ≥ 3:1 ([w3.org/WAI/WCAG21/quickref](https://www.w3.org/WAI/WCAG21/quickref/)). Never convey info by color alone.
- Every input has a linked `<label>` — plain HTML: `<label for="email">Email</label><input id="email" name="email">`. Errors via `aria-describedby`. Required fields marked.
- Touch targets ≥ 44×44 CSS px. Flash/loading regions use `aria-live`.

---

## Dark Mode + Theme Switch **[recommended]**

**Consensus is light by default**: `:root` carries the light values,
`[data-theme="dark"]` overrides with the dark column, and `@media print`
forces the light values unconditionally regardless of the active toggle. The
snippet below shows the mechanism with light-default, matching this app.

Theme selection is a **`data-theme` attribute on `<html>`** plus CSS-variable blocks — not a hardcoded class toggle. This keeps tokens as the single switch point and composes cleanly with per-tenant brand overrides (see `.claude/theming.md`).

```css
:root,
[data-theme="light"] { --bg: oklch(98% 0 0); --text-primary: oklch(20% 0 0); }
[data-theme="dark"]  { --bg: oklch(18% 0 0); --text-primary: oklch(96% 0 0); }

/* follow OS preference until the user explicitly chooses */
@media (prefers-color-scheme: dark) {
  :root:not([data-theme]) { --bg: oklch(18% 0 0); --text-primary: oklch(96% 0 0); }
}
```

Persist the choice in `localStorage` with a small vanilla JS file served from `public/js/`:

```js
// public/js/theme.js
(() => {
  const root = document.documentElement;
  const saved = localStorage.getItem("theme");
  if (saved) root.setAttribute("data-theme", saved);

  document.addEventListener("click", (e) => {
    if (!e.target.closest("[data-theme-toggle]")) return;
    const next = root.getAttribute("data-theme") === "dark" ? "light" : "dark";
    root.setAttribute("data-theme", next);
    localStorage.setItem("theme", next);
  });
})();
```

```erb
<%# views/layout.erb: load once, defer so it never blocks render %>
<script src="/js/theme.js" defer></script>

<button type="button" data-theme-toggle aria-label="Toggle dark mode">…</button>
```

---

## Design Tokens & Tone **[core]**

### Spacing & layout
- Base unit: 4px scale (`0.25rem` increments). Max content width: `72rem`; chart
  pages may go full-width. Page padding: `1rem` mobile / `2rem` desktop.
- Radius: `0.375rem` on cards and inputs; charts are square-cornered (instrument).
- Print stylesheet forces the light theme (`@media print` re-declares the light
  token values), hides nav/actions, one chart per page.

### Components inventory
- **Readout** — a measurement or result: large mono value, small unit, label
  above in `text-muted`. Never colored by its value.
- **Growth table** — the hero of the scan page: one row per chart reading,
  standard marker (`series-*` chip) + name, weight ±SD, percentile, type,
  formula inputs, citation footnote mark. Refusal rows render the reason
  sentence in `text-secondary` where the numbers would be — same row height,
  visibly quieter, never yellow/red.
- **Chart panel** — SVG chart + caption (standard, citation, variant note) +
  known-issues `<details>` disclosure. `role="img"` with an `aria-label`
  naming standard, centiles and the plotted point; the growth table is the
  accessible/data alternative.
- **Card / Button** — standard variants: primary (accent), secondary (hairline
  border), destructive (error, confirm step). Always `<button>`/`<a>`/real form;
  icon-only needs `aria-label`.

### Tone of voice
- Principles: precise, cited, calm. Say what the number is and where it came
  from; never what it means clinically.
- Error copy: explain what happened + what to do. Surface service-object
  `Failure([:tag, …])` results as human sentences, not tags. Gem refusals are
  *content*, not errors — render them in place, in the standard's row/panel.

| Situation | ❌ Don't | ✅ Do |
|---|---|---|
| Chart refusal | "Error: out_of_range" | "NICHD covers 15–40 weeks; this scan is at 13w2d." |
| Missing measurement | "Invalid input" | "Hadlock needs BPD, HC, AC and FL; this scan has no FL." |
| Form validation | "Invalid GA" | "Gestational age reads as weeks and days, like 32w0d." |

- Empty states: every list surface has one — plain, with the create action.
- Buttons: verbs ("Save scan", "New scan"); sentence case; no "click here".

---

## Absolute Rules — Never Violate **[core]**

- Never use hardcoded hex/rgb/raw color in templates or CSS rules — always semantic tokens.
- Never put click handlers on `<div>`/`<span>` — use `<button>`, `<a href>`, or a real `<form>` submit.
- Never mutate state on a `GET`; state-changing actions use `<form method="post">` (+ hidden `_method`).
- Never ship an icon-only control without `aria-label`.
- Never animate layout properties; never skip `prefers-reduced-motion`.
- Never remove focus outlines without a visible replacement.
- Never use placeholder-only labels — always a visible `<label>`.
- Never put business logic (Sequel queries, `Current`/policy checks) in a partial or ERB view — resolve it in the route/service and pass it in as locals.
- Never apply color, iconography or emphasis that implies a clinical verdict:
  no red/green/amber on weights or percentiles, no shaded "normal" chart
  regions, no threshold lines, no warning glyphs beside values. (CLAUDE.md
  clinical rules; the gem property-tests the payloads, the UI must not
  reintroduce a verdict by stylesheet.)
- Never render a clinical number without its citation reachable on the same
  surface.
- Never let a chart curve color double as a status color; `series-*` and
  `centile-*` tokens are identity/order only.
- Print always uses the light theme; never ship a page whose chart is
  illegible on paper.
</content>
</invoke>
