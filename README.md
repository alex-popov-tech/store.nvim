<img alt="store.nvim heading image" src="https://github.com/user-attachments/assets/f42b94e4-e3b0-44dc-a8b3-ca59f0817d17" />
<img alt="store.nvim ui" src="https://github.com/user-attachments/assets/07c8b311-3948-4f6c-8364-fa9e6c50440c" />

## Features

A Neovim plugin for browsing and installing Neovim plugins through an intuitive UI interface.

- 🤯 **Plugins installation**: Easily install plugins with `lazy.nvim` without leaving terminal
- 💅 **Live README Preview**: Real-time markdown rendering with syntax highlighting
- 🤓 **Smart Filtering and Sorting**: Filter/sort plugins `name`, `tags`, `author`, `activity` and so on
- 🧳 **Efficient Caching**: configurable 24-hour 2-layer cache with automatic staleness detection and manual refresh

## Installation

### Using lazy.nvim

```lua
{
  "alex-popov-tech/store.nvim",
  dependencies = { "OXY2DEV/markview.nvim" },
  cmd = "Store",
  keys = {
    { "<leader>s", function() require("store").open() end, desc = "Open store.nvim modal" }
  }
}
```

## Usage

Open the plugin browser with `:Store` or `require("store").open()`, and follow hints from help window.

## ❓ FAQ

<details>
  <summary><strong>Why is plugin not listed?</strong></summary>

  That usually happens in two cases:
  - Repository doesn't have the `neovim-plugin` or `neovim-plugins` tag
  - Those tags were added less than 24h ago, and the crawler hasn't refreshed the database yet

  If neither applies — please [create an issue](https://github.com/alex-popov-tech/store.nvim.crawler/issues).
</details>

<details>
  <summary><strong>Why is plugin not installable?</strong></summary>

  A plugin is considered installable if it has at least one *valid* configuration block in its readme. If it isn’t marked as installable, try the following:
  - Wait up to 24h after last readme change — the crawler needs time to re-fetch and re-process it.
  - Make sure code blocks contain valid Lua code. You can check this using `lua-ls` — just create a `tmp.lua` file and paste the code block into it.
  - Adding clear context before code blocks helps too. For example, prefix it with something like: `lazy.nvim configuration example`.
  - You can also check the latest debug artifacts from the README processor [here](https://github.com/alex-popov-tech/store.nvim.crawler/actions/workflows/crawler.yml).

  If none of that helps, and your plugin should be installable — please [create an issue](https://github.com/alex-popov-tech/store.nvim.crawler/issues/new).
</details>

<details>
  <summary><strong>I have a <code>lazy.nvim</code> config in readme, but <code>store.nvim</code> suggests using a migrated version from <code>packer</code>/<code>vim-plug</code>.</strong></summary>

  By default, native `lazy.nvim` configs are preferred. If you have one but it's not being used:
  - Wait up to 24h after your last README.md change — the crawler may not have picked it up yet.
  - Ensure your `lazy.nvim` config block is valid Lua. `lua-ls` can help with that (try pasting it into a temporary `tmp.lua` file).

  Still not working? Please [create an issue](https://github.com/alex-popov-tech/store.nvim.crawler/issues/new).
</details>
