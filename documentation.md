# store.nvim

## Installation

```lua
{
  "alex-popov-tech/store.nvim",
  dependencies = { "OXY2DEV/markview.nvim" },
  cmd = "Store",
  keys = {
    { "<leader>s", "<cmd>Store<cr>", desc = "Open Plugin Store" },
  },
  opts = {
    -- optional configuration here
  }
}
```

## Usage

Open with:

- **Command**: `:Store`

- **Lua API**: `require("store").open()`

## Keys

In the store (list or preview focused):

- `f` — fullscreen whatever the preview is showing (Docs or Readme tab); `f` or `q` brings the modal back
- `<C-t>` — take the previewed doc (or README) out into a real new tab (buffer named `store://owner/repo/doc-path`); the modal closes
- `<C-v>` — the same, in a vertical split
- `<C-s>` — the same, in a horizontal split
- `D` — switch to / cycle the Docs tab, `R` — Readme, `L` — List, `I` — Install
- `q` — close the store

The keys come from the `keybindings` table (`toggle_docs_fullscreen`, `open_docs_tab`, `open_docs_vsplit`, `open_docs_split`, ...).

## Default Configuration

```lua
require("store").setup({
  -- Layout mode: "modal" (floating) or "tab" (native splits)
  layout = "modal",

  -- Main window dimensions (percentage of screen, 0.0-1.0)
  width = 0.8,
  height = 0.8,

  -- Window layout proportions (must sum to 1.0)
  proportions = {
    list = 0.5,
    preview = 0.5,
  },

  -- Behavior
  preview_debounce = 100, -- ms delay for preview updates
  plugin_manager = "not-selected", -- "lazy.nvim" or "vim.pack"

  -- Logging level: "off"|"error"|"warn"|"info"|"debug"
  logging = "warn",

  -- Custom list renderer
  ---@param repo Repository
  ---@param opts RendererOpts -- { sort_type, downloads, views, is_installed }
  repository_renderer = function(repo, opts)
    return {
      { content = "⭐" .. repo.pretty.stars, limit = 10 },
      { content = repo.name, limit = 25 },
      { content = repo.description, limit = 150 },
    }
  end,

  -- Z-index configuration for modal layers
  zindex = {
    base = 10,
    backdrop = 15,
    popup = 20,
  },

  -- Resize behavior
  resize_debounce = 30, -- ms (10-200 range)

  -- Plugin installation folder (absolute path or starts with ~)
  -- Defaults to ~/.config/nvim/lua/plugins if not specified
  plugins_folder = nil,

  -- Anonymous, open-source, and public usage telemetry (opt-out by setting false)
  -- Source: https://github.com/alex-popov-tech/store.nvim.telemetry
  telemetry = true,
  -- Browser-style cache: everything you view lands on disk and opens
  -- without the network; stale lists refresh silently in the background
  cache = {
    enabled = true,          -- false = no disk cache, network required
    update_interval = 1800,  -- seconds a cached list/page stays trusted (0 = revalidate on every open)
    implicit_updates = true, -- false = only <leader>r refreshes stale lists
    -- per-section switches, all on by default; a section switched off is
    -- fetched live every time (offline it says "not connected" instead
    -- of erroring, like any uncached page)
    sections = {
      list = true,             -- the plugin database
      install_catalogue = true, -- lazy.nvim / vim.pack install catalogues
      readme = true,           -- the READMEs the preview shows
      docs = true,             -- the doc files the preview shows
    },
  },

})
```

## Caching

store.nvim keeps what you view in a browser-style cache under
`stdpath("cache")/store.nvim`:

- **Lists** (the plugin database, the install catalogues), **READMEs**,
  **docs** and the **download/view stats** are all cached on disk.
- While a cached resource is inside `cache.update_interval` seconds it is
  served with NO request at all (the browser's max-age window).
- When it goes stale the next open sends ONE conditional request
  (`If-None-Match` / `If-Modified-Since`): a `304` keeps the copy and
  costs nothing, a `200` replaces it. At most one such request runs per
  URL at a time — cycling fast over stale pages never stacks requests.
- With `cache.implicit_updates = true` (the default) a stale page — the
  list and the previews alike — is shown the instant the cursor lands
  on it, and the refresh happens behind it: cycling through the store
  never waits on the network. The refreshed content swaps in silently
  when it actually changed.
- When the network is down — no internet, a dead proxy, a captive
  portal — the cached copy is shown with a warning instead of an
  error, so the store still opens.
- The first network-level failure latches "offline" for a minute: pages
  that were never loaded (so not cached) skip the doomed request
  entirely and the preview says **Not connected** — no error per
  keystroke while cycling through plugins. Any successful request (or
  the explicit `<leader>r`) unlatches.
- `cache.sections` toggles the cache per kind of content — `list`,
  `install_catalogue`, `readme`, `docs` — all on by default. A section
  switched off is fetched live every time; offline it behaves like an
  uncached page: "Not connected" in the preview, never an error storm.
- With `cache.implicit_updates = true` (the default) a stale list is
  shown immediately and the fresh one arrives silently in the background;
  with `false` the list (and the previews) refresh only when you press
  `<leader>r`.
- `cache.enabled = false` turns the disk cache off (network required).
- The explicit refresh (`<leader>r`) always bypasses the freshness window.
- Upgrading from an older store.nvim keeps its cache: the previous
  `db.json` / `db.etag` and the temp-dir READMEs are adopted as-is.

Clear it with `<leader>r`'s full refresh or by deleting the directory.

## API

### Functions

#### `require("store").setup(config)`

Initialize the plugin with optional configuration.

#### `require("store").open()`

Open the store modal interface.

### Commands

#### `:Store`

Opens the store modal interface.

## Filtering

  ```
  -- Basic search (searches author/name)
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
  author:folke;tags:ui,colorscheme;
  ```
