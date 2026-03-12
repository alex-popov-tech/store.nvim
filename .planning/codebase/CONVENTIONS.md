# Coding Conventions

**Analysis Date:** 2026-03-12

## Naming Patterns

**Files:**
- Module files use snake_case: `github_client.lua`, `event_handlers.lua`, `list.lua`
- Type definition files suffixed with `_types.lua`: `lua/store/ui/list/types.lua`
- Validation files suffixed with `_validations.lua`: `lua/store/ui/list/validations.lua`
- No underscore prefix for private modules (privacy convention documented in code)

**Functions:**
- Public functions in module table `M`: `function M.setup(user_config)` in `lua/store/config.lua`
- Private functions prefixed with underscore: `function List:_render_loading()` in `lua/store/ui/list/init.lua`
- Instance methods use colon notation: `function List:open(win_id)` where `List` is metatable class
- Factory functions use `M.new()`: `function M.new(list_config)` in `lua/store/ui/list/init.lua`
- Callback functions with verb names: `on_repo`, `keymaps_applier`, `repository_renderer`

**Variables:**
- Local state object fields use snake_case: `self.state.win_id`, `self.state.buf_id`, `self.state.is_open`
- Configuration tables use snake_case: `preview_debounce`, `plugin_manager_mode`, `cursor_debounce_delay`
- Constants in UPPER_SNAKE_CASE with comments: `local MIN_MODAL_WIDTH = 85` in `lua/store/ui/heading/init.lua`
- Temporary loop variables short: `for _, repo in ipairs(items)` in `lua/store/ui/list/init.lua`

**Types:**
- Annotation classes use PascalCase: `---@class UserConfig`, `---@class ListState`, `---@class Repository`
- Type annotation fields use snake_case: `---@field width number`, `---@field buf_id number|nil`
- Union types inline with `|`: `---@return string|nil error`
- Optional fields marked with `?`: `---@field plugins_folder? string` in `lua/store/config.lua`

## Code Style

**Formatting:**
- Line width: 120 columns (`.stylua.toml`: `column_width = 120`)
- Indentation: 2 spaces (`indent_width = 2`)
- Unix line endings (`line_endings = "Unix"`)
- Tool: StyLua (`.stylua.toml` at project root)
- Double quotes preferred: `quote_style = "AutoPreferDouble"`

**Linting:**
- Configured in `.luarc.json`: Diagnostics disable `missing-fields` to allow partial tables
- Global `vim` namespace configured as global

## Import Organization

**Order:**
1. Standard library (Neovim/vim APIs)
2. Local project modules (require statements)
3. Same-directory modules (validations, utils, types)

**Examples:**
```lua
-- From lua/store/ui/list/init.lua
local validations = require("store.ui.list.validations")
local utils = require("store.utils")
local tabs = require("store.ui.tabs")
local logger = require("store.logger").createLogger({ context = "list" })

-- From lua/store/config.lua
local validators = require("store.validators")
local utils = require("store.utils")
local keymaps = require("store.keymaps")
local sort = require("store.sort")
```

**Path Aliases:**
- No alias shortcuts used; absolute paths from `lua/` root: `require("store.ui.list.init")`
- Logger pattern: inline instantiation with context: `require("store.logger").createLogger({ context = "heading" })`

## Error Handling

**Patterns:**
- Return tuple `(value, error)` where second return is error string or `nil` on success
- Example from `lua/store/config.lua` line 498: `function M.setup(user_config) ... return nil` (nil means success)
- Example from `lua/store/ui/list/init.lua` line 119: `return nil, "error message"` (nil value, error second)
- Validation functions return error string or nil: `function M.validate_config(config) ... return nil` (line 229)
- Use pcall for unsafe operations: `local success, err = pcall(vim.notify, message, level, opts)` in `lua/store/utils.lua`

**Validation Approach:**
- Centralized validators module `lua/store/validators.lua` with functions: `should_be_number()`, `should_be_string()`, `should_be_table()`, `should_be_function()`, `should_be_positive_number()`, `should_be_number_in_range()`, `should_be_string_enum()`, `should_be_valid_border()`, `should_be_valid_buffer()`
- Custom validators per component in `lua/store/ui/[component]/validations.lua`
- Validation happens at config merge time, before instance creation
- Chain validation checks: early return on first error (line 81-84 in list/init.lua)

**Error Messages:**
- Prepend context: `"List window: Cannot render - "` (line 343 in list/init.lua)
- Include type information in format_actual: `'"value" (string)'` (line 8 in validators.lua)
- Chain error context: `"Modal configuration validation failed: " .. error_msg` (line 25 in store_modal/init.lua)

## Logging

**Framework:** Custom logger module `lua/store/logger.lua`

**Usage:**
- Create logger instance with context: `local logger = require("store.logger").createLogger({ context = "list" })` (line 4 in list/init.lua)
- Levels: `debug()`, `warn()`, `info()`, `error()` (logger.lua lines 75-95)
- Configuration via `config.logging` with levels: `"off"`, `"error"`, `"warn"`, `"info"`, `"debug"` (config.lua line 200)
- Format: `[HH:MM:SS] [store.nvim] [context] [LEVEL] message` (logger.lua line 37)
- Output via `vim.notify` with fallback to print (utils.lua line 13)

**Patterns:**
- Debug for state transitions: `logger.debug("Rendering list with " .. item_count .. " items, state: " .. state.state)` (line 365 in list/init.lua)
- Warn for unexpected conditions: `logger.warn("List window: open() called when window is already open")` (line 121)
- Info for HTTP operations: `logger.info("Fetching from GitHub: " .. url)` (database/github_client.lua line 57)

## Comments

**When to Comment:**
- Above TSDoc/LuaDoc annotations: no additional comments needed (docs serve as comments)
- Complex calculations need explanation: e.g., column width calculation in heading/init.lua line 46-52
- Non-obvious logic decisions: e.g., why pcall wraps cursor position save in list/init.lua line 205
- Avoid commenting obvious code: `self.state.is_open = true` needs no comment

**JSDoc/TSDoc:**
- Lua annotation comments with `---@` prefix for all public functions
- Required fields: `@param`, `@return`, `@class` for types
- Example from config.lua line 67-69:
```lua
---@param config table Configuration with width, height, proportions, and keybindings
---@return StoreModalLayout|nil layout Complete layout if calculation succeeded, nil if failed
---@return string|nil error Error message if calculation failed
```
- Private functions marked with `---@private` comment (list/init.lua line 141)
- Type unions in annotations: `---@return number|nil` for optional returns

## Function Design

**Size:**
- Single responsibility: functions 50-200 lines typical
- Larger orchestration functions can reach 400+ lines (e.g., config layout calculation)
- Private helper methods break up complex rendering: `_calculate_column_widths()`, `_generate_aligned_line()` in list/init.lua

**Parameters:**
- Configuration objects over multiple parameters: `function M.new(list_config)` takes single config table
- Merge with defaults: `local config = vim.tbl_deep_extend("force", DEFAULT_CONFIG, list_config or {})` (line 78)
- Callbacks in config: `on_repo`, `keymaps_applier` passed at construction time
- Use vim.tbl_* functions for table operations: `vim.tbl_deep_extend()`, `vim.tbl_extend()`, `vim.tbl_count()`

**Return Values:**
- Consistent error tuple: `(value, error)` or `(error)` depending on success/failure semantics
- Nil for success in one-return functions: `return nil` means "no error" (config.lua line 516)
- State queries return value or nil: `get_window_id()` returns window ID or nil (list/init.lua line 601)
- Render functions return error or nil (list/init.lua line 341)

## Module Design

**Exports:**
- All modules return single table `M` assigned with public interface
- No direct field access to private state outside metatable class
- Instance methods accessed through returned metatable instance
- Example (list/init.lua line 649): `return M` where M has factory `M.new()` and validators

**Barrel Files:**
- No barrel files (index.lua) observed
- Each component module self-contained with separate types and validations
- Direct imports: `require("store.ui.list.init")` or `require("store.ui.list")`

**State Management:**
- Metatable classes for UI components: `List`, `Heading`, `Preview` with `__index = ClassName` pattern (list/init.lua lines 69-70)
- Instance state in `self.state` table: separate from config in `self.config`
- Immutable config after merge: `self.config = vim.tbl_deep_extend("force", DEFAULT_CONFIG, ...)`
- State updates via `render(state_update)` which merges: `vim.tbl_extend("force", self.state, state)` (list/init.lua line 353)
- Private methods prefixed underscore and called with `:` notation: `self:_render_loading()`

## Class Pattern

**Object-Oriented Structure:**
- Metatable-based classes used for stateful components
- Constructor pattern: `M.new(config)` returns instance with metatable set
- Example from list/init.lua lines 76-101:
```lua
function M.new(list_config)
  local config = vim.tbl_deep_extend("force", DEFAULT_CONFIG, list_config or {})
  local error_msg = validations.validate_config(config)
  if error_msg then
    return nil, error_msg
  end

  local instance = {
    config = config,
    state = vim.tbl_deep_extend("force", DEFAULT_STATE, {...})
  }

  setmetatable(instance, ClassName)
  return instance, nil
end
```

---

*Convention analysis: 2026-03-12*
