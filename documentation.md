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

Open the with:

- **Command**: `:Store`

- **Lua API**: `require("store").open()`

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
})
```

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
