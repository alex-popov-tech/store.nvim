local validators = require("store.validators")

local M = {}

-- Default preview window configuration
local DEFAULT_PREVIEW_CONFIG = {
  width = 60,
  height = 20,
  row = 0,
  col = 0,
  border = "rounded",
  zindex = 50,
  keymap = {}, -- Table of lhs-callback pairs for buffer-scoped keybindings
}

-- Validate preview window configuration
local function validate(config)
  if config == nil then
    return nil
  end

  local err = validators.should_be_table(config, "preview window config must be a table")
  if err then
    return err
  end

  if config.width ~= nil then
    local width_err = validators.should_be_number(config.width, "preview_window.width must be a number")
    if width_err then
      return width_err
    end
  end

  if config.height ~= nil then
    local height_err = validators.should_be_number(config.height, "preview_window.height must be a number")
    if height_err then
      return height_err
    end
  end

  if config.row ~= nil then
    local row_err = validators.should_be_number(config.row, "preview_window.row must be a number")
    if row_err then
      return row_err
    end
  end

  if config.col ~= nil then
    local col_err = validators.should_be_number(config.col, "preview_window.col must be a number")
    if col_err then
      return col_err
    end
  end

  if config.border ~= nil then
    local border_err = validators.should_be_string(config.border, "preview_window.border must be a string")
    if border_err then
      return border_err
    end
  end

  if config.zindex ~= nil then
    local zindex_err = validators.should_be_number(config.zindex, "preview_window.zindex must be a number")
    if zindex_err then
      return zindex_err
    end
  end

  if config.keymap ~= nil then
    local keymap_err = validators.should_be_table(config.keymap, "preview_window.keymap must be a table")
    if keymap_err then
      return keymap_err
    end
  end

  return nil
end

-- PreviewWindow class
local PreviewWindow = {}
PreviewWindow.__index = PreviewWindow

---Create a new preview window instance
---@param preview_config table|nil Preview window configuration
---@return table PreviewWindow instance
function M.new(preview_config)
  -- Validate configuration first
  local error_msg = validate(preview_config)
  if error_msg then
    error("Preview window configuration validation failed: " .. error_msg)
  end

  -- Check if markview is available - required dependency
  local markview_ok, markview = pcall(require, "markview")
  if not markview_ok then
    error("markview plugin is required for preview window functionality")
  end

  -- Merge with defaults
  local config = vim.tbl_deep_extend("force", DEFAULT_PREVIEW_CONFIG, preview_config or {})

  local instance = {
    config = config,
    markview = markview,
    win_id = nil,
    buf_id = nil,
    is_open = false,
    cursor_positions = {}, -- Map of README identifier -> cursor position
    current_readme_id = nil, -- Track current README being displayed
  }

  setmetatable(instance, PreviewWindow)

  -- Create hidden buffer immediately
  instance.buf_id = instance:_create_buffer()

  return instance
end

---Create preview buffer with proper options
---@return number Buffer ID
function PreviewWindow:_create_buffer()
  local buf_id = vim.api.nvim_create_buf(false, true)

  local buf_opts = {
    modifiable = false,
    swapfile = false,
    buftype = "",
    bufhidden = "wipe",
    buflisted = false,
    filetype = "markdown",
    undolevels = -1,
  }

  for option, value in pairs(buf_opts) do
    vim.api.nvim_set_option_value(option, value, { buf = buf_id })
  end

  -- Set buffer-scoped keymaps
  for lhs, callback in pairs(self.config.keymap) do
    vim.keymap.set("n", lhs, callback, {
      buffer = buf_id,
      silent = true,
      desc = "Store.nvim preview window: " .. lhs,
    })
  end

  return buf_id
end
---Create floating window for preview (internal method)
---@return boolean Success status
function PreviewWindow:_create_window()
  if self.is_open then
    return false
  end
end

---Open the preview window with default content
---@return boolean Success status
function PreviewWindow:open()
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
  }

  self.win_id = vim.api.nvim_open_win(self.buf_id, false, win_config)
  if not self.win_id then
    return false
  end

  -- Set window options optimized for markdown preview
  local win_opts = {
    conceallevel = 3, -- Required for markview to hide markdown syntax
    concealcursor = "nvc", -- Hide concealed text in normal, visual, command modes
    wrap = true, -- Enable text wrapping for markdown content
    cursorline = false,
    number = false,
    relativenumber = false,
    signcolumn = "no",
    foldcolumn = "0",
    colorcolumn = "",
  }

  for option, value in pairs(win_opts) do
    vim.api.nvim_set_option_value(option, value, { win = self.win_id })
  end

  self.is_open = true

  -- Setup markview - attach and enable for this buffer
  if not self.markview.actions then
    error("markview.actions is not available - check markview plugin version")
  end
  self.markview.actions.attach(self.buf_id)
  self.markview.actions.enable(self.buf_id)

  -- Set default content
  self:render({ "Loading preview..." })

  return true
end

---Save current cursor position for the current README
---@return nil
function PreviewWindow:_save_cursor_position()
  if not self.current_readme_id or not self.win_id then
    return
  end

  local readme_id = self.current_readme_id
  local win_id = self.win_id
  vim.schedule(function()
    pcall(function()
      local cursor = vim.api.nvim_win_get_cursor(win_id)
      self.cursor_positions[readme_id] = { cursor[1], cursor[2] }
    end)
  end)
end

---Restore cursor position for a specific README
---@param readme_id string README identifier
---@return nil
function PreviewWindow:_restore_cursor_position(readme_id)
  if not readme_id or not self.win_id or not vim.api.nvim_win_is_valid(self.win_id) then
    return
  end

  local saved_position = self.cursor_positions[readme_id]
  if saved_position then
    -- Validate that the saved position is within bounds
    local line_count = vim.api.nvim_buf_line_count(self.buf_id)
    local line = math.min(saved_position[1], line_count)
    local col = saved_position[2]

    vim.api.nvim_win_set_cursor(self.win_id, { line, col })
  else
    -- First time viewing this README, set cursor to top
    vim.api.nvim_win_set_cursor(self.win_id, { 1, 0 })
  end
end

---Render markdown content in the preview window
---@param content table Array of markdown lines
---@param readme_id string|nil Optional README identifier for cursor position tracking
function PreviewWindow:render(content, readme_id)
  if type(content) ~= "table" or type(content[1]) ~= "string" then
    error("render() requires content to be a table of rows, got: " .. type(content))
  end
  if not self.is_open then
    error("Window must be opened before rendering content")
  end
  if not self.buf_id then
    error("buf_id is nil or invalid")
  end

  -- Save cursor position for current README before switching
  self:_save_cursor_position()

  vim.schedule(function()
    vim.api.nvim_set_option_value("modifiable", true, { buf = self.buf_id })
    vim.api.nvim_buf_set_lines(self.buf_id, 0, -1, false, content)
    vim.api.nvim_set_option_value("modifiable", false, { buf = self.buf_id })
    if not self.markview.render then
      error("markview.render is not available - check markview plugin version")
    end
    self.markview.render(self.buf_id, { enable = true, hybrid_mode = false }, nil)

    -- Update current README ID and restore cursor position
    self.current_readme_id = readme_id
    if readme_id then
      self:_restore_cursor_position(readme_id)
    end
  end)
end

---Check if preview window is currently open
---@return boolean Window open status
function PreviewWindow:is_window_open()
  return self.is_open
    and self.win_id
    and vim.api.nvim_win_is_valid(self.win_id)
    and self.buf_id
    and vim.api.nvim_buf_is_valid(self.buf_id)
end

---Focus the preview window
---@return boolean Success status
function PreviewWindow:focus()
  if not self:is_window_open() then
    return false
  end

  vim.api.nvim_set_current_win(self.win_id)
  return true
end

---Save cursor position when losing focus (called externally)
---@return nil
function PreviewWindow:save_cursor_on_blur()
  self:_save_cursor_position()
end

---Close the preview window
---@return boolean Success status
function PreviewWindow:close()
  if not self.is_open then
    return false
  end

  -- Cleanup markview
  if self.buf_id and self.markview.actions then
    self.markview.actions.detach(self.buf_id)
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
