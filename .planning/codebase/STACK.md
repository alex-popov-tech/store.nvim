# Technology Stack

**Analysis Date:** 2026-03-12

## Languages

**Primary:**
- Lua 5.1 / LuaJIT - Core plugin implementation language

**Secondary:**
- YAML - GitHub Actions CI/CD workflow configuration

## Runtime

**Environment:**
- Neovim 0.10+ (required, uses `vim.ui.open` and Lua API)
- LuaJIT 2.0+ (configured in `.luarc.json` with `runtime.version: "LuaJIT"`)

**Package Manager:**
- Manual installation via plugin manager (lazy.nvim, vim.pack, etc.)
- No centralized package manager; plugin dependencies managed by Neovim package managers

## Frameworks

**Core:**
- None (pure Lua with Neovim API)

**UI:**
- Neovim native window API (`nvim_open_win`, `nvim_buf_*`) - Window/buffer management
- Neovim highlighting API (`nvim_set_hl`) - Syntax highlighting and theme support
- `OXY2DEV/markview.nvim` [optional dependency] - Rich markdown rendering for preview windows

**HTTP Client:**
- Custom `curl` wrapper (`lua/store/plenary/curl.lua`) - HTTP requests via system curl

**Testing/Checking:**
- Lua Language Server 3.13.6+ - Static type checking via GitHub Actions workflow (`.github/workflows/typecheck.yml`)

**Build/Dev:**
- StyLua 0.20+ (`.stylua.toml`) - Lua code formatting
- Lua Language Server - Type annotations via `.luarc.json`

## Key Dependencies

**Critical:**
- `vim` global module (Neovim Lua API) - Core editor functionality (windows, buffers, notifications, keymaps)
- Custom plenary modules:
  - `store.plenary.curl` - HTTP requests with async callbacks
  - `store.plenary.path` - Cross-platform path handling
  - `store.plenary.job` - Async job/shell execution
  - `store.plenary.functional` - Functional utilities (map, filter, etc.)
  - `store.plenary.scandir` - Directory scanning
  - `store.plenary.compat` - Compatibility helpers

**Infrastructure:**
- `markview.nvim` [optional] - Markdown rendering for rich preview display (loaded via `pcall(require, "markview")`)

## Configuration

**Environment:**
- `vim.fn.stdpath("cache")` - Cache directory (`~/.cache/nvim/`) for README/doc cache storage
- `vim.fn.stdpath("config")` - Config directory (`~/.config/nvim/`) for plugins folder default
- `XDG_RUNTIME_DIR` env var (or `/tmp`) - Temporary file storage for curl headers
- `USERPROFILE` env var (Windows) - Temp directory for Windows paths

**Build:**
- `.luarc.json` - Lua language server configuration for type checking and diagnostics
  - Runtime: LuaJIT with `vim.loop` library
  - Globals: `vim` API
  - Disable: "missing-fields" diagnostic
- `.stylua.toml` - Code formatting configuration
  - Column width: 120
  - Indentation: 2 spaces
  - Line endings: Unix
  - Quote style: AutoPreferDouble
  - Newline call parentheses: true

## Platform Requirements

**Development:**
- Neovim 0.10+
- Lua 5.1+ runtime (LuaJIT typically)
- Curl executable (system-level for HTTP requests)
- Lua Language Server 3.13.6+ (for type checking in CI)

**Production:**
- Neovim 0.10+
- Curl executable accessible in `$PATH`
- Optional: `markview.nvim` for enhanced markdown preview
- Target environments: Linux, macOS, Windows (via AppData temp directory)

## CI/CD

**Testing/Checking:**
- GitHub Actions workflow (`/.github/workflows/typecheck.yml`)
  - Triggers: push to main, pull requests to main
  - Tool: LuaLS lua-language-server-action (v3.13.6)
  - Check: Full static type checking via `.luarc.json` configuration

---

*Stack analysis: 2026-03-12*
