local store_config = require("store.config")
local validations = require("store.ui.list.validations")
local utils = require("store.utils")
local logger = require("store.logger").createLogger({ context = "list" })

local M = {}

local DEFAULT_CONFIG = {
  on_repo = function()
    vim.notify("store.nvim: on_repo callback not configured", vim.log.levels.WARN)
  end,
  keymaps_applier = function(buf_id)
    vim.notify("store.nvim: keymaps for list window not configured", vim.log.levels.WARN)
  end,
  cursor_debounce_delay = 150, -- ms delay for cursor movement debouncing
  repository_renderer = nil, -- Will be set from store config
}

local DEFAULT_STATE = {
  -- Window state
  win_id = nil,
  buf_id = nil,
  is_open = false,

  -- UI state
  state = "loading",
  items = {},
  installed_items = {},

  -- Selection state
  current_repository = nil,

  -- Operational state
  cursor_autocmd_id = nil,
  cursor_debounce_timer = nil,

  -- Performance cache
  -- map full_name => Repository
  full_dataset_cache = {}, -- Pre-formatted lines for full dataset
}

local function is_repo_installed(installed_items, repo)
  if not installed_items or not repo then
    return false
  end

  if installed_items[repo.name] == true then
    return true
  end

  if repo.full_name and installed_items[repo.full_name] == true then
    return true
  end

  return false
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
  local error_msg = validations.validate_config(config)
  if error_msg then
    return nil, "List window configuration validation failed: " .. error_msg
  end

  local instance = {
    config = config,
    state = vim.tbl_deep_extend("force", DEFAULT_STATE, {
      buf_id = utils.create_scratch_buffer({
        filetype = "markdown", -- Set to markdown for markview rendering
      }),
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

  local store_config = require("store.config")
  local plugin_config = store_config.get()

  local window_config = {
    width = self.config.width,
    height = self.config.height,
    row = self.config.row,
    col = self.config.col,
    focusable = true,
    zindex = plugin_config.zindex.base,
  }

  -- Window options optimized for list display with markview
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
    conceallevel = 3, -- Required for markview to hide markdown syntax
    concealcursor = "nvc", -- Hide concealed text in normal, visual, command modes
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

  -- Initialize markview for table rendering
  local markview_ok, markview = pcall(require, "markview")
  if markview_ok and markview.strict_render then
    markview.strict_render:render(self.state.buf_id)
  end

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
    logger.warn("List window: Cannot setup cursor callbacks - on_repo callback not provided")
    return
  end

  if not self.state.win_id then
    logger.warn("List window: Cannot setup cursor callbacks - win_id is nil")
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
          logger.debug("Cursor event ignored: invalid window")
          return
        end

        local cursor = vim.api.nvim_win_get_cursor(self.state.win_id)
        local line_num = cursor[1]
        logger.debug("Cursor moved to line " .. line_num)

        local repo_data = self.state.items[line_num]
        if repo_data then
          -- Only trigger callback if repository selection has changed
          local needs_callback = not self.state.current_repository
            or self.state.current_repository.full_name ~= repo_data.full_name

          if needs_callback then
            self.state.current_repository = repo_data
            logger.debug("Selected repository: " .. repo_data.full_name .. " triggering on_repo callback")
            self.config.on_repo(repo_data)
          else
            logger.debug("Repository selection unchanged: " .. repo_data.full_name)
          end
        else
          logger.debug("No repository data for line " .. line_num)
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
  local new_state = vim.tbl_extend("force", self.state, state)

  -- Validate the merged state before applying it
  local validation_error = validations.validate_state(state)
  if validation_error then
    return "List window: Invalid state update - " .. validation_error
  end

  -- Only assign to self.state if validation passes
  self.state = new_state

  local item_count = (state.items and #state.items) or 0
  logger.debug("Rendering list with " .. item_count .. " items, state: " .. (state.state or "unknown"))

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

---Resize the list window and preserve state
---@param layout_config {width: number, height: number, row: number, col: number} New layout configuration
---@return string|nil error Error message if resize failed, nil if successful
function List:resize(layout_config)
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
    return "Cannot resize list window: window not open or invalid"
  end

  -- Save current cursor position and scroll state
  local cursor_pos = vim.api.nvim_win_get_cursor(self.state.win_id)
  local topline = vim.fn.line("w0", self.state.win_id)

  local win_config = {
    relative = "editor",
    row = layout_config.row,
    col = layout_config.col,
    width = layout_config.width,
    height = layout_config.height,
  }

  local success, err = pcall(vim.api.nvim_win_set_config, self.state.win_id, win_config)
  if not success then
    return "Failed to resize list window: " .. (err or "unknown error")
  end

  -- Update config for future operations
  self.config.width = layout_config.width
  self.config.height = layout_config.height
  self.config.row = layout_config.row
  self.config.col = layout_config.col

  -- Clear cache since window width change may affect column alignment
  self:_clear_cache()

  -- Re-render content if we have items to ensure proper formatting with new width
  if self.state.items and #self.state.items > 0 then
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

---Calculate column widths for a set of repositories using repository renderer
---@private
---@param items Repository[] List of repositories to analyze
---@return number[] column_widths Array of maximum widths for each field position
function List:_calculate_column_widths(items)
  if not self.config.repository_renderer then
    return {}
  end

  local column_widths = {}

  -- Sample render for each repository to determine column widths
  for _, repo in ipairs(items) do
    local is_installed = is_repo_installed(self.state.installed_items, repo)
    local rendered_fields = self.config.repository_renderer(repo, is_installed)

    for field_index, field_data in ipairs(rendered_fields) do
      if field_data.content then
        local actual_width = vim.fn.strdisplaywidth(field_data.content)
        local max_width = math.min(actual_width, field_data.limit or actual_width)
        column_widths[field_index] = math.max(column_widths[field_index] or 0, max_width)
      end
    end
  end

  return column_widths
end

---Generate aligned line for a repository using repository renderer and column widths
---@private
---@param repo Repository Repository to format
---@param column_widths number[] Column widths for alignment (indexed by field position)
---@return string formatted_line Complete line with proper alignment
function List:_generate_aligned_line(repo, column_widths)
  if not self.config.repository_renderer then
    return ""
  end

  local is_installed = is_repo_installed(self.state.installed_items, repo)
  local rendered_fields = self.config.repository_renderer(repo, is_installed)
  local columns = {}

  for field_index, field_data in ipairs(rendered_fields) do
    local content = field_data.content or ""
    local target_width = column_widths[field_index] or 0
    local current_width = vim.fn.strdisplaywidth(content)

    -- Truncate content if it exceeds target width
    if current_width > target_width and target_width > 3 then
      content = string.sub(content, 1, target_width - 3) .. "..."
      current_width = target_width
    end

    -- Pad content to target width, but not the last one
    if field_index < #rendered_fields and current_width < target_width then
      content = content .. string.rep(" ", target_width - current_width)
    end

    table.insert(columns, content)
  end

  return " " .. table.concat(columns, " ")
end

---Clear all caches
---@private
function List:_clear_cache()
  self.state.full_dataset_cache = {}
  logger.debug("Cleared full dataset cache")
end

---Render ready state with repository list
---@private
---@param state ListState List state containing repository data
function List:_render_ready(state)
  local items = state.items

  local cache_size = vim.tbl_count(self.state.full_dataset_cache)
  local can_use_cache = cache_size > 0 and #items == cache_size

  local content_lines = {}
  if can_use_cache then
    -- Use cached lines
    for _, repo in ipairs(items) do
      local formatted_line = self.state.full_dataset_cache[repo.full_name]
      table.insert(content_lines, formatted_line)
    end
  else
    -- Calculate fresh and cache (first render builds cache, subsequent renders just calculate)
    local column_widths = self:_calculate_column_widths(items)
    for _, repo in ipairs(items) do
      local formatted_line = self:_generate_aligned_line(repo, column_widths)
      table.insert(content_lines, formatted_line)
      self.state.full_dataset_cache[repo.full_name] = formatted_line
    end
  end

  utils.set_lines(self.state.buf_id, content_lines)

  -- Render with markview for table formatting
  local markview_ok, markview = pcall(require, "markview")
  if markview_ok and markview.strict_render then
    markview.strict_render:render(self.state.buf_id)
  end

  -- Position cursor at first line if window is valid
  if self.state.win_id and vim.api.nvim_win_is_valid(self.state.win_id) and #content_lines > 0 then
    vim.api.nvim_win_set_cursor(self.state.win_id, { 1, 0 })

    -- Trigger initial callback only if repository selection has changed
    if self.config.on_repo and items[1] then
      local first_repo = items[1]
      local needs_callback = not self.state.current_repository
        or self.state.current_repository.full_name ~= first_repo.full_name

      if needs_callback then
        self.state.current_repository = first_repo
        logger.debug("Repository selection changed to: " .. first_repo.full_name)
        self.config.on_repo(first_repo)
      end
    end
  end
end

---Get the window ID of the list component
---@return number|nil window_id Window ID if open, nil otherwise
function List:get_window_id()
  if self.state.is_open then
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

---Get the currently selected repository
---@return Repository|nil repository Currently selected repository, nil if none selected
function List:get_current_repository()
  return self.state.current_repository
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

  -- Clear caches since configuration affects rendering
  self:_clear_cache()

  return nil
end

---Update installed items and invalidate cache
---@param installed_items table<string, boolean> Map of plugin names to installation status
function List:update_installed_items(installed_items)
  if type(installed_items) == "table" then
    self.state.installed_items = installed_items
    -- Clear caches since installation status affects emoji display
    self:_clear_cache()
  end
end

return M
