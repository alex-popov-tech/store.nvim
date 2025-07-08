local validators = require("store.validators")
local utils = require("store.utils")

local M = {}

---@class Repository
---@field full_name string Repository full name (owner/repo)
---@field description string Repository description
---@field homepage string Repository homepage URL
---@field html_url string Repository GitHub URL
---@field stargazers_count number Number of stars
---@field watchers_count number Number of watchers
---@field fork_count number Number of forks
---@field updated_at string Last updated timestamp
---@field topics string[] Array of topic tags

---@class ListState
---@field state string current component state - "loading", "ready"
---@field repositories Repository[] List of repositories

---@class ListWindowConfig
---@field width number Window width
---@field height number Window height
---@field row number Window row position
---@field col number Window column position
---@field border string Window border style
---@field zindex number Window z-index
---@field on_repo fun(repository: Repository, line_number?: number) Callback when cursor moves over repository
---@field keymap table<string, function> Table of keybinding to callback mappings
---@field cursor_debounce_delay number Debounce delay for cursor movement in milliseconds

---@class ListWindow
---@field config ListWindowConfig Window configuration
---@field win_id number|nil Window ID
---@field buf_id number|nil Buffer ID
---@field is_open boolean Window open status
---@field content_lines string[] Current content lines
---@field repositories Repository[] Repository data indexed by line number
---@field cursor_autocmd_id number|nil Cursor movement autocmd ID
---@field cursor_debounce_timer number|nil Cursor movement debounce timer

-- Default list window configuration
---@type ListWindowConfig
local DEFAULT_CONFIG = {
  width = 40,
  height = 20,
  row = 0,
  col = 0,
  border = "rounded",
  zindex = 50,
  on_repo = function() end, -- Callback function when cursor moves over repository
  keymap = {}, -- Table of lhs-callback pairs for buffer-scoped keybindings
  cursor_debounce_delay = 200, -- Debounce delay for cursor movement in milliseconds
}

---@type ListState
local DEFAULT_STATE = { state = "loading", repositories = {} }

-- Validate list window configuration
---@param config ListWindowConfig|nil
---@return string|nil Error message if validation fails
local function validate(config)
  if config == nil then
    return nil
  end

  local err = validators.should_be_table(config, "list window config must be a table")
  if err then
    return err
  end

  if config.width ~= nil then
    local width_err = validators.should_be_number(config.width, "list_window.width must be a number")
    if width_err then
      return width_err
    end
  end

  if config.height ~= nil then
    local height_err = validators.should_be_number(config.height, "list_window.height must be a number")
    if height_err then
      return height_err
    end
  end

  if config.row ~= nil then
    local row_err = validators.should_be_number(config.row, "list_window.row must be a number")
    if row_err then
      return row_err
    end
  end

  if config.col ~= nil then
    local col_err = validators.should_be_number(config.col, "list_window.col must be a number")
    if col_err then
      return col_err
    end
  end

  if config.border ~= nil then
    local border_err = validators.should_be_string(config.border, "list_window.border must be a string")
    if border_err then
      return border_err
    end
  end

  if config.zindex ~= nil then
    local zindex_err = validators.should_be_number(config.zindex, "list_window.zindex must be a number")
    if zindex_err then
      return zindex_err
    end
  end

  if config.on_repo ~= nil then
    local callback_err = validators.should_be_function(config.on_repo, "list_window.on_repo must be a function")
    if callback_err then
      return callback_err
    end
  end

  if config.keymap ~= nil then
    local keymap_err = validators.should_be_table(config.keymap, "list_window.keymap must be a table")
    if keymap_err then
      return keymap_err
    end
  end

  if config.cursor_debounce_delay ~= nil then
    local debounce_err =
      validators.should_be_number(config.cursor_debounce_delay, "list_window.cursor_debounce_delay must be a number")
    if debounce_err then
      return debounce_err
    end
  end

  return nil
end

-- ListWindow class
local ListWindow = {}
ListWindow.__index = ListWindow

---Create a new list window instance
---@param list_config ListWindowConfig|nil List window configuration
---@return ListWindow ListWindow instance
function M.new(list_config)
  -- Validate configuration first
  local error_msg = validate(list_config)
  if error_msg then
    error("List window configuration validation failed: " .. error_msg)
  end

  -- Merge with defaults
  local config = vim.tbl_deep_extend("force", DEFAULT_CONFIG, list_config or {})

  local instance = {
    config = config,
    win_id = nil,
    buf_id = nil,
    is_open = false,
    content_lines = {},
    repositories = {}, -- Store repository data for cursor callbacks
    cursor_autocmd_id = nil,
    cursor_debounce_timer = nil,
  }

  setmetatable(instance, ListWindow)

  -- Create hidden buffer immediately
  instance.buf_id = instance:_create_buffer()

  return instance
end

---Create list buffer with proper options
---@return number Buffer ID
function ListWindow:_create_buffer()
  local buf_id = vim.api.nvim_create_buf(false, true)

  local buf_opts = {
    modifiable = false,
    swapfile = false,
    buftype = "nofile",
    bufhidden = "wipe",
    buflisted = false,
    filetype = "text",
    undolevels = -1,
  }

  for option, value in pairs(buf_opts) do
    vim.api.nvim_set_option_value(option, value, { buf = buf_id })
  end

  -- Set buffer-scoped keymaps
  for lhs, callback in pairs(self.config.keymap) do
    vim.keymap.set("n", lhs, callback, {
      buffer = buf_id,
      silent = true,
      desc = "Store.nvim list window: " .. lhs,
    })
  end

  return buf_id
end

---Open the list window with default content
---@return boolean Success status
function ListWindow:open()
  if self.is_open then
    return false
  end

  -- Buffer already created in constructor

  local win_config = {
    relative = "editor",
    width = self.config.width,
    height = self.config.height,
    row = self.config.row,
    col = self.config.col,
    style = "minimal",
    border = self.config.border,
    zindex = self.config.zindex,
    focusable = true,
  }

  self.win_id = vim.api.nvim_open_win(self.buf_id, false, win_config)
  if not self.win_id then
    return false
  end

  -- Set window options optimized for list display
  local win_opts = {
    cursorline = true,
    number = false,
    relativenumber = false,
    signcolumn = "no",
    foldcolumn = "0",
    colorcolumn = "",
    wrap = false,
    linebreak = false,
    sidescrolloff = 0, -- Disable side scroll offset for precise width calculations
  }

  for option, value in pairs(win_opts) do
    vim.api.nvim_set_option_value(option, value, { win = self.win_id })
  end

  self.is_open = true

  -- Setup cursor movement callback if provided
  if self.config.on_repo then
    self:_setup_cursor_callbacks()
  end

  -- Set default content
  self:render(DEFAULT_STATE)

  return true
end

---Create floating window for list (internal method)
---@return boolean Success status
function ListWindow:_create_window()
  if self.is_open then
    return false
  end
end

---Setup cursor movement callbacks with debouncing
---@return nil
function ListWindow:_setup_cursor_callbacks()
  if not self.config.on_repo then
    error("on_repo callback must be provided")
  end

  if not self.win_id then
    error("win_id is nil - cannot setup cursor callbacks")
  end

  -- Create autocommand for cursor movement (only CursorMoved, no insert mode)
  self.cursor_autocmd_id = vim.api.nvim_create_autocmd({ "CursorMoved" }, {
    buffer = self.buf_id,
    callback = function()
      if not self.win_id or not vim.api.nvim_win_is_valid(self.win_id) then
        return
      end

      -- Cancel existing timer
      if self.cursor_debounce_timer then
        vim.fn.timer_stop(self.cursor_debounce_timer)
        self.cursor_debounce_timer = nil
      end

      -- Set new timer with debounce delay
      self.cursor_debounce_timer = vim.fn.timer_start(self.config.cursor_debounce_delay, function()
        self.cursor_debounce_timer = nil
        vim.schedule(function()
          if not self.win_id or not vim.api.nvim_win_is_valid(self.win_id) then
            return
          end

          local cursor = vim.api.nvim_win_get_cursor(self.win_id)
          local line_num = cursor[1]

          -- Get repository data for current line
          local repo_data = self.repositories[line_num]
          if repo_data then
            self.config.on_repo(repo_data)
          end
        end)
      end)
    end,
  })
end

---Render content for the list window
---@param state ListState List state to render
---@return nil
function ListWindow:render(state)
  if not self.is_open then
    error("Window must be opened before rendering content")
  end
  if not self.buf_id or not vim.api.nvim_buf_is_valid(self.buf_id) then
    error("buf_id is nil or invalid")
  end
  if not state or type(state) ~= "table" then
    error("state must be a table")
  end
  if not state.repositories or type(state.repositories) ~= "table" then
    error("state.repositories must be a table")
  end

  if state.state == "loading" then
    vim.api.nvim_set_option_value("modifiable", true, { buf = self.buf_id })
    vim.api.nvim_buf_set_lines(self.buf_id, 0, -1, false, { "Loading plugins..." })
    vim.api.nvim_set_option_value("modifiable", false, { buf = self.buf_id })
    return
  end

  -- Store repository data and create content lines
  self.repositories = {}
  local content_lines = {}

  for i, repo in ipairs(state.repositories) do
    self.repositories[i] = repo

    -- Create metadata string with consistent structure
    local metadata_parts = {}

    -- Always show stars (or 0 if missing)
    local stars = repo.stargazers_count or 0
    table.insert(metadata_parts, "⭐" .. stars)

    -- Always show forks (or 0 if missing)
    local forks = repo.fork_count or 0
    table.insert(metadata_parts, "🍴" .. forks)

    -- Always show watchers (or 0 if missing)
    local watchers = repo.watchers_count or 0
    table.insert(metadata_parts, "👀" .. watchers)

    local metadata = table.concat(metadata_parts, " ")
    local full_name = repo.full_name or repo.html_url

    -- Format line with full_name on left and metadata on right
    -- Account for border width (2 characters for rounded borders)
    local content_width = self.config.width - 2
    local formatted_line = utils.format_line_priority_right(content_width, full_name, metadata)
    table.insert(content_lines, formatted_line)
  end

  vim.api.nvim_set_option_value("modifiable", true, { buf = self.buf_id })
  vim.api.nvim_buf_set_lines(self.buf_id, 0, -1, false, content_lines)
  vim.api.nvim_set_option_value("modifiable", false, { buf = self.buf_id })

  -- Position cursor at first line if window is valid
  if self.win_id and vim.api.nvim_win_is_valid(self.win_id) and #content_lines > 0 then
    vim.api.nvim_win_set_cursor(self.win_id, { 1, 0 })

    -- Trigger initial callback if we have repository data for first line
    if self.config.on_repo and self.repositories[1] then
      self.config.on_repo(self.repositories[1], 1)
    end
  end
end

---Check if list window is currently open
---@return boolean Window open status
function ListWindow:is_window_open()
  return self.is_open
    and self.win_id
    and vim.api.nvim_win_is_valid(self.win_id)
    and self.buf_id
    and vim.api.nvim_buf_is_valid(self.buf_id)
end

---Focus the list window
---@return boolean Success status
function ListWindow:focus()
  if not self:is_window_open() then
    return false
  end

  vim.api.nvim_set_current_win(self.win_id)
  return true
end

---Close the list window
---@return boolean Success status
function ListWindow:close()
  if not self.is_open then
    return false
  end

  -- Clean up cursor autocmd
  if self.cursor_autocmd_id then
    vim.api.nvim_del_autocmd(self.cursor_autocmd_id)
    self.cursor_autocmd_id = nil
  end

  -- Cancel debounce timer
  if self.cursor_debounce_timer then
    vim.fn.timer_stop(self.cursor_debounce_timer)
    self.cursor_debounce_timer = nil
  end

  -- Close window
  if self.win_id and vim.api.nvim_win_is_valid(self.win_id) then
    vim.api.nvim_win_close(self.win_id, true)
  end

  -- Reset window state (keep buffer and data)
  self.win_id = nil
  self.is_open = false
  self.repositories = {}

  return true
end

return M
