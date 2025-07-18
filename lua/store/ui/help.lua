local logger = require("store.logger")

local M = {}

---@class HelpConfig
---@field on_exit fun() Callback when user cancels (handles focus restoration)

---@class HelpWindow
---@field config HelpConfig
---@field win_id number|nil Window ID
---@field buf_id number|nil Buffer ID
---@field is_open boolean
---@field help_items table[] Array of help items

-- Static instance to prevent multiple opens
local instance = nil

---Help modal configuration - list of keybinding to action pairs
---@type table[]
local help_items = {
  { keybinding = "f", action = "Filter repos" },
  { keybinding = "s", action = "Sort repos" },
  { keybinding = "<CR>", action = "Open repo" },
  { keybinding = "r", action = "Refresh list" },
  { keybinding = "q", action = "Close modal" },
  { keybinding = "<Esc>", action = "Close modal" },
  { keybinding = "<Tab>", action = "Switch focus" },
  { keybinding = "?", action = "Show help" },
}

---Calculate column widths for help content
---@return number, number max_key_width, max_action_width
local function _calculate_column_widths()
  local max_key_width = 3 -- Minimum for "Key" header
  local max_action_width = 6 -- Minimum for "Action" header

  for _, item in ipairs(help_items) do
    max_key_width = math.max(max_key_width, vim.fn.strchars(item.keybinding))
    max_action_width = math.max(max_action_width, vim.fn.strchars(item.action))
  end

  return max_key_width, max_action_width
end

---Format a single help line similar to list component formatting
---@param key string Keybinding
---@param action string Action description
---@param key_width number Width for key column
---@param action_width number Width for action column
---@return string Formatted line
local function _format_help_line(key, action, key_width, action_width)
  -- Use padding similar to list component
  local key_part = string.format("%-" .. key_width .. "s", key)
  local action_part = string.format("%-" .. action_width .. "s", action)

  -- Add spacing between columns
  return key_part .. "  " .. action_part
end

---Generate help content lines
---@return string[] List of content lines
local function _create_content_lines()
  local key_width, action_width = _calculate_column_widths()
  local lines = {}

  -- Add header
  table.insert(lines, _format_help_line("Key", "Action", key_width, action_width))

  -- Add separator line
  local separator = string.rep("-", key_width) .. "  " .. string.rep("-", action_width)
  table.insert(lines, separator)

  -- Add help items
  for _, item in ipairs(help_items) do
    table.insert(lines, _format_help_line(item.keybinding, item.action, key_width, action_width))
  end

  return lines
end

---Handle cancellation and close window
local function _cancel_and_close()
  if not instance then
    return
  end

  local on_exit = instance.config.on_exit

  M.close()

  -- Call callback after cleanup
  if on_exit then
    on_exit()
  end
end

---Create and configure buffer
---@return number Buffer ID
local function _create_buffer()
  local buf_id = vim.api.nvim_create_buf(false, true)

  -- Set buffer content
  local content_lines = _create_content_lines()
  vim.api.nvim_buf_set_lines(buf_id, 0, -1, false, content_lines)

  -- Make buffer read-only
  vim.api.nvim_buf_set_option(buf_id, "modifiable", false)
  vim.api.nvim_buf_set_option(buf_id, "readonly", true)
  vim.api.nvim_buf_set_option(buf_id, "bufhidden", "wipe")
  vim.api.nvim_buf_set_option(buf_id, "buftype", "nofile")
  vim.api.nvim_buf_set_option(buf_id, "buflisted", false)
  vim.api.nvim_buf_set_option(buf_id, "filetype", "text")

  -- Set buffer name
  vim.api.nvim_buf_set_name(buf_id, "Help")

  return buf_id
end

---Setup buffer-local keymaps
---@param buf_id number Buffer ID
local function _setup_keymaps(buf_id)
  local keymaps = {
    ["<cr>"] = _cancel_and_close,
    ["<esc>"] = _cancel_and_close,
    ["q"] = _cancel_and_close,
  }

  for key, callback in pairs(keymaps) do
    vim.api.nvim_buf_set_keymap(buf_id, "n", key, "", {
      noremap = true,
      silent = true,
      callback = callback,
    })
  end
end

---Create floating window
---@param buf_id number Buffer ID
---@return number|nil Window ID or nil on failure
local function _create_window(buf_id)
  -- Get modal layout information
  local config = require("store.config").get()
  local layout = config.layout

  -- Calculate window dimensions based on content
  local key_width, action_width = _calculate_column_widths()
  local win_width = key_width + 2 + action_width -- key + spacing + action
  local win_height = #help_items + 2 -- items + header + separator

  -- Position at top of modal space, overlapping heading (same as sort select)
  local row = layout.start_row + 1 -- Slightly below modal top
  local col = layout.start_col + math.floor((layout.total_width - win_width) / 2) -- Centered horizontally within modal

  -- Create window
  local win_id = vim.api.nvim_open_win(buf_id, true, {
    relative = "editor",
    width = win_width,
    height = win_height,
    row = row,
    col = col,
    style = "minimal",
    border = "rounded",
    zindex = 60,
  })

  return win_id
end

---Close the help window
function M.close()
  if not instance then
    return
  end

  logger.debug("Closing Help window")

  -- Store references before cleanup to prevent race conditions
  local win_id = instance.win_id
  local buf_id = instance.buf_id

  -- Clean up instance immediately to prevent multiple calls
  instance = nil

  -- Close window
  if win_id and vim.api.nvim_win_is_valid(win_id) then
    vim.api.nvim_win_close(win_id, true)
  end

  -- Close buffer
  if buf_id and vim.api.nvim_buf_is_valid(buf_id) then
    vim.api.nvim_buf_delete(buf_id, { force = true })
  end
end

---Open help window
---@param config HelpConfig Configuration
function M.open(config)
  -- Prevent multiple instances
  if instance then
    logger.warn("Help window already open")
    return
  end

  -- Validate configuration
  if not config or not config.on_exit then
    logger.error("Help requires on_exit callback")
    return
  end

  -- Create instance
  instance = {
    config = config,
    win_id = nil,
    buf_id = nil,
    is_open = false,
    help_items = help_items,
  }

  -- Create components with error handling
  local success, err = pcall(function()
    instance.buf_id = _create_buffer()
    _setup_keymaps(instance.buf_id)
    instance.win_id = _create_window(instance.buf_id)

    if not instance.win_id then
      error("Failed to create window")
    end

    instance.is_open = true

    logger.debug("Help window opened successfully")
  end)

  if not success then
    logger.error("Help window creation failed: " .. tostring(err))

    -- Cleanup partial state
    if instance then
      if instance.buf_id and vim.api.nvim_buf_is_valid(instance.buf_id) then
        vim.api.nvim_buf_delete(instance.buf_id, { force = true })
      end
      instance = nil
    end
  end
end

return M
