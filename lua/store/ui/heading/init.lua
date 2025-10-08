local validations = require("store.ui.heading.validations")
local utils = require("store.utils")
local logger = require("store.logger").createLogger({ context = "heading" })

local M = {}

local DEFAULT_HEADING_CONFIG = {}

local DEFAULT_STATE = {
  -- Window state
  win_id = nil,
  buf_id = nil,
  is_open = false,
  -- UI state
  state = "loading",
  filter_query = "",
  sort_type = "default",
  filtered_count = 0,
  total_count = 0,
  installed_count = 0,
  plugin_manager_mode = "not-selected",
  plugin_manager_overview = {},
}

-- ASCII art for store.nvim
local ASCII_ART = {
  "      _                              _",
  "     | |                            (_)",
  "  ___| |_ ___  _ __ ___   _ ____   ___ _ __ ___",
  " / __| __/ _ \\| '__/ _ \\ | '_ \\ \\ / / | '_ ` _ \\",
  " \\__ \\ || (_) | | |  __/_| | | \\ V /| | | | | | |",
  " |___/\\__\\___/|_|  \\___(_)_| |_|\\_/ |_|_| |_| |_|",
}

---Create a formatted line with left and right content, properly spaced and padded
---@param width number Total width of the line
---@param left string|nil Left-aligned content
---@param right string|nil Right-aligned content
---@return string Formatted line with proper spacing and 1 column right padding
local function format_line(width, left, right)
  left = left or ""
  right = right or ""

  -- Reserve 1 column for right padding
  local right_padding = 1
  local usable_width = width - right_padding

  -- If both left and right content fit with at least 1 space between
  local min_spacing = 1
  local available_space = usable_width - #left - #right - min_spacing

  if available_space >= 0 then
    -- Normal case: both fit with proper spacing
    local spacing = min_spacing + available_space
    return left .. string.rep(" ", spacing) .. right .. string.rep(" ", right_padding)
  else
    -- Content is too long for the width, truncate right content
    local max_right_length = usable_width - #left - min_spacing
    if max_right_length > 0 then
      local truncated_right = string.sub(right, 1, max_right_length - 3) .. "..."
      return left .. string.rep(" ", min_spacing) .. truncated_right .. string.rep(" ", right_padding)
    else
      -- Even left content is too long, just return left content truncated
      return string.sub(left, 1, usable_width) .. string.rep(" ", right_padding)
    end
  end
end

-- Heading class
local Heading = {}
Heading.__index = Heading

---Create a new heading window instance
---@param heading_config HeadingConfig|nil Heading window configuration
---@return Heading|nil instance Heading instance on success, nil on error
---@return string|nil error Error message on failure, nil on success
function M.new(heading_config)
  -- Merge with defaults first
  local config = vim.tbl_deep_extend("force", DEFAULT_HEADING_CONFIG, heading_config or {})

  -- Validate merged configuration
  local error_msg = validations.validate_config(config)
  if error_msg then
    return nil, "Heading window configuration validation failed: " .. error_msg
  end

  local instance = {
    config = config,
    state = vim.tbl_deep_extend("force", DEFAULT_STATE, {
      buf_id = utils.create_scratch_buffer(),
      plugin_manager_overview = {},
    }),
  }

  setmetatable(instance, Heading)

  return instance, nil
end

---Open the heading window with default content
---@return string|nil error Error message on failure, nil on success
function Heading:open()
  if self.state.is_open then
    logger.warn("Heading window: open() called when window is already open")
    return nil
  end

  local store_config = require("store.config")
  local plugin_config = store_config.get()

  local window_config = {
    width = self.config.width,
    height = self.config.height,
    row = self.config.row,
    col = self.config.col,
    focusable = false, -- Header should not be focusable
    zindex = plugin_config.zindex.base,
  }

  -- Window options optimized for static header display
  local window_opts = {
    cursorline = false, -- No cursor line for header
    wrap = false,
    linebreak = false,
  }

  local win_id, error_message = utils.create_floating_window({
    buf_id = self.state.buf_id,
    config = window_config,
    opts = window_opts,
  })
  if error_message then
    return "Cannot open heading window: " .. error_message
  end

  self.state.win_id = win_id
  self.state.is_open = true

  -- Set default content
  return self:render(self.state)
end

---Render error state (ASCII art only)
---@private
function Heading:_render_error()
  local content_lines = {}
  local width = self.config.width

  for i = 1, #ASCII_ART do
    table.insert(content_lines, format_line(width, ASCII_ART[i]))
  end

  utils.set_lines(self.state.buf_id, content_lines)
end

---Render loading state (ASCII art only)
---@private
function Heading:_render_loading()
  local content_lines = {}
  local width = self.config.width

  for i = 1, #ASCII_ART do
    table.insert(content_lines, format_line(width, ASCII_ART[i]))
  end

  utils.set_lines(self.state.buf_id, content_lines)
end

---Render ready state (ASCII art with full info)
---@private
---@param state HeadingState Heading display data
function Heading:_render_ready(state)
  local content_lines = {}
  local width = self.config.width

  -- Line 0: ASCII art + plugin manager summary
  local overview = state.plugin_manager_overview or {}
  local manager_segments = {}
  local ordered_managers = { "vim.pack", "lazy.nvim" }

  for _, manager in ipairs(ordered_managers) do
    local info = overview[manager]
    if info and type(info.count) == "number" and info.count > 0 then
      table.insert(manager_segments, string.format("%d plugin(s) managed by %s", info.count, manager))
    end
  end

  local manager_text
  if #manager_segments > 0 then
    manager_text = table.concat(manager_segments, ", ")
  elseif state.plugin_manager_mode and state.plugin_manager_mode ~= "not-selected" then
    manager_text = string.format("%d plugins managed by %s", state.installed_count or 0, state.plugin_manager_mode)
  else
    manager_text = ""
  end

  table.insert(content_lines, format_line(width, ASCII_ART[1], manager_text))

  -- Line 1: ASCII art + showing plugins count
  local showing_text = string.format("Showing %d plugins", state.filtered_count)
  table.insert(content_lines, format_line(width, ASCII_ART[2], showing_text))

  -- Line 2: ASCII art + filter and sort info
  local filter_text = "Filter: " .. (state.filter_query ~= "" and state.filter_query or "none")
  table.insert(content_lines, format_line(width, ASCII_ART[3], filter_text))

  -- Line 3: ASCII art + empty line
  local sort_text = ""
  if state.sort_type and state.sort_type ~= "default" then
    local sort = require("store.sort")
    sort_text = sort.sorts[state.sort_type].label
  else
    sort_text = "Default"
  end
  table.insert(content_lines, format_line(width, ASCII_ART[4], "Sort: " .. sort_text))

  -- Line 4: ASCII art + empty line
  table.insert(content_lines, format_line(width, ASCII_ART[5]))

  -- Line 5: ASCII art + help text
  table.insert(content_lines, format_line(width, ASCII_ART[6], "`?` for help"))

  utils.set_lines(self.state.buf_id, content_lines)
end

---Render updated heading content
---@param state HeadingStateUpdate Updated partial state
---@return string|nil error Error message on failure, nil on success
function Heading:render(state)
  if not self.state.is_open then
    return "Heading window: Cannot render - window not open"
  end

  if not self.state.buf_id then
    return "Heading window: Cannot render - invalid buffer"
  end

  -- Create new state locally by merging current state with update
  local new_state = vim.tbl_deep_extend("force", self.state, state)

  -- Validate the merged state before applying it
  local validation_error = validations.validate_state(new_state)
  if validation_error then
    return "Heading window: Invalid state update - " .. validation_error
  end

  -- Only assign to self.state if validation passes
  self.state = new_state

  -- Only schedule the final rendering dispatch using safe self.state
  vim.schedule(function()
    if self.state.state == "loading" then
      self:_render_loading()
    elseif self.state.state == "error" then
      self:_render_error()
    else
      self:_render_ready(self.state)
    end
  end)

  return nil
end

---Close the heading window
---@return string|nil error Error message on failure, nil on success
function Heading:close()
  if not self.state.is_open then
    logger.warn("Heading window: close() called when window is not open")
    return nil
  end

  -- Close window
  if self.state.win_id and vim.api.nvim_win_is_valid(self.state.win_id) then
    local success, err = pcall(vim.api.nvim_win_close, self.state.win_id, true)
    if not success then
      return "Failed to close heading window: " .. tostring(err)
    end
  end

  -- Reset window state (keep buffer)
  self.state.win_id = nil
  self.state.is_open = false

  return nil
end

---Focus the heading window
---@return string|nil error Error message on failure, nil on success
function Heading:focus()
  if not self.state.is_open then
    return "Heading window: Cannot focus - window not open"
  end
  if not self.state.win_id or not vim.api.nvim_win_is_valid(self.state.win_id) then
    return "Heading window: Cannot focus - invalid window"
  end

  vim.api.nvim_set_current_win(self.state.win_id)
  return nil
end

---Resize the heading window and update layout
---@param layout_config {width: number, height: number, row: number, col: number} New layout configuration
---@return string|nil error Error message if resize failed, nil if successful
function Heading:resize(layout_config)
  -- Validate layout_config parameters
  if not layout_config or type(layout_config) ~= "table" then
    return "Invalid layout_config: must be a table"
  end

  local required_fields = { "width", "height", "row", "col" }
  for _, field in ipairs(required_fields) do
    if not layout_config[field] or type(layout_config[field]) ~= "number" then
      return "Invalid layout_config: " .. field .. " must be a number"
    end
    if layout_config[field] < 0 then
      return "Invalid layout_config: " .. field .. " must be non-negative"
    end
  end

  if not self.state.is_open or not self.state.win_id or not vim.api.nvim_win_is_valid(self.state.win_id) then
    return "Cannot resize heading window: window not open or invalid"
  end

  -- Update config for future renders
  self.config.width = layout_config.width
  self.config.height = layout_config.height
  self.config.row = layout_config.row
  self.config.col = layout_config.col

  local store_config = require("store.config")
  local plugin_config = store_config.get()

  local win_config = {
    relative = "editor",
    row = layout_config.row,
    col = layout_config.col,
    width = layout_config.width,
    height = layout_config.height,
    style = "minimal",
    border = "rounded",
    zindex = plugin_config.zindex.base,
  }

  local success, err = pcall(vim.api.nvim_win_set_config, self.state.win_id, win_config)
  if not success then
    return "Failed to resize heading window: " .. (err or "unknown error")
  end

  -- Re-render content with new dimensions to ensure proper formatting
  if self.state.state ~= "loading" then
    local render_error = self:render({
      state = self.state.state,
      filter_query = self.state.filter_query,
      sort_type = self.state.sort_type,
      filtered_count = self.state.filtered_count,
      total_count = self.state.total_count,
      installed_count = self.state.installed_count,
    })
    if render_error then
      logger.warn("Failed to re-render heading after resize: " .. render_error)
    end
  end

  return nil
end

---Get the window ID of the heading component
---@return number|nil window_id Window ID if open, nil otherwise
function Heading:get_window_id()
  if self.state.is_open and self.state.win_id and vim.api.nvim_win_is_valid(self.state.win_id) then
    return self.state.win_id
  end
  return nil
end

---Check if the heading component is in a valid state
---@return boolean is_valid True if component is valid and ready for use
function Heading:is_valid()
  return self.state.buf_id ~= nil
    and vim.api.nvim_buf_is_valid(self.state.buf_id)
    and (not self.state.is_open or (self.state.win_id and vim.api.nvim_win_is_valid(self.state.win_id)))
end

return M
