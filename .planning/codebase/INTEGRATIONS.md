# External Integrations

**Analysis Date:** 2026-03-12

## APIs & External Services

**Plugin Database:**
- GitHub Releases (Crawler Service) - Hosts minified JSON database of Neovim plugins
  - SDK/Client: Custom curl wrapper (`lua/store/plenary/curl.lua`)
  - Endpoint: `https://github.com/alex-popov-tech/store.nvim.crawler/releases/latest/download/db_minified.json`
  - Purpose: Main database of 5,500+ plugins with metadata (stars, description, tags, README/doc paths)

**Package Manager Catalogues:**
- GitHub Releases (Crawler Service) - Plugin configs for specific package managers
  - Endpoint (lazy.nvim): `https://github.com/alex-popov-tech/store.nvim.crawler/releases/latest/download/lazy_db_minified.json`
  - Endpoint (vim.pack): `https://github.com/alex-popov-tech/store.nvim.crawler/releases/latest/download/vimpack_db_minified.json`
  - Purpose: Package manager-specific plugin installation configurations

**Repository Content:**
- GitHub Raw CDN (`raw.githubusercontent.com`) - Fetches README/doc files from plugin repos
  - Client: `lua/store/database/github_client.lua`
  - Auth: None (public repos)
  - Purpose: Live preview of plugin documentation

- GitLab Raw CDN (`gitlab.com/-/raw/`) - Fetches README/doc files from GitLab-hosted plugin repos
  - Client: `lua/store/database/gitlab_client.lua`
  - Auth: None (public repos)
  - Purpose: GitLab-hosted plugin documentation support

## Data Storage

**Databases:**
- None (stateless plugin)

**File Storage:**
- Local filesystem cache - Plugin data and documentation
  - Cache Location: `~/.cache/nvim/store.nvim/` (via `vim.fn.stdpath("cache")`)
  - Contents: README and doc files cached locally after first fetch
  - Files: `{owner}-{repo}.md` (README cache), `{owner}-{repo}.txt` (doc cache)
  - Implementation: `lua/store/database/cache.lua`

**Caching:**
- In-Memory Cache (session-based):
  - Plugin database cache (`db_memory_cache`) - Holds fetched DB in RAM during session
  - README cache (`readmes_memory_cache`) - Maps plugin full_name to content lines
  - Doc cache (`docs_memory_cache`) - Maps plugin full_name to doc lines
  - Install catalogue cache (`install_catalogue_memory_cache`) - Maps plugin manager to catalogue data
  - Implementation: `lua/store/database/cache.lua`

## Authentication & Identity

**Auth Provider:**
- None - All integrations use public APIs with no authentication
- GitHub API access: Public repositories only (no rate limiting concerns for public data)
- GitLab API access: Public repositories only

## Monitoring & Observability

**Error Tracking:**
- None

**Logs:**
- Vim notifications (`vim.notify()`) - User-facing error/warning messages
- Configurable logger with levels: "off", "error", "warn", "info", "debug"
  - Implementation: `lua/store/logger.lua`
  - Configuration: `config.logging` setting (default: "warn")
  - Output: Neovim notification system with timestamps and module context

## Telemetry & Analytics

**Telemetry Service:**
- store-nvim-telemetry endpoint - Anonymous usage tracking
  - Endpoint: `https://store-nvim-telemetry.alex-popov-tech.workers.dev/events`
  - Method: POST
  - Payload: `{ event_type: "view" | "install", plugin_full_name: string }`
  - Opt-out: `config.telemetry = false`
  - Implementation: `lua/store/telemetry.lua`
  - Trigger: Fire-and-forget requests on plugin view/install actions

## CI/CD & Deployment

**Hosting:**
- Plugin hosted on GitHub (alex-popov-tech/store.nvim)
- Installable via lazy.nvim, vim.pack, or other Neovim package managers

**CI Pipeline:**
- GitHub Actions - Type checking workflow
  - Workflow: `.github/workflows/typecheck.yml`
  - Trigger: push to main, pull requests to main
  - Tool: Lua Language Server 3.13.6 (full static type checking)

## Environment Configuration

**Required env vars:**
- None (plugin works with defaults)

**Optional env vars:**
- `XDG_RUNTIME_DIR` - Override temp directory for curl headers (Unix/Linux)
- `USERPROFILE` - Windows user profile path (auto-detected)

**Secrets location:**
- No secrets used (all public APIs)

## Webhooks & Callbacks

**Incoming:**
- None

**Outgoing:**
- POST to telemetry service on plugin view/install events (fire-and-forget)

## HTTP Configuration

**Timeouts:**
- HEAD requests: 5000ms (for database size checks)
- GET requests: 10000ms (for README, doc, and catalogue fetches)
- Telemetry: 5000ms (fire-and-forget, non-blocking)

**User-Agent:**
- `store.nvim` - All HTTP requests use this User-Agent header

**Headers:**
- `Accept: application/json` - For JSON API endpoints
- `Content-Type: application/json` - For telemetry POST requests

## Data Exchange Formats

**JSON:**
- Plugin database: Minified JSON with repository metadata
- Install catalogues: Minified JSON with package manager configs
- Telemetry events: JSON POST body

**Markdown:**
- README files: Cached and processed (HTML tags removed, images converted)
- Doc files: Cached as-is

---

*Integration audit: 2026-03-12*
