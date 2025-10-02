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
  -- Main window dimensions
  width = 0.8, -- 80% of screen width
  height = 0.8, -- 80% of screen height

  -- Window layout proportions (must sum to 1.0)
  proportions = {
    list = 0.5,
    preview = 0.5,
  },

  -- Keybindings configuration
  keybindings = {
    help = { "?" },
    close = { "q", "<esc>", "<c-c>" },
    filter = { "f" },
    reset = { "r" },
    open = { "<cr>", "o" },
    switch_focus = { "<tab>", "<s-tab>" },
    sort = { "s" },
    install = { "i" },
    hover = { "K" },
  },

  -- Behavior
  preview_debounce = 100, -- ms delay for preview updates
  cache_duration = 24 * 60 * 60, -- 24 hours
  data_source_url = "https://gist.githubusercontent.com/alex-popov-tech/dfb6adf1ee0506461d7dc029a28f851d/raw/db_minified.json", -- URL for plugin data

  -- Logging
  logging = "off",

  -- List display settings (using function-based renderer)
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
  end, -- Function to render repository data for list display

  -- Z-index configuration for modal layers
  zindex = {
    base = 10, -- Base modal components (heading, list, preview)
    backdrop = 15, -- Reserved for backdrop/dimming layer
    popup = 20, -- Popup modals (help, sort, filter)
  },

  -- Resize behavior
  resize_debounce = 30, -- ms delay for resize debouncing (10-200ms range)

  -- Plugin installation folder (absolute path or starts with ~)
  -- Defaults to ~/.config/nvim/lua/plugins if not specified
  plugins_folder = nil, -- Example: "~/my-nvim-plugins" or "/opt/nvim/plugins"
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
