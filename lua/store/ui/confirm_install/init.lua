local logger = require("store.logger").createLogger({ context = "install" })
local utils = require("store.utils")
local validations = require("store.ui.confirm_install.validations")

local M = {}

---Extract configuration from markdown buffer
---@param buf_id number Buffer ID
---@return string|nil Extracted config or nil if not found
local function extract_config_from_buffer(buf_id)
  if not buf_id or not vim.api.nvim_buf_is_valid(buf_id) then
    return nil
  end

  local lines = vim.api.nvim_buf_get_lines(buf_id, 0, -1, false)
  local in_code_block = false
  local config_lines = {}

  for _, line in ipairs(lines) do
    if line:match("^```lua") then
      in_code_block = true
    elseif line:match("^```") and in_code_block then
      break -- End of lua code block
    elseif in_code_block then
      table.insert(config_lines, line)
    end
  end

  if #config_lines == 0 then
    return nil
  end

  return table.concat(config_lines, "\n")
end

---Create buffer content
---@param repository Repository
---@return string[] Content lines
local function create_content(repository)
  local lines = {}

  -- Header
  table.insert(lines, "# Confirm Plugin Installation")
  table.insert(lines, "")

  -- Plugin info
  table.insert(lines, "**Plugin**: " .. repository.full_name)

  -- Installation path with ~ shortening
  local filename = repository.name .. ".lua"
  local config_dir = vim.fn.stdpath("config")
  local home = vim.fn.expand("~")
  local short_path = config_dir:gsub("^" .. vim.pesc(home), "~")
  table.insert(lines, "**Install to**: `" .. short_path .. "/lua/plugins/" .. filename .. "`")

  -- Migration info
  if repository.install and repository.install.initial then
    if repository.install.initial == "lazy.nvim" then
      table.insert(lines, "**Source**: lazy.nvim native")
    else
      table.insert(lines, "**Source**: Migrated from " .. repository.install.initial .. " to lazy.nvim")
    end
  end

  table.insert(lines, "")
  table.insert(lines, "## Configuration:")
  table.insert(lines, "")
  table.insert(lines, "```lua")

  -- Add return prefix and configuration lines
  if repository.install and repository.install.lazyConfig then
    local config = repository.install.lazyConfig
    -- Add return prefix if not already present
    if not config:match("^return ") then
      config = "return " .. config
    end

    -- Split config into lines for proper display
    for line in config:gmatch("([^\n]*)\n?") do
      if line ~= "" then
        table.insert(lines, line)
      end
    end
  end

  table.insert(lines, "```")
  table.insert(lines, "")
  table.insert(lines, "---")
  table.insert(lines, "Press `Enter` to confirm or `Esc` to cancel")
  table.insert(lines, "You can edit the configuration above before installing")

  return lines
end

---Setup keymaps for the buffer
---@param buf_id number Buffer ID
---@param instance ConfirmInstall Instance for callbacks
local function setup_keymaps(buf_id, instance)
  -- Normal mode keymaps only
  local keymaps = {
    ["<cr>"] = function()
      local edited_config = extract_config_from_buffer(buf_id)
      if not edited_config then
        logger.warn("Failed to extract configuration from buffer")
        instance:close()
        return
      end

      instance:close()
      instance.config.on_confirm(edited_config)
    end,
    ["<esc>"] = function()
      instance:close()
      instance.config.on_cancel()
    end,
    ["q"] = function()
      instance:close()
      instance.config.on_cancel()
    end,
  }

  for key, callback in pairs(keymaps) do
    vim.api.nvim_buf_set_keymap(buf_id, "n", key, "", {
      noremap = true,
      silent = true,
      callback = callback,
    })
  end
end

---Calculate dimensions for content (80% of store modal)
---@param content string[] Content lines
---@return {width: number, height: number, row: number, col: number}
local function calculate_dimensions(content)
  local config = require("store.config").get()
  local layout = config.layout

  -- Calculate 80% of store modal dimensions
  local max_width = math.floor(layout.total_width * 0.8)
  local max_height = math.floor(layout.total_height * 0.8)

  -- Get actual content dimensions
  local content_height = #content -- Exact content height, no extra padding
  local content_width = 0

  for _, line in ipairs(content) do
    content_width = math.max(content_width, vim.fn.strchars(line))
  end
  content_width = content_width + 4 -- Add padding

  -- Use smaller of content size or max size
  local width = math.min(content_width, max_width)
  local height = math.min(content_height, max_height)

  -- Center the popup
  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)

  return {
    width = width,
    height = height,
    row = row,
    col = col,
  }
end

---Create new confirm install component
---@param config ConfirmInstallConfig
---@return ConfirmInstall|nil, string|nil Component instance or nil, error message
function M.new(config)
  -- Validate configuration
  local validation_error = validations.validate_config(config)
  if validation_error then
    return nil, validation_error
  end

  -- Create modifiable markdown buffer for editing
  local buf_id = utils.create_scratch_buffer({
    buftype = "nofile",
    modifiable = true,
    readonly = false,
    filetype = "markdown",
  })

  if not buf_id then
    return nil, "Failed to create buffer"
  end

  -- Create content and calculate dimensions
  local content = create_content(config.repository)
  local dimensions = calculate_dimensions(content)

  -- Set content
  utils.set_lines(buf_id, content)

  -- Create instance
  local instance = {
    config = config,
    win_id = nil,
    buf_id = buf_id,
    dimensions = dimensions,
  }

  setmetatable(instance, { __index = M })

  -- Setup keymaps
  setup_keymaps(buf_id, instance)

  return instance, nil
end

---Open the confirmation popup
---@return string|nil Error message or nil on success
function M:open()
  if self.win_id and vim.api.nvim_win_is_valid(self.win_id) then
    return "Window already open"
  end

  if not self.buf_id or not vim.api.nvim_buf_is_valid(self.buf_id) then
    return "Buffer is invalid"
  end

  -- Get config for z-index
  local config = require("store.config").get()

  -- Create window using utility function
  local win_id, error_message = utils.create_floating_window({
    buf_id = self.buf_id,
    config = {
      relative = "editor",
      width = self.dimensions.width,
      height = self.dimensions.height,
      row = self.dimensions.row,
      col = self.dimensions.col,
      style = "minimal",
      border = "rounded",
      zindex = config.zindex.popup,
    },
    opts = {
      conceallevel = 3,
      concealcursor = "nvc",
      wrap = true,
      cursorline = false,
    },
    focus = true,
  })

  if error_message then
    return "Cannot open confirm install window: " .. error_message
  end

  self.win_id = win_id

  -- Enable markview.nvim for beautiful rendering
  local markview_ok, markview = pcall(require, "markview")
  if markview_ok then
    markview.actions.attach(self.buf_id)
    markview.actions.enable(self.buf_id)
  end

  return nil
end

---Close the confirmation popup
---@return string|nil Error message or nil on success
function M:close()
  -- Detach markview before closing
  local markview_ok, markview = pcall(require, "markview")
  if self.buf_id and markview_ok then
    markview.actions.detach(self.buf_id)
  end

  if self.win_id and vim.api.nvim_win_is_valid(self.win_id) then
    vim.api.nvim_win_close(self.win_id, true)
  end

  if self.buf_id and vim.api.nvim_buf_is_valid(self.buf_id) then
    vim.api.nvim_buf_delete(self.buf_id, { force = true })
  end

  self.win_id = nil
  self.buf_id = nil

  return nil
end

return M
