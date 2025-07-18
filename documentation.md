# store.nvim

A Neovim plugin for browsing and discovering awesome Neovim plugins through an intuitive UI modal interface.

## Features

- **Interactive Modal Interface**: Clean UI with header, list, and preview panes with dynamic resizing
- **Live README Preview**: Real-time markdown rendering with syntax highlighting
- **Smart Filtering**: Advanced filtering by name, author, description, and tags with special syntax
- **Interactive Sorting**: Sort plugins by Recently Updated, Most Stars, or Default order
- **Customizable Display**: Configure which repository fields to show and their display order
- **Intelligent Caching**: 24-hour cache with automatic staleness detection and manual refresh
- **Expanded Database**: Browse 3k+ Neovim plugins with daily updates

## Installation

```lua
{
  "alex-popov-tech/store.nvim",
  dependencies = {
    "OXY2DEV/markview.nvim", -- optional, for pretty readme preview / help window
  },
  cmd = "Store",
  keys = {
    { "<leader>s", "<cmd>Store<cr>", desc = "Open Plugin Store" },
  },
  opts = {
    -- optional configuration here
  },
}
```

## Usage

Open the plugin browser:

- **Command**: `:Store`

- **Lua API**: `require("store").open()`

```lua
-- Custom keybinding
vim.keymap.set("n", "<leader>s", require("store").open, { desc = "Open Plugin Store" })
```

## Configuration

```lua
require("store").setup({
  -- Window dimensions (percentages or absolute)
  width = 0.8,
  height = 0.8,

  -- Layout proportions (must sum to 1.0)
  proportions = {
    list = 0.3,     -- 30% for repository list
    preview = 0.7,  -- 70% for preview pane
  },

  -- Keybindings (arrays of keys for each action)
  keybindings = {
    help = { "?" },                    -- Show help
    close = { "q", "<esc>", "<c-c>" }, -- Close modal
    filter = { "f" },                  -- Open filter input
    refresh = { "r" },                 -- Refresh data
    open = { "<cr>", "o" },            -- Open selected repository
    switch_focus = { "<tab>", "<s-tab>" }, -- Switch focus between panes
    sort = { "s" },                    -- Sort repositories
  },

  -- Repository display options
  list_fields = { "full_name", "pushed_at", "stars", "forks", "issues", "tags" },
  full_name_limit = 35,              -- Max characters for repository names

  -- GitHub API (optional)
  github_token = nil,                -- GitHub token for increased rate limits

  -- Behavior
  preview_debounce = 100,            -- ms delay for preview updates
  cache_duration = 24 * 60 * 60,    -- 24 hours in seconds
  logging = "off",                   -- Levels: off, error, warn, log, debug
})
```

## API

### Functions

#### `require("store").setup(config)`

Initialize the plugin with optional configuration.

#### `require("store").open()`

Open the store modal interface.

#### `require("store").close()`

Close the currently open store modal.

### Commands

#### `:Store`

Opens the store modal interface.

## Keybindings

| Key | Action | Description |
|-----|--------|-------------|
| `?` | Help | Show help modal |
| `q`, `<Esc>`, `<C-c>` | Close | Close the store modal |
| `f` | Filter | Open filter input |
| `r` | Refresh | Hard reset caches and refresh all data from network |
| `s` | Sort | Cycle through sorting options (Default, Recently Updated, Most Stars) |
| `<CR>`, `o` | Open | Open repository in browser |
| `<Tab>`, `<S-Tab>` | Switch Focus | Switch between panes |

### Filter Mode

| Key | Action |
|-----|--------|
| `<CR>` | Apply filter |
| `<Esc>` | Cancel filter |

## Examples

### Basic Setup

```lua
require("store").setup()
```

### Custom Layout

```lua
require("store").setup({
  width = 0.95,
  height = 0.90,
  proportions = {
    list = 0.4,    -- 40% for list
    preview = 0.6, -- 60% for preview
  }
})
```

### Custom Keybindings

```lua
require("store").setup({
  keybindings = {
    help = "<F1>",
    close = "<Esc>",
    filter = "/",
    refresh = "<F5>",
    switch_focus = "<C-w>",
  },
})
```

### Development Mode

```lua
require("store").setup({
  logging = "debug",
  cache_duration = 60,      -- 1 minute for development
  preview_debounce = 50,    -- Faster preview updates
})
```

### Customizable List Display

```lua
require("store").setup({
  -- Show only essential information
  list_fields = { "full_name", "stars", "pushed_at" },
  full_name_limit = 45,  -- Longer names for better readability
})
```

```lua
require("store").setup({
  -- Minimal display for small screens
  list_fields = { "full_name", "stars" },
  full_name_limit = 25,
})
```

### GitHub Token Configuration

```lua
require("store").setup({
  github_token = "ghp_your_token_here",  -- Increases API rate limits
})
```

## Filtering

The enhanced filtering system supports field-specific searches with special syntax:

### Basic Search
```lua
-- Search in repository name and author (legacy behavior)
telescope
nvim-lua/plenary
```

### Field-Specific Search
```lua
-- Search by specific fields
author:nvim-telescope          -- Find plugins by specific author
name:telescope                 -- Search only in repository names
description:fuzzy finder       -- Search in descriptions
tags:lsp,completion           -- Search by tags (comma-separated)
```

### Combined Queries
```lua
-- Multiple conditions (all must match)
telescope;author:nvim-telescope;tags:fuzzy,finder

-- Complex multi-field query
author:folke;tags:ui,colorscheme;description:modern
```

## Sorting

Use the `s` key to cycle through available sorting options:

- **Default**: Original order from the plugin database
- **Recently Updated**: Sort by last repository update (newest first)
- **Most Stars**: Sort by GitHub star count (highest first)

The current sorting mode is displayed in the header for reference.

For more help: https://github.com/alex-popov-tech/store.nvim/issues
