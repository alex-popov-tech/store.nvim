<img alt="store.nvim heading image" src="https://github.com/user-attachments/assets/f42b94e4-e3b0-44dc-a8b3-ca59f0817d17" />
<img alt="store.nvim ui" src="https://github.com/user-attachments/assets/07c8b311-3948-4f6c-8364-fa9e6c50440c" />

## Features

A Neovim plugin for browsing and installing Neovim plugins through an intuitive UI interface.

- 🚀 **5,500+ Plugins Available**: Comprehensive plugin database updated every few hours, ensuring absolutely all recent plugins are added to database right away
- 🤯 **Universal Plugin Installation**: All plugins are installable with your package manager of choice (`lazy.nvim`, `vim.pack`, etc. )
- 💅 **Live README Preview**: Real-time markdown rendering with enhanced syntax highlighting via markview.nvim
- 🤓 **Smart Filtering and Sorting**: Filter/sort plugins by `name`, `tags`, `author`, `activity` and more
- 🧳 **Smart Caching**: Users always have the most recent database available at all times

## Requirements

- Neovim 0.10+ (uses `vim.ui.open` for opening URLs)
- [`OXY2DEV/markview.nvim`](https://github.com/OXY2DEV/markview.nvim) for rich markdown rendering in the list/preview/etc windows

## Installation

### Using lazy.nvim

```lua
{
  "alex-popov-tech/store.nvim",
  dependencies = { "OXY2DEV/markview.nvim" },
  opts = {},
  cmd = "Store"
}
```

## Usage

Open the plugin browser with `:Store` or `require("store").open()`, and follow hints from help window.

## ❓ FAQ

<details>
  <summary><strong>Why is plugin %plugin_name not listed?</strong></summary>

  Please add `neovim-plugin` tag to your repository, and wait for the crawler to pick it up.
</details>


<details>
  <summary><strong>Plugin has <code>lazy.nvim</code> config in readme, but <code>store.nvim</code> suggests migrated/default version instead.</strong></summary>

  Usually that happens when code snippets with configs are invalid lua, if thats not the case - please [create an issue](https://github.com/alex-popov-tech/store.nvim/issues/).
</details>
