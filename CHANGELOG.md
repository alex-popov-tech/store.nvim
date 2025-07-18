# Changelog 📝

All notable changes to this project will be documented in this file.

## [1.1.0] - 2025-07-18

### ✨ Features Added

- 🚀 **Major Crawler Update:**
  - Now scanning the entire GitHub for repositories with `neovim-plugin` topic - grew from `~1k` to `3k+` repositories available in `store.nvim`! 💥
  - Daily scanner ensures that new plugins are added daily (please add proper topics to your repo for the crawler to find it) - one of initial goals achieved! ✅
  - Moved to a separate [repository](https://github.com/alex-popov-tech/store.nvim.crawler) - no more pesky `crawler.js` file in your shiny Lua plugin! 🎉
  - Written in TypeScript - should be less prone to breaking the production database 😅

- 🔄 **Interactive Sorting:** Added sorting by `Recently Updated` and `Most Stars` (in addition to the `Default` sorting)

- 🔍 **Enhanced Filtering:** Upgraded from filtering by repository name/author to filtering by any relevant field (`name`, `author`, `description`, `tags`) with special syntax
  
  **Examples:**
  ```lua
  -- Basic search (searches author/name like before)
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
  author:folke;tags:ui,colorscheme;description:modern
  ```

- 🎨 **Enhanced Repository Display:** Improved the `List` component (left side) - now you can control which fields and their order you want to see through configuration
  
  **Example Configuration:**
  ```lua
  require("store").setup({
    list_fields = { "full_name", "pushed_at", "stars", "forks", "issues", "tags" },
    full_name_limit = 35,  -- Max characters for repo names
  })
  
  -- Available fields:
  -- "full_name"   - Repository name with owner
  -- "stars"       - Star count with ⭐ emoji  
  -- "forks"       - Fork count with 🍴 emoji
  -- "issues"      - Open issues with 🐛 emoji
  -- "pushed_at"   - Last updated date
  -- "tags"        - Repository tags
  
  -- Minimal display example
  require("store").setup({
    list_fields = { "full_name", "stars" },
    full_name_limit = 50,
  })
  ```

- 🔑 **GitHub Token Support:** Added ability to pass GitHub bearer token for increased API rate limits

- 🖼️ **Dynamic Window Resizing:** List and preview windows now automatically resize based on focus - the focused pane gets more screen space for better visibility (proportions swap between 30%/70% and 70%/30%)

### 🐞 Bug Fixes

- 🪟 **Window Management:** Added hook for unexpectedly closed windows of store.nvim (e.g., with `:close`) - now all windows will be gracefully closed

### 🛠️ Other Improvements

- 🌐 **URL Opening:** Use `vim.ui.open` to open URLs ([#2](https://github.com/alex-popov-tech/store.nvim/issues/2))
