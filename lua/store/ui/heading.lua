local validators = require("store.validators")
local logger = require("store.logger")
local utils = require("store.utils")

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

local M = {}

---@class HeadingConfig
---@field width number Window width
---@field height number Window height
---@field row number Window row position
---@field col number Window column position

---@class HeadingState
---@field win_id number|nil Window ID
---@field buf_id number|nil Buffer ID
---@field is_open boolean Window open status
---@field state string current component state - "loading", "ready", "error"
---@field filter_query string Current filter query
---@field sort_type string Current sort type
---@field filtered_count number Number of plugins after filtering
---@field total_count number Total number of plugins

---@class HeadingStateUpdate
---@field state string?
---@field filter_query string?
---@field sort_type string?
---@field filtered_count number?
---@field total_count number?

---@class Heading
---@field config HeadingConfig Window configuration
---@field state HeadingState Component state
---@field open fun(self: Heading): string|nil
---@field close fun(self: Heading): string|nil
---@field render fun(self: Heading, data: HeadingStateUpdate): string|nil
---@field focus fun(self: Heading): string|nil
---@field resize fun(self: Heading, layout_config: {width: number, height: number, row: number, col: number}): string|nil
---@field get_window_id fun(self: Heading): number|nil
---@field is_valid fun(self: Heading): boolean

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

---Validate heading window configuration
---@param config HeadingConfig Heading window configuration to validate
---@return string|nil error_message Error message if validation fails, nil if valid
local function validate_config(config)
  local err = validators.should_be_table(config, "heading window config must be a table")
  if err then
    return err
  end

  local width_err = validators.should_be_number(config.width, "heading.width must be a number")
  if width_err then
    return width_err
  end

  local height_err = validators.should_be_number(config.height, "heading.height must be a number")
  if height_err then
    return height_err
  end

  local row_err = validators.should_be_number(config.row, "heading.row must be a number")
  if row_err then
    return row_err
  end

  local col_err = validators.should_be_number(config.col, "heading.col must be a number")
  if col_err then
    return col_err
  end

  return nil
end

---Validate heading state for consistency and safety
---@param state HeadingState Heading state to validate
---@return string|nil error_message Error message if validation fails, nil if valid
local function validate_state(state)
  local err = validators.should_be_table(state, "heading state must be a table")
  if err then
    return err
  end

  -- Validate state field
  if state.state ~= nil then
    local state_err = validators.should_be_string(state.state, "heading.state must be a string")
    if state_err then
      return state_err
    end

    local valid_states = { loading = true, ready = true, error = true }
    if not valid_states[state.state] then
      return "heading.state must be one of 'loading', 'ready', 'error', got: " .. state.state
    end
  end

  -- Validate window state fields
  if state.win_id ~= nil then
    local win_err = validators.should_be_number(state.win_id, "heading.win_id must be nil or a number")
    if win_err then
      return win_err
    end
  end

  if state.buf_id ~= nil then
    local buf_err = validators.should_be_number(state.buf_id, "heading.buf_id must be nil or a number")
    if buf_err then
      return buf_err
    end
  end

  if state.is_open ~= nil then
    if type(state.is_open) ~= "boolean" then
      return "heading.is_open must be nil or a boolean, got: " .. type(state.is_open)
    end
  end

  -- Validate UI state fields
  if state.filter_query ~= nil then
    local filter_err = validators.should_be_string(state.filter_query, "heading.filter_query must be nil or a string")
    if filter_err then
      return filter_err
    end
  end

  if state.sort_type ~= nil then
    local sort_err = validators.should_be_string(state.sort_type, "heading.sort_type must be nil or a string")
    if sort_err then
      return sort_err
    end
  end

  if state.filtered_count ~= nil then
    local filtered_err =
      validators.should_be_number(state.filtered_count, "heading.filtered_count must be nil or a number")
    if filtered_err then
      return filtered_err
    end

    if state.filtered_count < 0 then
      return "heading.filtered_count must be non-negative, got: " .. state.filtered_count
    end
  end

  if state.total_count ~= nil then
    local total_err = validators.should_be_number(state.total_count, "heading.total_count must be nil or a number")
    if total_err then
      return total_err
    end

    if state.total_count < 0 then
      return "heading.total_count must be non-negative, got: " .. state.total_count
    end
  end

  return nil
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
  local error_msg = validate_config(config)
  if error_msg then
    return nil, "Heading window configuration validation failed: " .. error_msg
  end

  local instance = {
    config = config,
    state = vim.tbl_deep_extend("force", DEFAULT_STATE, {
      buf_id = utils.create_scratch_buffer(),
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

  local window_config = {
    width = self.config.width,
    height = self.config.height,
    row = self.config.row,
    col = self.config.col,
    focusable = false, -- Header should not be focusable
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

  -- Line 0: ASCII art + filter info
  local filter_text = ""
  if state.filter_query ~= "" then
    filter_text = "Filter: " .. state.filter_query
  else
    filter_text = "Filter: none"
  end
  table.insert(content_lines, format_line(width, ASCII_ART[1], filter_text))

  -- Line 1: ASCII art only (empty line)
  table.insert(content_lines, format_line(width, ASCII_ART[2]))

  -- Line 2: ASCII art + sort info
  local sort_text = ""
  if state.sort_type then
    local sort = require("store.sort")
    sort_text = "Sort: " .. sort.sorts[state.sort_type].label
  else
    sort_text = "Sort: Default"
  end
  table.insert(content_lines, format_line(width, ASCII_ART[3], sort_text))

  -- Line 3: ASCII art only (empty line)
  table.insert(content_lines, format_line(width, ASCII_ART[4]))

  -- Line 4: ASCII art + plugin count
  local count_text = string.format("Showing %d of %d plugins", state.filtered_count, state.total_count)
  table.insert(content_lines, format_line(width, ASCII_ART[5], count_text))

  -- Line 5: ASCII art + help text
  local help_text = "Press ? for help"
  table.insert(content_lines, format_line(width, ASCII_ART[6], help_text))

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
  local validation_error = validate_state(new_state)
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

---Resize the heading window to new layout dimensions
---@param layout_config {width: number, height: number, row: number, col: number} New layout configuration
---@return string|nil error Error message if resize failed, nil if successful
function Heading:resize(layout_config)
  if not self.state.is_open or not self.state.win_id or not vim.api.nvim_win_is_valid(self.state.win_id) then
    return "Cannot resize heading window: window not open or invalid"
  end

  local success, err = pcall(vim.api.nvim_win_set_config, self.state.win_id, {
    relative = "editor",
    width = layout_config.width,
    height = layout_config.height,
    row = layout_config.row,
    col = layout_config.col,
    style = "minimal",
    border = "rounded",
    zindex = 50,
  })

  if not success then
    return "Failed to resize heading window: " .. (err or "unknown error")
  end

  -- Update internal config
  self.config.width = layout_config.width
  self.config.height = layout_config.height
  self.config.row = layout_config.row
  self.config.col = layout_config.col

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
