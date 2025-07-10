# store.nvim

A Neovim plugin for browsing and discovering awesome Neovim plugins through an intuitive UI modal interface.

## Features

- **Interactive Modal Interface**: Clean UI with header, list, and preview panes
- **Live README Preview**: Real-time markdown rendering with syntax highlighting
- **Smart Filtering**: Filter plugins by name with instant search ( TBD filtering by category and tags )
- **Intelligent Caching**: 24-hour cache with automatic staleness detection and manual refresh

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

  -- Modal appearance
  modal = {
    border = "rounded",  -- Border style
    zindex = 50,        -- Z-index for modal windows
  },

  -- Keybindings
  keybindings = {
    help = "?",         -- Show help
    close = "q",        -- Close modal
    filter = "f",       -- Open filter input
    refresh = "r",      -- Refresh data
    open = "<cr>",      -- Open selected repository
    switch_focus = "<tab>", -- Switch focus between panes
  },

  -- Behavior
  preview_debounce = 150,           -- ms delay for preview updates
  cache_duration = 24 * 60 * 60,   -- 24 hours in seconds
  logging = "off",                  -- Levels: off, error, warn, log, debug
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
| `q` | Close | Close the store modal |
| `f` | Filter | Open filter input |
| `r` | Refresh | Hard reset caches and refresh all data from network |
| `<CR>` | Open | Open repository in browser |
| `<Tab>` | Switch Focus | Switch between panes |

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

For more help: https://github.com/alex-popov-tech/store.nvim/issues
