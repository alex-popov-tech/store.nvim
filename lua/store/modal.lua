local Modal = {}
Modal.__index = Modal

function Modal:new(options, config)
  local current_config = config

  if not current_config then
    current_config = {
      modal = { width = 50, height = 20, border = "rounded", zindex = 50 },
    }
  end

  local modal_config = current_config.modal
  local default_options = {
    width = modal_config.width,
    height = modal_config.height,
    border = modal_config.border,
    zindex = modal_config.zindex,
    content = {},
    keybindings = {},
    on_close = nil,
    on_init = nil,
    on_win_leave = nil,
    on_keypress = nil,
    auto_close = true,
    row = nil,
    col = nil,
    filter_query = "",
  }

  local instance = {
    win_id = nil,
    buf_id = nil,
    header_win_id = nil,
    header_buf_id = nil,
    options = vim.tbl_deep_extend("force", default_options, options or {}),
    is_open = false,
    config = current_config,
    header_line_count = 0,
    preview_debounce_timer = nil,
    preview_debounce_delay = 150,
    markview_enabled = false,
    cursor_move_autocmd = nil,
  }

  setmetatable(instance, self)
  return instance
end

function Modal:_calculate_size()
  -- Use custom dimensions if provided, otherwise use config
  if self.options.width and self.options.height then
    return self.options.width, self.options.height
  end
  -- Use the already calculated dimensions from config
  return self.config.modal.width, self.config.modal.height
end

function Modal:_calculate_position(width, height)
  -- Use custom position if provided
  if self.options.row and self.options.col then
    return self.options.row, self.options.col
  end
  -- Calculate centered position for custom dimensions
  if self.options.width and self.options.height then
    local screen_width = vim.o.columns
    local screen_height = vim.o.lines
    local row = math.floor((screen_height - height) / 2)
    local col = math.floor((screen_width - width) / 2)
    return row, col
  end
  -- Use the already calculated position from config
  return self.config.modal.row, self.config.modal.col
end

function Modal:_create_buffer()
  local buf_id = vim.api.nvim_create_buf(false, true)

  -- Set buffer options
  local buf_opts = {
    modifiable = false,
    swapfile = false,
    buftype = "nofile",
    bufhidden = "wipe",
    buflisted = false,
    filetype = "store_modal",
    undolevels = -1,
  }

  for option, value in pairs(buf_opts) do
    vim.api.nvim_buf_set_option(buf_id, option, value)
  end

  return buf_id
end

function Modal:_set_content(content)
  if not self.buf_id then
    return
  end

  -- Make buffer modifiable temporarily
  vim.api.nvim_buf_set_option(self.buf_id, "modifiable", true)

  -- Handle both structured {header, body} and simple array content
  local lines_to_set
  if type(content) == "table" and content.header and content.body then
    -- Structured content with header and body - set header and body separately
    self:_set_header_content(content.header)
    lines_to_set = content.body
    self.header_line_count = #content.header
  else
    -- Simple array content (backward compatibility)
    lines_to_set = content
    self.header_line_count = 0
  end

  -- Set the main content (body only now)
  vim.api.nvim_buf_set_lines(self.buf_id, 0, -1, false, lines_to_set)

  -- Make buffer read-only again
  vim.api.nvim_buf_set_option(self.buf_id, "modifiable", false)
end

function Modal:_setup_keybindings()
  if not self.buf_id then
    return
  end

  local config_keybindings = self.config.keybindings or { close = "q", close_alt = "<Esc>" }
  local default_keybindings = {
    [config_keybindings.close] = function(config, modal)
      modal:close()
    end,
    [config_keybindings.close_alt] = function(config, modal)
      modal:close()
    end,
  }

  -- Add tab switching keybinding if in preview mode
  if self.preview_mode then
    default_keybindings["<Tab>"] = function(config, modal)
      modal:_switch_window_focus()
    end
  end

  local all_keybindings = vim.tbl_extend("force", default_keybindings, self.options.keybindings)

  for key, action in pairs(all_keybindings) do
    if type(action) == "function" then
      vim.keymap.set("n", key, function()
        if self.options.on_keypress and type(self.options.on_keypress) == "function" then
          self.options.on_keypress()
        end
        action(self.config, self)
      end, { buffer = self.buf_id, silent = true, desc = "Modal action for " .. key })
    end
  end

  -- Set up tab keybinding on preview buffer as well
  if self.preview_mode and self.preview_buf_id then
    vim.keymap.set("n", "<Tab>", function()
      if self.options.on_keypress and type(self.options.on_keypress) == "function" then
        self.options.on_keypress()
      end
      self:_switch_window_focus()
    end, { buffer = self.preview_buf_id, silent = true, desc = "Switch to main window" })

    -- Also add close keybindings to preview buffer
    vim.keymap.set("n", config_keybindings.close, function()
      self:close()
    end, { buffer = self.preview_buf_id, silent = true, desc = "Close modal" })

    vim.keymap.set("n", config_keybindings.close_alt, function()
      self:close()
    end, { buffer = self.preview_buf_id, silent = true, desc = "Close modal" })
  end

  -- Set up keybindings on header buffer as well
  if self.header_buf_id then
    vim.keymap.set("n", config_keybindings.close, function()
      self:close()
    end, { buffer = self.header_buf_id, silent = true, desc = "Close modal" })

    vim.keymap.set("n", config_keybindings.close_alt, function()
      self:close()
    end, { buffer = self.header_buf_id, silent = true, desc = "Close modal" })

    -- Add tab switching from header to main window
    if self.preview_mode then
      vim.keymap.set("n", "<Tab>", function()
        if self.options.on_keypress and type(self.options.on_keypress) == "function" then
          self.options.on_keypress()
        end
        self:_switch_window_focus()
      end, { buffer = self.header_buf_id, silent = true, desc = "Switch to main window" })
    end
  end
end

function Modal:_setup_auto_close()
  if not self.options.auto_close or not self.buf_id then
    return
  end

  self._auto_close_autocmd = vim.api.nvim_create_autocmd("WinLeave", {
    buffer = self.buf_id,
    callback = function()
      -- Don't close if switching to preview window (in preview mode)
      if self.preview_mode then
        vim.schedule(function()
          local current_win = vim.api.nvim_get_current_win()
          if current_win == self.preview_win_id or current_win == self.win_id or current_win == self.header_win_id then
            -- Still within modal windows, don't close
            return
          end
          -- Left modal completely, close it
          if self.options.on_win_leave and type(self.options.on_win_leave) == "function" then
            self.options.on_win_leave(self)
          else
            self:close()
          end
        end)
      else
        -- Not in preview mode, use original behavior
        if self.options.on_win_leave and type(self.options.on_win_leave) == "function" then
          self.options.on_win_leave(self)
        else
          self:close()
        end
      end
    end,
    desc = "Auto-close modal on window leave",
  })
end

function Modal:_setup_preview_auto_close()
  if not self.options.auto_close or not self.preview_buf_id then
    return
  end

  self._preview_auto_close_autocmd = vim.api.nvim_create_autocmd("WinLeave", {
    buffer = self.preview_buf_id,
    callback = function()
      -- Don't close if switching to main window (in preview mode)
      vim.schedule(function()
        local current_win = vim.api.nvim_get_current_win()
        if current_win == self.preview_win_id or current_win == self.win_id or current_win == self.header_win_id then
          -- Still within modal windows, don't close
          return
        end
        -- Left modal completely, close it
        if self.options.on_win_leave and type(self.options.on_win_leave) == "function" then
          self.options.on_win_leave(self)
        else
          self:close()
        end
      end)
    end,
    desc = "Auto-close modal on preview window leave",
  })
end

function Modal:_setup_header_auto_close()
  if not self.options.auto_close or not self.header_buf_id then
    return
  end

  self._header_auto_close_autocmd = vim.api.nvim_create_autocmd("WinLeave", {
    buffer = self.header_buf_id,
    callback = function()
      -- Don't close if switching to other modal windows
      vim.schedule(function()
        local current_win = vim.api.nvim_get_current_win()
        if current_win == self.preview_win_id or current_win == self.win_id or current_win == self.header_win_id then
          -- Still within modal windows, don't close
          return
        end
        -- Left modal completely, close it
        if self.options.on_win_leave and type(self.options.on_win_leave) == "function" then
          self.options.on_win_leave(self)
        else
          self:close()
        end
      end)
    end,
    desc = "Auto-close modal on header window leave",
  })
end

function Modal:_setup_cursor_preview_autocmd()
  if not self.preview_mode or not self.buf_id then
    return
  end

  self.cursor_move_autocmd = vim.api.nvim_create_autocmd("CursorMoved", {
    buffer = self.buf_id,
    callback = function()
      self:_handle_cursor_move()
    end,
    desc = "Update preview on cursor movement",
  })
end

function Modal:_handle_cursor_move()
  if not self.preview_mode or not self.win_id or not vim.api.nvim_win_is_valid(self.win_id) then
    return
  end

  local cursor = vim.api.nvim_win_get_cursor(self.win_id)
  local line_num = cursor[1]

  -- No need to skip header lines since they're in a separate window now
  -- Get current line content
  local lines = vim.api.nvim_buf_get_lines(self.buf_id, line_num - 1, line_num, false)
  if #lines == 0 then
    self:update_preview_debounced({ "Put cursor on repository to see its preview" })
    return
  end

  local line = lines[1]
  local github_url = line:match("(https://github%.com/[^%s]+)")

  if github_url and self.options.on_cursor_move then
    -- Call external handler if provided (for module.lua integration)
    self.options.on_cursor_move(self, github_url)
  elseif not github_url then
    -- Show static text when no GitHub URL found
    self:update_preview_debounced({ "Put cursor on repository to see its preview" })
  end
end

function Modal:open(content)
  -- Redirect to preview mode since that's now the only mode
  return self:open_with_preview(content or self.options.content or {}, { "Select a plugin to preview" })
end

function Modal:update_content(content)
  if not self.is_open then
    return
  end

  -- Use vim.schedule to avoid fast event context issues
  vim.schedule(function()
    self:_set_content(content)
  end)
end

function Modal:is_modal_open()
  return self.is_open
    and self.win_id
    and vim.api.nvim_win_is_valid(self.win_id)
    and self.buf_id
    and vim.api.nvim_buf_is_valid(self.buf_id)
end

function Modal:get_options()
  return vim.deepcopy(self.options)
end

function Modal:update_options(options)
  self.options = vim.tbl_deep_extend("force", self.options, options)
end

-- Filter management methods
function Modal:update_filter_query(query)
  self.options.filter_query = query or ""
end

function Modal:get_filter_query()
  return self.options.filter_query
end

function Modal:render(data)
  if not data then
    return self:open()
  end

  -- For now, if data is a table of strings, use it as content
  if type(data) == "table" and #data > 0 and type(data[1]) == "string" then
    return self:open_with_preview(data, { "Select a plugin to preview" })
  end

  -- Convert other data types to string representation
  local content = { vim.inspect(data) }
  return self:open_with_preview(content, { "Select a plugin to preview" })
end

-- Add method to get header line count for external use
function Modal:get_header_line_count()
  return self.header_line_count or 0
end

function Modal:_create_header_buffer()
  local buf_id = vim.api.nvim_create_buf(false, true)

  -- Set buffer options
  local buf_opts = {
    modifiable = false,
    swapfile = false,
    buftype = "nofile",
    bufhidden = "wipe",
    buflisted = false,
    filetype = "store_header",
    undolevels = -1,
  }

  for option, value in pairs(buf_opts) do
    vim.api.nvim_buf_set_option(buf_id, option, value)
  end

  return buf_id
end

function Modal:_set_header_content(header_lines)
  if not self.header_buf_id or not header_lines then
    return
  end

  vim.api.nvim_buf_set_option(self.header_buf_id, "modifiable", true)
  vim.api.nvim_buf_set_lines(self.header_buf_id, 0, -1, false, header_lines)
  vim.api.nvim_buf_set_option(self.header_buf_id, "modifiable", false)
end

-- Preview window management for 3-window mode
function Modal:open_with_preview(content, preview_content)
  if self.is_open then
    return false
  end

  -- Calculate dimensions for 3-window layout (ensure integers)
  local total_width = math.floor(vim.o.columns * 0.8)
  local total_height = math.floor(vim.o.lines * 0.8)
  local header_height = 5 -- Fixed height for header
  local gap_between_windows = 2 -- Padding between header and content windows
  local content_height = total_height - header_height - gap_between_windows
  local left_width = math.floor(total_width * 0.4) -- 40% for list
  local right_width = math.floor(total_width * 0.6) -- 60% for preview

  local start_row = math.floor((vim.o.lines - total_height) / 2)
  local start_col = math.floor((vim.o.columns - total_width) / 2)
  local header_row = start_row
  local content_row = start_row + header_height + gap_between_windows
  local left_col = start_col
  local right_col = start_col + left_width + 3 -- +3 for prettier gap

  -- Create header window (full width at top)
  self.header_buf_id = self:_create_header_buffer()
  local header_win_config = {
    relative = "editor",
    width = total_width,
    height = header_height,
    row = header_row,
    col = start_col,
    style = "minimal",
    border = self.options.border,
    zindex = self.options.zindex,
  }

  self.header_win_id = vim.api.nvim_open_win(self.header_buf_id, false, header_win_config)
  if not self.header_win_id then
    return false
  end

  -- Create main (left) window
  self.buf_id = self:_create_buffer()
  local left_win_config = {
    relative = "editor",
    width = left_width,
    height = content_height,
    row = content_row,
    col = left_col,
    style = "minimal",
    border = self.options.border,
    zindex = self.options.zindex,
  }

  self.win_id = vim.api.nvim_open_win(self.buf_id, true, left_win_config)
  if not self.win_id then
    vim.api.nvim_win_close(self.header_win_id, true)
    return false
  end

  -- Create preview (right) window
  self.preview_buf_id = vim.api.nvim_create_buf(false, true)
  local preview_buf_opts = {
    modifiable = false,
    swapfile = false,
    buftype = "",
    bufhidden = "wipe",
    buflisted = false,
    filetype = "markdown",
    undolevels = -1,
  }

  for option, value in pairs(preview_buf_opts) do
    vim.api.nvim_buf_set_option(self.preview_buf_id, option, value)
  end

  local right_win_config = {
    relative = "editor",
    width = right_width,
    height = content_height,
    row = content_row,
    col = right_col,
    style = "minimal",
    border = self.options.border,
    zindex = self.options.zindex,
  }

  self.preview_win_id = vim.api.nvim_open_win(self.preview_buf_id, false, right_win_config)
  if not self.preview_win_id then
    vim.api.nvim_win_close(self.header_win_id, true)
    vim.api.nvim_win_close(self.win_id, true)
    return false
  end

  -- Enable markview for the preview buffer if available
  self.markview_enabled = self:_setup_markview()

  -- Set window options for all three windows
  local win_opts = {
    cursorline = true,
    wrap = false,
    number = false,
    relativenumber = false,
    signcolumn = "no",
    foldcolumn = "0",
    colorcolumn = "",
  }

  -- Header window options (no cursor line)
  local header_win_opts = vim.tbl_extend("force", win_opts, {
    cursorline = false,
  })

  for option, value in pairs(header_win_opts) do
    vim.api.nvim_win_set_option(self.header_win_id, option, value)
  end

  -- Main window options
  for option, value in pairs(win_opts) do
    vim.api.nvim_win_set_option(self.win_id, option, value)
  end

  -- Set preview window options with markview-specific settings
  local preview_win_opts = vim.tbl_extend("force", win_opts, {
    conceallevel = 3, -- Required for markview to hide markdown syntax
    concealcursor = "nvc", -- Hide concealed text in normal, visual, command modes
    wrap = true, -- Enable text wrapping for markdown content
  })

  for option, value in pairs(preview_win_opts) do
    vim.api.nvim_win_set_option(self.preview_win_id, option, value)
  end

  -- Set content for both windows
  local modal_content = content or self.options.content or {}
  self:_set_content(modal_content)
  self:_set_preview_content(preview_content or { "Select an item to preview" })

  self:_setup_auto_close()
  self:_setup_preview_auto_close()
  self:_setup_header_auto_close()

  self.is_open = true
  self.preview_mode = true
  self:_setup_keybindings()
  self:_setup_cursor_preview_autocmd()

  if self.options.on_init and type(self.options.on_init) == "function" then
    self.options.on_init(self)
  end

  return true
end

function Modal:_set_preview_content(content)
  if not self.preview_buf_id then
    return
  end

  vim.api.nvim_buf_set_option(self.preview_buf_id, "modifiable", true)

  local lines_to_set = content
  if type(content) ~= "table" then
    lines_to_set = { tostring(content) }
  end

  vim.api.nvim_buf_set_lines(self.preview_buf_id, 0, -1, false, lines_to_set)
  vim.api.nvim_buf_set_option(self.preview_buf_id, "modifiable", false)

  -- Trigger markview rendering if available
  if self.markview_enabled then
    vim.schedule(function()
      local markview_ok, markview = pcall(require, "markview")
      if markview_ok and markview.render then
        markview.render(self.preview_buf_id, { enable = true, hybrid_mode = false }, nil)
      end
    end)
  end
end

function Modal:_switch_window_focus()
  if not self.preview_mode or not self.win_id or not self.preview_win_id then
    return
  end

  -- Check which window is currently focused and switch between main and preview
  -- (Header window is not focusable in normal workflow)
  local current_win = vim.api.nvim_get_current_win()

  if current_win == self.win_id then
    -- Currently in main window, switch to preview
    if vim.api.nvim_win_is_valid(self.preview_win_id) then
      vim.api.nvim_set_current_win(self.preview_win_id)
    end
  elseif current_win == self.preview_win_id then
    -- Currently in preview window, switch to main
    if vim.api.nvim_win_is_valid(self.win_id) then
      vim.api.nvim_set_current_win(self.win_id)
    end
  elseif current_win == self.header_win_id then
    -- If somehow in header window, switch to main
    if vim.api.nvim_win_is_valid(self.win_id) then
      vim.api.nvim_set_current_win(self.win_id)
    end
  end
end

function Modal:update_preview(content)
  if not self.preview_mode or not self.preview_buf_id then
    return
  end

  vim.schedule(function()
    self:_set_preview_content(content)
  end)
end

function Modal:close()
  if not self.is_open then
    return false
  end

  if self._auto_close_autocmd then
    vim.api.nvim_del_autocmd(self._auto_close_autocmd)
    self._auto_close_autocmd = nil
  end

  if self._preview_auto_close_autocmd then
    vim.api.nvim_del_autocmd(self._preview_auto_close_autocmd)
    self._preview_auto_close_autocmd = nil
  end

  if self._header_auto_close_autocmd then
    vim.api.nvim_del_autocmd(self._header_auto_close_autocmd)
    self._header_auto_close_autocmd = nil
  end

  if self.options.on_close and type(self.options.on_close) == "function" then
    self.options.on_close(self.config, self)
  end

  -- Cleanup markview if enabled
  if self.markview_enabled and self.preview_buf_id then
    local markview_ok, markview = pcall(require, "markview")
    if markview_ok and markview.actions then
      markview.actions.detach(self.preview_buf_id)
    end
  end

  -- Cancel debounce timer
  if self.preview_debounce_timer then
    vim.fn.timer_stop(self.preview_debounce_timer)
    self.preview_debounce_timer = nil
  end

  -- Cleanup cursor move autocmd
  if self.cursor_move_autocmd then
    vim.api.nvim_del_autocmd(self.cursor_move_autocmd)
    self.cursor_move_autocmd = nil
  end

  -- Close all three windows if in preview mode
  if self.preview_mode and self.preview_win_id and vim.api.nvim_win_is_valid(self.preview_win_id) then
    vim.api.nvim_win_close(self.preview_win_id, true)
  end

  if self.win_id and vim.api.nvim_win_is_valid(self.win_id) then
    vim.api.nvim_win_close(self.win_id, true)
  end

  if self.header_win_id and vim.api.nvim_win_is_valid(self.header_win_id) then
    vim.api.nvim_win_close(self.header_win_id, true)
  end

  self.win_id = nil
  self.buf_id = nil
  self.header_win_id = nil
  self.header_buf_id = nil
  self.preview_win_id = nil
  self.preview_buf_id = nil
  self.is_open = false
  self.preview_mode = false
  self.markview_enabled = false

  return true
end

-- Setup markview for preview buffer
function Modal:_setup_markview()
  local markview_ok, markview = pcall(require, "markview")
  if not markview_ok then
    return false
  end

  local success, err = pcall(function()
    markview.actions.attach(self.preview_buf_id)
    markview.actions.enable(self.preview_buf_id)
  end)

  if not success then
    return false
  end

  return true
end

-- Debounced preview update to prevent excessive re-rendering
function Modal:update_preview_debounced(content)
  if not self.preview_mode or not self.preview_buf_id then
    return
  end

  -- Capture content in local variable to avoid closure issues
  local content_to_set = content

  -- Cancel existing timer
  if self.preview_debounce_timer then
    vim.fn.timer_stop(self.preview_debounce_timer)
    self.preview_debounce_timer = nil
  end

  -- Set new timer
  self.preview_debounce_timer = vim.fn.timer_start(self.preview_debounce_delay, function()
    self.preview_debounce_timer = nil
    vim.schedule(function()
      self:_set_preview_content(content_to_set)
    end)
  end)
end

return Modal
