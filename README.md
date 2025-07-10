<img alt="store.nvim heading image" src="https://github.com/user-attachments/assets/f42b94e4-e3b0-44dc-a8b3-ca59f0817d17" />
<img alt="store.nvim ui" src="https://github.com/user-attachments/assets/29ababaf-6027-4646-ab30-ce253691d72d" />

A Neovim plugin for browsing and discovering awesome Neovim plugins through an intuitive UI modal interface.

## Features

- **Interactive Modal Interface**: Clean UI with header, list, and preview panes
- **Live README Preview**: Real-time markdown rendering with syntax highlighting
- **Smart Filtering**: Filter plugins by name with instant search
- **Intelligent Caching**: 24-hour 2-layer cache with automatic staleness detection and manual refresh

## Installation

### Using lazy.nvim

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

## Default Configuration

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
    zindex = 50,         -- Z-index for modal windows
  },

  -- Keybindings
  keybindings = {
    help = "?",             -- Show help
    close = "q",            -- Close modal
    filter = "f",           -- Open filter input
    refresh = "r",          -- Refresh data
    open = "<cr>",          -- Open selected repository
    switch_focus = "<tab>", -- Switch focus between panes
  },

  -- Behavior
  preview_debounce = 150,           -- ms delay for preview updates
  cache_duration = 24 * 60 * 60,    -- 24 hours in seconds
  logging = "off",                  -- Levels: off, error, warn, log, debug
})
```

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
