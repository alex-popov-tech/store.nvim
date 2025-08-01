local validators = require("store.validators")
local utils = require("store.utils")
local sort = require("store.sort")

---Create buffer content with checkmarks for current sort
---@param current_sort string Current sort type
---@param sort_types string[] Array of sort type keys
---@return string[] Array of content lines
local function _create_content_lines(current_sort, sort_types)
  local lines = {}
  for _, sort_type in ipairs(sort_types) do
    local checkmark = (sort_type == current_sort) and "✓ " or "  "
    local label = sort.sorts[sort_type] and sort.sorts[sort_type].label or sort_type
    table.insert(lines, checkmark .. label)
  end
  return lines
end

local M = {}

---@class SortSelectConfig
---@field width number Window width
---@field height number Window height
---@field row number Window row position
---@field col number Window column position
---@field current_sort string Current sort type to mark with checkmark
---@field on_value fun(selected_sort: string) Callback when user selects a sort
---@field on_exit fun() Callback when user cancels (handles focus restoration)
---@field sort_types string[]|nil Optional sort types array (falls back to store.sort)

---@class SortSelectState
---@field win_id number|nil Window ID
---@field buf_id number|nil Buffer ID
---@field is_open boolean Window open status
---@field state string Current component state - "loading", "ready", "error"
---@field sort_types string[] Array of sort type keys
---@field current_sort string Current sort selection

---@class SortSelectStateUpdate
---@field state string?
---@field current_sort string?
---@field sort_types string[]?

---@class SortSelect
---@field config SortSelectConfig Window configuration
---@field state SortSelectState Component state
---@field open fun(self: SortSelect): string|nil
---@field close fun(self: SortSelect): string|nil
---@field render fun(self: SortSelect, data: SortSelectStateUpdate|nil): string|nil
---@field focus fun(self: SortSelect): string|nil
---@field get_window_id fun(self: SortSelect): number|nil
---@field is_valid fun(self: SortSelect): boolean
---@field get_selected_sort fun(self: SortSelect): string

local DEFAULT_SORT_SELECT_CONFIG = {
  width = 30,
  height = 3,
}

local DEFAULT_STATE = {
  win_id = nil,
  buf_id = nil,
  is_open = false,
  state = "loading",
  sort_types = {},
  current_sort = "default",
}

---Validate sort select configuration
---@param config SortSelectConfig|nil
---@return string|nil Error message or nil if valid
local function validate_config(config)
  if not config then
    return "sort_select.config must be a table, got: nil"
  end

  local width_error = validators.should_be_positive_number(config.width, "sort_select.config.width must be a positive number")
  if width_error then
    return width_error
  end

  local height_error = validators.should_be_positive_number(config.height, "sort_select.config.height must be a positive number")
  if height_error then
    return height_error
  end

  local row_error = validators.should_be_number(config.row, "sort_select.config.row must be a number")
  if row_error then
    return row_error
  end

  local col_error = validators.should_be_number(config.col, "sort_select.config.col must be a number")
  if col_error then
    return col_error
  end

  local current_sort_error = validators.should_be_string(config.current_sort, "sort_select.config.current_sort must be a string")
  if current_sort_error then
    return current_sort_error
  end

  if not config.on_value or type(config.on_value) ~= "function" then
    return "sort_select.config.on_value must be a function, got: " .. type(config.on_value)
  end

  if not config.on_exit or type(config.on_exit) ~= "function" then
    return "sort_select.config.on_exit must be a function, got: " .. type(config.on_exit)
  end

  if config.sort_types and type(config.sort_types) ~= "table" then
    return "sort_select.config.sort_types must be a table or nil, got: " .. type(config.sort_types)
  end

  return nil
end

---Validate sort select state
---@param state SortSelectState
---@return string|nil Error message or nil if valid
local function validate_state(state)
  if not state then
    return "sort_select.state must be a table, got: nil"
  end

  local is_open_error = validators.should_be_boolean(state.is_open, "sort_select.state.is_open must be a boolean")
  if is_open_error then
    return is_open_error
  end

  local state_error = validators.should_be_string(state.state, "sort_select.state.state must be a string")
  if state_error then
    return state_error
  end

  if state.sort_types and type(state.sort_types) ~= "table" then
    return "sort_select.state.sort_types must be a table, got: " .. type(state.sort_types)
  end

  local current_sort_error = validators.should_be_string(state.current_sort, "sort_select.state.current_sort must be a string")
  if current_sort_error then
    return current_sort_error
  end

  return nil
end

---Validate sort types integration
---@param sort_types string[]|nil
---@return string[]|nil, string|nil Sort types array or nil, error message
local function validate_sort_types(sort_types)
  if sort_types then
    if type(sort_types) ~= "table" then
      return nil, "sort_types must be a table, got: " .. type(sort_types)
    end

    if #sort_types == 0 then
      return nil, "sort_types cannot be empty"
    end

    -- Validate each sort type exists in store.sort
    for i, sort_type in ipairs(sort_types) do
      if type(sort_type) ~= "string" then
        return nil, "sort_types[" .. i .. "] must be a string, got: " .. type(sort_type)
      end

      if not sort.sorts[sort_type] then
        return nil, "sort_types[" .. i .. "] '" .. sort_type .. "' not found in store.sort.sorts"
      end
    end

    return sort_types, nil
  else
    -- Use store.sort.get_sort_types() as fallback
    local store_sort_types = sort.get_sort_types()
    if not store_sort_types or #store_sort_types == 0 then
      return nil, "No sort types available from store.sort"
    end
    return store_sort_types, nil
  end
end

-- SortSelect class
local SortSelect = {}
SortSelect.__index = SortSelect

---Create new SortSelect instance
---@param sort_select_config SortSelectConfig|nil Configuration
---@return SortSelect|nil, string|nil Instance or nil, error message or nil
function M.new(sort_select_config)
  -- Merge with defaults
  local merged_config = vim.tbl_deep_extend("force", DEFAULT_SORT_SELECT_CONFIG, sort_select_config or {})

  -- Validate configuration
  local config_error = validate_config(merged_config)
  if config_error then
    return nil, config_error
  end

  -- Validate and get sort types
  local validated_sort_types, sort_error = validate_sort_types(merged_config.sort_types)
  if sort_error then
    return nil, sort_error
  end

  -- Initialize state
  local merged_state = vim.tbl_deep_extend("force", DEFAULT_STATE, {
    sort_types = validated_sort_types,
    current_sort = merged_config.current_sort,
  })

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

  setmetatable(instance, SortSelect)
  return instance, nil
end

---Get selected sort type based on current cursor position
---@return string Selected sort type
function SortSelect:get_selected_sort()
  if not self.state.win_id or not vim.api.nvim_win_is_valid(self.state.win_id) then
    return self.state.sort_types[1] or "default"
  end

  local cursor_line = vim.api.nvim_win_get_cursor(self.state.win_id)[1]
  return self.state.sort_types[cursor_line] or self.state.sort_types[1] or "default"
end

---Handle selection and close window
---@return string|nil Error message or nil on success
function SortSelect:_select_and_close()
  local selected_sort = self:get_selected_sort()
  local on_value = self.config.on_value

  local close_error = self:close()
  if close_error then
    return close_error
  end

  -- Call callback after cleanup
  if on_value then
    on_value(selected_sort)
  end

  return nil
end

---Handle cancellation and close window
---@return string|nil Error message or nil on success
function SortSelect:_cancel_and_close()
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
function SortSelect:_create_buffer()
  local buf_id = utils.create_scratch_buffer({
    buftype = "nofile",
    modifiable = false,
    readonly = true,
  })

  if not buf_id then
    return nil, "Failed to create scratch buffer"
  end

  -- Update buffer content
  local content_error = self:_update_buffer_content(buf_id)
  if content_error then
    return nil, content_error
  end

  return buf_id, nil
end

---Update buffer content with current sort data
---@param buf_id number|nil Buffer ID (uses self.state.buf_id if not provided)
---@return string|nil Error message or nil on success
function SortSelect:_update_buffer_content(buf_id)
  local target_buf_id = buf_id or self.state.buf_id
  if not target_buf_id or not vim.api.nvim_buf_is_valid(target_buf_id) then
    return "Invalid buffer ID for content update"
  end

  local content_lines = _create_content_lines(self.state.current_sort, self.state.sort_types)

  utils.set_lines(target_buf_id, content_lines)

  return nil
end

---Setup buffer-local keymaps
---@param buf_id number Buffer ID
---@return string|nil Error message or nil on success
function SortSelect:_setup_keymaps(buf_id)
  if not buf_id or not vim.api.nvim_buf_is_valid(buf_id) then
    return "Invalid buffer ID for keymap setup"
  end

  local keymaps = {
    ["<cr>"] = function()
      self:_select_and_close()
    end,
    ["<esc>"] = function()
      self:_cancel_and_close()
    end,
    ["q"] = function()
      self:_cancel_and_close()
    end,
  }

  for key, callback in pairs(keymaps) do
    vim.api.nvim_buf_set_keymap(buf_id, "n", key, "", {
      noremap = true,
      silent = true,
      callback = callback,
    })
  end

  return nil
end

---Open sort select window
---@return string|nil Error message or nil on success
function SortSelect:open()
  if self.state.is_open then
    return "SortSelect window is already open"
  end

  -- Create buffer
  local buf_id, buf_error = self:_create_buffer()
  if buf_error then
    return "SortSelect buffer creation failed: " .. buf_error
  end

  self.state.buf_id = buf_id

  -- Setup keymaps
  local keymap_error = self:_setup_keymaps(buf_id)
  if keymap_error then
    return "SortSelect keymap setup failed: " .. keymap_error
  end

  -- Create window
  local store_config = require("store.config")
  local plugin_config = store_config.get()

  local win_id, win_error = utils.create_floating_window({
    buf_id = buf_id,
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
    return "SortSelect window creation failed: " .. win_error
  end

  if not win_id then
    return "SortSelect window creation returned nil window ID"
  end

  self.state.win_id = win_id
  self.state.is_open = true
  self.state.state = "ready"

  return nil
end

---Close the sort select window
---@return string|nil Error message or nil on success
function SortSelect:close()
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

---Render sort select with updated data
---@param state_update SortSelectStateUpdate|nil State updates to apply
---@return string|nil Error message or nil on success
function SortSelect:render(state_update)
  if not self.state.is_open then
    return "Cannot render closed SortSelect window"
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

---Focus the sort select window
---@return string|nil Error message or nil on success
function SortSelect:focus()
  if not self.state.is_open or not self.state.win_id then
    return "Cannot focus closed or invalid SortSelect window"
  end

  if not vim.api.nvim_win_is_valid(self.state.win_id) then
    return "Cannot focus invalid window"
  end

  vim.api.nvim_set_current_win(self.state.win_id)
  return nil
end

---Get window ID
---@return number|nil Window ID or nil if not open
function SortSelect:get_window_id()
  if self.state.is_open and self.state.win_id and vim.api.nvim_win_is_valid(self.state.win_id) then
    return self.state.win_id
  end
  return nil
end

---Check if sort select is valid and ready
---@return boolean True if valid and usable
function SortSelect:is_valid()
  return self.state.is_open
    and self.state.win_id ~= nil
    and vim.api.nvim_win_is_valid(self.state.win_id)
    and self.state.buf_id ~= nil
    and vim.api.nvim_buf_is_valid(self.state.buf_id)
    and self.state.state == "ready"
end

return M
