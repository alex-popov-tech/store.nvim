local validations = require("store.ui.filter.validations")
local utils = require("store.utils")
local logger = require("store.logger").createLogger({ context = "filter" })

local M = {}

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
  local config_error = validations.validate_config(merged_config)
  if config_error then
    return nil, config_error
  end

  -- Initialize state
  local merged_state = vim.tbl_deep_extend("force", DEFAULT_STATE, {})

  -- Validate state
  local state_error = validations.validate_state(merged_state)
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
  local keymaps_error = instance:_setup_keymaps(buf_id)
  if keymaps_error then
    return nil, "Cannot setup keymaps: " .. keymaps_error
  end

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
  vim.cmd("stopinsert")
  local query = self:_get_current_query()
  local on_value = self.config.on_value

  -- Call callback after cleanup
  if on_value then
    on_value(query)
  end

  self.config.on_exit()

  local close_error = self:close()
  return close_error
end

---Cancel filter and close component
---@return string|nil Error message or nil on success
function Filter:cancel_filter()
  vim.cmd("stopinsert")
  local on_exit = self.config.on_exit

  -- Call callback after cleanup
  if on_exit then
    on_exit()
  end

  local close_error = self:close()
  return close_error
end

---Create and configure buffer
---@return number|nil, string|nil Buffer ID or nil, error message or nil
function Filter:_create_buffer()
  local buf_id = utils.create_scratch_buffer({
    buftype = "nofile",
    filetype = "store_filter",
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
      vim.cmd("stopinsert")
      self:apply_filter()
    end,
    ["<c-c>"] = function()
      vim.cmd("stopinsert")
      self:cancel_filter()
    end,
  }

  -- Set up normal mode keymaps
  for key, callback in pairs(normal_keymaps) do
    vim.keymap.set("n", key, callback, {
      buffer = buf_id,
      noremap = true,
      silent = true,
    })
  end

  -- Set up insert mode keymaps
  for key, callback in pairs(insert_keymaps) do
    vim.keymap.set("i", key, callback, {
      buffer = buf_id,
      noremap = true,
      silent = true,
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
    focus = true,
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
    local state_error = validations.validate_state(updated_state)
    if state_error then
      return "Invalid state update: " .. state_error
    end

    -- Apply valid state updates
    self.state = updated_state
  end

  -- Update buffer content method not defined in original, skip for now
  -- This could be added if needed

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
