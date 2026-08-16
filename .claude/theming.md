# Theming

> CSS-variable theming is universal; per-tenant theme loading is optional (include if multi-brand/multi-tenant).

Load this file when working on visual customization, template/layout selection, or branding configuration.

See also: `.claude/design-system.md` for token conventions, `.claude/database.md` for Sequel migrations and the single-writer SQLite constraint.

> **Baseline:** Plain CSS served as a static file from `public/css/app.css` · CSS custom properties for tokens · ERB partials for reusable components · ERB templates rendered by modular Sinatra (`class App < Sinatra::Base`). Tokens are CSS variables — overridable per tenant. No asset pipeline, no ViewComponent.

**Maturity tags:** **[core]** apply to every project · **[recommended]** strong default, skip only with reason · **[optional]** include only if the app needs it (e.g. multi-tenant / multi-brand).

---

## Approach — CSS variables are the single customization point **[core]**

Theming is **CSS custom properties** set from a stored theme configuration. Templates and partials consume those variables; they never hold hardcoded colors, fonts, or radii.

This gives you **one CSS file for every brand**. The only thing that changes per brand or tenant is the `:root` / `[data-theme]` variable block injected into the layout. No rebuild, no per-tenant stylesheet — `public/css/app.css` is served directly as a static file.

- **Single-brand apps:** write the variable block once, statically, in the base token layer at the top of `public/css/app.css` (see `.claude/design-system.md`).
- **Multi-brand / multi-tenant apps:** load values from a stored `Theme` row per tenant and server-render them into the layout at request time.

```erb
<%# ✅ component reads variables — re-brands for free %>
<style>.card { background: var(--surface); border-radius: var(--radius); color: var(--text-primary); }</style>

<%# ❌ hardcoded — bypasses theming, cannot be overridden per tenant %>
<style>.card { background: #1a1a1a; border-radius: 12px; }</style>
```

Layout properties (flex, grid, spacing, breakpoints) may be plain CSS. The variable rule applies only to **brand-customizable** properties: colors, fonts, radii, and similar identity values.

---

## Per-tenant theming — removed

This app is single-brand and single-tenant; the per-tenant theming, theme-schema
and asset-storage sections were removed with the optional modules. One brand,
one `:root` token block in CSS.

## Layout / template variants

One layout (`views/layout.erb`). Add variants only when a real second structure
exists (e.g. a print layout for charts), picked explicitly at render time.

### Template rules **[core]**

- Every variant implements the same required blocks. Unknown/missing name → the allowlist guard falls back to `default`.
- Templates control structure and layout only. **No business logic** — no Sequel queries, no Faraday/API calls, no `Current`/policy checks, no auth/subscription conditionals. That lives in the route/service; the template renders passed-in locals.
- All variants consume the same CSS custom properties for color and typography.

```erb
<%# ❌ business logic in a layout/template — Sequel query + Current in the view %>
<% if Current.user && Current.account.notes_dataset.any? %> … <% end %>

<%# ✅ route computed it; template just renders the passed-in local %>
<% if show_notes %> … <% end %>
```

---

## Absolute Rules — Never Violate **[core]**

- Never hardcode brand colors/fonts/radii in templates — read CSS variables.
- Never store binary asset data in SQLite — store object-store URLs (Litestream replicates the DB file; blobs slow every write).
- Never put business logic (Sequel queries, `Current`/policy checks, Faraday calls) in a layout/template variant.
- Never inject un-validated theme values into the inline `<style>` block — validate/whitelist color and URL fields on write. Sinatra's ERB does not auto-escape, and inside `<style>` escaping is not a sufficient defense; validation on write is.
- Ship one CSS file (`public/css/app.css`); per-tenant change is the `:root` variable block only.
