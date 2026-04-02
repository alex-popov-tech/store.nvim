---@class HoverConfig
---@field repository Repository The repository to show details for
---@field download_stats_weekly number|nil Weekly download count for this repo
---@field download_stats_monthly number|nil Monthly download count for this repo
---@field view_stats_weekly number|nil Weekly view count for this repo
---@field view_stats_monthly number|nil Monthly view count for this repo

---@class HoverState
---@field win_id number|nil Window ID
---@field buf_id number|nil Buffer ID
---@field is_closed boolean Closed state flag

---@class Hover
---@field config HoverConfig Configuration
---@field state HoverState Component state
---@field show fun(self: Hover): string|nil
---@field close fun(self: Hover): string|nil
