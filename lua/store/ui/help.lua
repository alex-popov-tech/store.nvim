local logger = require("store.logger").createLogger({ context = "help" })

local M = {}

-- Generate help items from keybindings configuration
---@param keybindings table Keybindings configuration from user config
---@return table[] Array of help items with keybinding and action fields
local function _generate_help_items(keybindings)
  local help_items = {}
  local keymaps = package.loaded["store.keymaps"]
  if not keymaps then return help_items end

  for action, keys in pairs(keybindings) do
    local label = keymaps.get_label(action)
    if keys and label then
      table.insert(help_items, {
        keybinding = table.concat(keys, " / "),
        action = label,
      })
    end
  end

  return help_items
end

---@class HelpConfig
---@field layout ComponentLayout Layout information for help window
---@field keybindings table Keybindings configuration from user config
---@field on_exit fun() Callback when user cancels (handles focus restoration)

---@class HelpWindow
---@field config HelpConfig
---@field win_id number|nil Window ID
---@field buf_id number|nil Buffer ID
---@field is_open boolean
---@field help_items table[] Array of help items

-- Static instance to prevent multiple opens
local instance = nil

---Generate help content as markdown table
---@return string[] List of content lines
local function _create_content_lines()
  local help_items = _generate_help_items(instance.config.keybindings)
  local lines = {}

  table.insert(lines, "")
  table.insert(lines, "| Key | Action |")
  table.insert(lines, "|-----|--------|")

  for _, item in ipairs(help_items) do
    table.insert(lines, "| `" .. item.keybinding .. "` | " .. item.action .. " |")
  end

  table.insert(lines, "")

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
  vim.api.nvim_buf_set_option(buf_id, "buftype", "")
  vim.api.nvim_buf_set_option(buf_id, "buflisted", false)
  vim.api.nvim_buf_set_option(buf_id, "filetype", "markdown")

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
    vim.keymap.set("n", key, callback, {
      buffer = buf_id,
      noremap = true,
      silent = true,
    })
  end
end

---Create floating window using provided layout
---@param buf_id number Buffer ID
---@return number|nil Window ID or nil on failure
local function _create_window(buf_id)
  -- Use provided layout from instance
  local help_layout = instance.config.layout

  -- Create window
  local store_config = package.loaded["store.config"]
  if not store_config then return nil end
  local plugin_config = store_config.get()

  -- Compute width from actual buffer content (longest line)
  local content_lines = vim.api.nvim_buf_get_lines(buf_id, 0, -1, false)
  local max_width = 0
  for _, line in ipairs(content_lines) do
    max_width = math.max(max_width, vim.fn.strdisplaywidth(line))
  end
  local width = math.max(max_width, 1) + 5 -- +5 for markview table border decorations
  local height = #content_lines
  local screen_width = vim.o.columns
  local screen_height = vim.o.lines

  local win_id = vim.api.nvim_open_win(buf_id, true, {
    relative = "editor",
    width = width,
    height = height,
    row = math.floor((screen_height - height) / 2),
    col = math.floor((screen_width - width) / 2),
    style = "minimal",
    border = "none",
    zindex = plugin_config.zindex.popup,
  })

  if win_id then
    vim.api.nvim_win_set_var(win_id, "store_window", true)
  end

  return win_id
end

---Close the help window
function M.close()
  if not instance then
    return
  end

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
    logger.warn("Help requires on_exit callback")
    return
  end

  if not config.layout then
    logger.warn("Help requires layout information")
    return
  end

  if not config.keybindings then
    logger.warn("Help requires keybindings information")
    return
  end

  -- Create instance
  instance = {
    config = config,
    win_id = nil,
    buf_id = nil,
    is_open = false,
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
  end)

  if not success then
    logger.warn("Help window creation failed: " .. tostring(err))

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
