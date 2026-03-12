# Codebase Structure

**Analysis Date:** 2026-03-12

## Directory Layout

```
lua/store/
├── actions.lua                    # High-level user actions (filter, sort, navigate)
├── config.lua                     # Configuration schema and layout calculation
├── init.lua                       # Plugin entry point (setup, open)
├── keymaps.lua                    # Keymap binding definitions
├── logger.lua                     # Structured logging module
├── sort.lua                       # Sort type definitions and comparators
├── telemetry.lua                  # Anonymous usage tracking
├── types.lua                      # Type definitions for repositories and schema
├── utils.lua                      # Shared utilities (URL opening, filtering, etc)
├── validators.lua                 # Central config validators
│
├── database/                      # Data access layer
│   ├── init.lua                   # Database facade (fetch, cache, clear)
│   ├── cache.lua                  # Persistent file caching
│   ├── github_client.lua          # GitHub API client
│   ├── gitlab_client.lua          # GitLab API client
│   └── utils.lua                  # Database utilities (JSON parsing, etc)
│
├── modes/                         # Window layout strategies
│   ├── float.lua                  # Floating window implementation
│   └── split.lua                  # Split window implementation
│
├── plenary/                       # Vendored plenary.nvim utilities
│   ├── bit.lua                    # Bitwise operations
│   ├── compat.lua                 # Compatibility helpers
│   ├── curl.lua                   # HTTP client wrapper
│   ├── functional.lua             # Functional programming utilities
│   ├── job.lua                    # Job execution
│   ├── path.lua                   # Path manipulation
│   └── scandir.lua                # Directory scanning
│
└── ui/                            # User interface components
    ├── highlights.lua             # Highlight group definitions
    ├── help.lua                   # Help popup component
    ├── tabs.lua                   # Tab label building utilities
    │
    ├── filter/                    # Filter modal component
    │   ├── init.lua               # Filter component implementation
    │   ├── types.lua              # Filter type definitions
    │   └── validations.lua        # Filter config validation
    │
    ├── heading/                   # Heading/status bar component
    │   ├── init.lua               # Heading rendering and state
    │   ├── types.lua              # Heading type definitions
    │   ├── validations.lua        # Heading config validation
    │   └── wave.lua               # Wave animation for status
    │
    ├── hover/                     # Hover info component
    │   ├── init.lua               # Hover display implementation
    │   └── types.lua              # Hover type definitions
    │
    ├── install_modal/             # Installation instructions modal
    │   ├── init.lua               # Install modal implementation
    │   ├── types.lua              # Install modal types
    │   └── validations.lua        # Install modal validation
    │
    ├── list/                      # Plugin list component
    │   ├── init.lua               # List rendering and interaction
    │   ├── types.lua              # List type definitions
    │   └── validations.lua        # List config validation
    │
    ├── preview/                   # README/docs preview component
    │   ├── init.lua               # Preview rendering and state
    │   ├── types.lua              # Preview type definitions
    │   └── validations.lua        # Preview config validation
    │
    ├── sort_select/               # Sort selection modal
    │   ├── init.lua               # Sort modal implementation
    │   ├── types.lua              # Sort modal types
    │   └── validations.lua        # Sort modal validation
    │
    └── store_modal/               # Main modal orchestrator
        ├── init.lua               # StoreModal class and lifecycle
        ├── event_handlers.lua     # Data fetch and Vim event handlers
        ├── event_listeners.lua    # Autocmd registration
        ├── types.lua              # Modal config and state types
        ├── utils.lua              # Modal utilities (filter, sort)
        └── validators.lua         # Modal config validators
```

## Directory Purposes

**lua/store:**
- Purpose: Main plugin namespace
- Contains: Entry point, configuration, core utilities
- Key files: `init.lua` (public API), `config.lua` (configuration), `actions.lua` (operations)

**lua/store/database:**
- Purpose: Data access and caching
- Contains: HTTP clients, cache persistence, plugin database operations
- Key files: `init.lua` (main facade), `cache.lua` (filesystem cache), `github_client.lua` (GitHub API)

**lua/store/modes:**
- Purpose: Window layout implementations
- Contains: Different strategies for displaying windows (floating or split)
- Key files: `float.lua` (floating window layout), `split.lua` (split window layout)

**lua/store/plenary:**
- Purpose: Vendored utility library
- Contains: HTTP client, file operations, functional programming tools
- Key files: `curl.lua` (HTTP), `job.lua` (process execution), `path.lua` (filesystem)

**lua/store/ui:**
- Purpose: User interface components
- Contains: All visual elements and interaction logic
- Key files: `highlights.lua` (colors), `store_modal/init.lua` (main component), component subfolders

**lua/store/ui/store_modal:**
- Purpose: Main modal orchestration
- Contains: StoreModal class, event handling, state management
- Key files: `init.lua` (class definition), `event_handlers.lua` (callbacks), `event_listeners.lua` (Vim autocmds)

**lua/store/ui/{heading,list,preview}:**
- Purpose: Individual window components
- Contains: Component class, rendering logic, event handling
- Pattern: Each has `init.lua` (component), `types.lua` (schemas), `validations.lua` (checks)

**lua/store/ui/{filter,sort_select,install_modal,hover,help}:**
- Purpose: Popup and modal dialogs
- Contains: Temporary UI components that open over main modal
- Pattern: Simpler components with fewer responsibilities than main windows

## Key File Locations

**Entry Points:**
- `lua/store/init.lua`: Plugin setup and open (public API)
- `lua/store/keymaps.lua`: Creates keymap callbacks for each component
- `lua/store/actions.lua`: High-level actions triggered by keybindings

**Configuration:**
- `lua/store/config.lua`: Merges user config with defaults, calculates layouts
- `lua/store/types.lua`: Type definitions for Repository, Database, schema

**Core Logic:**
- `lua/store/ui/store_modal/init.lua`: StoreModal class, component composition
- `lua/store/ui/store_modal/event_handlers.lua`: Responses to data changes and Vim events
- `lua/store/database/init.lua`: Database facade with fetch, cache, clear operations

**UI Components:**
- `lua/store/ui/list/init.lua`: List window with plugin items
- `lua/store/ui/heading/init.lua`: Header/status bar
- `lua/store/ui/preview/init.lua`: README and documentation preview
- `lua/store/ui/highlights.lua`: Highlight group definitions

**Testing:**
- Not yet committed (to be added)

## Naming Conventions

**Files:**
- `init.lua`: Module entry point (e.g., `lua/store/ui/list/init.lua`)
- `types.lua`: Type definitions for component
- `validations.lua`: Config schema validators
- Kebab-case for feature directories: `filter/`, `sort_select/`, `install_modal/`
- Snake_case for utility files: `github_client.lua`, `event_handlers.lua`

**Directories:**
- Kebab-case for feature directories: `store_modal`, `install_modal`, `sort_select`
- Snake_case for functional groupings: `database`, `plenary`
- Descriptive names matching functionality

**Lua Module Names:**
- Lowercase with underscores: `github_client`, `event_handlers`
- Namespaced by path: `store.database.github_client`, `store.ui.filter`

**Functions:**
- snake_case for local and module functions
- PascalCase for class names (e.g., `StoreModal`, `List`, `Preview`)
- Methods defined as `Class:method_name()`

**Variables:**
- snake_case for local and module-level variables
- UPPERCASE for constants
- Prefix `_` for intentionally unused parameters

## Where to Add New Code

**New Feature (New Action):**
- Primary code: Add function to `lua/store/actions.lua`
- Keybinding: Add to `lua/store/keymaps.lua` with callback
- Helpers: Add to `lua/store/ui/store_modal/utils.lua` if action-specific
- Tests: Create `lua/store/actions_spec.lua` (when testing framework added)

**New UI Component (Window or Popup):**
- Implementation: Create `lua/store/ui/component_name/init.lua`
- Types: Create `lua/store/ui/component_name/types.lua`
- Validation: Create `lua/store/ui/component_name/validations.lua`
- Integration: Instantiate in `lua/store/ui/store_modal/init.lua:M.new()`
- Interaction: Add handlers in `lua/store/ui/store_modal/event_handlers.lua` if needed

**New Database Client (GitHub → GitHub/GitLab):**
- Implementation: Create `lua/store/database/gitlab_client.lua` (already exists)
- Reference: Add to database facade `lua/store/database/init.lua` with conditional logic
- Configuration: Add URL mapping in `config.lua` install_catalogue_urls

**Utilities and Helpers:**
- Shared helpers (filter, URL, etc): `lua/store/utils.lua`
- Modal-specific utilities: `lua/store/ui/store_modal/utils.lua`
- Component-specific helpers: Within component directory as needed

**Configuration Options:**
- Add to `UserConfig` class in `lua/store/config.lua`
- Add defaults with type annotation
- Add layout calculation if dimension-related
- Add validator if validation needed
- Document in type definition comments

**Type Definitions:**
- Core domain types (Repository, Database): `lua/store/types.lua`
- Component config types: Component's `types.lua`
- Reusable domain types: Central location or component-specific as appropriate

## Special Directories

**lua/store/plenary/:**
- Purpose: Vendored utility library
- Generated: No (hand-curated from plenary.nvim)
- Committed: Yes (necessary for standalone plugin)
- Modification: Minimal; prefer external plenary.nvim dependency where possible

**lua/store/modes/:**
- Purpose: Layout strategy implementations
- Generated: No
- Committed: Yes
- Extensible: Add new mode file (e.g., `split.lua` or `tiled.lua`) following same pattern

**lua/store/ui/ (all components):**
- Purpose: Isolated UI components
- Generated: No
- Committed: Yes
- Pattern: Each component owns its own state, methods, validation; composed by StoreModal

**.planning/:**
- Purpose: GSD planning documents
- Generated: Yes (by GSD tools)
- Committed: Yes
- Not tracked as codebase (documentation only)

---

*Structure analysis: 2026-03-12*
