# store.nvim — Sort by Downloads

## What This Is

A new sorting strategy for store.nvim that lets users sort the plugin list by install count ("Most Downloads"), powered by telemetry data from the store.nvim.telemetry Cloudflare Worker backend. The backend already exists and exposes `GET /stats` returning per-plugin view and install counts.

## Core Value

Users can discover popular plugins by sorting the list by real install data — the one metric that reflects actual community adoption rather than GitHub stars.

## Requirements

### Validated

<!-- Shipped and confirmed valuable — existing capabilities. -->

- ✓ Plugin browsing with 5,500+ plugins — existing
- ✓ Sorting by stars, recently updated, recently created, installed — existing
- ✓ Filtering by name, tags, author — existing
- ✓ Live README preview via markview.nvim — existing
- ✓ Smart caching of plugin database — existing
- ✓ Telemetry tracking of view/install events — existing
- ✓ Telemetry backend with `GET /stats` endpoint returning install counts — existing

### Active

- [ ] Fetch telemetry stats on Store open (single request, cached for session)
- [ ] Add "Most Downloads" sort strategy to sort.lua
- [ ] Wire install counts into the sort comparator
- [ ] Handle plugins with no telemetry data gracefully (sort to bottom)

### Out of Scope

- Backend changes — telemetry API already returns what we need
- "Sort by Views" — user specified installs only
- Persistent cross-session caching of stats — session-only cache is sufficient
- Displaying download counts in the UI — just sorting, not showing the number

## Context

- The telemetry backend is a Cloudflare Worker + D1 at `https://store-nvim-telemetry.alex-popov-tech.workers.dev`
- `GET /stats` returns `{ stats: [{ plugin_full_name, views, installs }] }` sorted by installs DESC
- The Neovim client already has `lua/store/telemetry.lua` that POSTs events to the same backend
- Existing sorts live in `lua/store/sort.lua` — each is a `{ label, fn }` entry
- Sort comparators receive `(a, b, installed_items)` — third param is context data
- Stats fetch should happen alongside the existing `database.fetch_plugins()` call in the modal open flow
- The `StoreModal` state object holds all runtime data — stats would be added there

## Constraints

- **Telemetry opt-in**: Stats fetch should respect the existing `config.telemetry` flag — if telemetry is disabled, this sort should either be hidden or gracefully degrade (no data → no sorting effect)
- **Performance**: Stats endpoint returns all plugins in one response — must not block UI; use async callback pattern consistent with existing fetches
- **Backwards compatibility**: Existing sort types and their order must not change

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Installs only, not combined score | User preference — installs reflect actual adoption | — Pending |
| Fetch on Store open, cache for session | Avoid repeated API calls; data doesn't change fast | — Pending |
| Use existing telemetry opt-in flag | Consistent privacy model | — Pending |

---
*Last updated: 2026-03-12 after initialization*
