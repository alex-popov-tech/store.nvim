local logger = require("store.logger").createLogger({ context = "install" })
local utils = require("store.utils")
local validations = require("store.ui.install_modal.validations")

local M = {}

---Extract configuration and filepath from markdown buffer
---@param buf_id number Buffer ID
---@return table|nil, string|nil Extracted data {config: string, filepath: string} or nil, error message
local function extract_data_from_buffer(buf_id)
  if not buf_id or not vim.api.nvim_buf_is_valid(buf_id) then
    return nil, "Invalid buffer"
  end

  local lines = vim.api.nvim_buf_get_lines(buf_id, 0, -1, false)
  local in_code_block = false
  local in_filepath_block = false
  local config_lines = {}
  local filepath_lines = {}
  local filepath = nil

  logger.debug("Extracting data from buffer with " .. #lines .. " lines")

  for i, line in ipairs(lines) do
    logger.debug("Line " .. i .. ": " .. line)

    -- Track filepath block for user path selection
    if line:match("^```text$") then
      in_filepath_block = true
      filepath_lines = {}
      logger.debug("Started filepath block")
    -- Extract config from code block
    elseif line:match("^```lua") then
      in_code_block = true
      logger.debug("Started lua code block")
    elseif line:match("^```$") then
      if in_code_block then
        logger.debug("Ended lua code block")
        break -- End of lua code block
      elseif in_filepath_block then
        logger.debug("Ended filepath block")
        in_filepath_block = false
        if #filepath_lines > 0 then
          filepath = filepath_lines[1]
          logger.debug("Captured filepath: " .. filepath)
        end
      end
    elseif in_code_block then
      table.insert(config_lines, line)
    elseif in_filepath_block then
      if vim.trim(line) ~= "" then
        table.insert(filepath_lines, vim.trim(line))
      end
    end
  end

  if #config_lines == 0 then
    return nil, "No configuration found in code block"
  end

  if not filepath then
    return nil, "No filepath found in Install to block"
  end

  local result = {
    config = table.concat(config_lines, "\n"),
    filepath = filepath,
  }

  logger.debug("Extracted config: " .. result.config)
  logger.debug("Extracted filepath: " .. result.filepath)

  return result, nil
end

---Create buffer content
---@param repository Repository
---@param snippet string
---@return string[] Content lines
local function create_content(repository, snippet)
  local lines = {}

  -- Header
  table.insert(lines, "# Confirm installation of `" .. repository.full_name .. "`")
  table.insert(lines, "")

  local plugins_folder = utils.get_plugins_folder()
  local filename = repository.name .. ".lua"
  local filepath = plugins_folder .. "/" .. filename

  -- Convert to user-friendly path with ~
  local home = vim.fn.expand("~")
  local display_path = filepath:gsub("^" .. vim.pesc(home), "~")
  table.insert(lines, "**Install to** (create new file or append if exists):")
  table.insert(lines, "```text")
  table.insert(lines, display_path)
  table.insert(lines, "```")
  table.insert(lines, "## Configuration ( ✏️editable ):")
  table.insert(lines, "```lua")

  local raw_lines = vim.split(snippet or "", "\n", { plain = true })

  local start_idx = 1
  local end_idx = #raw_lines

  while start_idx <= end_idx and vim.trim(raw_lines[start_idx]) == "" do
    start_idx = start_idx + 1
  end

  while end_idx >= start_idx and vim.trim(raw_lines[end_idx]) == "" do
    end_idx = end_idx - 1
  end

  local snippet_lines = {}
  for i = start_idx, end_idx do
    table.insert(snippet_lines, raw_lines[i])
  end

  if #snippet_lines == 0 then
    snippet_lines = { "-- snippet not provided" }
  end

  for _, line in ipairs(snippet_lines) do
    table.insert(lines, line)
  end

  table.insert(lines, "```")
  table.insert(lines, "---")
  table.insert(lines, "Press `Enter` to confirm or `Esc` to cancel")

  return lines
end

---Setup keymaps for the buffer
---@param buf_id number Buffer ID
---@param instance InstallModal Instance for callbacks
local function setup_keymaps(buf_id, instance)
  -- Normal mode keymaps only
  local keymaps = {
    ["<cr>"] = function()
      local extracted_data, err = extract_data_from_buffer(buf_id)
      if not extracted_data then
        local message = "Failed to extract configuration and filepath from buffer"
        if err then
          message = message .. "\n" .. err
        end
        logger.warn(message)
        instance:close()
        return
      end

      instance:close()
      instance.config.on_confirm(extracted_data)
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
    vim.keymap.set("n", key, callback, {
      buffer = buf_id,
      noremap = true,
      silent = true,
    })
  end
end

---Calculate dimensions for content (80% of store modal)
---@param content string[] Content lines
---@return {width: number, height: number, row: number, col: number}
local function calculate_dimensions(content)
  local config = require("store.config").get()
  local layout = config.layout

  -- Calculate 70% of store modal dimensions as upper bounds
  local max_width = math.floor(layout.total_width * 0.7)
  local max_height = math.floor(layout.total_height * 0.7)

  -- Measure content dimensions
  local content_height = #content
  local content_width = 0
  for _, line in ipairs(content) do
    content_width = math.max(content_width, vim.fn.strdisplaywidth(line))
  end

  local horizontal_padding = 6 -- accounts for border and breathing space
  local vertical_padding = 4

  local width = math.min(math.max(content_width + horizontal_padding, 40), max_width)
  local height = math.min(math.max(content_height + vertical_padding, 10), max_height)

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
---@param config InstallModalConfig
---@return InstallModal|nil, string|nil Component instance or nil, error message
function M.new(config)
  -- Validate configuration
  local validation_error = validations.validate_config(config)
  if validation_error then
    return nil, validation_error
  end

  -- Create modifiable markdown buffer for editing
  local buf_id = utils.create_scratch_buffer({
    filetype = "markdown",
    buftype = "",
    modifiable = true,
    readonly = false,
  })

  if not buf_id then
    return nil, "Failed to create buffer"
  end

  -- Create content and calculate dimensions
  local content = create_content(config.repository, config.snippet)
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
      wrap = false,
      cursorline = false,
    },
    focus = true,
  })

  if error_message then
    return "Cannot open confirm install window: " .. error_message
  end

  self.win_id = win_id

  -- Render markdown using markview's strict renderer for consistency with list/preview
  local markview_ok, markview = pcall(require, "markview")
  if markview_ok and markview.strict_render then
    markview.strict_render:render(self.buf_id)
  end

  return nil
end

---Close the confirmation popup
---@return string|nil Error message or nil on success
function M:close()
  -- Clear markview rendering if available before closing the window
  local markview_ok, markview = pcall(require, "markview")
  if self.buf_id and markview_ok and markview.strict_render then
    markview.strict_render:clear(self.buf_id)
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
