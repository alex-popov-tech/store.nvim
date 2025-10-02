---@class HoverConfig
---@field repository Repository The repository to show details for

---@class HoverState
---@field win_id number|nil Window ID
---@field buf_id number|nil Buffer ID
---@field is_closed boolean Closed state flag

---@class Hover
---@field config HoverConfig Configuration
---@field state HoverState Component state
---@field show fun(self: Hover): string|nil
---@field close fun(self: Hover): string|nil
