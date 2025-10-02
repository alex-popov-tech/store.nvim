local utils = require("store.utils")
local logger = require("store.logger").createLogger({ context = "hover" })

local M = {}

local DEFAULT_STATE = {
  win_id = nil,
  buf_id = nil,
  is_closed = true, -- Initially closed
}

-- Hover class
local Hover = {}
Hover.__index = Hover

---Create a new hover window instance
---@param config HoverConfig Hover window configuration
---@return Hover|nil instance Hover instance on success, nil on error
---@return string|nil error Error message on failure, nil on success
function M.new(config)
  if not config or not config.repository then
    return nil, "Repository is required for hover component"
  end

  local instance = {
    config = config,
    state = vim.tbl_deep_extend("force", DEFAULT_STATE, {
      buf_id = utils.create_scratch_buffer({
        filetype = "markdown",
        buftype = "nofile",
        modifiable = false,
      }),
    }),
  }

  setmetatable(instance, Hover)
  return instance, nil
end

---Format repository information for display
---@param repo Repository The repository to format
---@return string[] lines Formatted lines for display
local function format_repository_info(repo)
  local lines = {}

  -- Title
  table.insert(lines, "# " .. repo.full_name)
  table.insert(lines, "")

  -- Stats table
  table.insert(
    lines,
    "⭐"
      .. repo.stars
      .. " 🚨"
      .. repo.issues
      .. " 📅 updated "
      .. repo.pretty.updated_at
      .. " 📅 created "
      .. repo.pretty.created_at
  )

  -- Description
  if repo.description ~= "" then
    table.insert(lines, "")
    table.insert(lines, repo.description)
  end

  -- Tags/Topics
  if #repo.tags > 0 then
    table.insert(lines, "")
    table.insert(lines, table.concat(repo.tags, ","))
  end

  return lines
end

---Show the hover window
---@return string|nil error Error message on failure, nil on success
function Hover:show()
  if not self.state.is_closed then
    logger.warn("Hover window: show() called when window is already open")
    return nil
  end

  local repo = self.config.repository
  local content_lines = format_repository_info(repo)

  -- Set buffer content
  vim.api.nvim_buf_set_option(self.state.buf_id, "modifiable", true)
  vim.api.nvim_buf_set_lines(self.state.buf_id, 0, -1, false, content_lines)
  vim.api.nvim_buf_set_option(self.state.buf_id, "modifiable", false)

  -- Calculate content dimensions
  local max_width = 0
  for _, line in ipairs(content_lines) do
    max_width = math.max(max_width, vim.fn.strdisplaywidth(line))
  end

  -- Better content fitting - pad for borders but keep reasonable limits
  local width = math.min(math.max(max_width + 2, 40), 60)
  local height = math.min(#content_lines, 15)

  -- Create floating window positioned relative to cursor
  local window_config = {
    relative = "cursor",
    width = width,
    height = height,
    row = 1, -- 1 line below cursor
    col = 0, -- Aligned with cursor column
    focusable = false,
    zindex = 60, -- Higher than modal windows
    style = "minimal",
    border = "rounded",
  }

  -- Window options for proper text display
  local window_opts = {
    wrap = true,
    linebreak = true, -- Break at word boundaries
  }

  local win_id, err = utils.create_floating_window({
    buf_id = self.state.buf_id,
    config = window_config,
    opts = window_opts,
  })

  if err then
    return "Failed to create hover window: " .. err
  end

  self.state.win_id = win_id
  self.state.is_closed = false

  -- Setup auto-close behavior
  local function close_hover()
    if self.state.win_id and vim.api.nvim_win_is_valid(self.state.win_id) then
      vim.api.nvim_win_close(self.state.win_id, true)
      self.state.win_id = nil
      self.state.is_closed = true
    end
  end

  -- Close on cursor move or mode change
  local group = vim.api.nvim_create_augroup("StoreHover" .. self.state.buf_id, { clear = true })

  vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI", "ModeChanged" }, {
    group = group,
    callback = function()
      close_hover()
      vim.api.nvim_del_augroup_by_id(group)
    end,
  })

  -- Close on window leave
  vim.api.nvim_create_autocmd("WinLeave", {
    group = group,
    callback = function()
      vim.defer_fn(function()
        close_hover()
        vim.api.nvim_del_augroup_by_id(group)
      end, 10)
    end,
  })

  -- Enable markview rendering like in preview when available
  local ok, markview = pcall(require, "markview")
  if ok and markview.strict_render then
    markview.strict_render:render(self.state.buf_id)
  end

  return nil
end

---Close the hover window
---@return string|nil error Error message on failure, nil on success
function Hover:close()
  if self.state.is_closed then
    return nil
  end

  if self.state.win_id and vim.api.nvim_win_is_valid(self.state.win_id) then
    vim.api.nvim_win_close(self.state.win_id, true)
  end

  self.state.win_id = nil
  self.state.is_closed = true

  return nil
end

return M
