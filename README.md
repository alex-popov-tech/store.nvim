# store.nvim - Largest Neovim Plugins Store
<img alt="store.nvim ui" src="https://github.com/user-attachments/assets/1e90204c-dcfb-4f0e-8e7d-05a57301092c" />

## Features

A Neovim plugin for browsing and installing Neovim plugins through an intuitive UI interface.

- 🚀 **6,200+ Plugins Available**: Comprehensive plugin database updated daily, ensuring new plugins are added to database right away
- 🤯 **Universal Plugin Installation**: All plugins are installable with your package manager of choice (`lazy.nvim`, `vim.pack`, etc.)
- 💅 **Live README Preview**: Real-time markdown rendering via markview.nvim with server-side pre-processing and CDN caching for instant loading
- 🤓 **Smart Filtering and Sorting**: Filter/sort plugins by `name`, `tags`, `author`, `activity`, `rising stars`, `downloads`, `views` and more
- 🖼️ **Image Preview**: Optional [image.nvim](https://github.com/3rd/image.nvim) integration renders inline images from plugin READMEs directly in your terminal

## Installation

### Using lazy.nvim

```lua
{
  "alex-popov-tech/store.nvim",
  dependencies = {
    { "OXY2DEV/markview.nvim", opts = {} },
    -- Optional: inline image rendering in README previews (Kitty, Ghostty, WezTerm only)
    -- { "3rd/image.nvim", opts = { integrations = { markdown = { enabled = false } } } },
  },
  opts = {
    -- layout = "tab", -- recommended when using image preview
  },
  cmd = "Store",
}
```

## ❓ FAQ

<details>
  <summary><strong>Why is plugin %plugin_name not listed?</strong></summary>

  Please add `neovim-plugin` tag to your repository, and wait for the crawler to pick it up.
</details>


<details>
  <summary><strong>Plugin has <code>lazy.nvim</code> config in readme, but <code>store.nvim</code> suggests migrated/default version instead.</strong></summary>

  Usually that happens when code snippets with configs are invalid lua, if thats not the case - please [create an issue](https://github.com/alex-popov-tech/store.nvim/issues/).
</details>
