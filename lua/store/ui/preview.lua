local validators = require("store.validators")
local logger = require("store.logger")
local utils = require("store.utils")

local M = {}

---@class PreviewState
---@field win_id number|nil Window ID
---@field buf_id number|nil Buffer ID
---@field is_open boolean Window open status
---@field state string current component state - "loading", "ready", "error"
---@field content string[] Array of content lines
---@field readme_id string|nil README identifier for cursor position tracking
---@field cursor_positions table Cursor positions for different README files
---@field current_readme_id string|nil Current README identifier

---@class PreviewStateUpdate
---@field state string?
---@field content string[]|nil?
---@field readme_id string|nil?

---@class PreviewConfig
---@field width number Window width
---@field height number Window height
---@field row number Window row position
---@field col number Window column position
---@field keymaps_applier fun(buf_id: number) Function to apply keymaps to buffer

local DEFAULT_PREVIEW_CONFIG = {
  keymaps_applier = function(buf_id)
    vim.notify("store.nvim: keymaps for preview window not configured", vim.log.levels.WARN)
  end,
}

---@class Preview
---@field config PreviewConfig Window configuration
---@field state PreviewState Component state
---@field open fun(self: Preview): string|nil
---@field close fun(self: Preview): string|nil
---@field render fun(self: Preview, state: PreviewStateUpdate): string|nil
---@field focus fun(self: Preview): string|nil
---@field resize fun(self: Preview, layout_config: {width: number, height: number, row: number, col: number}): string|nil
---@field save_cursor_on_blur fun(self: Preview): nil
---@field get_window_id fun(self: Preview): number|nil
---@field is_valid fun(self: Preview): boolean

local DEFAULT_STATE = {
  -- Window state
  win_id = nil,
  buf_id = nil,
  is_open = false,
  -- Content state
  content = nil,
  readme_id = nil,
  -- Cursor state
  cursor_positions = {},
  current_readme_id = nil,
}

---Validate preview window configuration
---@param config PreviewConfig Preview window configuration to validate
---@return string|nil error_message Error message if validation fails, nil if valid
local function validate_config(config)
  local err = validators.should_be_table(config, "preview window config must be a table")
  if err then
    return err
  end

  local width_err = validators.should_be_number(config.width, "preview.width must be a number")
  if width_err then
    return width_err
  end

  local height_err = validators.should_be_number(config.height, "preview.height must be a number")
  if height_err then
    return height_err
  end

  local row_err = validators.should_be_number(config.row, "preview.row must be a number")
  if row_err then
    return row_err
  end

  local col_err = validators.should_be_number(config.col, "preview.col must be a number")
  if col_err then
    return col_err
  end

  return validators.should_be_function(config.keymaps_applier, "preview.keymaps_applier must be a function")
end

---Validate preview state for consistency and safety
---@param state PreviewState Preview state to validate
---@return string|nil error_message Error message if validation fails, nil if valid
local function validate_state(state)
  local err = validators.should_be_table(state, "preview state must be a table")
  if err then
    return err
  end

  -- Validate state field
  if state.state ~= nil then
    local state_err = validators.should_be_string(state.state, "preview.state must be a string")
    if state_err then
      return state_err
    end

    local valid_states = { loading = true, ready = true, error = true }
    if not valid_states[state.state] then
      return "preview.state must be one of 'loading', 'ready', 'error', got: " .. state.state
    end
  end

  -- Validate content field
  if state.content ~= nil then
    if type(state.content) ~= "table" then
      return "preview.content must be nil or an array of strings, got: " .. type(state.content)
    end

    for i, line in ipairs(state.content) do
      if type(line) ~= "string" then
        return "preview.content[" .. i .. "] must be a string, got: " .. type(line)
      end
    end
  end

  -- Validate readme_id field
  if state.readme_id ~= nil then
    local readme_err = validators.should_be_string(state.readme_id, "preview.readme_id must be nil or a string")
    if readme_err then
      return readme_err
    end
  end

  -- Validate window state fields if present
  if state.win_id ~= nil then
    local win_err = validators.should_be_number(state.win_id, "preview.win_id must be nil or a number")
    if win_err then
      return win_err
    end
  end

  if state.buf_id ~= nil then
    local buf_err = validators.should_be_number(state.buf_id, "preview.buf_id must be nil or a number")
    if buf_err then
      return buf_err
    end
  end

  if state.is_open ~= nil then
    if type(state.is_open) ~= "boolean" then
      return "preview.is_open must be nil or a boolean, got: " .. type(state.is_open)
    end
  end

  -- Validate cursor state fields if present
  if state.cursor_positions ~= nil then
    if type(state.cursor_positions) ~= "table" then
      return "preview.cursor_positions must be nil or a table, got: " .. type(state.cursor_positions)
    end
  end

  if state.current_readme_id ~= nil then
    local current_readme_err =
      validators.should_be_string(state.current_readme_id, "preview.current_readme_id must be nil or a string")
    if current_readme_err then
      return current_readme_err
    end
  end

  return nil
end

-- Preview class
local Preview = {}
Preview.__index = Preview

---Create a new preview window instance
---@param preview_config PreviewConfig|nil Preview window configuration
---@return Preview|nil instance Preview instance on success, nil on error
---@return string|nil error Error message on failure, nil on success
function M.new(preview_config)
  -- Merge with defaults first
  local config = vim.tbl_deep_extend("force", DEFAULT_PREVIEW_CONFIG, preview_config or {})

  -- Validate merged configuration
  local error_msg = validate_config(config)
  if error_msg then
    return nil, "Preview window configuration validation failed: " .. error_msg
  end

  local instance = {
    config = config,
    state = vim.tbl_deep_extend("force", DEFAULT_STATE, {
      buf_id = utils.create_scratch_buffer({
        filetype = "markdown",
        buftype = "",
      }),
    }),
  }

  setmetatable(instance, Preview)

  -- Apply keymaps to buffer
  config.keymaps_applier(instance.state.buf_id)

  return instance, nil
end

---Open the preview window with default content
---@return string|nil error Error message on failure, nil on success
function Preview:open()
  if self.state.is_open then
    logger.warn("Preview window: open() called when window is already open")
    return nil
  end

  local window_config = {
    width = self.config.width,
    height = self.config.height,
    row = self.config.row,
    col = self.config.col,
    focusable = true,
  }

  local window_opts = {
    conceallevel = 3, -- Required for markview to hide markdown syntax
    concealcursor = "nvc", -- Hide concealed text in normal, visual, command modes
    wrap = true, -- Enable text wrapping for markdown content
    cursorline = false,
  }

  local win_id, error_message = utils.create_floating_window({
    buf_id = self.state.buf_id,
    config = window_config,
    opts = window_opts,
  })
  if error_message then
    return "Cannot open preview window: " .. error_message
  end

  self.state.win_id = win_id
  self.state.is_open = true

  local markview_ok, markview = pcall(require, "markview")
  if markview_ok then
    markview.actions.attach(self.state.buf_id)
    markview.actions.enable(self.state.buf_id)
  end

  -- Set default content
  return self:render({ state = "loading" })
end

---Render content in the preview window based on state
---@param state PreviewStateUpdate Preview state to render
---@return string|nil error Error message on failure, nil on success
function Preview:render(state)
  if type(state) ~= "table" then
    return "Preview window: Cannot render - state must be a table, got: " .. type(state)
  end
  if not self.state.is_open then
    return "Preview window: Cannot render - window not open"
  end
  if not self.state.buf_id then
    return "Preview window: Cannot render - invalid buffer"
  end

  -- Save cursor position for current README before switching
  self:_save_cursor_position()

  -- Create new state locally by merging current state with update
  local new_state = vim.tbl_deep_extend("force", self.state, state)

  -- Validate the merged state before applying it
  local validation_error = validate_state(new_state)
  if validation_error then
    return "Preview window: Invalid state update - " .. validation_error
  end

  -- Only assign to self.state if validation passes
  self.state = new_state

  -- Only schedule the final rendering dispatch using safe self.state
  vim.schedule(function()
    if self.state.state == "loading" then
      self:_render_loading()
    elseif self.state.state == "error" then
      self:_render_error(self.state)
    else
      self:_render_ready(self.state)
    end
  end)

  return nil
end

---Focus the preview window
---@return string|nil error Error message on failure, nil on success
function Preview:focus()
  if not self.state.is_open then
    return "Preview window: Cannot focus - window not open"
  end
  if not self.state.win_id or not vim.api.nvim_win_is_valid(self.state.win_id) then
    return "Preview window: Cannot focus - invalid window"
  end

  vim.api.nvim_set_current_win(self.state.win_id)
  return nil
end

---Save cursor position when losing focus (called externally)
---@return nil
function Preview:save_cursor_on_blur()
  self:_save_cursor_position()
end

---Resize the preview window to new layout dimensions
---@param layout_config {width: number, height: number, row: number, col: number} New layout configuration
---@return string|nil error Error message if resize failed, nil if successful
function Preview:resize(layout_config)
  if not self.state.is_open or not self.state.win_id or not vim.api.nvim_win_is_valid(self.state.win_id) then
    return "Cannot resize preview window: window not open or invalid"
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
    return "Failed to resize preview window: " .. (err or "unknown error")
  end

  -- Update internal config
  self.config.width = layout_config.width
  self.config.height = layout_config.height
  self.config.row = layout_config.row
  self.config.col = layout_config.col

  return nil
end

---Close the preview window
---@return string|nil error Error message on failure, nil on success
function Preview:close()
  if not self.state.is_open then
    logger.warn("Preview window: close() called when window is not open")
    return nil
  end

  local markview_ok, markview = pcall(require, "markview")
  if self.state.buf_id and markview_ok then
    markview.actions.detach(self.state.buf_id)
  end

  -- Close window
  if self.state.win_id and vim.api.nvim_win_is_valid(self.state.win_id) then
    local success, err = pcall(vim.api.nvim_win_close, self.state.win_id, true)
    if not success then
      return "Failed to close preview window: " .. tostring(err)
    end
  end

  -- Reset window state (keep buffer)
  self.state.win_id = nil
  self.state.is_open = false

  return nil
end
---Save current cursor position for the current README
---@return nil
function Preview:_save_cursor_position()
  if not self.state.current_readme_id or not self.state.win_id then
    return
  end

  local readme_id = self.state.current_readme_id
  local win_id = self.state.win_id
  vim.schedule(function()
    pcall(function()
      local cursor = vim.api.nvim_win_get_cursor(win_id)
      self.state.cursor_positions[readme_id] = { cursor[1], cursor[2] }
    end)
  end)
end

---Restore cursor position for a specific README
---@param readme_id string README identifier
---@return nil
function Preview:_restore_cursor_position(readme_id)
  if not readme_id or not self.state.win_id or not vim.api.nvim_win_is_valid(self.state.win_id) then
    return
  end

  local saved_position = self.state.cursor_positions[readme_id]
  if saved_position then
    -- Validate that the saved position is within bounds
    local line_count = vim.api.nvim_buf_line_count(self.state.buf_id)
    local line = math.min(saved_position[1], line_count)
    local col = saved_position[2]

    vim.api.nvim_win_set_cursor(self.state.win_id, { line, col })
  else
    -- First time viewing this README, set cursor to top
    vim.api.nvim_win_set_cursor(self.state.win_id, { 1, 0 })
  end
end

---Render loading state
---@private
function Preview:_render_loading()
  local content_lines = { "Loading preview..." }
  utils.set_lines(self.state.buf_id, content_lines)
end

---Render error state
---@private
---@param state PreviewState Preview state containing error content
function Preview:_render_error(state)
  local content_lines = state.content or { "Error occurred while loading content" }
  utils.set_lines(self.state.buf_id, content_lines)
end

---Render ready state with content
---@private
---@param state PreviewState Preview state containing ready content
function Preview:_render_ready(state)
  local content_lines = state.content or { "No content available" }
  utils.set_lines(self.state.buf_id, content_lines)

  local markview_ok, markview = pcall(require, "markview")
  if markview_ok then
    markview.render(self.state.buf_id, { enable = true, hybrid_mode = false }, nil)
  end

  -- Update current README ID and restore cursor position
  self.state.current_readme_id = state.readme_id
  if state.readme_id then
    self:_restore_cursor_position(state.readme_id)
  end
end

---Get the window ID of the preview component
---@return number|nil window_id Window ID if open, nil otherwise
function Preview:get_window_id()
  if self.state.is_open and self.state.win_id and vim.api.nvim_win_is_valid(self.state.win_id) then
    return self.state.win_id
  end
  return nil
end

---Check if the preview component is in a valid state
---@return boolean is_valid True if component is valid and ready for use
function Preview:is_valid()
  return self.state.buf_id ~= nil
    and vim.api.nvim_buf_is_valid(self.state.buf_id)
    and (not self.state.is_open or (self.state.win_id and vim.api.nvim_win_is_valid(self.state.win_id)))
end

return M
