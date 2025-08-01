<img alt="store.nvim heading image" src="https://github.com/user-attachments/assets/f42b94e4-e3b0-44dc-a8b3-ca59f0817d17" />
<img alt="store.nvim ui" src="https://github.com/user-attachments/assets/adcd03ae-cfa3-4330-bea7-9f1031163191" />

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
    "OXY2DEV/markview.nvim", -- optional, for pretty readme preview
  },
  cmd = "Store",
  keys = {
    { "<leader>s", function() require("store").open() end, desc = "Open store.nvim modal" },
  },
  opts = {
    -- optional configuration here
  },
}
```

## Usage

Open the plugin browser with `:Store` or `require("store").open()`, and follow hints from help window.

## ❓ FAQ

<details>
  <summary><strong>Why is my plugin not listed?</strong></summary>

  That usually happens in two cases:
  - Your repository doesn't have the `neovim-plugin` or `neovim-plugins` tag.
  - You added those tags less than 24h ago, and the crawler hasn't refreshed the database yet.

  If neither applies — please [create an issue](https://github.com/alex-popov-tech/store.nvim/issues).
</details>

<details>
  <summary><strong>Why is my plugin not installable?</strong></summary>

  A plugin is considered installable if it has at least one *valid* configuration block in `README.md`. If it isn’t marked as installable, try the following:
  - Wait up to 24h after your last README.md change — the crawler needs time to re-fetch and re-process it.
  - Make sure your code blocks contain valid Lua code. You can check this using `lua-ls` — just create a `tmp.lua` file and paste the code block into it.
  - Adding clear context before code blocks helps too. For example, prefix it with something like: `lazy.nvim configuration example`.
  - You can also check the latest debug artifacts from the README processor [here](https://github.com/alex-popov-tech/store.nvim.crawler/actions/workflows/crawler.yml).

  If none of that helps, and your plugin should be installable — please [create an issue](https://github.com/alex-popov-tech/store.nvim/issues).
</details>

<details>
  <summary><strong>I have a <code>lazy.nvim</code> config, but <code>store.nvim</code> suggests using a migrated version from <code>packer</code>/<code>vim-plug</code>.</strong></summary>

  By default, native `lazy.nvim` configs are preferred. If you have one but it's not being used:
  - Wait up to 24h after your last README.md change — the crawler may not have picked it up yet.
  - Ensure your `lazy.nvim` config block is valid Lua. Again, `lua-ls` can help (try pasting it into a temporary `tmp.lua` file).

  Still not working? Please [create an issue](https://github.com/alex-popov-tech/store.nvim/issues).
</details>
