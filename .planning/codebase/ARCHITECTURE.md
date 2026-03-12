# Architecture

**Analysis Date:** 2026-03-12

## Pattern Overview

**Overall:** Event-driven stateful modal UI with component-based architecture

**Key Characteristics:**
- Modular component system (heading, list, preview, modal orchestrator)
- Centralized state management in StoreModal instance
- Event-driven data flow (fetch → handlers → render)
- Callback-based async communication with database layer
- Tab-based interface with per-component focus management

## Layers

**Presentation (UI Components):**
- Purpose: Render interactive user interface across multiple windows
- Location: `lua/store/ui/`
- Contains: Window management, rendering logic, user input handling
- Depends on: Config, utilities, keymaps, highlights
- Used by: StoreModal orchestrator

**State & Orchestration:**
- Purpose: Centralized modal state and component coordination
- Location: `lua/store/ui/store_modal/init.lua`
- Contains: StoreModal class, component instances, state object
- Depends on: UI components, database, actions, event handlers
- Used by: Plugin entry point, actions module

**Actions:**
- Purpose: High-level operations triggered by keybindings
- Location: `lua/store/actions.lua`
- Contains: filter, sort, switch_list, switch_install, switch_readme, switch_docs, hover, reset, help, open, close
- Depends on: Database, filters, sorting, UI components
- Used by: Event handlers, keymaps

**Data Access:**
- Purpose: Async data fetching and caching
- Location: `lua/store/database/`
- Contains: GitHub/GitLab clients, cache layer, HTTP utilities
- Depends on: Curl HTTP client, local filesystem for caching
- Used by: Actions, event handlers

**Configuration:**
- Purpose: User settings and layout calculations
- Location: `lua/store/config.lua`
- Contains: UserConfig schema, layout computation, defaults
- Depends on: Validators, utilities
- Used by: Init module, modal setup

**Presentation Modes:**
- Purpose: Window layout strategies
- Location: `lua/store/modes/`
- Contains: Float mode, split mode implementations
- Depends on: Utils, config
- Used by: StoreModal

## Data Flow

**Initialization Flow:**

1. User calls `store.setup(user_config)` → `lua/store/init.lua:M.setup()`
2. Config merges user settings with defaults → `lua/store/config.lua:M.setup()`
3. Config calculates window layout dimensions for all components
4. Plugin is ready, awaiting `store.open()`

**Modal Open Flow:**

1. User calls `store.open()` → `lua/store/init.lua:M.open()`
2. Highlights are setup → `lua/store/ui/highlights.lua:setup()`
3. StoreModal instance created → `lua/store/ui/store_modal/init.lua:M.new(config)`
   - Mode instance created (float/split)
   - Component instances created: heading, list, preview
   - State object initialized with empty data
4. Modal opened → `lua/store/ui/store_modal/init.lua:instance:open()`
   - Windows created via mode
   - Event listeners registered (focus, resize, close)
   - Initial render with loading state
5. Concurrent async fetches triggered:
   - `database.fetch_plugins()` → `lua/store/database/init.lua`
   - `utils.get_installed_plugins()` → Detects plugin manager

**Data Fetch Response Flow:**

1. HTTP response received from remote database
2. Callback invoked → `lua/store/ui/store_modal/event_handlers.lua:on_db()`
3. Event handler updates modal state:
   - `modal.state.repos` = full repository list
   - `modal.state.currently_displayed_repos` = copy for mutations
4. Event handler triggers re-render:
   - `modal.list:render({ items = currently_displayed_repos })`
   - `modal.heading:render({ state = "ready", ... })`

**User Action Flow (Example: Filter):**

1. User presses filter keybinding in list window
2. Keymap calls action → `lua/store/actions.lua:M.filter(instance)`
3. Action creates filter UI component with callback
4. Filter component opens modal
5. User enters query, filter component calls `on_value(query)` callback
6. Callback in action:
   - Calls `utils.filter(repos, query)` to search
   - Updates `instance.state.currently_displayed_repos`
   - Updates `instance.state.filter_query`
   - Re-renders heading and list with filtered data
7. User exits filter, callback restores previous focus

**State Management:**

The `StoreModal` instance maintains state in `lua/store/ui/store_modal/init.lua`:

```lua
state = {
  filter_query = "",                    -- Current filter text
  sort_config = { type = "default" },  -- Sort configuration
  repos = {},                           -- Full unfiltered repo list from DB
  currently_displayed_repos = {},       -- Mutated list (filtered/sorted)

  total_installed_count = 0,            -- Count of installed plugins
  installed_items = {},                 -- Lookup table: repo name → true
  install_catalogue = nil,              -- Install snippets for manager
  install_catalogue_manager = nil,      -- Detected plugin manager
  plugin_manager_mode = "not-selected", -- User's selected manager

  current_focus = nil,                  -- Window ID of focused component
  current_repository = nil,             -- Currently selected repo

  is_closing = false,                   -- Graceful close flag
  autocmds = {},                        -- Registered autocmd IDs
}
```

State mutations flow: Action handler → State update → Component re-render

## Key Abstractions

**Modal Component Pattern:**
- Purpose: Encapsulate window state and rendering
- Examples: `lua/store/ui/heading/init.lua`, `lua/store/ui/list/init.lua`, `lua/store/ui/preview/init.lua`, `lua/store/ui/filter/init.lua`, `lua/store/ui/sort_select/init.lua`
- Pattern: Lua class with metatable, instance methods for render/focus/close

**Event Handler Pattern:**
- Purpose: Respond to database callbacks and Vim autocmds
- Examples: `lua/store/ui/store_modal/event_handlers.lua`, `lua/store/ui/store_modal/event_listeners.lua`
- Pattern: Named handler functions passed as callbacks, update modal state and trigger renders

**Renderer Function Pattern:**
- Purpose: Convert Repository object to display format
- Location: User-provided config function or default in repo
- Pattern: `fun(repo: Repository, isInstalled: boolean): RepositoryField[]`

## Entry Points

**Plugin Entry Point:**
- Location: `lua/store/init.lua`
- Triggers: User calls `:Store` or `require("store").open()`
- Responsibilities: Setup validation, modal creation, window opening

**User Actions:**
- Location: `lua/store/actions.lua`
- Triggers: Keybindings in focused component windows
- Responsibilities: High-level operations (filter, sort, navigate, refresh)

**Event Handlers:**
- Location: `lua/store/ui/store_modal/event_handlers.lua`
- Triggers: Database callbacks, Vim autocmds (WinEnter, VimResized)
- Responsibilities: State updates, component re-renders, error handling

**Keybinding Callbacks:**
- Location: `lua/store/keymaps.lua`
- Triggers: User keypresses in modal windows
- Responsibilities: Invoke actions with modal instance context

## Error Handling

**Strategy:** Propagate errors upward with nil-coalescing, notify user of critical failures

**Patterns:**

1. **Validation Errors** (Configuration):
   - Validators check config schema → Return error string
   - Handled by setup/creation functions → Log or notify user
   - Example: `lua/store/config.lua:M.setup()` validates config

2. **Data Fetch Errors** (Database):
   - HTTP failures captured in curl callbacks
   - Event handlers check for error parameter
   - Modal displays error state in all components
   - Example: `lua/store/ui/store_modal/event_handlers.lua:on_db(modal, data, err)`

3. **Component Creation Errors**:
   - Component constructors return `(instance, error)` tuple
   - Modal propagates to user as vim.notify error
   - Example: `lua/store/ui/store_modal/init.lua:M.new()` checks creation errors

4. **Runtime Errors**:
   - Wrapped in pcall where needed (e.g., vim.notify)
   - Logged via logger module
   - Do not crash modal (graceful degradation)
   - Example: `lua/store/utils.lua:tryNotify()` wraps notify in pcall

## Cross-Cutting Concerns

**Logging:**
- Module: `lua/store/logger.lua`
- Usage: `local logger = require("store.logger").createLogger({ context = "module_name" })`
- Levels: debug, info, warn, error
- Output: Controlled by `config.logging` level setting

**Validation:**
- Schema validators in each component: `lua/store/ui/*/validations.lua`
- Central config validation: `lua/store/validators.lua`
- Also: `lua/store/ui/store_modal/validators.lua`, `lua/store/ui/store_modal/utils.lua`

**Authentication:**
- GitHub API: Token from environment (optional, increases rate limits)
- GitLab API: Token from environment (optional)
- Handled by clients: `lua/store/database/github_client.lua`, `lua/store/database/gitlab_client.lua`

**Async Operations:**
- Database fetches use callbacks, not coroutines
- Cursor movement debounced with `lua/store/utils.lua:debounce()`
- Resize events debounced via `lua/store/ui/store_modal/event_listeners.lua:listen_for_resize()`
- Pattern: Callback-based async with optional debouncing

**Focus Management:**
- Per-window tracking: `state.current_focus` holds win_id
- Tab switching updates focus: List and Preview maintain separate tab contexts
- Focus restoration: Actions save previous focus before opening popups
- Implementation: `lua/store/ui/store_modal/event_handlers.lua:on_focus_change()`

---

*Architecture analysis: 2026-03-12*
