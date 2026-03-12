# Testing Patterns

**Analysis Date:** 2026-03-12

## Test Framework

**Runner:** Not detected
- No test runner configuration files found (jest.config.js, vitest.config.ts, etc.)
- No Busted, Luaunit, or other Lua test frameworks detected in store.nvim codebase
- No test files in repository

**Assertion Library:** Not applicable

**Build/Dev Commands:**
```bash
# No test execution scripts configured
# Code quality via:
stylua .                # Format code with StyLua
stylua --check .        # Check formatting without changes
```

## Test File Organization

**Current State:** No test files exist

**Recommended Locations (if testing is added):**
- Co-located pattern preferred: `lua/store/ui/list/init.lua` → `lua/store/ui/list/init_spec.lua`
- Alternatively separate directory: `tests/store/ui/list_spec.lua`
- Test discovery would use `*_spec.lua` suffix

**Naming Convention (not yet implemented):**
- Files: `[module_name]_spec.lua`
- Test suites: `describe("[module context]", function() ... end)`
- Test cases: `it("should [expected behavior]", function() ... end)`

## Code Quality Practices (Current)

**Static Analysis:**
- Language server configuration in `.luarc.json`:
  - Runtime: LuaJIT
  - Neovim API support via vim global
  - Third-party library checking disabled
  - Missing-fields diagnostic disabled for flexible table usage

**Code Formatting:**
- Tool: StyLua (`.stylua.toml` at project root)
- Automatically enforced formatting:
  - Column width: 120
  - Indentation: 2 spaces
  - Line endings: Unix
  - Quote style: AutoPreferDouble (prefer double quotes)
- No manual enforcement (no pre-commit hooks detected)

**Validation Pattern (used instead of tests):**
- Runtime validation at component construction time
- Comprehensive validator module `lua/store/validators.lua` with 11 validation functions
- Per-component validation in `lua/store/ui/[component]/validations.lua`
- Validation on config merge before instance creation (list/init.lua lines 78-84)
- Early error returns prevent invalid state construction

## Manual Testing Approach

**Configuration Validation:**
- `lua/store/config.lua` validates all user config fields before setup
- Type checking via `validators.should_be_[type]()` functions
- Range validation: `should_be_number_in_range(value, min, max)`
- Enum validation: `should_be_string_enum(value, allowed_values)`
- Example validation chain (config.lua lines 234-254):
```lua
if config.width ~= nil then
  local err = validators.should_be_positive_number(config.width, "width must be a positive number")
  if err then
    return err
  end
  if config.width > 1 then
    return "width must be a percentage between 0 and 1"
  end
end
```

**State Validation:**
- Component state validated before application (list/init.lua lines 356-359)
- State schema validation in `lua/store/ui/[component]/validations.lua`
- Validates: state field values, type consistency, window ID validity
- Example (list/validations.lua lines 48-59):
```lua
if state.state ~= nil then
  local state_err = validators.should_be_string(state.state, "list.state must be a string")
  if state_err then
    return state_err
  end

  local valid_states = { loading = true, ready = true, error = true }
  if not valid_states[state.state] then
    return "list.state must be one of..."
  end
end
```

**Component Lifecycle Testing:**
- Components implement state machine: `loading` → `ready` or `error`
- State transitions via `render(state_update)` function
- Window validity checks before operations (e.g., list/init.lua lines 384-388)
- Buffer validity checks before mutations (e.g., list/init.lua line 348-350)

## Validator Patterns

**Validators Module (`lua/store/validators.lua`):**
- 11 validation functions exported
- All return `string|nil` (error message or nil for valid)
- Custom error messages supported: `should_be_number(value, "custom message")`
- Type validators: `should_be_number`, `should_be_string`, `should_be_table`, `should_be_function`, `should_be_boolean`
- Specialized validators: `should_be_positive_number`, `should_be_number_in_range`, `should_be_string_enum`, `should_be_valid_border`, `should_be_valid_buffer`, `should_be_valid_keybindings`

**Component Validators:**
- Location: `lua/store/ui/[component]/validations.lua`
- Two validation functions per component:
  - `validate_config(config)` - Validates configuration table at construction
  - `validate_state(state)` - Validates state updates before applying
- Example (list/validations.lua):
```lua
function M.validate_config(config)
  local err = validators.should_be_table(config, "list window config must be a table")
  if err then return err end

  local callback_err = validators.should_be_function(config.on_repo, "list.on_repo must be a function")
  if callback_err then return callback_err end
  -- ... more validations
end

function M.validate_state(state)
  -- Validates state updates
end
```

## Error Handling Testing

**Patterns:**
- Error tuple returns tested in config merge (config.lua lines 502-510)
- Validation errors caught at component construction (list/init.lua lines 81-84)
- Type errors include type information: `"expected to be a number but actual: 'foo' (string)"`
- Safe Vim API calls wrapped in pcall: `local success, err = pcall(vim.notify, ...)` (utils.lua line 14)
- Window/buffer validity checked before operations: `if not vim.api.nvim_win_is_valid(self.state.win_id) then return error`

**Error Callback Testing:**
- HTTP errors captured in response callbacks (github_client.lua lines 25-27)
- JSON parse errors handled: `local success, data = pcall(vim.json.decode, response.body)` (line 70)
- Readme fetch errors with fallback: `if not success then callback(nil, error)` (line 95)

## Performance & State Testing

**Caching Pattern (list/init.lua):**
- Full dataset cache tested via cache hit detection (lines 559-567)
- Cache invalidation on config/state changes: `_clear_cache()` called on update (line 634)
- Cache verification: cache_size vs items array length comparison (line 559)

**Debouncing Pattern (list/init.lua):**
- Cursor movement debouncing tested via timer management (lines 300-306)
- Timer cancellation before new timer (line 301)
- Debounce delay configurable: `cursor_debounce_delay` parameter (line 19)

**Window State Consistency:**
- Active tab state maintained separately from buffer content (lines 207-216)
- Cursor position saved/restored per tab (lines 227-228)
- Window option changes per tab: `vim.api.nvim_set_option_value("cursorline", ...)` (line 225)

## Type Safety Testing

**Annotation Coverage:**
- All public functions have `@param` and `@return` annotations
- All local classes have `@class` definitions with field types
- Type unions used for optional returns: `---@return Repository|nil`
- Optional fields marked: `---@field plugins_folder? string`
- Function signature examples (config.lua lines 497-498):
```lua
---@param user_config? UserConfig User configuration to merge with defaults
---@return string|nil error Error message if setup failed, nil if successful
function M.setup(user_config)
```

**Type Definition Files:**
- Separate type files per component: `lua/store/ui/[component]/types.lua`
- Defines complete class/interface contracts
- Example (list/types.lua):
```lua
---@class ListState
---@field win_id number|nil Window ID
---@field buf_id number|nil Buffer ID
---@field is_open boolean Window open status
---@field state string current component state - "loading", "ready", "error"
---@field items Repository[] List of repositories
```

## Missing Test Coverage

**Untested Areas (High Priority):**
- Network requests (HTTP client behavior): `lua/store/database/github_client.lua`
  - No mocking of curl responses
  - No retry logic testing
  - No timeout handling verification
- Event handlers and callbacks: `lua/store/ui/store_modal/event_handlers.lua`
  - No testing of keyboard/mouse event routing
- Database caching layer: `lua/store/database/utils.lua`
  - No file system operation testing
  - No cache invalidation logic testing
- Installation workflow: list/init.lua `render_install()` and install buffer write handling
  - No file write operation verification
  - No path expansion testing

**Untested Areas (Medium Priority):**
- Resize operations and layout recalculation: all components `on_resize()` methods
- Focus management and window switching: tabs.lua, store_modal/init.lua
- Filter and sort state management: ui components state transitions
- Plugin manager detection and scaffold generation

**Why No Tests Exist:**
- Neovim plugin development typically relies on manual testing in editor
- Heavy dependency on Neovim API (vim.api.nvim_*) makes unit testing difficult
- Window/buffer management inherently stateful and hard to mock
- No test framework integrated in plugin setup

## Recommended Testing Strategy (If Implemented)

**Framework Choice:**
- Busted (Lua testing framework) with assert.is_* assertions
- Or Luaunit for simpler assertion library
- Test file location: `tests/` directory with mirrored structure

**Mock Strategy:**
- Mock Neovim API calls for unit tests
- Mock HTTP responses for github_client testing
- Use fixture data for plugin databases

**Test Coverage Goals:**
- Priority 1: Config validation (high impact, deterministic)
- Priority 2: Component state transitions (core UI logic)
- Priority 3: Event handler routing (prevents regression)
- Priority 4: Integration tests with real Neovim API

---

*Testing analysis: 2026-03-12*
