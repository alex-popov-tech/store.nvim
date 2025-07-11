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
  - ❌ **PENDING**: Sorting options by different metrics not implemented

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
- [ ] **3. Update script to count readme sections as 'categories' for modal switching**
  - Parse README sections to create browsable categories

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

- [ ] **21. Add ability to source from multiple sources**
  - Extend beyond awesome-neovim to support multiple plugin registries
  - Add configuration for custom plugin sources
  - Implement source-specific crawlers and parsers
  - Merge and deduplicate plugins from multiple sources

- [ ] **28. Make filtering use custom structure for unified search**
  - Implement syntax like 'tags:one,two,three category:lsp' in filter input
  - Enable searching across descriptions, categories, and tags in same field
  - Parse filter input to extract different search criteria
  - Apply multiple filters simultaneously for more precise results

- [ ] **29. Track 'new' plugins introduced recently**
  - Implement system to identify recently added plugins
  - Add timestamp tracking for plugin discovery
  - Display "NEW" indicators for recently introduced plugins
  - Configure time threshold for what constitutes "new" plugins

- [ ] **30. Display plugin last updated time in GitHub-style format**
  - Show relative time stamps like "2 days ago", "6 hours ago", "yesterday", "3 weeks ago"
  - Use GitHub's `updated_at` field from repository API data
  - Format timestamps in human-readable relative format
  - Display in plugin list alongside stars/forks/watchers for activity overview

- [ ] **31. Add sandboxed plugin installation for testing** ( needs investigation, efforts required )
  - Create `store.nvim.sandbox.lua` file for temporary plugin loading
  - Source sandbox file synchronously in init.lua for testing purposes
  - Allow users to "try before install" plugins without permanent changes
  - Investigate technical approach for safe plugin sandboxing
  - Implement cleanup mechanism to remove sandbox plugins after testing
  - Add keybinding to toggle sandbox mode for selected plugin

- [ ] **32. Reach out to Dotfyle for plugin database collaboration**
  - Contact https://github.com/codicocodes/dotfyle team about sharing their plugin database
  - Request access to their plugin data in structured format (JSON/API)
  - Explore integration possibilities for richer plugin metadata
  - Investigate combining awesome-neovim data with Dotfyle's curated collection
  - Potentially access user ratings, categories, and usage statistics from Dotfyle

- [ ] **33. Add 'newly posted' plugins view similar to lazy.nvim updates**
  - Create dedicated view/tab showing recently added plugins to the database
  - Display plugins discovered in the last week/month with timestamps
  - Show diff-style interface highlighting new additions since last check
  - Add notification system for new plugins matching user's interests
  - Implement lazy.nvim-style update interface with expandable plugin details
  - Allow users to mark plugins as "seen" to track what's new for them

---

## 🔮 Future Enhancement Ideas (Optional)

- [ ] **23. Highlight groups integration**
  - Custom highlight groups for better theming support
  - Integration with user's colorscheme

- [ ] **24. Dynamic window resizing**
  - Resize windows on tab switching or focus changes
  - More responsive layout adjustments

- [ ] **25. Improved window management**
  - Add autocmd to close all components if one is closed unexpectedly
  - Better cleanup and error recovery

- [ ] **26. Tag-based filtering**
  - Add filtering by plugin categories/tags
  - Parse and display plugin tags from repository metadata

---

## 📝 Notes

**Last Updated**: 2025-07-09

This TODO.md file is now the canonical source for tracking development progress. The roadmap has been moved from CLAUDE.md to this dedicated tracking document for better organization and clarity.
