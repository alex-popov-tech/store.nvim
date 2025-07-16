local validators = require("store.validators")
local utils = require("store.utils")
local logger = require("store.logger")

local M = {}

---@class Repository
---@field author string Repository author/owner
---@field name string Repository name
---@field full_name string Repository full name (author/name)
---@field description string Repository description
---@field homepage string Repository homepage URL
---@field html_url string Repository GitHub URL
---@field tags string[] Array of topic tags
---@field stargazers_count number Raw star count for sorting
---@field pushed_at number Unix timestamp of last push for sorting
---@field pretty_stargazers_count string Formatted number of stars
---@field pretty_forks_count string Formatted number of forks
---@field pretty_open_issues_count string Formatted number of open issues
---@field pretty_pushed_at string Formatted last push time

---@class ListState
---@field state string current component state - "loading", "ready", "error"
---@field items Repository[] List of repositories

---@class ListWindowConfig
---@field width number Window width
---@field height number Window height
---@field row number Window row position
---@field col number Window column position
---@field border string Window border style
---@field zindex number Window z-index
---@field on_repo fun(repository: Repository) Callback when cursor moves over repository
---@field keymap table<string, function> Table of keybinding to callback mappings
---@field cursor_debounce_delay number Debounce delay for cursor movement in milliseconds
---@field max_lengths { full_name: number, pretty_stargazers_count: number, pretty_forks_count: number, pretty_open_issues_count: number, pretty_pushed_at: number } Maximum field lengths for table formatting
---@field list_fields string[] List of fields to display in order

---@class ListWindow
---@field config ListWindowConfig Window configuration
---@field win_id number|nil Window ID
---@field buf_id number|nil Buffer ID
---@field is_open boolean Window open status
---@field content_lines string[] Current content lines
---@field repositories Repository[] Repository data indexed by line number
---@field cursor_autocmd_id number|nil Cursor movement autocmd ID
---@field cursor_debounce_timer number|nil Cursor movement debounce timer

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
  max_lengths = {
    full_name = 35,
    pretty_stargazers_count = 8,
    pretty_forks_count = 8,
    pretty_open_issues_count = 8,
    pretty_pushed_at = 27, -- 13 chars for "Last updated " + 14 chars for data (fallback)
  },
  list_fields = { "full_name", "stars", "forks", "issues", "tags" }, -- Default field configuration
}

local DEFAULT_STATE = { state = "loading", items = {} }

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
    local width_err = validators.should_be_number(config.width, "list.width must be a number")
    if width_err then
      return width_err
    end
  end

  if config.height ~= nil then
    local height_err = validators.should_be_number(config.height, "list.height must be a number")
    if height_err then
      return height_err
    end
  end

  if config.row ~= nil then
    local row_err = validators.should_be_number(config.row, "list.row must be a number")
    if row_err then
      return row_err
    end
  end

  if config.col ~= nil then
    local col_err = validators.should_be_number(config.col, "list.col must be a number")
    if col_err then
      return col_err
    end
  end

  if config.border ~= nil then
    local border_err = validators.should_be_string(config.border, "list.border must be a string")
    if border_err then
      return border_err
    end
  end

  if config.zindex ~= nil then
    local zindex_err = validators.should_be_number(config.zindex, "list.zindex must be a number")
    if zindex_err then
      return zindex_err
    end
  end

  if config.on_repo ~= nil then
    local callback_err = validators.should_be_function(config.on_repo, "list.on_repo must be a function")
    if callback_err then
      return callback_err
    end
  end

  if config.keymap ~= nil then
    local keymap_err = validators.should_be_table(config.keymap, "list.keymap must be a table")
    if keymap_err then
      return keymap_err
    end
  end

  if config.cursor_debounce_delay ~= nil then
    local debounce_err =
      validators.should_be_number(config.cursor_debounce_delay, "list.cursor_debounce_delay must be a number")
    if debounce_err then
      return debounce_err
    end
  end

  if config.list_fields ~= nil then
    local list_fields_err = validators.should_be_table(config.list_fields, "list.list_fields must be an array")
    if list_fields_err then
      return list_fields_err
    end
  end

  return nil
end

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
      nowait = true,
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
    logger.error("List window: Cannot setup cursor callbacks - on_repo callback not provided")
    return
  end

  if not self.win_id then
    logger.error("List window: Cannot setup cursor callbacks - win_id is nil")
    return
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
  -- Graceful error handling instead of crashing
  if not self.is_open then
    logger.warn("List window: Cannot render - window not open")
    return
  end
  vim.schedule(function()
    if not self.buf_id or not vim.api.nvim_buf_is_valid(self.buf_id) then
      logger.warn("List window: Cannot render - invalid buffer")
      return
    end
    if not state or type(state) ~= "table" then
      logger.warn("List window: Cannot render - invalid state")
      return
    end
    if not state.items or type(state.items) ~= "table" then
      logger.warn("List window: Cannot render - invalid items")
      -- Provide fallback behavior
      state = vim.tbl_deep_extend("force", state, { items = {} })
    end

    if state.state == "loading" then
      vim.api.nvim_set_option_value("modifiable", true, { buf = self.buf_id })
      vim.api.nvim_buf_set_lines(self.buf_id, 0, -1, false, { "Loading plugins..." })
      vim.api.nvim_set_option_value("modifiable", false, { buf = self.buf_id })
      return
    end

    if state.state == "error" then
      vim.api.nvim_set_option_value("modifiable", true, { buf = self.buf_id })
      vim.api.nvim_buf_set_lines(self.buf_id, 0, -1, false, {})
      vim.api.nvim_set_option_value("modifiable", false, { buf = self.buf_id })
      return
    end

    -- Store repository data and create content lines
    self.repositories = {}
    local content_lines = {}

    -- Field renderer mapping
    local field_renderers = {
      full_name = function(repo)
        return repo.full_name
      end,
      stars = function(repo)
        return "⭐" .. repo.pretty_stargazers_count
      end,
      forks = function(repo)
        return "🍴" .. repo.pretty_forks_count
      end,
      issues = function(repo)
        return "🐛" .. repo.pretty_open_issues_count
      end,
      pushed_at = function(repo)
        local pushed_at = repo.pretty_pushed_at or "Unknown"
        return "Last updated " .. pushed_at
      end,
    }

    -- Max length mapping (with emoji prefix adjustments)
    local max_length_map = {
      full_name = self.config.max_lengths.full_name,
      stars = self.config.max_lengths.pretty_stargazers_count + 2, -- +2 for ⭐
      forks = self.config.max_lengths.pretty_forks_count + 2, -- +2 for 🍴
      issues = self.config.max_lengths.pretty_open_issues_count + 2, -- +2 for 🐛
      pushed_at = self.config.max_lengths.pretty_pushed_at,
    }

    for i, repo in ipairs(state.items) do
      self.repositories[i] = repo

      local columns = {}
      local append_content = ""

      -- Process fields in configured order
      for _, field in ipairs(self.config.list_fields) do
        if field == "tags" then
          -- Handle tags separately (append after main content)
          if repo.tags and #repo.tags > 0 then
            local tag_parts = {}
            for _, tag in ipairs(repo.tags) do
              table.insert(tag_parts, tag)
            end
            append_content = " " .. table.concat(tag_parts, ", ")
          end
        else
          -- Handle table fields
          local renderer = field_renderers[field]
          if renderer then
            local content = renderer(repo)
            local max_length = max_length_map[field] or 20 -- Fallback length
            table.insert(columns, { content, max_length })
          else
            -- Unknown field, skip with warning
            logger.warn("Unknown field in list_fields: " .. field)
          end
        end
      end

      local main_content = utils.format_table_line(columns)
      local final_line = main_content .. append_content

      table.insert(content_lines, final_line)
    end

    vim.api.nvim_set_option_value("modifiable", true, { buf = self.buf_id })
    vim.api.nvim_buf_set_lines(self.buf_id, 0, -1, false, content_lines)
    vim.api.nvim_set_option_value("modifiable", false, { buf = self.buf_id })

    -- Position cursor at first line if window is valid
    if self.win_id and vim.api.nvim_win_is_valid(self.win_id) and #content_lines > 0 then
      vim.api.nvim_win_set_cursor(self.win_id, { 1, 0 })

      -- Trigger initial callback if we have repository data for first line
      if self.config.on_repo and self.repositories[1] then
        self.config.on_repo(self.repositories[1])
      end
    end
  end)
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
