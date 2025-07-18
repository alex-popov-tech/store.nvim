local logger = require("store.logger")
local sort = require("store.sort")

local M = {}

---@class SortSelectConfig
---@field current_sort string Current sort type to mark with checkmark
---@field on_value fun(selected_sort: string) Callback when user selects a sort
---@field on_exit fun() Callback when user cancels (handles focus restoration)

---@class SortSelectWindow
---@field config SortSelectConfig
---@field win_id number|nil Window ID
---@field buf_id number|nil Buffer ID
---@field is_open boolean
---@field sort_types string[] Array of sort type keys

-- Static instance to prevent multiple opens
local instance = nil

---Create buffer content with checkmarks for current sort
---@param current_sort string Current sort type
---@param sort_types string[] Array of sort type keys
---@return string[] Array of content lines
local function _create_content_lines(current_sort, sort_types)
  local lines = {}
  for _, sort_type in ipairs(sort_types) do
    local checkmark = (sort_type == current_sort) and "✓ " or "  "
    local label = sort.sorts[sort_type].label
    table.insert(lines, checkmark .. label)
  end
  return lines
end

---Get selected sort type based on current cursor position
---@return string Selected sort type
local function _get_selected_sort()
  if not instance or not instance.win_id or not vim.api.nvim_win_is_valid(instance.win_id) then
    return instance.sort_types[1] or "default"
  end

  local cursor_line = vim.api.nvim_win_get_cursor(instance.win_id)[1]
  return instance.sort_types[cursor_line] or instance.sort_types[1] or "default"
end

---Handle selection and close window
local function _select_and_close()
  if not instance then
    return
  end

  local selected_sort = _get_selected_sort()
  local on_value = instance.config.on_value

  M.close()

  -- Call callback after cleanup
  if on_value then
    on_value(selected_sort)
  end
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
  local content_lines = _create_content_lines(instance.config.current_sort, instance.sort_types)
  vim.api.nvim_buf_set_lines(buf_id, 0, -1, false, content_lines)

  -- Make buffer read-only
  vim.api.nvim_buf_set_option(buf_id, "modifiable", false)
  vim.api.nvim_buf_set_option(buf_id, "readonly", true)

  -- Set buffer name
  vim.api.nvim_buf_set_name(buf_id, "SortSelect")

  return buf_id
end

---Setup buffer-local keymaps
---@param buf_id number Buffer ID
local function _setup_keymaps(buf_id)
  local keymaps = {
    ["<cr>"] = _select_and_close,
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

  local win_width = 30
  local win_height = 3 -- only three sorting options right now

  -- Position at top of modal space, overlapping heading
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

---Close the sort select window
function M.close()
  if not instance then
    return
  end

  logger.debug("Closing SortSelect window")

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

---Open sort select window
---@param config SortSelectConfig Configuration
function M.open(config)
  -- Prevent multiple instances
  if instance then
    logger.warn("SortSelect window already open")
    return
  end

  -- Validate configuration
  if not config or not config.on_value or not config.on_exit then
    logger.error("SortSelect requires on_value and on_exit callbacks")
    return
  end

  -- Get sort types
  local sort_types = sort.get_sort_types()
  if not sort_types or #sort_types == 0 then
    logger.error("No sort types available")
    return
  end

  -- Create instance
  instance = {
    config = config,
    win_id = nil,
    buf_id = nil,
    is_open = false,
    sort_types = sort_types,
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

    logger.debug("SortSelect window opened successfully")
  end)

  if not success then
    logger.error("SortSelect window creation failed: " .. tostring(err))

    -- Cleanup partial state
    if instance then
      if instance.buf_id and vim.api.nvim_buf_is_valid(instance.buf_id) then
        vim.api.nvim_buf_delete(instance.buf_id, { force = true })
      end
      instance = nil
    end

    -- Fallback to vim.ui.select
    vim.ui.select(sort_types, {
      prompt = "Sort by:",
      format_item = function(item)
        return sort.sorts[item].label
      end,
    }, function(choice)
      if choice then
        config.on_value(choice)
      end
      config.on_exit()
    end)
  end
end

return M
