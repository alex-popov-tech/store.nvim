# Roadmap: store.nvim — Sort by Downloads

## Overview

A single focused integration: fetch install stats from the existing telemetry backend when the Store opens, then surface those counts as a "Most Downloads" sort strategy. All five requirements form one coherent delivery — the sort option is useless without the data fetch, and the data fetch serves no purpose without the sort.

## Phases

- [ ] **Phase 1: Sort by Downloads** - Fetch telemetry stats async on Store open and expose "Most Downloads" as a sort strategy

## Phase Details

### Phase 1: Sort by Downloads
**Goal**: Users can sort the plugin list by real install count from the telemetry backend
**Depends on**: Nothing (first phase)
**Requirements**: FETCH-01, FETCH-02, SORT-01, SORT-02, SORT-03
**Success Criteria** (what must be TRUE):
  1. "Most Downloads" appears as a selectable sort option when the Store opens
  2. Selecting "Most Downloads" orders plugins by install count descending, with plugins that have no telemetry data sorted to the bottom
  3. Selecting "Most Downloads" before stats have finished loading is a no-op — it does not crash, freeze, or produce errors
  4. A stats endpoint failure produces no visible error and all other sort strategies continue to work normally
**Plans:** 2 plans

Plans:
- [ ] 01-01-PLAN.md — Refactor sort comparator to context table + add Most Downloads sort entry
- [ ] 01-02-PLAN.md — Stats fetch pipeline from telemetry API + wire into modal lifecycle

## Progress

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Sort by Downloads | 0/2 | Not started | - |
