local validators = require("store.validators")
local logger = require("store.logger")
local utils = require("store.utils")

---Pad or truncate a string to a fixed length with ellipsis
---@param text string String to process
---@param expected_length number Maximum length of the result
---@return string Fixed-length string, either padded with spaces or truncated with ellipsis
local function pad_or_truncate(text, expected_length)
  if type(text) ~= "string" then
    logger.error("pad_or_truncate: expected string, got " .. type(text))
    text = tostring(text or "")
  end

  if expected_length <= 0 then
    return ""
  end

  local char_count = vim.fn.strchars(text)

  if char_count == expected_length then
    return text
  end

  if char_count < expected_length then
    local spaces_needed = expected_length - char_count
    return text .. string.rep(" ", spaces_needed)
  end

  -- char_count > max_length, truncate and add ellipsis
  if expected_length == 1 then
    return "…"
  end

  local truncated = vim.fn.strcharpart(text, 0, expected_length - 1)
  return truncated .. "…"
end

---Format a list of string-length pairs into a table-like line with consistent column widths
---@param pairs table[] List of {string, number} pairs where string is content and number is column width
---@return string Formatted line with space-separated columns of fixed widths
local function format_table_line(pairs)
  if type(pairs) ~= "table" then
    logger.error("format_table_line: expected table, got " .. type(pairs))
    return ""
  end

  if #pairs == 0 then
    return ""
  end

  local columns = {}

  for i, pair in ipairs(pairs) do
    if type(pair) ~= "table" or #pair ~= 2 then
      logger.error("format_table_line: pair " .. i .. " is not a valid {string, number} pair")
      table.insert(columns, "")
    else
      local str, length = pair[1], pair[2]
      local formatted = pad_or_truncate(str, length)
      table.insert(columns, formatted)
    end
  end

  return table.concat(columns, " ")
end

local M = {}

---@class ListState
---@field win_id number|nil Window ID
---@field buf_id number|nil Buffer ID
---@field is_open boolean Window open status
---@field state string current component state - "loading", "ready", "error"
---@field items Repository[] List of repositories
---@field cursor_autocmd_id number|nil Cursor movement autocmd ID
---@field cursor_debounce_timer number|nil Cursor movement debounce timer
---@field full_name_to_rendering_line_cache {[string]: string} Cache of full name to rendering line

---@class ListStateUpdate
---@field state string
---@field items Repository[]|nil?

---@class ListConfig
---@field width number Window width
---@field height number Window height
---@field row number Window row position
---@field col number Window column position
---@field on_repo fun(repository: Repository) Callback when cursor moves over repository
---@field keymaps_applier fun(buf_id: number) Function to apply keymaps to buffer
---@field cursor_debounce_delay number Debounce delay for cursor movement in milliseconds
---@field max_lengths { full_name: number, pretty_stargazers_count: number, pretty_forks_count: number, pretty_open_issues_count: number, pretty_pushed_at: number } Maximum field lengths for table formatting
---@field list_fields string[] List of fields to display in order

---@class List
---@field config ListConfig Window configuration
---@field state ListState Component state
---@field open fun(self: List): string|nil
---@field close fun(self: List): string|nil
---@field render fun(self: List, state: ListStateUpdate): string|nil
---@field focus fun(self: List): string|nil
---@field resize fun(self: List, layout_config: {width: number, height: number, row: number, col: number}): string|nil
---@field get_window_id fun(self: List): number|nil
---@field is_valid fun(self: List): boolean
---@field update_config fun(self: List, config_updates: table): string|nil

local DEFAULT_CONFIG = {
  on_repo = function()
    vim.notify("store.nvim: on_repo callback not configured", vim.log.levels.WARN)
  end,
  keymaps_applier = function(buf_id)
    vim.notify("store.nvim: keymaps for list window not configured", vim.log.levels.WARN)
  end,
  max_lengths = {
    pretty_stargazers_count = 8,
    pretty_forks_count = 8,
    pretty_open_issues_count = 8,
    pretty_pushed_at = 27,
  },
}

local DEFAULT_STATE = {
  -- Window state
  win_id = nil,
  buf_id = nil,
  is_open = false,

  -- UI state
  state = "loading",
  items = {},

  -- Operational state
  cursor_autocmd_id = nil,
  cursor_debounce_timer = nil,
  -- Performance cache
  full_name_to_rendering_line_cache = {}, -- full_name => rendered_line map for O(1) access
}

---Validate list window configuration
---@param config ListConfig List window configuration to validate
---@return string|nil error_message Error message if validation fails, nil if valid
local function validate_config(config)
  local err = validators.should_be_table(config, "list window config must be a table")
  if err then
    return err
  end

  local width_err = validators.should_be_number(config.width, "list.width must be a number")
  if width_err then
    return width_err
  end

  local height_err = validators.should_be_number(config.height, "list.height must be a number")
  if height_err then
    return height_err
  end

  local row_err = validators.should_be_number(config.row, "list.row must be a number")
  if row_err then
    return row_err
  end

  local col_err = validators.should_be_number(config.col, "list.col must be a number")
  if col_err then
    return col_err
  end

  local callback_err = validators.should_be_function(config.on_repo, "list.on_repo must be a function")
  if callback_err then
    return callback_err
  end

  local keymaps_err = validators.should_be_function(config.keymaps_applier, "list.keymaps_applier must be a function")
  if keymaps_err then
    return keymaps_err
  end

  local debounce_err =
    validators.should_be_number(config.cursor_debounce_delay, "list.cursor_debounce_delay must be a number")
  if debounce_err then
    return debounce_err
  end

  local list_fields_err = validators.should_be_table(config.list_fields, "list.list_fields must be an array")
  if list_fields_err then
    return list_fields_err
  end

  return nil
end

---Validate list state for consistency and safety
---@param state ListStateUpdate List state to validate
---@return string|nil error_message Error message if validation fails, nil if valid
local function validate_state(state)
  local err = validators.should_be_table(state, "list state must be a table")
  if err then
    return err
  end

  -- Validate state field
  if state.state ~= nil then
    local state_err = validators.should_be_string(state.state, "list.state must be a string")
    if state_err then
      return state_err
    end

    local valid_states = { loading = true, ready = true, error = true }
    if not valid_states[state.state] then
      return "list.state must be one of 'loading', 'ready', 'error', got: " .. state.state
    end
  end

  -- Validate items field
  if state.items ~= nil then
    if type(state.items) ~= "table" then
      return "list.items must be nil or an array of repositories, got: " .. type(state.items)
    end

    for i, item in ipairs(state.items) do
      if type(item) ~= "table" then
        return "list.items[" .. i .. "] must be a repository table, got: " .. type(item)
      end
    end
  end

  -- Validate window state fields if present
  if state.win_id ~= nil then
    local win_err = validators.should_be_number(state.win_id, "list.win_id must be nil or a number")
    if win_err then
      return win_err
    end
  end

  if state.buf_id ~= nil then
    local buf_err = validators.should_be_number(state.buf_id, "list.buf_id must be nil or a number")
    if buf_err then
      return buf_err
    end
  end

  if state.is_open ~= nil then
    if type(state.is_open) ~= "boolean" then
      return "list.is_open must be nil or a boolean, got: " .. type(state.is_open)
    end
  end

  -- Validate operational state fields if present

  -- Validate cursor state fields if present
  if state.cursor_autocmd_id ~= nil then
    local autocmd_err =
      validators.should_be_number(state.cursor_autocmd_id, "list.cursor_autocmd_id must be nil or a number")
    if autocmd_err then
      return autocmd_err
    end
  end

  if state.cursor_debounce_timer ~= nil then
    local timer_err =
      validators.should_be_number(state.cursor_debounce_timer, "list.cursor_debounce_timer must be nil or a number")
    if timer_err then
      return timer_err
    end
  end

  return nil
end

local List = {}
List.__index = List

---Create a new list window instance
---@param list_config ListConfig|nil List window configuration
---@return List|nil instance List instance on success, nil on error
---@return string|nil error Error message on failure, nil on success
function M.new(list_config)
  -- Merge with defaults first
  local config = vim.tbl_deep_extend("force", DEFAULT_CONFIG, list_config or {})

  -- Validate merged configuration
  local error_msg = validate_config(config)
  if error_msg then
    return nil, "List window configuration validation failed: " .. error_msg
  end

  local instance = {
    config = config,
    state = vim.tbl_deep_extend("force", DEFAULT_STATE, {
      buf_id = utils.create_scratch_buffer(),
    }),
  }

  setmetatable(instance, List)

  -- Apply keymaps to buffer
  config.keymaps_applier(instance.state.buf_id)

  return instance, nil
end

---Open the list window with default content
---@return string|nil error Error message on failure, nil on success
function List:open()
  if self.state.is_open then
    logger.warn("List window: open() called when window is already open")
    return nil
  end

  local window_config = {
    width = self.config.width,
    height = self.config.height,
    row = self.config.row,
    col = self.config.col,
    focusable = true,
  }

  -- Window options optimized for list display
  local window_opts = {
    cursorline = true,
    number = false,
    relativenumber = false,
    signcolumn = "no",
    foldcolumn = "0",
    colorcolumn = "",
    wrap = false,
    linebreak = false,
    sidescrolloff = 0,
  }

  local win_id, error_message = utils.create_floating_window({
    buf_id = self.state.buf_id,
    config = window_config,
    opts = window_opts,
  })
  if error_message then
    return "Cannot open list window: " .. error_message
  end

  self.state.win_id = win_id
  self.state.is_open = true

  -- Setup cursor movement callback if provided
  if self.config.on_repo then
    self:_setup_cursor_callbacks()
  end

  -- Set default content
  return self:render({ state = "loading" })
end

---Setup cursor movement callbacks with debouncing
---@return nil
function List:_setup_cursor_callbacks()
  if not self.config.on_repo then
    logger.error("List window: Cannot setup cursor callbacks - on_repo callback not provided")
    return
  end

  if not self.state.win_id then
    logger.error("List window: Cannot setup cursor callbacks - win_id is nil")
    return
  end

  -- Create autocommand for cursor movement (only CursorMoved, no insert mode)
  self.state.cursor_autocmd_id = vim.api.nvim_create_autocmd({ "CursorMoved" }, {
    buffer = self.state.buf_id,
    callback = function()
      if not self.state.win_id or not vim.api.nvim_win_is_valid(self.state.win_id) then
        return
      end

      -- Cancel existing timer
      if self.state.cursor_debounce_timer then
        vim.fn.timer_stop(self.state.cursor_debounce_timer)
        self.state.cursor_debounce_timer = nil
      end

      -- Set new timer with debounce delay
      self.state.cursor_debounce_timer = vim.fn.timer_start(self.config.cursor_debounce_delay, function()
        self.state.cursor_debounce_timer = nil
        if not self.state.win_id or not vim.api.nvim_win_is_valid(self.state.win_id) then
          return
        end

        local cursor = vim.api.nvim_win_get_cursor(self.state.win_id)
        local line_num = cursor[1]

        -- Get repository data for current line
        local repo_data = self.state.items[line_num]
        if repo_data then
          self.config.on_repo(repo_data)
        end
      end)
    end,
  })
end

---Render content for the list window
---@param state ListStateUpdate List state to render
---@return string|nil error Error message on failure, nil on success
function List:render(state)
  if type(state) ~= "table" then
    return "List window: Cannot render - state must be a table, got: " .. type(state)
  end
  if not self.state.is_open then
    return "List window: Cannot render - window not open"
  end
  if not self.state.buf_id then
    return "List window: Cannot render - invalid buffer"
  end

  -- Create new state locally by merging current state with update
  local new_state = vim.tbl_deep_extend("force", self.state, state)

  -- Validate the merged state before applying it
  local validation_error = validate_state(state)
  if validation_error then
    return "List window: Invalid state update - " .. validation_error
  end

  -- Only assign to self.state if validation passes
  self.state = new_state

  -- Only schedule the final rendering dispatch using safe self.state
  vim.schedule(function()
    if self.state.state == "loading" then
      self:_render_loading()
    elseif self.state.state == "error" then
      self:_render_error()
    else
      self:_render_ready(self.state)
    end
  end)

  return nil
end

---Focus the list window
---@return string|nil error Error message on failure, nil on success
function List:focus()
  if not self.state.is_open then
    return "List window: Cannot focus - window not open"
  end
  if not self.state.win_id or not vim.api.nvim_win_is_valid(self.state.win_id) then
    return "List window: Cannot focus - invalid window"
  end

  vim.api.nvim_set_current_win(self.state.win_id)
  return nil
end

---Resize the list window to new layout dimensions
---@param layout_config {width: number, height: number, row: number, col: number} New layout configuration
---@return string|nil error Error message if resize failed, nil if successful
function List:resize(layout_config)
  if not self.state.is_open or not self.state.win_id or not vim.api.nvim_win_is_valid(self.state.win_id) then
    return "Cannot resize list window: window not open or invalid"
  end

  local success, err = pcall(vim.api.nvim_win_set_config, self.state.win_id, {
    relative = "editor",
    width = layout_config.width,
    height = layout_config.height,
    row = layout_config.row,
    col = layout_config.col,
    style = "minimal",
    border = "rounded",
    zindex = 50,
  })

  if not success then
    return "Failed to resize list window: " .. (err or "unknown error")
  end

  -- Update internal config
  self.config.width = layout_config.width
  self.config.height = layout_config.height
  self.config.row = layout_config.row
  self.config.col = layout_config.col

  return nil
end

---Close the list window
---@return string|nil error Error message on failure, nil on success
function List:close()
  if not self.state.is_open then
    logger.warn("List window: close() called when window is not open")
    return nil
  end

  -- Clean up cursor autocmd
  if self.state.cursor_autocmd_id then
    vim.api.nvim_del_autocmd(self.state.cursor_autocmd_id)
    self.state.cursor_autocmd_id = nil
  end

  -- Cancel debounce timer
  if self.state.cursor_debounce_timer then
    vim.fn.timer_stop(self.state.cursor_debounce_timer)
    self.state.cursor_debounce_timer = nil
  end

  -- Close window
  if self.state.win_id and vim.api.nvim_win_is_valid(self.state.win_id) then
    local success, err = pcall(vim.api.nvim_win_close, self.state.win_id, true)
    if not success then
      return "Failed to close list window: " .. tostring(err)
    end
  end

  -- Reset window state (keep buffer and data)
  self.state.win_id = nil
  self.state.is_open = false

  return nil
end

---Render loading state
---@private
function List:_render_loading()
  local content_lines = { "Loading plugins..." }
  utils.set_lines(self.state.buf_id, content_lines)
end

---Render error state
---@private
function List:_render_error()
  local content_lines = { "Error occurred while loading plugins" }
  utils.set_lines(self.state.buf_id, content_lines)
end

---Calculate formatted display line for a repository
---@private
---@param repo Repository Repository to format
---@return string formatted_line Complete formatted line with padding and content
function List:_calculate_display_line(repo)
  -- Field renderer mapping
  local field_renderers = {
    full_name = function(r)
      return r.full_name
    end,
    stars = function(r)
      return "⭐" .. r.pretty_stargazers_count
    end,
    forks = function(r)
      return "🍴" .. r.pretty_forks_count
    end,
    issues = function(r)
      return "🐛" .. r.pretty_open_issues_count
    end,
    pushed_at = function(r)
      local pushed_at = r.pretty_pushed_at or "Unknown"
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

  local main_content = format_table_line(columns)
  return main_content .. append_content
end

---Clear the display line cache
---@private
function List:_clear_cache()
  self.state.full_name_to_rendering_line_cache = {}
end

---Render ready state with repository list
---@private
---@param state ListState List state containing repository data
function List:_render_ready(state)
  -- Create content lines
  local content_lines = {}

  for i, repo in ipairs(state.items or {}) do
    -- Check cache first for O(1) access
    local cached_line = self.state.full_name_to_rendering_line_cache[repo.full_name]
    if cached_line then
      table.insert(content_lines, cached_line)
    else
      -- Cache miss - calculate and cache the line
      local formatted_line = self:_calculate_display_line(repo)
      self.state.full_name_to_rendering_line_cache[repo.full_name] = formatted_line
      table.insert(content_lines, formatted_line)
    end
  end

  utils.set_lines(self.state.buf_id, content_lines)

  -- Position cursor at first line if window is valid
  if self.state.win_id and vim.api.nvim_win_is_valid(self.state.win_id) and #content_lines > 0 then
    vim.api.nvim_win_set_cursor(self.state.win_id, { 1, 0 })

    -- Trigger initial callback if we have repository data for first line
    if self.config.on_repo and self.state.items[1] then
      self.config.on_repo(self.state.items[1])
    end
  end
end

---Get the window ID of the list component
---@return number|nil window_id Window ID if open, nil otherwise
function List:get_window_id()
  if self.state.is_open and self.state.win_id and vim.api.nvim_win_is_valid(self.state.win_id) then
    return self.state.win_id
  end
  return nil
end

---Check if the list component is in a valid state
---@return boolean is_valid True if component is valid and ready for use
function List:is_valid()
  return self.state.buf_id ~= nil
    and vim.api.nvim_buf_is_valid(self.state.buf_id)
    and (not self.state.is_open or (self.state.win_id and vim.api.nvim_win_is_valid(self.state.win_id)))
end

---Update component configuration safely
---@param config_updates table Configuration updates to apply
---@return string|nil error Error message if update failed, nil if successful
function List:update_config(config_updates)
  if type(config_updates) ~= "table" then
    return "List: config_updates must be a table, got: " .. type(config_updates)
  end

  -- Apply updates to config
  self.config = vim.tbl_deep_extend("force", self.config, config_updates)

  return nil
end

return M
