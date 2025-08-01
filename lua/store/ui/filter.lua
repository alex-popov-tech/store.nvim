local validators = require("store.validators")
local utils = require("store.utils")

local M = {}

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

local DEFAULT_FILTER_CONFIG = {
  width = 60,
  height = 1,
}

local DEFAULT_STATE = {
  win_id = nil,
  buf_id = nil,
  is_open = false,
  state = "loading",
}

---Validate filter configuration
---@param config FilterConfig|nil
---@return string|nil Error message or nil if valid
local function validate_config(config)
  if not config then
    return "filter.config must be a table, got: nil"
  end

  local width_error =
    validators.should_be_positive_number(config.width, "filter.config.width must be a positive number")
  if width_error then
    return width_error
  end

  local height_error =
    validators.should_be_positive_number(config.height, "filter.config.height must be a positive number")
  if height_error then
    return height_error
  end

  local row_error = validators.should_be_number(config.row, "filter.config.row must be a number")
  if row_error then
    return row_error
  end

  local col_error = validators.should_be_number(config.col, "filter.config.col must be a number")
  if col_error then
    return col_error
  end

  local current_query_error =
    validators.should_be_string(config.current_query, "filter.config.current_query must be a string")
  if current_query_error then
    return current_query_error
  end

  if not config.on_value or type(config.on_value) ~= "function" then
    return "filter.config.on_value must be a function, got: " .. type(config.on_value)
  end

  if not config.on_exit or type(config.on_exit) ~= "function" then
    return "filter.config.on_exit must be a function, got: " .. type(config.on_exit)
  end

  return nil
end

---Validate filter state
---@param state FilterState
---@return string|nil Error message or nil if valid
local function validate_state(state)
  if not state then
    return "filter.state must be a table, got: nil"
  end

  local is_open_error = validators.should_be_boolean(state.is_open, "filter.state.is_open must be a boolean")
  if is_open_error then
    return is_open_error
  end

  local state_error = validators.should_be_string(state.state, "filter.state.state must be a string")
  if state_error then
    return state_error
  end

  return nil
end

-- Filter class
local Filter = {}
Filter.__index = Filter

---Create new Filter instance
---@param filter_config FilterConfig|nil Configuration
---@return Filter|nil, string|nil Instance or nil, error message or nil
function M.new(filter_config)
  -- Merge with defaults
  local merged_config = vim.tbl_deep_extend("force", DEFAULT_FILTER_CONFIG, filter_config or {})

  -- Validate configuration
  local config_error = validate_config(merged_config)
  if config_error then
    return nil, config_error
  end

  -- Initialize state
  local merged_state = vim.tbl_deep_extend("force", DEFAULT_STATE, {})

  -- Validate state
  local state_error = validate_state(merged_state)
  if state_error then
    return nil, state_error
  end

  -- Create instance
  local instance = {
    config = merged_config,
    state = merged_state,
  }
  setmetatable(instance, Filter)

  -- Create buffer in constructor
  local buf_id, buf_error = instance:_create_buffer()
  if buf_error then
    return nil, "Filter buffer creation failed: " .. buf_error
  end
  instance.state.buf_id = buf_id

  return instance, nil
end

---Get current filter query from buffer
---@return string Current query text
function Filter:_get_current_query()
  if not self.state.buf_id or not vim.api.nvim_buf_is_valid(self.state.buf_id) then
    return ""
  end

  local lines = vim.api.nvim_buf_get_lines(self.state.buf_id, 0, -1, false)
  -- Join multiple lines with spaces and trim whitespace
  local query = table.concat(lines, " ")
  return vim.trim(query)
end

---Apply current filter and close component
---@return string|nil Error message or nil on success
function Filter:apply_filter()
  local query = self:_get_current_query()
  local on_value = self.config.on_value

  local close_error = self:close()
  if close_error then
    return close_error
  end

  -- Call callback after cleanup
  if on_value then
    on_value(query)
  end

  return nil
end

---Cancel filter and close component
---@return string|nil Error message or nil on success
function Filter:cancel_filter()
  local on_exit = self.config.on_exit

  local close_error = self:close()
  if close_error then
    return close_error
  end

  -- Call callback after cleanup
  if on_exit then
    on_exit()
  end

  return nil
end

---Create and configure buffer
---@return number|nil, string|nil Buffer ID or nil, error message or nil
function Filter:_create_buffer()
  local buf_id = utils.create_scratch_buffer({
    buftype = "nofile",
    modifiable = true,
    readonly = false,
  })

  if not buf_id then
    return nil, "Failed to create scratch buffer"
  end

  -- Set initial content (just the current query)
  vim.api.nvim_buf_set_lines(buf_id, 0, -1, false, { self.config.current_query })

  return buf_id, nil
end

---Setup buffer-local keymaps
---@param buf_id number Buffer ID
---@return string|nil Error message or nil on success
function Filter:_setup_keymaps(buf_id)
  if not buf_id or not vim.api.nvim_buf_is_valid(buf_id) then
    return "Invalid buffer ID for keymap setup"
  end

  -- Normal mode keymaps
  local normal_keymaps = {
    ["<cr>"] = function()
      self:apply_filter()
    end,
    ["<esc>"] = function()
      self:cancel_filter()
    end,
    ["q"] = function()
      self:cancel_filter()
    end,
    ["<c-c>"] = function()
      self:cancel_filter()
    end,
  }

  -- Insert mode keymaps
  local insert_keymaps = {
    ["<cr>"] = function()
      self:apply_filter()
    end,
  }

  -- Set up normal mode keymaps
  for key, callback in pairs(normal_keymaps) do
    vim.api.nvim_buf_set_keymap(buf_id, "n", key, "", {
      noremap = true,
      silent = true,
      callback = callback,
    })
  end

  -- Set up insert mode keymaps
  for key, callback in pairs(insert_keymaps) do
    vim.api.nvim_buf_set_keymap(buf_id, "i", key, "", {
      noremap = true,
      silent = true,
      callback = callback,
    })
  end

  return nil
end

---Open filter window
---@return string|nil Error message or nil on success
function Filter:open()
  if self.state.is_open then
    return "Filter window is already open"
  end

  if not self.state.buf_id or not vim.api.nvim_buf_is_valid(self.state.buf_id) then
    return "Filter buffer is invalid"
  end

  -- Setup keymaps
  local keymap_error = self:_setup_keymaps(self.state.buf_id)
  if keymap_error then
    return "Filter keymap setup failed: " .. keymap_error
  end

  -- Create window
  local store_config = require("store.config")
  local plugin_config = store_config.get()

  local win_id, win_error = utils.create_floating_window({
    buf_id = self.state.buf_id,
    config = {
      relative = "editor",
      width = self.config.width,
      height = self.config.height,
      row = self.config.row,
      col = self.config.col,
      style = "minimal",
      border = "rounded",
      zindex = plugin_config.zindex.popup,
    },
    opts = {
      focus = true,
    },
  })

  if win_error then
    return "Filter window creation failed: " .. win_error
  end

  if not win_id then
    return "Filter window creation returned nil window ID"
  end

  self.state.win_id = win_id
  self.state.is_open = true
  self.state.state = "ready"

  -- Start in insert mode at end of line
  if vim.api.nvim_win_is_valid(win_id) then
    vim.api.nvim_win_set_cursor(win_id, { 1, #self.config.current_query })
    vim.cmd("startinsert!")
  end

  return nil
end

---Close the filter window
---@return string|nil Error message or nil on success
function Filter:close()
  if not self.state.is_open then
    return nil -- Already closed, not an error
  end

  -- Store references before cleanup to prevent race conditions
  local win_id = self.state.win_id
  local buf_id = self.state.buf_id

  -- Clean up state immediately to prevent multiple calls
  self.state.win_id = nil
  self.state.buf_id = nil
  self.state.is_open = false
  self.state.state = "loading"

  -- Close window
  if win_id and vim.api.nvim_win_is_valid(win_id) then
    vim.api.nvim_win_close(win_id, true)
  end

  -- Close buffer
  if buf_id and vim.api.nvim_buf_is_valid(buf_id) then
    vim.api.nvim_buf_delete(buf_id, { force = true })
  end

  return nil
end

---Render filter with updated data
---@param state_update FilterStateUpdate|nil State updates to apply
---@return string|nil Error message or nil on success
function Filter:render(state_update)
  if not self.state.is_open then
    return "Cannot render closed Filter window"
  end

  if state_update then
    -- Merge state updates
    local updated_state = vim.tbl_deep_extend("force", self.state, state_update)

    -- Validate merged state
    local state_error = validate_state(updated_state)
    if state_error then
      return "Invalid state update: " .. state_error
    end

    -- Apply valid state updates
    self.state = updated_state
  end

  -- Update buffer content
  local content_error = self:_update_buffer_content()
  if content_error then
    return "Failed to render content: " .. content_error
  end

  return nil
end

---Focus the filter window
---@return string|nil Error message or nil on success
function Filter:focus()
  if not self.state.is_open or not self.state.win_id then
    return "Cannot focus closed or invalid Filter window"
  end

  if not vim.api.nvim_win_is_valid(self.state.win_id) then
    return "Cannot focus invalid window"
  end

  vim.api.nvim_set_current_win(self.state.win_id)
  return nil
end

---Get window ID
---@return number|nil Window ID or nil if not open
function Filter:get_window_id()
  if self.state.is_open and self.state.win_id and vim.api.nvim_win_is_valid(self.state.win_id) then
    return self.state.win_id
  end
  return nil
end

---Check if filter is valid and ready
---@return boolean True if valid and usable
function Filter:is_valid()
  return self.state.is_open
    and self.state.win_id ~= nil
    and vim.api.nvim_win_is_valid(self.state.win_id)
    and self.state.buf_id ~= nil
    and vim.api.nvim_buf_is_valid(self.state.buf_id)
    and self.state.state == "ready"
end

return M
