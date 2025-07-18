# TODO.md - store.nvim Development Tracking

## Project Status

**Status Summary**: The store.nvim plugin is **feature-complete and production-ready**. All core functionality has been implemented with a modern, well-structured codebase. The plugin provides a complete 3-window modal interface for browsing Neovim plugins with caching, filtering, and GitHub integration.

---

## ✅ Completed Features

### Core Infrastructure
- [x] **1. Built JS script which grabs all awesome plugins and puts into 'database' (gist)**
  - ✅ Script: `awesome-neovim-crawler.js` - Fully implemented with GitHub API integration
  - ✅ Database: `store.nvim-repos.json` - Generated and populated with 100+ repositories
  - ✅ Gist integration for public data hosting

- [x] **2. Create GitHub Actions cron job to run script and update 'database' daily** ( must have before release )
  - ✅ **IMPLEMENTED AND SECURE**: Daily GitHub Actions workflow with proper environment variables
  - ✅ Daily cron job runs at 3 AM UTC to update plugin database
  - ✅ Environment variable validation implemented with early failure
  - ✅ Automated updates to both local file and GitHub Gist

- [x] **8. Ensure passing tokens, URLs, etc to GitHub Actions script, not hardcoding them** ( must have before release )
  - ✅ **IMPLEMENTED AND SECURE**: All tokens and URLs use environment variables
  - ✅ GitHub secrets properly configured for sensitive data
  - ✅ Environment variable validation with early failure implemented
  - ✅ No hardcoded credentials in codebase

- [x] **9. Ensure script validates it has all required envs and fails early if missing** ( must have before release )
  - ✅ Environment validation implemented at script startup
  - ✅ Clear error messages for missing configuration
  - ✅ Script exits early if required environment variables are missing

### UI & User Experience
- [x] **4. Improve modal - on init pull 'db', parse it, save as table, write repo URLs for e2e proof**
  - ✅ Implemented data loading and display in modal UI (`lua/store/init.lua:454-471`)
  - ✅ Proven end-to-end data flow works
  - ✅ HTTP client implementation with plenary.curl (`lua/store/http.lua`)
  - ✅ Modal displays repository URLs from fetched data

- [x] **5. Add 'search' functionality - '/' filters rows until 'esc' (cancel) or 'cr' (save)**
  - ✅ Interactive filtering system implemented (`lua/store/init.lua:477-503`)
  - ✅ Uses 'f' key to open filter input modal
  - ✅ Case-insensitive URL filtering with real-time updates
  - ✅ Filter state preserved in modal instance

- [x] **6. Utilize markdownview plugin for vertical split with readme preview on selection**
  - ✅ Split view with live README preview implemented (`lua/store/modal.lua:358-471`)
  - ✅ Markview integration for markdown rendering (`lua/store/modal.lua:590-606`)
  - ✅ Debounced cursor movement preview updates
  - ✅ Dual-window layout (40% list, 60% preview)

- [x] **7. Make keybindings to open repo page in browser**
  - ✅ Browser integration implemented (`lua/store/init.lua:34-53`)
  - ✅ Cross-platform support (macOS, Linux, Windows)
  - ✅ `<CR>` keybinding to open repository in browser

- [x] **17. Separate header in float window for 3-window layout** ( must have before release )
  - ✅ Header component implemented as dedicated floating window
  - ✅ Complete 3-window layout: header + main list + preview
  - ✅ Header stays synchronized with current state (loading, filtering, etc.)
  - ✅ Proper window focus management across all 3 windows
  - ✅ ASCII art branding with dynamic status display

- [x] **20. Add repository stats to plugins list** ( must have before release )
  - ✅ Display ⭐ stars count, 👀 watchers, 🍴 forks in list
  - ✅ Format numbers with appropriate suffixes (1.2k, 3.4M)
  - ✅ Repository statistics displayed with emoji icons
  - ✅ Clean formatting with proper spacing and alignment
  - ✅ **COMPLETED**: Sorting options by different metrics implemented (v1.1.0)

- [x] **22. Add ASCII art heading for plugin names** ( must have before release )
  - ✅ ASCII art header implemented in dedicated header window
  - ✅ "store.nvim" branding with visual flair
  - ✅ Dynamic status display (loading, ready, error states)
  - ✅ Proper formatting within window constraints
  - ✅ Header stays synchronized with modal state

### Performance & Reliability
- [x] **10. For preview - ensure there is debounce, so we won't send too many requests clicking next-next-next**
  - ✅ Request debouncing implemented (`lua/store/modal.lua:608-630`)
  - ✅ 150ms debounce delay for preview updates
  - ✅ Timer-based debouncing prevents API rate limiting

- [x] **11. Add caching with 1-day staleness - if modal opened twice in hour, don't re-fetch same READMEs**
  - ✅ Comprehensive caching system (`lua/store/cache.lua`)
  - ✅ Dual-layer caching: memory + file system
  - ✅ 24-hour default cache duration
  - ✅ Cache staleness validation and automatic cleanup

- [x] **12. Use plenary.nvim in main code since tests already depend on it**
  - ✅ Plenary.nvim fully integrated for HTTP requests (`lua/store/http.lua:1`)
  - ✅ File system operations with `plenary.path` (`lua/store/cache.lua:1`)
  - ✅ Consistent dependency usage across test and runtime

- [ ] **27. Preheat file cache on startup for instant modal response**
  - Background cache warming when plugin loads
  - Async fetch of plugin database and popular READMEs
  - Modal opens with all data already in memory
  - Improves user experience with instant UI response

### Documentation & CI/CD
- [x] **13. Document with API documentation all methods and classes, make vim doc, and README**
  - ✅ Comprehensive README with installation, usage, and API reference
  - ✅ Full Lua annotations throughout codebase
  - ✅ Complete API documentation for Modal class and configuration
  - ✅ Usage examples and keybinding documentation

- [x] **14. Make GitHub Actions to check tests** ( partially abandoned )
  - ✅ CI pipeline implemented (`.github/workflows/lint-test.yml`)
  - ✅ StyLua formatting checks
  - ❌ **REMOVED**: Test execution was removed during cleanup
  - ❌ **REMOVED**: Test files and infrastructure deleted
  - ⚠️ **NEEDS RESTORATION**: Testing infrastructure needs to be rebuilt

- [x] **18. Manual modules review and cleanup** ( must have before release )
  - ✅ All modules reviewed for code consistency and patterns
  - ✅ Comprehensive Lua annotations throughout codebase
  - ✅ Modular architecture with clear separation of concerns
  - ✅ Robust error handling and logging system implemented
  - ✅ Standardized logging with configurable levels
  - ✅ Clean, production-ready codebase structure

---

## 🔄 In Progress / Pending Tasks

### Core Features
- [x] **3. Update script to count readme sections as 'categories' for modal switching**
  - ✅ **COMPLETED**: Crawler transforms categories into tags (v1.1.0)
  - ✅ Parses awesome-neovim README sections and converts them to searchable tags
  - ✅ Categories accessible through enhanced filtering system with `tags:` syntax

- [ ] **15. Add ability for preview to toggle between README and doc.txt**
  - Implement tab/keybinding to switch between README.md and doc.txt views
  - Fallback to README if doc.txt doesn't exist
  - Update preview header to show current document type

- [ ] **16. Add installed plugins list at the top**
  - Detect locally installed plugins from package managers (lazy.nvim, packer, etc.)
  - Display installed status indicators in repository list
  - Add filter option to show only installed/not installed plugins

- [ ] **19. Make help window pretty with smooth animations**
  - Replace current help modal with vim.notify-style appearance
  - Add smooth fade-in/fade-out animations
  - Improve visual design with better formatting and icons
  - Implement gradual disappearing effect instead of abrupt close

- [x] **21. Add ability to source from multiple sources**
  - ✅ **COMPLETED**: Major crawler update (v1.1.0)
  - ✅ Now scanning entire GitHub for `neovim-plugin` topic (3k+ repositories)
  - ✅ Moved to separate TypeScript crawler repository
  - ✅ Daily automated scanning ensures new plugins are discovered

- [x] **28. Make filtering use custom structure for unified search**
  - ✅ **COMPLETED**: Advanced filtering syntax implemented (v1.1.0)
  - ✅ Supports `author:`, `name:`, `description:`, `tags:` syntax
  - ✅ Combined queries with `;` separator for multiple criteria
  - ✅ Complex multi-field queries fully functional

- [ ] **29. Track 'new' plugins introduced recently**
  - Implement system to identify recently added plugins
  - Add timestamp tracking for plugin discovery
  - Display "NEW" indicators for recently introduced plugins
  - Configure time threshold for what constitutes "new" plugins

- [x] **30. Display plugin last updated time in GitHub-style format**
  - ✅ **COMPLETED**: `pushed_at` field added to list display (v1.1.0)
  - ✅ Configurable through `list_fields` configuration option
  - ✅ Shows last updated timestamp in plugin list
  - ✅ Part of enhanced repository display system

- [ ] **31. Add sandboxed plugin installation for testing** ( needs investigation, efforts required )
  - Create `store.nvim.sandbox.lua` file for temporary plugin loading
  - Source sandbox file synchronously in init.lua for testing purposes
  - Allow users to "try before install" plugins without permanent changes
  - Investigate vim's native package manager (:h vim-pack) for temporary plugin installation
  - Explore using vim-pack JSON specs for marketplace-managed plugin installation
  - Implement cleanup mechanism to remove sandbox plugins after testing
  - Add keybinding to toggle sandbox mode for selected plugin

- [~] **32. Reach out to Dotfyle for plugin database collaboration** ( suspended )
  - ⏸️ **SUSPENDED**: Limited responsiveness from Dotfyle team
  - 📝 GitHub issue created: https://github.com/codicocodes/dotfyle/issues/178
  - 🔄 Awaiting response for plugin database collaboration
  - 💡 Alternative: Current crawler expansion to 3k+ repos may provide sufficient coverage

- [ ] **33. Add 'newly posted' plugins view similar to lazy.nvim updates**
  - Create dedicated view/tab showing recently added plugins to the database
  - Display plugins discovered in the last week/month with timestamps
  - Show diff-style interface highlighting new additions since last check
  - Add notification system for new plugins matching user's interests
  - Implement lazy.nvim-style update interface with expandable plugin details
  - Allow users to mark plugins as "seen" to track what's new for them

- [ ] **34. Add 'installed' label for plugins using multiple package manager detection**
  - Parse `lazy-lock.json` from Neovim data directory to detect lazy.nvim installed plugins
  - Investigate vim's native package manager (:h vim-pack) for JSON plugin specs
  - Display visual indicator (label/icon) for plugins that are already installed
  - Show installed status in plugin list alongside repository statistics
  - Add filtering option to show only installed or non-installed plugins
  - Handle different plugin specification formats across package managers (lazy, packer, vim-pack)
  - Cache parsed lock file data and track installation state changes for dynamic updates

---

## 🔮 Future Enhancement Ideas (Optional)

- [ ] **23. Highlight groups integration**
  - Custom highlight groups for better theming support
  - Integration with user's colorscheme

- [x] **24. Dynamic window resizing**
  - ✅ **COMPLETED**: Dynamic window resizing (v1.1.0)
  - ✅ Focused pane gets more screen space (30%/70% ↔ 70%/30%)
  - ✅ Responsive layout adjustments based on focus
  - ✅ Improved visibility for active pane

- [x] **25. Improved window management**
  - ✅ **COMPLETED**: WindowManager improvements (v1.1.0)
  - ✅ Added hook for unexpectedly closed windows
  - ✅ Graceful cleanup when any window is closed unexpectedly
  - ✅ Better error recovery and component-level management

- [x] **26. Tag-based filtering**
  - ✅ **COMPLETED**: Tag-based filtering implemented (v1.1.0)
  - ✅ Filter by plugin categories/tags using `tags:` syntax
  - ✅ Tags parsed from repository metadata and awesome-neovim categories

---

## 📝 Notes

**Last Updated**: 2025-07-18

This TODO.md file is now the canonical source for tracking development progress. The roadmap has been moved from CLAUDE.md to this dedicated tracking document for better organization and clarity.
