local validations = require("store.ui.preview.validations")
local utils = require("store.utils")
local tabs = require("store.ui.tabs")
local logger = require("store.logger").createLogger({ context = "preview" })

local M = {}

local DEFAULT_PREVIEW_CONFIG = {
  keymaps_applier = function(buf_id)
    logger.warn("store.nvim: keymaps for preview window not configured")
  end,
  keymaps_applier_docs = function(buf_id)
    logger.warn("store.nvim: keymaps for docs buffer not configured")
  end,
}

local DEFAULT_STATE = {
  -- Window state
  win_id = nil,
  buf_id = nil,
  is_open = false,
  -- Content state
  content = nil,
  readme_id = nil,
  -- Cursor state
  cursor_positions = {},
  current_readme_id = nil,
  -- Tab state
  active_tab = "readme",
  docs_buf_id = nil,
  docs_cursor_positions = {},
  current_docs_id = nil,
}

-- Preview class
local Preview = {}
Preview.__index = Preview

---Create a new preview window instance
---@param preview_config PreviewConfig|nil Preview window configuration
---@return Preview|nil instance Preview instance on success, nil on error
---@return string|nil error Error message on failure, nil on success
function M.new(preview_config)
  -- Merge with defaults first
  local config = vim.tbl_deep_extend("force", DEFAULT_PREVIEW_CONFIG, preview_config or {})

  -- Validate merged configuration
  local error_msg = validations.validate_config(config)
  if error_msg then
    return nil, "Preview window configuration validation failed: " .. error_msg
  end

  local instance = {
    config = config,
    state = vim.tbl_deep_extend("force", DEFAULT_STATE, {
      buf_id = utils.create_scratch_buffer({
        filetype = "markdown", -- Set to markdown for proper markview rendering
        buftype = "", -- Keep as nofile for scratch buffer behavior
        bufhidden = "hide",
      }),
      docs_buf_id = utils.create_scratch_buffer({
        filetype = "help",
        bufhidden = "hide",
      }),
    }),
  }

  setmetatable(instance, Preview)

  -- Apply keymaps to buffers
  config.keymaps_applier(instance.state.buf_id)
  config.keymaps_applier_docs(instance.state.docs_buf_id)

  return instance, nil
end

---Open the preview window with default content
---@return string|nil error Error message on failure, nil on success
function Preview:open()
  if self.state.is_open then
    logger.warn("Preview window: open() called when window is already open")
    return nil
  end

  local store_config = require("store.config")
  local plugin_config = store_config.get()

  local window_config = {
    width = self.config.width,
    height = self.config.height,
    row = self.config.row,
    col = self.config.col,
    focusable = true,
    zindex = plugin_config.zindex.base,
    title = tabs.build_title(tabs.RIGHT_TABS, self.state.active_tab or "readme"),
    title_pos = "left",
  }

  local window_opts = {
    conceallevel = 3, -- Required for markview to hide markdown syntax
    concealcursor = "nvc", -- Hide concealed text in normal, visual, command modes
    wrap = false, -- Disable text wrapping for markdown content
    cursorline = false,
  }

  local win_id, error_message = utils.create_floating_window({
    buf_id = self.state.buf_id,
    config = window_config,
    opts = window_opts,
  })
  if error_message then
    return "Cannot open preview window: " .. error_message
  end

  self.state.win_id = win_id
  self.state.is_open = true

  local markview_ok, markview = pcall(require, "markview")
  if markview_ok and markview.strict_render then
    -- markview.strict_render:clear(self.state.buf_id)  -- Clear any previous render
    markview.strict_render:render(self.state.buf_id)
  end
  -- local markview_ok, markview = pcall(require, "markview")
  -- if markview_ok then
  --   markview.actions.attach(self.state.buf_id)
  --   markview.actions.enable(self.state.buf_id)
  -- end

  -- Set default content
  return self:render({ state = "loading" })
end

---Render content in the preview window based on state
---@param state PreviewStateUpdate Preview state to render
---@return string|nil error Error message on failure, nil on success
function Preview:render(state)
  if type(state) ~= "table" then
    return "Preview window: Cannot render - state must be a table, got: " .. type(state)
  end
  if not self.state.is_open then
    return "Preview window: Cannot render - window not open"
  end
  if not self.state.buf_id then
    return "Preview window: Cannot render - invalid buffer"
  end

  -- Save cursor position for current README before switching
  self:_save_cursor_position()

  -- Create new state locally by merging current state with update
  local new_state = vim.tbl_deep_extend("force", self.state, state)

  -- Validate the merged state before applying it
  local validation_error = validations.validate_state(new_state)
  if validation_error then
    return "Preview window: Invalid state update - " .. validation_error
  end

  -- Only assign to self.state if validation passes
  self.state = new_state

  -- Only schedule the final rendering dispatch using safe self.state
  vim.schedule(function()
    local start_time = vim.loop.hrtime()

    if self.state.state == "loading" then
      self:_render_loading()
    elseif self.state.state == "error" then
      self:_render_error(self.state)
    else
      self:_render_ready(self.state)
    end

    local elapsed = (vim.loop.hrtime() - start_time) / 1000000
    if elapsed > 100 then
      logger.debug(string.format("Preview render took %dms", elapsed))
    end
  end)

  return nil
end

---Focus the preview window and restore cursor position
---@return string|nil error Error message on failure, nil on success
function Preview:focus()
  if not self.state.is_open then
    return "Preview window: Cannot focus - window not open"
  end
  if not self.state.win_id or not vim.api.nvim_win_is_valid(self.state.win_id) then
    return "Preview window: Cannot focus - invalid window"
  end

  vim.api.nvim_set_current_win(self.state.win_id)

  -- Restore cursor position for current README if available
  if self.state.current_readme_id then
    self:_restore_cursor_position(self.state.current_readme_id)
  end

  return nil
end

---Save cursor position when losing focus (called externally)
---@return nil
function Preview:save_cursor_on_blur()
  self:_save_cursor_position()
end

---Switch the active tab (readme or docs) in the preview pane
---@param tab_id string "readme" or "docs"
function Preview:set_active_tab(tab_id)
  if not self.state.is_open or not self.state.win_id or not vim.api.nvim_win_is_valid(self.state.win_id) then
    return
  end

  -- Save cursor for current tab
  if self.state.active_tab == "readme" then
    self:_save_cursor_position()
  elseif self.state.active_tab == "docs" and self.state.current_docs_id then
    pcall(function()
      local cursor = vim.api.nvim_win_get_cursor(self.state.win_id)
      self.state.docs_cursor_positions[self.state.current_docs_id] = { cursor[1], cursor[2] }
    end)
  end

  self.state.active_tab = tab_id

  -- Swap buffer
  local target_buf = tab_id == "docs" and self.state.docs_buf_id or self.state.buf_id
  vim.api.nvim_win_set_buf(self.state.win_id, target_buf)

  -- Update title
  pcall(vim.api.nvim_win_set_config, self.state.win_id, {
    title = tabs.build_title(tabs.RIGHT_TABS, tab_id),
    title_pos = "left",
  })

  -- Update window options per tab
  if tab_id == "readme" then
    vim.api.nvim_set_option_value("conceallevel", 3, { win = self.state.win_id })
    vim.api.nvim_set_option_value("concealcursor", "nvc", { win = self.state.win_id })
    -- Restore cursor for readme
    if self.state.current_readme_id then
      self:_restore_cursor_position(self.state.current_readme_id)
    end
  else
    vim.api.nvim_set_option_value("conceallevel", 0, { win = self.state.win_id })
    vim.api.nvim_set_option_value("concealcursor", "", { win = self.state.win_id })
    -- Restore cursor for docs
    if self.state.current_docs_id then
      local saved = self.state.docs_cursor_positions[self.state.current_docs_id]
      if saved then
        local line_count = vim.api.nvim_buf_line_count(self.state.docs_buf_id)
        pcall(vim.api.nvim_win_set_cursor, self.state.win_id, { math.min(saved[1], line_count), saved[2] })
      else
        pcall(vim.api.nvim_win_set_cursor, self.state.win_id, { 1, 0 })
      end
    end
  end
end

---Render docs content into the docs buffer
---@param state table {state: string, content: string[]|nil, docs_id: string|nil}
function Preview:render_docs(state)
  vim.schedule(function()
    if not self.state.docs_buf_id or not vim.api.nvim_buf_is_valid(self.state.docs_buf_id) then
      return
    end
    if state.state == "error" then
      local lines = state.content or { "Error loading documentation" }
      utils.set_lines(self.state.docs_buf_id, lines)
    elseif state.state == "ready" then
      local lines = state.content or { "No documentation available" }
      utils.set_lines(self.state.docs_buf_id, lines)
    else
      utils.set_lines(self.state.docs_buf_id, { "Loading documentation..." })
    end

    if state.docs_id then
      self.state.current_docs_id = state.docs_id
      -- Restore cursor for docs
      if self.state.win_id and vim.api.nvim_win_is_valid(self.state.win_id) and self.state.active_tab == "docs" then
        local saved = self.state.docs_cursor_positions[state.docs_id]
        if saved then
          local line_count = vim.api.nvim_buf_line_count(self.state.docs_buf_id)
          pcall(vim.api.nvim_win_set_cursor, self.state.win_id, { math.min(saved[1], line_count), saved[2] })
        else
          pcall(vim.api.nvim_win_set_cursor, self.state.win_id, { 1, 0 })
        end
      end
    end
  end)
end

---Get the currently active tab
---@return string "readme" or "docs"
function Preview:get_active_tab()
  return self.state.active_tab
end

---Resize the preview window and preserve scroll state
---@param layout_config {width: number, height: number, row: number, col: number} New layout configuration
---@return string|nil error Error message if resize failed, nil if successful
function Preview:resize(layout_config)
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

  if not self.state.is_open or not self.state.win_id or not vim.api.nvim_win_is_valid(self.state.win_id) then
    return "Cannot resize preview window: window not open or invalid"
  end

  -- Save current scroll position and cursor state
  local cursor_pos = vim.api.nvim_win_get_cursor(self.state.win_id)
  local topline = vim.fn.line("w0", self.state.win_id)
  local current_readme_id = self.state.current_readme_id

  local win_config = {
    relative = "editor",
    row = layout_config.row,
    col = layout_config.col,
    width = layout_config.width,
    height = layout_config.height,
    title = tabs.build_title(tabs.RIGHT_TABS, self.state.active_tab or "readme"),
    title_pos = "left",
  }

  local success, err = pcall(vim.api.nvim_win_set_config, self.state.win_id, win_config)
  if not success then
    return "Failed to resize preview window: " .. (err or "unknown error")
  end

  -- Update config for future operations
  self.config.width = layout_config.width
  self.config.height = layout_config.height
  self.config.row = layout_config.row
  self.config.col = layout_config.col

  -- Save cursor position for current readme if we have one
  if current_readme_id then
    self.state.cursor_positions[current_readme_id] = cursor_pos
  end

  if self.state.content then
    vim.schedule(function()
      if vim.api.nvim_win_is_valid(self.state.win_id) then
        -- Restore scroll position first
        pcall(vim.api.nvim_win_call, self.state.win_id, function()
          vim.cmd("normal! " .. topline .. "Gzt")
        end)
        -- Then restore cursor position
        pcall(vim.api.nvim_win_set_cursor, self.state.win_id, cursor_pos)
      end
    end)
  end

  return nil
end

---Close the preview window
---@return string|nil error Error message on failure, nil on success
function Preview:close()
  if not self.state.is_open then
    logger.warn("Preview window: close() called when window is not open")
    return nil
  end

  -- Clear strict render instead of detaching (for preview-only buffers)
  local markview_ok, markview = pcall(require, "markview")
  if markview_ok and markview.strict_render then
    markview.strict_render:clear(self.state.buf_id)
  end

  -- Close window
  if self.state.win_id and vim.api.nvim_win_is_valid(self.state.win_id) then
    local success, err = pcall(vim.api.nvim_win_close, self.state.win_id, true)
    if not success then
      return "Failed to close preview window: " .. tostring(err)
    end
  end

  -- Clean up docs buffer
  if self.state.docs_buf_id and vim.api.nvim_buf_is_valid(self.state.docs_buf_id) then
    pcall(vim.api.nvim_buf_delete, self.state.docs_buf_id, { force = true })
  end

  -- Clean up readme buffer
  if self.state.buf_id and vim.api.nvim_buf_is_valid(self.state.buf_id) then
    pcall(vim.api.nvim_buf_delete, self.state.buf_id, { force = true })
  end

  -- Reset window state
  self.state.win_id = nil
  self.state.is_open = false

  return nil
end

---Save current cursor position for the current README
---@return nil
function Preview:_save_cursor_position()
  if not self.state.current_readme_id or not self.state.win_id then
    return
  end

  local readme_id = self.state.current_readme_id
  local win_id = self.state.win_id
  vim.schedule(function()
    pcall(function()
      local cursor = vim.api.nvim_win_get_cursor(win_id)
      self.state.cursor_positions[readme_id] = { cursor[1], cursor[2] }
    end)
  end)
end

---Restore cursor position for a specific README
---@param readme_id string README identifier
---@return nil
function Preview:_restore_cursor_position(readme_id)
  if not readme_id or not self.state.win_id or not vim.api.nvim_win_is_valid(self.state.win_id) then
    return
  end

  local saved_position = self.state.cursor_positions[readme_id]
  if saved_position then
    -- Validate that the saved position is within bounds
    local line_count = vim.api.nvim_buf_line_count(self.state.buf_id)
    local line = math.min(saved_position[1], line_count)
    local col = saved_position[2]

    vim.api.nvim_win_set_cursor(self.state.win_id, { line, col })
  else
    -- First time viewing this README, set cursor to top
    vim.api.nvim_win_set_cursor(self.state.win_id, { 1, 0 })
  end
end

---Render loading state
---@private
function Preview:_render_loading()
  local content_lines = { "Loading preview..." }
  utils.set_lines(self.state.buf_id, content_lines)
end

---Render error state
---@private
---@param state PreviewState Preview state containing error content
function Preview:_render_error(state)
  local content_lines = state.content or { "Error occurred while loading content" }
  utils.set_lines(self.state.buf_id, content_lines)
end

---Render ready state with content
---@private
---@param state PreviewState Preview state containing ready content
function Preview:_render_ready(state)
  local content_lines = state.content or { "No content available" }
  utils.set_lines(self.state.buf_id, content_lines)

  -- Use strict_render for preview-only scenarios (recommended by markview author)
  local markview_ok, markview = pcall(require, "markview")
  if markview_ok and markview.strict_render then
    markview.strict_render:clear(self.state.buf_id) -- Clear any previous render
    markview.strict_render:render(self.state.buf_id)
  end

  -- Update current README ID and restore cursor position
  self.state.current_readme_id = state.readme_id
  if state.readme_id then
    self:_restore_cursor_position(state.readme_id)
  end
end

---Get the window ID of the preview component
---@return number|nil window_id Window ID if open, nil otherwise
function Preview:get_window_id()
  if self.state.is_open and self.state.win_id and vim.api.nvim_win_is_valid(self.state.win_id) then
    return self.state.win_id
  end
  return nil
end

---Check if the preview component is in a valid state
---@return boolean is_valid True if component is valid and ready for use
function Preview:is_valid()
  return self.state.buf_id ~= nil
    and vim.api.nvim_buf_is_valid(self.state.buf_id)
    and (not self.state.is_open or (self.state.win_id and vim.api.nvim_win_is_valid(self.state.win_id)))
end

return M
