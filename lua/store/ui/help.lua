---@class HelpModal
---@field win_id number|nil Window ID of the help modal
---@field buf_id number|nil Buffer ID of the help modal
---@field timer userdata|nil Timer reference for cleanup
local HelpModal = {}

local ZINDEX = {
  HELP_MODAL = 152,
}

---@type HelpModal|nil
local current_help = nil

---Help modal configuration - list of keybinding to action pairs
---@type table[]
local help_config = {
  { keybinding = "f", action = "Filter repos" },
  { keybinding = "<CR>", action = "Open repo" },
  { keybinding = "r", action = "Refresh list" },
  { keybinding = "q", action = "Close modal" },
  { keybinding = "<Esc>", action = "Close modal" },
  { keybinding = "?", action = "Show help" },
}

---Generate help content for the modal with vertical padding only
---@return string[] List of help content lines
local function generate_help_content()
  -- Calculate column widths
  local max_key_width = 3 -- Minimum for "Key" header
  local max_action_width = 6 -- Minimum for "Action" header

  for _, item in ipairs(help_config) do
    max_key_width = math.max(max_key_width, vim.fn.strchars(item.keybinding))
    max_action_width = math.max(max_action_width, vim.fn.strchars(item.action))
  end

  -- Build table header
  local header = string.format("| %-" .. max_key_width .. "s | %-" .. max_action_width .. "s |", "Key", "Action")
  local separator = string.format("|%s|%s|", string.rep("-", max_key_width + 2), string.rep("-", max_action_width + 2))

  -- Build content lines
  local content = {
    "", -- Additional top padding
    header,
    separator,
  }

  for _, item in ipairs(help_config) do
    local line =
      string.format("| %-" .. max_key_width .. "s | %-" .. max_action_width .. "s |", item.keybinding, item.action)
    table.insert(content, line)
  end

  table.insert(content, "") -- Additional bottom padding

  return content
end

---Create and display the help window
---@return boolean Success status
local function create_help_window()
  if current_help then
    if current_help.win_id and vim.api.nvim_win_is_valid(current_help.win_id) then
      vim.api.nvim_win_close(current_help.win_id, true)
    end
    current_help = nil
  end

  -- Create buffer for help content
  local help_bufnr = vim.api.nvim_create_buf(false, true)
  vim.bo[help_bufnr].bufhidden = "wipe"
  vim.bo[help_bufnr].buftype = ""
  vim.bo[help_bufnr].filetype = "markdown"

  -- Set help content
  local help_content = generate_help_content()
  vim.api.nvim_buf_set_lines(help_bufnr, 0, -1, false, help_content)
  vim.bo[help_bufnr].modifiable = false

  -- Calculate dimensions based on content (no horizontal padding needed)
  local max_width = 0
  for _, line in ipairs(help_content) do
    max_width = math.max(max_width, vim.fn.strchars(line))
  end
  local help_width = max_width -- No additional horizontal padding
  local help_height = #help_content -- Content already has vertical padding

  local screen_width = vim.o.columns
  local screen_height = vim.o.lines
  local help_row = math.floor((screen_height - help_height) / 2)
  local help_col = math.floor((screen_width - help_width) / 2)

  -- Create floating window (borderless, just for display)
  local help_winid = vim.api.nvim_open_win(help_bufnr, false, {
    relative = "editor",
    width = help_width,
    height = help_height,
    row = help_row,
    col = help_col,
    style = "minimal",
    border = "none", -- Remove border completely
    zindex = ZINDEX.HELP_MODAL,
    focusable = false, -- Make it non-focusable so it's just for reading
  })

  if not help_winid then
    return false
  end

  -- Store reference
  -- Auto-close after 2 seconds
  local timer = vim.loop.new_timer()
  
  current_help = {
    win_id = help_winid,
    buf_id = help_bufnr,
    timer = timer,
  }

  timer:start(
    2000,
    0,
    vim.schedule_wrap(function()
      if current_help and current_help.win_id and vim.api.nvim_win_is_valid(current_help.win_id) then
        vim.api.nvim_win_close(current_help.win_id, true)
      end
      if current_help and current_help.timer then
        current_help.timer:close()
      end
      current_help = nil
    end)
  )

  return true
end

---Close help modal if open
local function close_help_if_open()
  if current_help then
    if current_help.win_id and vim.api.nvim_win_is_valid(current_help.win_id) then
      vim.api.nvim_win_close(current_help.win_id, true)
    end
    -- Clean up timer to prevent resource leak
    if current_help.timer then
      current_help.timer:close()
    end
    current_help = nil
  end
end

---Public API
local M = {}

---Open the help modal
---@return boolean Success status
function M.open()
  return create_help_window()
end

---Close the help modal if it's open
function M.close()
  close_help_if_open()
end

---Check if help modal is currently open
---@return boolean True if help modal is open
function M.is_open()
  return current_help ~= nil
    and current_help.win_id ~= nil
    and vim.api.nvim_win_is_valid(current_help.win_id)
end

return M
