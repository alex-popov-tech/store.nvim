# Codebase Concerns

**Analysis Date:** 2026-03-12

## Tech Debt

**Large monolithic component files:**
- Issue: Core UI components exceed 600 lines (list 649L, preview 420L, heading 363L), making testing and modification difficult
- Files: `lua/store/ui/list/init.lua` (649 lines), `lua/store/ui/preview/init.lua` (420 lines), `lua/store/ui/heading/init.lua` (363 lines)
- Impact: Changes to one concern (e.g., rendering) require touching state management and event handling code in same file; harder to test isolated functionality
- Fix approach: Extract rendering logic into separate modules; move state management into focused state handlers; create focused test suites for each concern

**Monolithic utility module:**
- Issue: `lua/store/utils.lua` is 782 lines containing unrelated concerns (URL handling, plugin detection, window setup, filtering, sorting, caching, buffering)
- Files: `lua/store/utils.lua`
- Impact: Difficult to navigate; high risk of unintended side effects when modifying utilities; hard to determine what functions are safe to change
- Fix approach: Split into focused modules: `utils/url.lua` (URL opening/validation), `utils/plugins.lua` (plugin detection), `utils/ui.lua` (window/buffer operations), `utils/data.lua` (filtering/sorting), `utils/cache.lua` (cache operations)

**Bundled Plenary utilities:**
- Issue: Plugin ships with copies of Plenary modules (path, curl, job, scandir, bit) rather than depending on plenary directly
- Files: `lua/store/plenary/*.lua` (948 lines for path.lua alone, 678 for job.lua, 620 for scandir.lua)
- Impact: Multiple TODOs in bundled plenary code never get addressed; maintenance burden if plenary API changes; code duplication if user has plenary separately; plenary has Windows path support issues (path.lua:319 TODO)
- Fix approach: Add plenary.nvim as explicit dependency; remove bundled copies; update imports to require from plenary

## Callback Timing Issues

**Potential race condition during modal close:**
- Issue: Multiple concurrent callbacks (`fetch_plugins`, `get_installed_plugins`, `get_readme`, `get_doc`) can fire after modal closes; code attempts to guard with `is_closing` flag but protection is incomplete
- Files: `lua/store/ui/store_modal/init.lua` (line 48, 164), `lua/store/ui/store_modal/event_handlers.lua` (line 74), `lua/store/database/init.lua` (callback handlers)
- Symptoms: Callbacks try to access modal components or state that no longer exist; errors trying to render to closed windows; memory leaks if callback holds references to freed resources
- Trigger: Open store modal, start fetching (multiple network requests), close modal immediately before responses arrive
- Workaround: Wait for network requests to complete before closing
- Example: Line 74 in event_handlers checks `is_closing` but only after error occurs; by then component may already be attempting render operations

**Missing buffer/window validity checks in callbacks:**
- Issue: Several callback functions update UI without validating window/buffer still exists before render operations
- Files: `lua/store/ui/store_modal/event_handlers.lua` (on_db, on_installed_plugins, on_focus_change), `lua/store/database/init.lua` (cache.save_readme via vim.schedule)
- Impact: Errors attempting to write to deleted buffers; error messages in user logs; potential Neovim crashes if vim.api calls on invalid windows
- Fix approach: Add guard checks before rendering: `vim.api.nvim_buf_is_valid(buf_id)` before `nvim_buf_set_lines`, `vim.api.nvim_win_is_valid(win_id)` before window operations; check `is_closing` state before proceeding

**Incomplete error recovery in cascading callbacks:**
- Issue: Database fetch has nested callbacks (HEAD check → GET if stale); if callback 1 fails, callback 2 doesn't have context about original request; error messages may be misleading
- Files: `lua/store/database/init.lua` (lines 108-158 fetch_plugins with nested callbacks)
- Impact: Users see "Failed to fetch data" without knowing if it was HEAD validation step or actual download
- Fix approach: Wrap callbacks in context manager; pass through request metadata; add request ID for tracing

## Missing Test Coverage Gaps

**No integration tests for callback flow:**
- What's not tested: Multi-step async operations (HEAD → GET → save → render); race conditions during close; error handling in nested callbacks
- Files: No test files found in codebase for `lua/store/database/init.lua`, `lua/store/ui/store_modal/event_handlers.lua`
- Risk: Callbacks from network requests can crash modal or corrupt state; only discovered in production
- Priority: High

**No tests for plugin detection and installation:**
- What's not tested: Different plugin manager detection scenarios (none installed, multiple managers, misconfigured); installation path validation
- Files: No test files for `lua/store/utils.lua` plugin detection (lines 100-200 approx), `lua/store/actions.lua` install handler
- Risk: Silent failures when plugin managers not detected; incorrect installation paths; user data loss if paths are miscalculated
- Priority: High

**No error path validation:**
- What's not tested: JSON parsing failures, network timeouts, invalid cache files, truncated responses
- Files: `lua/store/database/cache.lua` (reading corrupted JSON), `lua/store/database/github_client.lua` (malformed responses)
- Risk: Uncaught errors in pcall blocks may mask real issues; cache corruption could require manual cleanup
- Priority: Medium

## Performance Bottlenecks

**Synchronous JSON decoding blocks UI:**
- Problem: `vim.json.decode()` called in HTTP response callbacks without scheduling to next tick
- Files: `lua/store/database/github_client.lua` (line 70), `lua/store/database/init.lua` (line 61)
- Cause: Large database JSON (potentially MB) parsed on callback thread; blocks Neovim event loop
- Improvement path: Use `vim.schedule()` to defer JSON parsing; show progress indicator to user while parsing

**No pagination for large plugin lists:**
- Problem: All plugins loaded into memory at once; entire list rendered even if only 20 visible
- Files: `lua/store/ui/list/init.lua` (renders full dataset; see line 44 full_dataset_cache)
- Cause: List component maintains full dataset in memory and renders all lines
- Impact: Performance degrades significantly with 5000+ plugins; startup time increases
- Improvement path: Implement virtual scrolling; render only visible lines; lazy-load dataset chunks

**Inefficient README processing:**
- Problem: HTML stripping and regex operations done character-by-character for every line
- Files: `lua/store/database/utils.lua` (lines 84-175 process_readme_content); multiple regex passes
- Cause: Pattern `:%match()` and `:gsub()` called on every line; no caching of compiled patterns
- Impact: 500-line README takes several milliseconds to process
- Improvement path: Pre-compile regex patterns; use single-pass processing; cache common HTML snippets

## Security Considerations

**URL validation is insufficient:**
- Risk: Regex in line 39 of `lua/store/utils.lua` may reject valid URLs or accept edge cases
- Files: `lua/store/utils.lua` (line 39 URL validation pattern)
- Current mitigation: Basic regex check for http/https and common URL chars
- Recommendations: Use `vim.uri.parse()` if available (Neovim 0.10+); handle special characters better; add tests for edge cases (URLs with fragments, query params, unicode domains)

**No validation of install paths:**
- Risk: User-configured `plugins_folder` path could point anywhere; could write plugins to `/etc` or other system paths
- Files: `lua/store/config.lua` (plugins_folder configuration), `lua/store/utils.lua` (get_plugins_folder)
- Current mitigation: None
- Recommendations: Validate path is within user's home or config directory; refuse to install outside nvim config; add path normalization to prevent `../` traversal

**Network requests expose User-Agent:**
- Risk: Requests include hardcoded `User-Agent: store.nvim` which identifies plugin and version
- Files: `lua/store/database/github_client.lua` (line 21), `lua/store/database/init.lua` (line 12)
- Current mitigation: None
- Recommendations: Consider privacy implications; document in README; allow User-Agent customization in config

## Fragile Areas

**Window/buffer lifecycle management:**
- Files: `lua/store/ui/store_modal/init.lua` (open/close methods), all UI component modules
- Why fragile: Components created in one module, destroyed in another; no centralized lifecycle manager; autocmds registered but cleanup depends on explicit close call
- Safe modification: Always validate window/buffer exists before accessing; add integration test for close sequence; verify all autocmds deleted on close
- Test coverage: No tests for window lifecycle; close behavior not validated

**Filter/sort interaction with displayed repos:**
- Files: `lua/store/ui/store_modal/init.lua` (state.currently_displayed_repos), `lua/store/actions.lua` (filter/sort operations), `lua/store/ui/list/init.lua` (renders displayed_repos)
- Why fragile: Filter and sort both modify same `currently_displayed_repos` array; no transaction/rollback mechanism; if render fails between filter and sort, state is inconsistent
- Safe modification: Implement copy-on-write for repo lists; separate read-only view from mutable state; test all filter→sort→render sequences
- Test coverage: No tests for combined filter+sort operations

**Cache file corruption recovery:**
- Files: `lua/store/database/cache.lua` (read operations lines 214-227, 257-270), `lua/store/database/init.lua`
- Why fragile: If cache file corrupted (partial write, truncation), `vim.json.decode()` fails silently; modal may not recover; no cache validation on read
- Safe modification: Add cache version header; validate JSON schema on load; fall back to fresh fetch if cache invalid; implement atomic writes (write to temp file, rename)
- Test coverage: No tests for corrupted cache scenarios

## Scaling Limits

**Memory consumption unbounded:**
- Current capacity: ~5000 plugins in-memory cache works fine; hitting issues reported at 10000+
- Limit: Each repository object stored fully in memory; with READMEs cached (100-200KB each), 10000 plugins = 1-2GB of RAM
- Scaling path: Implement lazy README loading; store only metadata in initial load; fetch README on-demand with LRU cache (keep last 50); periodically clear old cache entries

**Network timeout handling:**
- Current capacity: Single HEAD request timeout 5s, GET timeout 10s; works for <1MB databases
- Limit: Larger databases (>5MB) may timeout; no resume/retry for partial downloads
- Scaling path: Implement exponential backoff retry; add resume support using Range header; show user progress during fetch; allow user to cancel

## Dependencies at Risk

**Bundled Plenary code is unmaintained:**
- Risk: Plenary is still active project; changes in plenary.nvim may break bundled copies
- Impact: If user has newer plenary.nvim installed, conflicts possible; job.lua has memory leak warning (line 176 of job.lua mentions "memory leaking")
- Migration plan: Remove bundled copies; add explicit `plenary.nvim` dependency; update CI/tests to verify with latest plenary version

**No explicit dependency management:**
- Risk: Plugin depends on plenary features but doesn't declare dependency in plugin manager
- Files: Plugin spec should require `{"nvim-lua/plenary.nvim"}`
- Impact: Users must manually install plenary or plugin fails silently
- Recommendations: Add explicit dependency declaration; verify dependency in setup; warn user if plenary not found

## Known Limitations

**README rendering loses formatting:**
- Issue: HTML stripping in line 101 of database/github_client.lua converts `<img>` to `![](url)` but loses other HTML context
- Impact: Some READMEs with complex HTML structures display incorrectly
- Workaround: View repository on GitHub for full formatting

**GitLab support incomplete:**
- Issue: GitLab client has parallel URL builder to GitHub but may not handle GitLab-specific paths (subgroups, wiki)
- Files: `lua/store/database/gitlab_client.lua` (mirrors github_client structure)
- Impact: Some GitLab repos may not fetch README/docs correctly
- Recommendations: Test with real GitLab repos; add GitLab-specific path handling

**Database source hardcoded:**
- Issue: `config.data_source_url` points to single hardcoded gist; no fallback sources
- Files: `lua/store/config.lua` (data_source_url default)
- Impact: If gist goes down, plugin unable to function
- Recommendations: Support multiple database URLs; implement fallback chain; add local database option

---

*Concerns audit: 2026-03-12*
