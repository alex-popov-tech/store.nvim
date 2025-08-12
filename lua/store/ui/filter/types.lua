---@class FilterConfig
---@field width number Window width
---@field height number Window height in lines
---@field row number Window row position
---@field col number Window column position
---@field current_query string Current filter query to pre-fill
---@field on_value fun(query: string) Callback when filter is applied
---@field on_exit fun() Callback when filter is cancelled (handles focus restoration)

---@class FilterState
---@field win_id number|nil Window ID
---@field buf_id number|nil Buffer ID
---@field is_open boolean Window open status
---@field state string Current component state - "loading", "ready", "error"

---@class FilterStateUpdate
---@field state string?

---@class Filter
---@field config FilterConfig Window configuration
---@field state FilterState Component state
---@field open fun(self: Filter): string|nil
---@field close fun(self: Filter): string|nil
---@field render fun(self: Filter, data: FilterStateUpdate|nil): string|nil
---@field focus fun(self: Filter): string|nil
---@field get_window_id fun(self: Filter): number|nil
---@field is_valid fun(self: Filter): boolean
---@field apply_filter fun(self: Filter): string|nil
---@field cancel_filter fun(self: Filter): string|nil
