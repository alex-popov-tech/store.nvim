local validations = require("store.ui.heading.validations")
local wave = require("store.ui.heading.wave")
local utils = require("store.utils")
local logger = require("store.logger").createLogger({ context = "heading" })

local ns_id = vim.api.nvim_create_namespace("store.heading")

local M = {}

local DEFAULT_HEADING_CONFIG = {}

local DEFAULT_STATE = {
  buf = {
    id = nil,
    wave_handle = nil,
  },
  win = {
    id = nil,
    is_open = false,
  },
  -- Display/content state (neither purely buf nor win)
  state = "loading",
  filter_query = "",
  sort_type = "recently_updated",
  filtered_count = 0,
  total_count = 0,
  installed_count = 0,
  plugin_manager_mode = "not-selected",
  plugin_manager_overview = {},
}

-- ASCII art for store.nvim
local ASCII_ART = {
  "      _                              _",
  "  ___| |_ ___  _ __ ___   _ ____   _(_)_ __ ___",
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
  local left_width = vim.fn.strdisplaywidth(left)
  local right_width = vim.fn.strdisplaywidth(right)
  local available_space = usable_width - left_width - right_width - min_spacing

  if available_space >= 0 then
    -- Normal case: both fit with proper spacing
    local spacing = min_spacing + available_space
    return left .. string.rep(" ", spacing) .. right .. string.rep(" ", right_padding)
  else
    -- Content is too long for the width, truncate right content
    local max_right_length = usable_width - left_width - min_spacing
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
    state = vim.tbl_deep_extend("force", vim.deepcopy(DEFAULT_STATE), {
      buf = { id = utils.create_scratch_buffer({ bufhidden = "hide" }) },
      plugin_manager_overview = {},
    }),
  }

  setmetatable(instance, Heading)

  return instance, nil
end

---@private
---Open the heading window (window-only, no rendering or wave)
---@return string|nil error Error message on failure, nil on success
function Heading:_win_open()
  if self.state.win.is_open then
    return nil
  end

  local store_config = package.loaded["store.config"]
  if not store_config then
    return "Cannot open heading window: store.config not loaded"
  end
  local plugin_config = store_config.get()

  local win_id, err = utils.create_floating_window({
    buf_id = self.state.buf.id,
    config = {
      width = self.config.width,
      height = self.config.height,
      row = self.config.row,
      col = self.config.col,
      focusable = false,
      zindex = plugin_config.zindex.base,
    },
    opts = { cursorline = false, wrap = false, linebreak = false, list = true, listchars = "space: ,eol: " },
  })
  if err then
    return "Cannot open heading window: " .. err
  end

  self.state.win.id = win_id
  self.state.win.is_open = true
  return nil
end

---@private
---Start wave animation on the buffer
function Heading:_buf_start_wave()
  if self.state.buf.wave_handle then
    return -- already running
  end
  if not self.state.buf.id or not vim.api.nvim_buf_is_valid(self.state.buf.id) then
    return
  end
  self.state.buf.wave_handle = wave.start(self.state.buf.id)
end

---Open the heading window with default content
---@return string|nil error Error message on failure, nil on success
function Heading:open()
  if self.state.win.is_open then
    logger.warn("Heading window: open() called when window is already open")
    return nil
  end

  local win_err = self:_win_open()
  if win_err then
    return win_err
  end

  local render_err = self:render(self.state)
  if render_err then
    return render_err
  end

  self:_buf_start_wave()
  return nil
end

---Render error state (ASCII art only)
---@private
function Heading:_render_error()
  local content_lines = {}
  local width = self.config.width

  for i = 1, #ASCII_ART do
    table.insert(content_lines, format_line(width, ASCII_ART[i]))
  end

  utils.set_lines(self.state.buf.id, content_lines)

  if self.state.buf.wave_handle then
    wave.refresh_char_map(self.state.buf.wave_handle)
  end
end

---Render loading state (ASCII art only)
---@private
function Heading:_render_loading()
  local content_lines = {}
  local width = self.config.width

  for i = 1, #ASCII_ART do
    table.insert(content_lines, format_line(width, ASCII_ART[i]))
  end

  utils.set_lines(self.state.buf.id, content_lines)

  if self.state.buf.wave_handle then
    wave.refresh_char_map(self.state.buf.wave_handle)
  end
end

---Render ready state (ASCII art with full info)
---@private
---@param state HeadingState Heading display data
function Heading:_render_ready(state)
  local content_lines = {}
  local width = self.config.width

  -- Line 0: ASCII art + sort
  local sort = require("store.sort")
  local sort_label = sort.sorts[state.sort_type] and sort.sorts[state.sort_type].label or state.sort_type
  table.insert(content_lines, format_line(width, ASCII_ART[1], "Sort: " .. sort_label))

  -- Line 1: ASCII art + filter
  local filter_text = "Filter: " .. (state.filter_query ~= "" and state.filter_query or "none")
  table.insert(content_lines, format_line(width, ASCII_ART[2], filter_text))

  -- Line 2: ASCII art + help hint
  table.insert(content_lines, format_line(width, ASCII_ART[3], "Need help ?"))

  -- Line 3: ASCII art + "Made in"
  table.insert(content_lines, format_line(width, ASCII_ART[4], "Made in"))

  -- Line 4: ASCII art + "Ukraine"
  table.insert(content_lines, format_line(width, ASCII_ART[5], "Ukraine"))

  utils.set_lines(self.state.buf.id, content_lines)

  if self.state.buf.wave_handle then
    wave.refresh_char_map(self.state.buf.wave_handle)
  end

  -- Apply extmark highlights for the flag
  vim.schedule(function()
    if not self.state.buf.id or not vim.api.nvim_buf_is_valid(self.state.buf.id) then
      return
    end
    vim.api.nvim_buf_clear_namespace(self.state.buf.id, ns_id, 0, -1)

    -- Highlight "S" in "Sort:" on line 0 (0-indexed)
    local line0 = content_lines[1]
    if line0 then
      local col_start = line0:find("Sort:")
      if col_start then
        vim.api.nvim_buf_add_highlight(self.state.buf.id, ns_id, "StoreSortKey", 0, col_start - 1, col_start)
      end
    end

    -- Highlight "F" in "Filter:" on line 1 (0-indexed)
    local line1 = content_lines[2]
    if line1 then
      local col_start = line1:find("Filter:")
      if col_start then
        vim.api.nvim_buf_add_highlight(self.state.buf.id, ns_id, "StoreSortKey", 1, col_start - 1, col_start)
      end
    end

    -- Highlight last "?" (keybinding) in help hint on line 2 (0-indexed)
    local line2 = content_lines[3] -- 1-indexed
    if line2 then
      local col_start = line2:find("%?[^%?]*$")
      if col_start then
        vim.api.nvim_buf_add_highlight(self.state.buf.id, ns_id, "StoreSortKey", 2, col_start - 1, col_start)
      end
    end

    -- Find "Made in" on line 3 (0-indexed)
    local line3 = content_lines[4] -- 1-indexed
    if line3 then
      local col_start = line3:find("Made in")
      if col_start then
        vim.api.nvim_buf_add_highlight(self.state.buf.id, ns_id, "StoreUABlue", 3, col_start - 1, col_start - 1 + 7)
      end
    end

    -- Find "Ukraine" on line 4 (0-indexed)
    local line4 = content_lines[5] -- 1-indexed
    if line4 then
      local col_start = line4:find("Ukraine")
      if col_start then
        vim.api.nvim_buf_add_highlight(self.state.buf.id, ns_id, "StoreUAYellow", 4, col_start - 1, col_start - 1 + 7)
      end
    end
  end)
end

---@private
---Dispatch rendering to the buffer regardless of window state
function Heading:_buf_render()
  if not self.state.buf.id or not vim.api.nvim_buf_is_valid(self.state.buf.id) then
    return
  end
  vim.schedule(function()
    if not self.state.buf.id or not vim.api.nvim_buf_is_valid(self.state.buf.id) then
      return
    end
    if self.state.state == "loading" then
      self:_render_loading()
    elseif self.state.state == "error" then
      self:_render_error()
    else
      self:_render_ready(self.state)
    end
  end)
end

---Render updated heading content
---@param state HeadingStateUpdate Updated partial state
---@return string|nil error Error message on failure, nil on success
function Heading:render(state)
  if not self.state.buf.id or not vim.api.nvim_buf_is_valid(self.state.buf.id) then
    return "Heading: Cannot render - invalid buffer"
  end

  -- Create new state locally by merging current state with update
  local new_state = vim.tbl_deep_extend("force", self.state, state)

  -- Validate the merged state before applying it
  local validation_error = validations.validate_state(new_state)
  if validation_error then
    return "Heading: Invalid state update - " .. validation_error
  end

  -- Only assign to self.state if validation passes
  self.state = new_state

  self:_buf_render()
  return nil
end

---@private
---Close the heading window only (does NOT stop wave animation)
---@return string|nil error Error message on failure, nil on success
function Heading:_win_close()
  if not self.state.win.is_open then
    return nil
  end
  if self.state.win.id and vim.api.nvim_win_is_valid(self.state.win.id) then
    local success, err = pcall(vim.api.nvim_win_close, self.state.win.id, true)
    if not success then
      return "Failed to close heading window: " .. tostring(err)
    end
  end
  self.state.win.id = nil
  self.state.win.is_open = false
  return nil
end

---@private
---Destroy the buffer: stop wave animation and delete buffer
function Heading:_buf_destroy()
  if self.state.buf.wave_handle then
    wave.stop(self.state.buf.wave_handle)
    self.state.buf.wave_handle = nil
  end
  if self.state.buf.id and vim.api.nvim_buf_is_valid(self.state.buf.id) then
    pcall(vim.api.nvim_buf_delete, self.state.buf.id, { force = true })
  end
  self.state.buf.id = nil
end

---Close the heading window
---@return string|nil error Error message on failure, nil on success
function Heading:close()
  if not self.state.win.is_open then
    logger.warn("Heading window: close() called when window is not open")
    return nil
  end

  local win_err = self:_win_close()
  if win_err then
    return win_err
  end

  self:_buf_destroy()
  return nil
end

---@private
---Focus the heading window (window-only operation)
---@return string|nil error Error message on failure, nil on success
function Heading:_win_focus()
  if not self.state.win.is_open then
    return "Heading: Cannot focus - window not open"
  end
  if not self.state.win.id or not vim.api.nvim_win_is_valid(self.state.win.id) then
    return "Heading: Cannot focus - invalid window"
  end
  vim.api.nvim_set_current_win(self.state.win.id)
  return nil
end

---Focus the heading window
---@return string|nil error Error message on failure, nil on success
function Heading:focus()
  return self:_win_focus()
end

---@private
---Resize the heading window (window-only operation)
---@param layout_config {width: number, height: number, row: number, col: number} New layout configuration
---@return string|nil error Error message if resize failed, nil if successful
function Heading:_win_resize(layout_config)
  if not self.state.win.is_open or not self.state.win.id or not vim.api.nvim_win_is_valid(self.state.win.id) then
    return "Cannot resize heading window: window not open or invalid"
  end

  local store_config = package.loaded["store.config"]
  if not store_config then
    return "Cannot resize heading window: store.config not loaded"
  end
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

  local success, err = pcall(vim.api.nvim_win_set_config, self.state.win.id, win_config)
  if not success then
    return "Failed to resize heading window: " .. (err or "unknown error")
  end

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

  -- Update config for future renders
  self.config.width = layout_config.width
  self.config.height = layout_config.height
  self.config.row = layout_config.row
  self.config.col = layout_config.col

  local win_err = self:_win_resize(layout_config)
  if win_err then
    return win_err
  end

  -- Re-render content with new dimensions to ensure proper formatting
  self:_buf_render()

  return nil
end

---Get the window ID of the heading component
---@return number|nil window_id Window ID if open, nil otherwise
function Heading:get_window_id()
  if self.state.win.is_open and self.state.win.id and vim.api.nvim_win_is_valid(self.state.win.id) then
    return self.state.win.id
  end
  return nil
end

---Check if the heading component is in a valid state
---@return boolean is_valid True if component is valid and ready for use
function Heading:is_valid()
  return self.state.buf.id ~= nil
    and vim.api.nvim_buf_is_valid(self.state.buf.id)
    and (not self.state.win.is_open or (self.state.win.id and vim.api.nvim_win_is_valid(self.state.win.id)))
end

return M
