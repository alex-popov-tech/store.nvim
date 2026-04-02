local validations = require("store.ui.preview.validations")
local utils = require("store.utils")
local tabs = require("store.ui.tabs")
local logger = require("store.logger").createLogger({ context = "preview" })

local ns_id = vim.api.nvim_create_namespace("store.preview")

local M = {}

local DEFAULT_PREVIEW_CONFIG = {
  keymaps_applier = function(buf_id)
    logger.warn("store.nvim: keymaps for preview window not configured")
  end,
  keymaps_applier_docs = function(buf_id)
    logger.warn("store.nvim: keymaps for docs buffer not configured")
  end,
  on_tab_change = nil, -- callback when active tab changes (for winbar updates in tab mode)
}

local DEFAULT_STATE = {
  buf = {
    id = nil,
    docs_id = nil,
  },
  win = {
    id = nil,
    is_open = false,
    active_tab = "readme",
  },
  -- Content state (top-level, not buf or win)
  content = nil,
  readme_id = nil,
  -- Cursor tracking (content-keyed, survives window close -- top-level)
  cursor_positions = {},
  current_readme_id = nil,
  docs_cursor_positions = {},
  current_docs_id = nil,
  -- Doc navigation state
  doc_index = 0,    -- current doc index (1-based when viewing docs, 0 = not viewing)
  doc_paths = {},   -- string[] from repo.doc, set on plugin selection
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
    state = vim.tbl_deep_extend("force", vim.deepcopy(DEFAULT_STATE), {
      buf = {
        id = utils.create_scratch_buffer({
          filetype = "markdown",
          buftype = "", -- Keep as nofile for scratch buffer behavior
          bufhidden = "hide",
        }),
        docs_id = utils.create_scratch_buffer({
          filetype = "help",
          bufhidden = "hide",
        }),
      },
    }),
  }

  setmetatable(instance, Preview)

  -- Apply keymaps to buffers
  config.keymaps_applier(instance.state.buf.id)
  config.keymaps_applier_docs(instance.state.buf.docs_id)

  return instance, nil
end

-- =============================================================================
-- Private buffer methods
-- =============================================================================

---@private
---Dispatch rendering to the buffer regardless of window state
function Preview:_buf_render()
  if not self.state.buf.id or not vim.api.nvim_buf_is_valid(self.state.buf.id) then
    return
  end
  vim.schedule(function()
    if not self.state.buf.id or not vim.api.nvim_buf_is_valid(self.state.buf.id) then
      return
    end

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
end

---@private
---Destroy buffers: delete docs buffer and readme buffer
function Preview:_buf_destroy()
  -- Clean up docs buffer
  if self.state.buf.docs_id and vim.api.nvim_buf_is_valid(self.state.buf.docs_id) then
    pcall(vim.api.nvim_buf_delete, self.state.buf.docs_id, { force = true })
  end
  self.state.buf.docs_id = nil

  -- Clean up readme buffer
  if self.state.buf.id and vim.api.nvim_buf_is_valid(self.state.buf.id) then
    pcall(vim.api.nvim_buf_delete, self.state.buf.id, { force = true })
  end
  self.state.buf.id = nil
end

-- =============================================================================
-- Private window methods
-- =============================================================================

---@private
---Open the preview window (window-only, no rendering)
---@return string|nil error Error message on failure, nil on success
function Preview:_win_open()
  if self.state.win.is_open then
    return nil
  end

  local store_config = package.loaded["store.config"]
  if not store_config then return "Cannot open preview window: store.config not loaded" end
  local plugin_config = store_config.get()

  local window_config = {
    width = self.config.width,
    height = self.config.height,
    row = self.config.row,
    col = self.config.col,
    focusable = true,
    zindex = plugin_config.zindex.base,
    title = tabs.build_title(tabs.build_right_tabs(self.state.doc_paths, self.state.doc_index), self.state.win.active_tab or "readme"),
    title_pos = "left",
  }

  local window_opts = {
    conceallevel = 3, -- Required for markview to hide markdown syntax
    concealcursor = "nvc", -- Hide concealed text in normal, visual, command modes
    wrap = false, -- Disable text wrapping for markdown content
    cursorline = false,
    list = true,
    listchars = "space: ,eol: ",
  }

  local win_id, error_message = utils.create_floating_window({
    buf_id = self.state.buf.id,
    config = window_config,
    opts = window_opts,
  })
  if error_message then
    return "Cannot open preview window: " .. error_message
  end

  self.state.win.id = win_id
  self.state.win.is_open = true
  return nil
end

---@private
---Close the preview window (window-only, no buffer cleanup)
---@return string|nil error Error message on failure, nil on success
function Preview:_win_close()
  if not self.state.win.is_open then
    return nil
  end

  -- Clear markview strict_render before closing
  local markview_ok, markview = pcall(require, "markview")
  if markview_ok and markview.strict_render then
    markview.strict_render:clear(self.state.buf.id)
  end

  -- Close window
  if self.state.win.id and vim.api.nvim_win_is_valid(self.state.win.id) then
    local success, err = pcall(vim.api.nvim_win_close, self.state.win.id, true)
    if not success then
      return "Failed to close preview window: " .. tostring(err)
    end
  end

  self.state.win.id = nil
  self.state.win.is_open = false
  return nil
end

-- =============================================================================
-- Private cursor methods
-- =============================================================================

---Save current cursor position for the current README
---@private
---@return nil
function Preview:_save_cursor_position()
  if not self.state.current_readme_id or not self.state.win.id then
    return
  end
  if not self.state.win.is_open or not vim.api.nvim_win_is_valid(self.state.win.id) then
    return
  end

  local readme_id = self.state.current_readme_id
  local win_id = self.state.win.id
  vim.schedule(function()
    pcall(function()
      local cursor = vim.api.nvim_win_get_cursor(win_id)
      self.state.cursor_positions[readme_id] = { cursor[1], cursor[2] }
    end)
  end)
end

---Restore cursor position for a specific README
---@private
---@param readme_id string README identifier
---@return nil
function Preview:_restore_cursor_position(readme_id)
  if not readme_id or not self.state.win.id or not vim.api.nvim_win_is_valid(self.state.win.id) then
    return
  end

  local saved_position = self.state.cursor_positions[readme_id]
  if saved_position then
    -- Validate that the saved position is within bounds
    local line_count = vim.api.nvim_buf_line_count(self.state.buf.id)
    local line = math.min(saved_position[1], line_count)
    local col = saved_position[2]

    vim.api.nvim_win_set_cursor(self.state.win.id, { line, col })
  else
    -- First time viewing this README, set cursor to top
    vim.api.nvim_win_set_cursor(self.state.win.id, { 1, 0 })
  end
end

-- =============================================================================
-- Private render helpers
-- =============================================================================

---Clear any image.nvim images tied to the preview buffer (no-op if image.nvim absent)
---@private
function Preview:_clear_images()
  local ok, image_api = pcall(require, "image")
  if ok and image_api.get_images then
    local images = image_api.get_images({ buffer = self.state.buf.id })
    for _, img in ipairs(images) do
      img:clear()
    end
  end
end

---Render images manually via image.nvim API (bypasses auto-attach for full control)
---@private
---@param content_lines string[] Buffer content lines to scan for image URLs
---@param readme_id string|nil Plugin identifier to detect stale callbacks
function Preview:_render_images(content_lines, readme_id)
  local ok, image_api = pcall(require, "image")
  if not ok or not image_api.from_url then
    logger.debug("image.nvim not available, skipping image rendering")
    return
  end

  -- Track which plugin these images belong to
  self._image_render_for = readme_id

  local win_id = self.state.win.id
  local buf_id = self.state.buf.id
  local max_images = 5

  -- Collect image entries first
  local entries = {}
  for i, line in ipairs(content_lines) do
    for url in line:gmatch("!%[.-%]%((.-)%)") do
      if #entries >= max_images then break end
      if url:match("^https?://") then
        table.insert(entries, { url = url, line = i })
      end
    end
    if #entries >= max_images then break end
  end

  local is_tab_mode = require("store.config").get().layout_mode == "tab"

  if is_tab_mode then
    -- Tab mode (normal splits): parallel — screenpos handles virtual line offsets
    for _, entry in ipairs(entries) do
      local render_ok, render_err = pcall(image_api.from_url, entry.url, {
        window = win_id,
        buffer = buf_id,
        with_virtual_padding = true,
        namespace = "store",
      }, function(image)
        if self._image_render_for ~= readme_id then return end
        if image and vim.api.nvim_win_is_valid(win_id) then
          image:render({ x = 0, y = entry.line - 1 })
        end
      end)
      if not render_ok then
        logger.debug("image.nvim from_url failed for " .. entry.url .. ": " .. tostring(render_err))
      end
    end
  else
    -- Modal mode (floating windows): sequential — image.nvim's re-render cascade
    -- needs each image placed before the next to compute correct positions
    local function render_next(idx)
      if idx > #entries then return end
      if self._image_render_for ~= readme_id then return end
      if not vim.api.nvim_win_is_valid(win_id) then return end
      local entry = entries[idx]
      local render_ok, render_err = pcall(image_api.from_url, entry.url, {
        window = win_id,
        buffer = buf_id,
        with_virtual_padding = true,
        namespace = "store",
      }, function(image)
        if self._image_render_for ~= readme_id then return end
        if image and vim.api.nvim_win_is_valid(win_id) then
          image:render({ x = 0, y = entry.line - 1 })
        end
        render_next(idx + 1)
      end)
      if not render_ok then
        logger.debug("image.nvim from_url failed for " .. entry.url .. ": " .. tostring(render_err))
        render_next(idx + 1)
      end
    end
    render_next(1)
  end
end

---Render loading state
---@private
function Preview:_render_loading()
  local content_lines = { "Loading preview..." }
  self:_clear_images()
  utils.set_lines(self.state.buf.id, content_lines)
end

---Render error state
---@private
---@param state PreviewState Preview state containing error content
function Preview:_render_error(state)
  local content_lines = state.content or { "Error occurred while loading content" }
  self:_clear_images()
  utils.set_lines(self.state.buf.id, content_lines)
end

---Render ready state with content
---@private
---@param state PreviewState Preview state containing ready content
function Preview:_render_ready(state)
  local content_lines = state.content or { "No content available" }
  self:_clear_images()
  utils.set_lines(self.state.buf.id, content_lines)

  -- Use strict_render for preview-only scenarios (recommended by markview author)
  local markview_ok, markview = pcall(require, "markview")
  if markview_ok and markview.strict_render then
    markview.strict_render:clear(self.state.buf.id) -- Clear any previous render
    markview.strict_render:render(self.state.buf.id)
  end

  -- Debounce image rendering so fast navigation stays snappy
  if self._image_debounce_timer then
    vim.fn.timer_stop(self._image_debounce_timer)
  end
  self._image_debounce_timer = vim.fn.timer_start(50, function()
    self._image_debounce_timer = nil
    self:_render_images(content_lines, state.readme_id)
  end)

  -- Update current README ID and restore cursor position (window-guarded)
  self.state.current_readme_id = state.readme_id
  if state.readme_id and self.state.win.is_open and self.state.win.id and vim.api.nvim_win_is_valid(self.state.win.id) then
    self:_restore_cursor_position(state.readme_id)
  end
end

-- =============================================================================
-- Public methods
-- =============================================================================

---Open the preview window with default content
---@return string|nil error Error message on failure, nil on success
function Preview:open()
  if self.state.win.is_open then
    logger.warn("Preview window: open() called when window is already open")
    return nil
  end

  local win_err = self:_win_open()
  if win_err then
    return win_err
  end

  -- markview strict_render after window creation (needs window for proper attachment)
  local markview_ok, markview = pcall(require, "markview")
  if markview_ok and markview.strict_render then
    markview.strict_render:render(self.state.buf.id)
  end

  -- Set default content
  return self:render({ state = "loading" })
end

---Render content in the preview window based on state
---@param state PreviewStateUpdate Preview state to render
---@return string|nil error Error message on failure, nil on success
function Preview:render(state)
  if type(state) ~= "table" then
    return "Preview: Cannot render - state must be a table, got: " .. type(state)
  end
  if not self.state.buf.id or not vim.api.nvim_buf_is_valid(self.state.buf.id) then
    return "Preview: Cannot render - invalid buffer"
  end

  -- Save cursor position (WINDOW op, guarded)
  if self.state.win.is_open and self.state.win.id and vim.api.nvim_win_is_valid(self.state.win.id) then
    self:_save_cursor_position()
  end

  -- Create new state locally by merging current state with update
  local new_state = vim.tbl_deep_extend("force", self.state, state)

  -- Validate the merged state before applying it
  local validation_error = validations.validate_state(new_state)
  if validation_error then
    return "Preview: Invalid state update - " .. validation_error
  end

  -- Only assign to self.state if validation passes
  self.state = new_state

  self:_buf_render()
  return nil
end

---Close the preview window
---@return string|nil error Error message on failure, nil on success
function Preview:close()
  if not self.state.win.is_open then
    logger.warn("Preview window: close() called when window is not open")
    return nil
  end

  local win_err = self:_win_close()
  if win_err then
    return win_err
  end

  self:_buf_destroy()
  return nil
end

---Focus the preview window and restore cursor position
---@return string|nil error Error message on failure, nil on success
function Preview:focus()
  if not self.state.win.is_open then
    return "Preview window: Cannot focus - window not open"
  end
  if not self.state.win.id or not vim.api.nvim_win_is_valid(self.state.win.id) then
    return "Preview window: Cannot focus - invalid window"
  end

  vim.api.nvim_set_current_win(self.state.win.id)

  -- Restore cursor position for current README if available
  if self.state.current_readme_id then
    self:_restore_cursor_position(self.state.current_readme_id)
  end

  return nil
end

---Save cursor position when losing focus (called externally)
---@return nil
function Preview:save_cursor_on_blur()
  if self.state.win.is_open and self.state.win.id and vim.api.nvim_win_is_valid(self.state.win.id) then
    self:_save_cursor_position()
  end
end

---Switch the active tab (readme or docs) in the preview pane
---@param tab_id string "readme" or "docs"
function Preview:set_active_tab(tab_id)
  if not self.state.win.is_open or not self.state.win.id or not vim.api.nvim_win_is_valid(self.state.win.id) then
    return
  end

  -- Save cursor for current tab
  if self.state.win.active_tab == "readme" then
    self:_save_cursor_position()
  elseif self.state.win.active_tab == "docs" and self.state.current_docs_id then
    pcall(function()
      local cursor = vim.api.nvim_win_get_cursor(self.state.win.id)
      self.state.docs_cursor_positions[self.state.current_docs_id] = { cursor[1], cursor[2] }
    end)
  end

  self.state.win.active_tab = tab_id

  -- Swap buffer (suppress BufWinEnter to prevent image.nvim flicker on tab switch)
  local target_buf = tab_id == "docs" and self.state.buf.docs_id or self.state.buf.id
  local ei = vim.o.eventignore
  vim.o.eventignore = "BufWinEnter"
  vim.api.nvim_win_set_buf(self.state.win.id, target_buf)
  vim.o.eventignore = ei

  -- Update title (works for floating windows; silently fails for splits)
  local right_tabs = tabs.build_right_tabs(self.state.doc_paths, self.state.doc_index)
  pcall(vim.api.nvim_win_set_config, self.state.win.id, {
    title = tabs.build_title(right_tabs, tab_id),
    title_pos = "left",
  })

  -- Notify external listeners (e.g., layout provider for winbar updates)
  if self.config.on_tab_change then
    self.config.on_tab_change(tab_id, right_tabs)
  end

  -- Update window options per tab
  if tab_id == "readme" then
    if vim.api.nvim_get_option_value("conceallevel", { win = self.state.win.id }) ~= 3 then
      vim.api.nvim_set_option_value("conceallevel", 3, { win = self.state.win.id })
    end
    if vim.api.nvim_get_option_value("concealcursor", { win = self.state.win.id }) ~= "nvc" then
      vim.api.nvim_set_option_value("concealcursor", "nvc", { win = self.state.win.id })
    end
    -- Restore cursor for readme
    if self.state.current_readme_id then
      self:_restore_cursor_position(self.state.current_readme_id)
    end
  else
    if vim.api.nvim_get_option_value("conceallevel", { win = self.state.win.id }) ~= 0 then
      vim.api.nvim_set_option_value("conceallevel", 0, { win = self.state.win.id })
    end
    if vim.api.nvim_get_option_value("concealcursor", { win = self.state.win.id }) ~= "" then
      vim.api.nvim_set_option_value("concealcursor", "", { win = self.state.win.id })
    end
    -- Restore cursor for docs
    if self.state.current_docs_id then
      local saved = self.state.docs_cursor_positions[self.state.current_docs_id]
      if saved then
        local line_count = vim.api.nvim_buf_line_count(self.state.buf.docs_id)
        pcall(vim.api.nvim_win_set_cursor, self.state.win.id, { math.min(saved[1], line_count), saved[2] })
      else
        pcall(vim.api.nvim_win_set_cursor, self.state.win.id, { 1, 0 })
      end
    end
  end
end

---Render docs content into the docs buffer
---@param state table {state: string, content: string[]|nil, docs_id: string|nil}
function Preview:render_docs(state)
  vim.schedule(function()
    if not self.state.buf.docs_id or not vim.api.nvim_buf_is_valid(self.state.buf.docs_id) then
      return
    end
    if state.state == "error" then
      local lines = state.content or { "Error loading documentation" }
      utils.set_lines(self.state.buf.docs_id, lines)
    elseif state.state == "ready" then
      local lines = state.content or { "No documentation available" }
      utils.set_lines(self.state.buf.docs_id, lines)
    else
      utils.set_lines(self.state.buf.docs_id, { "Loading documentation..." })
    end

    if state.docs_id then
      self.state.current_docs_id = state.docs_id
      -- Restore cursor for docs (window-guarded)
      if self.state.win.is_open and self.state.win.id and vim.api.nvim_win_is_valid(self.state.win.id) and self.state.win.active_tab == "docs" then
        local saved = self.state.docs_cursor_positions[state.docs_id]
        if saved then
          local line_count = vim.api.nvim_buf_line_count(self.state.buf.docs_id)
          pcall(vim.api.nvim_win_set_cursor, self.state.win.id, { math.min(saved[1], line_count), saved[2] })
        else
          pcall(vim.api.nvim_win_set_cursor, self.state.win.id, { 1, 0 })
        end
      end
    end
  end)
end

---Update the doc tab label after cycling (without switching tabs)
function Preview:update_doc_label()
  if not self.state.win.is_open or not self.state.win.id or not vim.api.nvim_win_is_valid(self.state.win.id) then
    return
  end
  local right_tabs = tabs.build_right_tabs(self.state.doc_paths, self.state.doc_index)
  -- Update floating window title (modal mode -- silently fails for splits)
  pcall(vim.api.nvim_win_set_config, self.state.win.id, {
    title = tabs.build_title(right_tabs, self.state.win.active_tab),
    title_pos = "left",
  })
  -- Notify layout provider (tab mode winbar)
  if self.config.on_tab_change then
    self.config.on_tab_change(self.state.win.active_tab, right_tabs)
  end
end

---Get the currently active tab
---@return string "readme" or "docs"
function Preview:get_active_tab()
  return self.state.win.active_tab
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

  if not self.state.win.is_open or not self.state.win.id or not vim.api.nvim_win_is_valid(self.state.win.id) then
    return "Cannot resize preview window: window not open or invalid"
  end

  -- Save current scroll position and cursor state
  local cursor_pos = vim.api.nvim_win_get_cursor(self.state.win.id)
  local topline = vim.fn.line("w0", self.state.win.id)
  local current_readme_id = self.state.current_readme_id

  local win_config = {
    relative = "editor",
    row = layout_config.row,
    col = layout_config.col,
    width = layout_config.width,
    height = layout_config.height,
    title = tabs.build_title(tabs.build_right_tabs(self.state.doc_paths, self.state.doc_index), self.state.win.active_tab or "readme"),
    title_pos = "left",
  }

  local success, err = pcall(vim.api.nvim_win_set_config, self.state.win.id, win_config)
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

  -- Re-render via _buf_render (avoids unnecessary state merge)
  if self.state.content then
    vim.schedule(function()
      if self.state.win.id and vim.api.nvim_win_is_valid(self.state.win.id) then
        -- Restore scroll position first
        pcall(vim.api.nvim_win_call, self.state.win.id, function()
          vim.cmd("normal! " .. topline .. "Gzt")
        end)
        -- Then restore cursor position
        pcall(vim.api.nvim_win_set_cursor, self.state.win.id, cursor_pos)
      end
    end)
  end

  return nil
end

---Get the window ID of the preview component
---@return number|nil window_id Window ID if open, nil otherwise
function Preview:get_window_id()
  if self.state.win.is_open and self.state.win.id and vim.api.nvim_win_is_valid(self.state.win.id) then
    return self.state.win.id
  end
  return nil
end

---Check if the preview component is in a valid state
---@return boolean is_valid True if component is valid and ready for use
function Preview:is_valid()
  return self.state.buf.id ~= nil
    and vim.api.nvim_buf_is_valid(self.state.buf.id)
    and (not self.state.win.is_open or (self.state.win.id and vim.api.nvim_win_is_valid(self.state.win.id)))
end

return M
