local validators = require("store.validators")
local utils = require("store.utils")

local M = {}

---@class HeadingState
---@field query string Current filter query
---@field filtered_count number Number of plugins after filtering
---@field total_count number Total number of plugins
---@field state string current component state - "loading", "ready"

-- Default heading window configuration
local DEFAULT_CONFIG = {
  width = 80,
  height = 6,
  row = 0,
  col = 0,
  border = "rounded",
  zindex = 50,
}

local DEFAULT_STATE = {
  state = "loading",
  query = "",
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

-- Validate heading window configuration
local function validate(config)
  if config == nil then
    return nil
  end

  local err = validators.should_be_table(config, "heading window config must be a table")
  if err then
    return err
  end

  if config.width ~= nil then
    local width_err = validators.should_be_number(config.width, "heading.width must be a number")
    if width_err then
      return width_err
    end
  end

  if config.height ~= nil then
    local height_err = validators.should_be_number(config.height, "heading.height must be a number")
    if height_err then
      return height_err
    end
  end

  if config.row ~= nil then
    local row_err = validators.should_be_number(config.row, "heading.row must be a number")
    if row_err then
      return row_err
    end
  end

  if config.col ~= nil then
    local col_err = validators.should_be_number(config.col, "heading.col must be a number")
    if col_err then
      return col_err
    end
  end

  if config.border ~= nil then
    local border_err = validators.should_be_string(config.border, "heading.border must be a string")
    if border_err then
      return border_err
    end
  end

  if config.zindex ~= nil then
    local zindex_err = validators.should_be_number(config.zindex, "heading.zindex must be a number")
    if zindex_err then
      return zindex_err
    end
  end

  return nil
end

---@class HeadingConfig
---@field width number Window width
---@field height number Window height
---@field row number Window row position
---@field col number Window column position
---@field border string Window border style
---@field zindex number Window z-index

---@class HeadingWindow
---@field config HeadingConfig Window configuration
---@field win_id number|nil Window ID
---@field buf_id number|nil Buffer ID
---@field is_open boolean Window open status
---@field open fun(self: HeadingWindow): boolean
---@field close fun(self: HeadingWindow): boolean
---@field render fun(self: HeadingWindow, data: HeadingState)
---@field is_window_open fun(self: HeadingWindow): boolean

-- HeadingWindow class
local HeadingWindow = {}
HeadingWindow.__index = HeadingWindow

---Create a new heading window instance
---@param heading_config HeadingConfig|nil Heading window configuration
---@return HeadingWindow HeadingWindow instance
function M.new(heading_config)
  -- Validate configuration first
  local error_msg = validate(heading_config)
  if error_msg then
    error("Heading window configuration validation failed: " .. error_msg)
  end

  -- Merge with defaults
  local config = vim.tbl_deep_extend("force", DEFAULT_CONFIG, heading_config or {})

  local instance = {
    config = config,
    win_id = nil,
    buf_id = nil,
    is_open = false,
  }

  setmetatable(instance, HeadingWindow)

  -- Create hidden buffer immediately
  instance.buf_id = instance:_create_buffer()

  return instance
end

---Create heading buffer with proper options
---@return number Buffer ID
function HeadingWindow:_create_buffer()
  local buf_id = vim.api.nvim_create_buf(false, true)

  local buf_opts = {
    modifiable = false,
    swapfile = false,
    buftype = "nofile",
    bufhidden = "wipe",
    buflisted = false,
    filetype = "text",
    undolevels = -1,
  }

  for option, value in pairs(buf_opts) do
    vim.api.nvim_set_option_value(option, value, { buf = buf_id })
  end

  return buf_id
end

---Open the heading window with default content
---@return boolean Success status
function HeadingWindow:open()
  if self.is_open then
    return false
  end

  -- Buffer already created in constructor

  local win_config = {
    relative = "editor",
    width = self.config.width,
    height = self.config.height,
    row = self.config.row,
    col = self.config.col,
    style = "minimal",
    border = self.config.border,
    zindex = self.config.zindex,
    focusable = false, -- Header should not be focusable
  }

  self.win_id = vim.api.nvim_open_win(self.buf_id, false, win_config)
  if not self.win_id then
    return false
  end

  -- Set window options optimized for static header display
  local win_opts = {
    cursorline = false, -- No cursor line for header
    number = false,
    relativenumber = false,
    signcolumn = "no",
    foldcolumn = "0",
    colorcolumn = "",
    wrap = false,
    linebreak = false,
  }

  for option, value in pairs(win_opts) do
    vim.api.nvim_set_option_value(option, value, { win = self.win_id })
  end

  self.is_open = true

  -- Set default content
  self:render(DEFAULT_STATE)

  return true
end

---Create floating window for heading (internal method)
---@return boolean Success status
function HeadingWindow:_create_window()
  if self.is_open then
    return false
  end
end

---Render content for the heading window
---@param data HeadingState Heading display data
function HeadingWindow:render(data)
  -- Get logger from config module for consistent error handling
  local config = require("store.config")
  local log = config.get().log
  
  -- Only update content if window is open
  if not self.is_open then
    log.warn("Heading window: Cannot render - window not open")
    return
  end

  -- Generate header content lines
  local content_lines = {}
  local width = self.config.width

  -- Line 0: ASCII art only
  table.insert(content_lines, utils.format_line(width, ASCII_ART[1]))

  -- Line 1: ASCII art + filter info
  local filter_text = ""
  if data.query ~= "" then
    filter_text = "Filter: " .. data.query
  else
    filter_text = "Filter: none"
  end
  table.insert(content_lines, utils.format_line(width, ASCII_ART[2], filter_text))

  -- Line 2: ASCII art only
  table.insert(content_lines, utils.format_line(width, ASCII_ART[3]))

  -- Line 3: ASCII art + plugin count
  local count_text = ""
  if data.state == "loading" then
    count_text = "Loading plugins..."
  else
    count_text = string.format("Showing %d of %d plugins", data.filtered_count, data.total_count)
  end
  table.insert(content_lines, utils.format_line(width, ASCII_ART[4], count_text))

  -- Line 4: ASCII art only
  table.insert(content_lines, utils.format_line(width, ASCII_ART[5]))

  -- Line 5: ASCII art + help text
  local help_text = "Press ? for help"
  table.insert(content_lines, utils.format_line(width, ASCII_ART[6], help_text))

  if not self.buf_id or not vim.api.nvim_buf_is_valid(self.buf_id) then
    log.warn("Heading window: Cannot render - invalid buffer")
    return
  end

  vim.api.nvim_set_option_value("modifiable", true, { buf = self.buf_id })
  vim.api.nvim_buf_set_lines(self.buf_id, 0, -1, false, content_lines)
  vim.api.nvim_set_option_value("modifiable", false, { buf = self.buf_id })
end

---Check if heading window is currently open
---@return boolean Window open status
function HeadingWindow:is_window_open()
  return self.is_open
    and self.win_id
    and vim.api.nvim_win_is_valid(self.win_id)
    and self.buf_id
    and vim.api.nvim_buf_is_valid(self.buf_id)
end

---Close the heading window
---@return boolean Success status
function HeadingWindow:close()
  if not self.is_open then
    return false
  end

  -- Close window
  if self.win_id and vim.api.nvim_win_is_valid(self.win_id) then
    vim.api.nvim_win_close(self.win_id, true)
  end

  -- Reset window state (keep buffer)
  self.win_id = nil
  self.is_open = false

  return true
end

return M
