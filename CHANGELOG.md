# Changelog 📝

All notable changes to this project will be documented in this file.

## [4.0.0] - 2026-04-01

### ✨ Features Added

**New services in the store.nvim family:**

[store.nvim.readme-cache](https://github.com/alex-popov-tech/store.nvim.readme-cache):
- **Server-side README processing** — READMEs are now pre-processed and cached on a Cloudflare Workers + R2 CDN. Badge stripping, HTML entity cleanup, image tag conversion, and blank line collapsing all happen server-side via a proper markdown AST parser (remark/unified) — no more ~5 text-based regex passes on the client
- **Stale-while-revalidate caching** — processed READMEs are served instantly from R2 with background revalidation using GitHub ETags

[store.nvim.telemetry](https://github.com/alex-popov-tech/store.nvim.telemetry):
- **Anonymous usage tracking service** — self-hosted on Cloudflare Workers + D1. Tracks plugin views and installs with hourly deduplication, daily active users with country breakdown
- **Privacy-first design** — IP addresses are never stored; SHA-256 hashed with a daily rotating salt and purged after 90 days

`store.nvim`:
- **📐 Tab Layout Mode** — new `layout = "tab"` option opens store in a dedicated Neovim tab page with native splits instead of floating windows. Pairs well with image preview for smoother rendering
- **🖼️ Image Preview** — optional [image.nvim](https://github.com/3rd/image.nvim) integration renders inline images from plugin READMEs directly in your terminal — great for previewing colorschemes. Requires a terminal with image protocol support (Kitty, Ghostty, WezTerm)

  **Example setup with image.nvim:**
  ```lua
  {
    "alex-popov-tech/store.nvim",
    dependencies = {
      { "OXY2DEV/markview.nvim", opts = {} },
      {
        "3rd/image.nvim",
        opts = { integrations = {
          markdown = {
            enabled = false,
          },
        } },
      },
    },
    opts = {
      layout = "tab", -- recommended for image preview
    },
    cmd = { "Store" },
  }
  ```

- **📄 Multi-Doc Navigation** — browse all documentation files a plugin provides (README, CHANGELOG, doc/*.txt, etc.) with `D` to cycle through docs and `R` to jump back to README. Dynamic tab bar shows current doc and file count
- **📊 New Sort Options** — sort plugins by community activity:
  - `Rising Stars (weekly)` — stars gained this week
  - `Rising Stars (monthly)` — stars gained this month
  - `Most Downloads (monthly)` — download count from telemetry
  - `Most Views (monthly)` — view count from telemetry
- **📈 Opt-out Telemetry** — anonymous usage tracking powers download/view sort options. No host info, no IP — only aggregated counts. Configure with `telemetry = true/false` (default: `true`)
- **🎯 Redesigned Heading** — text labels replace emojis for better clarity. Active filter, sort mode, and keybinding hints shown inline. Installed plugin count and plugin manager info displayed prominently
- **🌊 Loading Wave Animation** — animated wave effect in the heading while data loads
- **📏 Graceful Resize Handling** — modal auto-closes with a notification if the terminal becomes too small. Debounced resize with configurable delay via `resize_debounce` (default: 30ms)

### ⚡ Performance Improvements

- **Server-side README processing** — READMEs are pre-processed and cached on a CDN worker, dramatically reducing client-side work
- **Smart image rendering** — debounced rendering keeps navigation snappy; image count capped at 5 per preview
- **Database migrated from GitHub Gist to GitHub Release assets** — faster, more reliable downloads with proper CDN caching

### 🛠️ API Changes

**📐 New Configuration Options**
- `layout` — `"modal"` (default) or `"tab"` for native split layout
- `proportions` — `{list = 0.5, preview = 0.5}` controls pane split ratio
- `resize_debounce` — debounce delay in ms (10-200, default: 30)
- `telemetry` — enable/disable anonymous usage tracking (default: `true`)
- `readme_cache_url` — base URL for pre-processed README cache

**📊 Repository Renderer Update**
- **Breaking Change**: `repository_renderer` function signature now includes an `opts` table:

  ```lua
  require("store").setup({
    ---@param repo Repository
    ---@param opts RendererOpts -- { sort_type, downloads, views, is_installed }
    repository_renderer = function(repo, opts)
      return {
        { content = opts.is_installed and "installed" or "available", limit = 10 },
        { content = repo.full_name, limit = 35 },
        { content = "⭐" .. repo.stars.curr, limit = 10 },
      }
    end,
  })
  ```

**⭐ Stars Field Schema**
- **Breaking Change**: `repo.stars` is now a table `{curr, weekly, monthly}` instead of a plain number

**🔑 New Keybindings**
- `D` — cycle through plugin documentation files
- `R` — jump to README tab
- Configurable via `switch_docs` and `switch_readme` in keybindings config

## [3.0.0] - 2025-10-02

### ✨ Features Added

[store.nvim.crawler](https://github.com/alex-popov-tech/store.nvim.crawler):
- **5,500+ plugins** now available - significantly expanded from 3.6k with enhanced discovery methods
- **`vim.pack` support** - depending of your used plugin manager, installation modal will show appropriate installation instructions
- **Universal installation support** - all plugins now have installation instructions with bulletproof verification
- **Comprehensive plugin discovery** - crawling GitHub with multiple strategies:
  - Multiple topic tags (`neovim-plugin`, `nvim-plugin`, `vim-plugin`, etc.)
  - Repository name patterns (containing 'nvim' or 'vim')
  - Awesome lists integration (`awesome-nvim`, `awesome-vim`)
- **Smart fallback system** - automatic lazy.nvim configuration generation for plugins without native configs
- **Enhanced verification** - bulletproof plugin validation ensures quality and installability

`store.nvim`:
- **📁 Configurable Installation Paths** - Added `plugins_folder` configuration option to customize plugin installation directory with support for absolute paths and `~` expansion
- **🎯 Hover Information Display** - New hover component for enhanced repository information and quick access to plugin details
- **🔧 Enhanced UI Components** - Improved installation modal with better user experience and visual consistency
- **📄 Flexible File Operations** - Added ability to append plugin configurations to existing files during installation - particularly useful for non-lazy.nvim workflows like `vim.pack` or `MiniPack`
- **🏠 Universal Plugin Installation** - All plugins are now installable (removed installable count limitation from header)
- **✏️ Direct File Path Editing** - Edit installation file paths directly in the modal interface

### ⚡ Performance Improvements

**🚀 Optimized README Processing**
- **20-50% faster README rendering** depending on README size and complexity
- Single-pass regex operations instead of multiple passes
- Pre-compiled patterns to avoid recompilation overhead
- Optimized HTML detection with cheaper preliminary checks

**🔄 Revolutionary Caching Strategy**
- **HEAD-first validation** ensures users have the most recent database **100% of the time** with minimal overhead
- Smart content-length comparison eliminates unnecessary downloads
- **Near real-time updates** - database freshness without performance impact
- Dramatically improved user experience with always up-to-date plugin information

### 🛠️ API Changes

**📊 List View Renderer Update**
- **Breaking Change**: `repository_renderer` now uses function-based rendering for enhanced flexibility

  **Example Configuration:**
  ```lua
  require("store").setup({
    repository_renderer = function(repo, isInstalled)
      return {
        {
          content = isInstalled and "🏠" or "📦",
          limit = 2,
        },
        {
          content = "⭐" .. repo.pretty.stars,
          limit = 10,
        },
        {
          content = repo.full_name,
          limit = 35,
        },
        {
          content = "Updated " .. repo.pretty.updated_at,
          limit = 25,
        },
        {
          content = repo.tags and table.concat(repo.tags, ", ") or "",
          limit = 30,
        },
      }
    end
  })
  ```

**🎨 Internal Rendering Improvements**
- Enhanced markview.nvim integration for better markdown rendering
- Improved syntax highlighting and preview quality
- Better handling of complex markdown structures

## [2.0.0] - 2025-08-12

<img src="https://github.com/user-attachments/assets/07c8b311-3948-4f6c-8364-fa9e6c50440c" />

### ✨ Features Added

[store.nvim.crawler](https://github.com/alex-popov-tech/store.nvim.crawler):
- more plugins (especially color themes) - now crawling since `2013` with `6` different topics resulted in `~3665` high-quality plugins in the list
- installation instructions - plugin readmes are now parsed for installation configurations; currently `~2485` plugins are available for installation through `store.nvim`
- better filtering - no more outdated (last updated more than `3 years` ago) and incorrect (people's dotfiles, plugin frameworks, plugin managers, no README, etc.) repositories in the list
- better ordering - now `default` sorts plugins by recent activity, so you can open `store.nvim` from time to time to see the latest, most cutting edge plugins being developed
- improved performance - crawling now takes less than 10 minutes (when I started to add topics it was about 30–60 minutes)

`store.nvim`:
- plugins installation - now you can use installation instructions from `store.nvim.crawler` to preview, edit, and save plugin configuration for installation (more details below)
- plugin statuses - in `list` you can see plugins that are `already installed` marked as 🏠 (because they feel like home 😌) and `ready to install` as 📦
- no more GitHub rate limits - now `store.nvim` uses `raw.githubusercontent.com` for preview, so no more api keys and limits
- more sorting options - sort plugins by stars, last update, last created, installed
- auto resize - when you resize your terminal/split, `store.nvim` will resize itself too, to keep the UI looking good

## [1.1.0] - 2025-07-18

### ✨ Features Added

- 🚀 **Major Crawler Update:**
  - Now scanning the entire GitHub for repositories with `neovim-plugin` topic - grew from `~1k` to `3k+` repositories available in `store.nvim`! 💥
  - Daily scanner ensures that new plugins are added daily (please add proper topics to your repo for the crawler to find it) - one of initial goals achieved! ✅
  - Moved to a separate [repository](https://github.com/alex-popov-tech/store.nvim.crawler) - no more pesky `crawler.js` file in your shiny Lua plugin! 🎉
  - Written in TypeScript - should be less prone to breaking the production database 😅

- 🔄 **Interactive Sorting:** Added sorting by `Recently Updated` and `Most Stars` (in addition to the `Default` sorting)

- 🔍 **Enhanced Filtering:** Upgraded from filtering by repository name/author to filtering by any relevant field (`name`, `author`, `description`, `tags`) with special syntax

  **Examples:**
  ```lua
  -- Basic search (searches author/name like before)
  telescope
  nvim-lua/plenary

  -- Field-specific searches
  author:nvim-telescope
  name:telescope
  description:fuzzy finder
  tags:lsp,completion

  -- Combined queries (all must match)
  telescope;author:nvim-telescope;tags:fuzzy,finder

  -- Complex multi-field query
  author:folke;tags:ui,colorscheme;description:modern
  ```

- 🎨 **Enhanced Repository Display:** Improved the `List` component (left side) - now you can control which fields and their order you want to see through configuration

  **Example Configuration:**
  ```lua
  require("store").setup({
    list_fields = { "full_name", "pushed_at", "stars", "forks", "issues", "tags" },
    full_name_limit = 35,  -- Max characters for repo names
  })

  -- Available fields:
  -- "full_name"   - Repository name with owner
  -- "stars"       - Star count with ⭐ emoji
  -- "forks"       - Fork count with 🍴 emoji
  -- "issues"      - Open issues with 🐛 emoji
  -- "pushed_at"   - Last updated date
  -- "tags"        - Repository tags

  -- Minimal display example
  require("store").setup({
    list_fields = { "full_name", "stars" },
    full_name_limit = 50,
  })
  ```

- 🔑 **GitHub Token Support:** Added ability to pass GitHub bearer token for increased API rate limits

- 🖼️ **Dynamic Window Resizing:** List and preview windows now automatically resize based on focus - the focused pane gets more screen space for better visibility (proportions swap between 30%/70% and 70%/30%)

### 🐞 Bug Fixes

- 🪟 **Window Management:** Added hook for unexpectedly closed windows of store.nvim (e.g., with `:close`) - now all windows will be gracefully closed

### 🛠️ Other Improvements

- 🌐 **URL Opening:** Use `vim.ui.open` to open URLs ([#2](https://github.com/alex-popov-tech/store.nvim/issues/2))
