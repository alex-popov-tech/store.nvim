local database = require("store.database")
local cache = require("store.cache")
local validators = require("store.validators")
local utils = require("store.utils")
local heading = require("store.ui.heading")
local list = require("store.ui.list")
local preview = require("store.ui.preview")
local logger = require("store.logger")
local WindowManager = require("store.ui.window_manager")
local keymaps = require("store.keymaps")

local M = {}

-- Helper function for safe cleanup operations with consistent error handling
---@param operation fun() Operation to perform
---@param error_message string Error message to log if operation fails
---@return boolean success True if operation succeeded
local function safe_cleanup(operation, error_message)
  local success, err = pcall(operation)
  if not success then
    logger.warn(error_message .. ": " .. tostring(err))
  end
  return success
end

-- Validate modal configuration
---@param config StoreModalConfig|nil Modal configuration to validate
---@return string|nil error_message Error message if validation fails, nil if valid
local function validate(config)
  if config == nil then
    return nil
  end

  local err = validators.should_be_table(config, "modal config must be a table")
  if err then
    return err
  end

  if config.width ~= nil then
    local width_err = validators.should_be_number(config.width, "modal.width must be a number")
    if width_err then
      return width_err
    end
  end

  if config.height ~= nil then
    local height_err = validators.should_be_number(config.height, "modal.height must be a number")
    if height_err then
      return height_err
    end
  end

  if config.proportions ~= nil then
    local proportions_err = validators.should_be_table(config.proportions, "modal.proportions must be a table")
    if proportions_err then
      return proportions_err
    end

    if config.proportions.list ~= nil then
      local list_err = validators.should_be_number(config.proportions.list, "modal.proportions.list must be a number")
      if list_err then
        return list_err
      end
    end

    if config.proportions.preview ~= nil then
      local preview_err =
        validators.should_be_number(config.proportions.preview, "modal.proportions.preview must be a number")
      if preview_err then
        return preview_err
      end
    end

    -- Note: proportions validation is handled in config.lua
  end

  return nil
end

---@class StoreModalConfig : PluginConfig
---@field on_close? fun(): void Callback when modal is closed

---@class StoreModal
---@field config StoreModalConfig Complete computed configuration
---@field is_open boolean Modal open status
---@field state table Modal state (filter_query, repos, etc.)
---@field heading Heading Header component instance
---@field list ListWindow List component instance
---@field preview Preview Preview component instance
---@field open fun(): void Open the modal and render all components
---@field focus fun(): void Focus list component
---@field close fun(): boolean Close the modal and all components

-- StoreModal class - stateful orchestrator for UI components
local StoreModal = {}
StoreModal.__index = StoreModal

---Create a new modal instance
---@param config StoreModalConfig Complete computed configuration with on_close callback
---@return StoreModal|nil instance StoreModal instance on success, nil on error
---@return string|nil error Error message on failure, nil on success
function M.new(config)
  if not config then
    return nil, "Configuration required. StoreModal expects config from config.lua"
  end

  logger.debug("Creating new StoreModal instance")

  -- Validate configuration first
  local error_msg = validate(config)
  if error_msg then
    logger.error("Modal configuration validation failed: " .. error_msg)
    return nil, "Modal configuration validation failed: " .. error_msg
  end

  local instance = {
    config = config,
    is_open = false,
    state = {
      filter_query = "",
      sort_config = {
        type = "default", -- Current sort type
      },
      repos = {},
      filtered_repos = {},
      installable_count = 0, -- Total installable plugins from database meta
      current_installable_count = 0, -- Current filtered installable plugins count
      total_installed_count = 0, -- Total installed plugins from lock file (static)
      installed_items = {}, -- Lookup table of installed plugin names for O(1) checks
      current_focus = "list", -- Track current focused component: "list" or "preview"
      current_repository = nil, -- Track currently selected repository
      is_refreshing = false, -- Track refresh state to prevent concurrent refreshes
      focus_augroup = nil, -- Autocmd group for focus detection
    },
  }

  -- Create UI component instances first
  local heading_instance, heading_error = heading.new({
    width = config.layout.header.width,
    height = config.layout.header.height,
    row = config.layout.header.row,
    col = config.layout.header.col,
  })
  if heading_error then
    logger.error("Failed to create heading component: " .. heading_error)
    return nil, "Failed to create heading component: " .. heading_error
  end

  local preview_instance, preview_error = preview.new({
    width = config.layout.preview.width,
    height = config.layout.preview.height,
    row = config.layout.preview.row,
    col = config.layout.preview.col,
    keymaps_applier = keymaps.make_keymaps_for_preview(instance),
  })
  if preview_error then
    logger.error("Failed to create preview component: " .. preview_error)
    return nil, "Failed to create preview component: " .. preview_error
  end

  local list_instance, list_error = list.new({
    width = config.layout.list.width,
    height = config.layout.list.height,
    row = config.layout.list.row,
    col = config.layout.list.col,
    cursor_debounce_delay = config.preview_debounce,
    max_lengths = { full_name = config.full_name_limit },
    list_fields = config.list_fields,
    keymaps_applier = keymaps.make_keymaps_for_list(instance),
    on_repo = function(repository)
      instance:on_repo(repository)
    end,
  })
  if list_error then
    logger.error("Failed to create list component: " .. list_error)
    return nil, "Failed to create list component: " .. list_error
  end

  instance.heading = heading_instance
  instance.preview = preview_instance
  instance.list = list_instance
  instance.window_manager = WindowManager:new(function()
    -- Modal-level cleanup: reset state and call on_close callback
    instance.is_open = false
    config.on_close()
  end)

  setmetatable(instance, StoreModal)
  return instance, nil
end

---@param repository Repository
function StoreModal:on_repo(repository)
  -- Track current repository for keybinding handlers
  self.state.current_repository = repository

  database.get_readme(repository.full_name, function(content, error)
    if error then
      logger.error("Error fetching README for " .. repository.full_name .. ": " .. error)
      local render_error = self.preview:render({ state = "error", content = { error } })
      if render_error then
        logger.error("Failed to render preview error state: " .. render_error)
      end
      return
    end

    local render_error = self.preview:render({ state = "ready", content = content, readme_id = repository.full_name })
    if render_error then
      logger.error("Failed to render preview ready state: " .. render_error)
    end
  end)
end

---Setup focus detection for auto-resize functionality
---@return nil
function StoreModal:_setup_focus_detection()
  -- Auto-resize is always enabled

  logger.debug("Setting up focus detection for auto-resize")

  -- Create autocmd group for focus detection
  self.state.focus_augroup = vim.api.nvim_create_augroup("StoreModalFocusResize", { clear = true })

  -- Setup WinEnter autocmd
  vim.api.nvim_create_autocmd("WinEnter", {
    group = self.state.focus_augroup,
    callback = function()
      logger.debug("WinEnter event triggered")
      self:_on_focus_change()
    end,
  })

  logger.debug("Focus detection setup complete")
end

---Handle focus change events with validation and debouncing
---@return nil
function StoreModal:_on_focus_change()
  logger.debug("_on_focus_change called")

  if not self.is_open then
    logger.debug("Focus change ignored: is_open=" .. tostring(self.is_open))
    return
  end

  -- Validate that components and window IDs exist
  local list_win_id = self.list:get_window_id()
  local preview_win_id = self.preview:get_window_id()
  if not self.list or not self.preview or not list_win_id or not preview_win_id then
    logger.warn("Cannot handle focus change: components or window IDs not initialized")
    return
  end

  local current_win = vim.api.nvim_get_current_win()
  local focused_component = nil

  logger.debug(
    "Current window: "
      .. current_win
      .. ", list window: "
      .. (list_win_id or "nil")
      .. ", preview window: "
      .. (preview_win_id or "nil")
  )

  -- Determine which component has focus with nil-safe comparisons
  if current_win == list_win_id then
    focused_component = "list"
  elseif current_win == preview_win_id then
    focused_component = "preview"
  else
    -- Focus is not on our modal components, ignore
    logger.debug("Focus is not on modal components, ignoring")
    return
  end

  logger.debug(
    "Focused component: " .. focused_component .. ", current focus state: " .. (self.state.current_focus or "nil")
  )

  -- Check if focus actually changed
  if focused_component == self.state.current_focus then
    return
  end

  -- Update focus state
  self.state.current_focus = focused_component

  -- Trigger resize immediately (no debouncing)
  vim.schedule(function()
    -- Re-validate modal state before resizing (race condition protection)
    if self.is_open then
      self:_resize_windows_for_focus(focused_component)
    end
  end)
end

---Resize windows based on focused component
---@param focused_component string Component that should be focused ("list" or "preview")
---@return nil
function StoreModal:_resize_windows_for_focus(focused_component)
  logger.debug("_resize_windows_for_focus called with: " .. focused_component)

  if not self.is_open then
    logger.debug("Resize aborted: is_open=" .. tostring(self.is_open))
    return
  end

  local config = require("store.config")
  local plugin_config = config.get()

  -- Get current proportions and swap them for focus effect
  local current_proportions = plugin_config.proportions
  local new_proportions = {
    list = current_proportions.preview, -- swap them
    preview = current_proportions.list, -- swap them
  }

  local new_layout, layout_error = config.update_layout(new_proportions)

  if not new_layout then
    logger.error(
      "Failed to calculate new layout for focus: " .. focused_component .. " - " .. (layout_error or "unknown error")
    )
    return
  end

  local resize_errors = {}

  -- Resize list window using component method
  local list_error = self.list:resize(new_layout.list)
  if list_error then
    table.insert(resize_errors, "list: " .. list_error)
  end

  -- Resize preview window using component method
  local preview_error = self.preview:resize(new_layout.preview)
  if preview_error then
    table.insert(resize_errors, "preview: " .. preview_error)
  end

  if #resize_errors == 0 then
    logger.debug("Successfully resized windows for focus: " .. focused_component)
  else
    logger.warn("Partial resize failure for focus " .. focused_component .. ": " .. table.concat(resize_errors, ", "))
  end
end

---Cleanup focus detection resources
---@return nil
function StoreModal:_cleanup_focus_detection()
  -- No timer to clean up (removed debouncing)

  -- Clean up autocmd group with consistent error handling
  if self.state.focus_augroup then
    safe_cleanup(function()
      vim.api.nvim_del_augroup_by_id(self.state.focus_augroup)
    end, "Failed to delete focus detection augroup during cleanup")
    self.state.focus_augroup = nil
  end
end

---Open the modal and render all components
function StoreModal:open()
  if self.is_open then
    logger.warn("Attempted to open modal that is already open")
  end

  logger.debug("Opening StoreModal")
  logger.debug("Auto-resize is always enabled")

  -- Open components with error handling
  local heading_error = self.heading:open()
  if heading_error then
    logger.error("Failed to open heading component: " .. heading_error)
    return
  end

  local list_error = self.list:open()
  if list_error then
    logger.error("Failed to open list component: " .. list_error)
    self.heading:close() -- Clean up already opened components
    return
  end

  local preview_error = self.preview:open()
  if preview_error then
    logger.error("Failed to open preview component: " .. preview_error)
    self.heading:close() -- Clean up already opened components
    self.list:close()
    return
  end

  self.is_open = true

  -- Register all components with the window manager for coordinated closing
  local heading_win_id = self.heading:get_window_id()
  local list_win_id = self.list:get_window_id()
  local preview_win_id = self.preview:get_window_id()

  if heading_win_id then
    self.window_manager:register_component(heading_win_id, function()
      self.heading:close()
    end, "heading")
  end
  if list_win_id then
    self.window_manager:register_component(list_win_id, function()
      self.list:close()
    end, "list")
  end
  if preview_win_id then
    self.window_manager:register_component(preview_win_id, function()
      self.preview:close()
    end, "preview")
  end

  logger.debug("StoreModal components opened successfully")

  -- Setup focus detection for auto-resize first
  self:_setup_focus_detection()

  -- Focus the list component by default
  local focus_error = self.list:focus()
  if focus_error then
    logger.warn("Failed to focus list component: " .. focus_error)
  end

  -- Trigger initial resize for list focus (auto-resize is always enabled)
  logger.debug("Triggering initial resize for list focus")
  vim.schedule(function()
    self:_resize_windows_for_focus("list")
  end)

  -- Concurrently fetch plugins data and installed plugins
  database.fetch_plugins(function(data, err)
    if err then
      -- Log the error and show user-friendly message
      logger.error("Failed to fetch plugin data: " .. err)
      self.heading:render({ state = "error" })
      self.list:render({ state = "error" })
      self.preview:render({ state = "error", content = { err } })
      return
    end

    if not data then
      logger.error("No plugin data received from server")
      self.heading:render({ state = "error" })
      self.list:render({ state = "error" })
      self.preview:render({ state = "error", content = { "No plugin data received from server" } })
      return
    end

    -- Store repositories in modal state
    self.state.repos = data.items or {}
    self.state.filtered_repos = data.items or {}
    self.state.installable_count = data.meta.installable_count or 0
    self.state.current_installable_count = data.meta.installable_count or 0

    -- Update list component configuration using public API
    self.list:update_config({
      max_lengths = {
        full_name = math.min(
          data.meta.max_full_name_length or self.config.full_name_limit,
          self.config.full_name_limit
        ),
        pretty_stargazers_count = data.meta.max_pretty_stargazers_length or 8,
        pretty_forks_count = data.meta.max_pretty_forks_length or 8,
        pretty_open_issues_count = data.meta.max_pretty_issues_length or 8,
        pretty_pushed_at = 13 + (data.meta.max_pretty_pushed_at_length or 14),
      },
    })

    logger.debug("Plugin data loaded successfully: " .. tostring(data.meta.total_count) .. " repositories")

    self.heading:render({
      state = "ready",
      filtered_count = data.meta.total_count,
      total_count = data.meta.total_count,
      installable_count = self.state.current_installable_count,
      installed_count = 0, -- Will be updated when installed plugins data loads
    })
    self.list:render({
      state = "ready",
      items = data.items or {},
    })
  end)

  -- Concurrently fetch installed plugins
  database.get_installed_plugins(function(installed_data, installed_err)
    if installed_err then
      logger.error("Failed to fetch installed plugins: " .. installed_err)
      -- Don't fail the entire modal, just continue without installed info
      return
    end

    logger.debug("Installed plugins loaded successfully: " .. vim.tbl_count(installed_data) .. " plugins")

    -- Store installed plugins data in modal state
    self.state.installed_items = installed_data or {}

    -- Calculate total installed count from ALL installed plugins (static)
    local total_installed_count = 0
    for _ in pairs(self.state.installed_items) do
      total_installed_count = total_installed_count + 1
    end
    self.state.total_installed_count = total_installed_count

    -- Update heading with counts
    self.heading:render({
      installable_count = self.state.current_installable_count,
      installed_count = self.state.total_installed_count,
    })

    -- Update list component with installed plugins data
    self.list:render({
      installed_items = installed_data,
    })
  end)
end

---Apply sorting to current filtered repositories
---@param sort_type string Sort type to apply
function StoreModal:apply_sort(sort_type)
  local sort = require("store.sort")

  -- Update sort state
  self.state.sort_config.type = sort_type

  -- For default sorting, restore original order by re-filtering from original repos
  if sort_type == "default" then
    self:_apply_filter()
  else
    -- Apply sort to current filtered repositories
    self.state.filtered_repos = sort.sort_repositories(self.state.filtered_repos, sort_type)
  end

  -- Update header with new sort status
  local heading_error = self.heading:render({
    sort_type = sort_type,
  })
  if heading_error then
    logger.error("Failed to render heading after sort: " .. heading_error)
  end

  -- Re-render list with sorted data
  local list_error = self.list:render({
    state = "ready",
    items = self.state.filtered_repos,
  })
  if list_error then
    logger.error("Failed to render list after sort: " .. list_error)
  end

  logger.debug("Applied sort: " .. sort_type)
end

---Focus the modal by focusing the list component
---@return nil
function StoreModal:focus()
  if not self.is_open then
    logger.warn("Attempted to focus modal that is not open")
    return
  end

  logger.debug("Focusing StoreModal (list component)")
  local focus_error = self.list:focus()
  if focus_error then
    logger.warn("Failed to focus list component: " .. focus_error)
  else
    self.state.current_focus = "list"
  end
end

---Close the modal and all components
---@return boolean Success status
function StoreModal:close()
  if not self.is_open then
    logger.warn("Attempted to close modal that is not open")
    return false
  end

  logger.debug("Closing StoreModal")

  -- Clean up focus detection first
  self:_cleanup_focus_detection()

  -- Clean up window manager
  self.window_manager:cleanup()

  -- Save cursor position before closing
  if self.preview then
    self.preview:save_cursor_on_blur()
  end

  -- Close all components with error handling
  local close_errors = {}

  if self.heading then
    local heading_error = self.heading:close()
    if heading_error then
      table.insert(close_errors, "heading: " .. heading_error)
    end
  end

  if self.list then
    local list_error = self.list:close()
    if list_error then
      table.insert(close_errors, "list: " .. list_error)
    end
  end

  if self.preview then
    local preview_error = self.preview:close()
    if preview_error then
      table.insert(close_errors, "preview: " .. preview_error)
    end
  end

  if #close_errors > 0 then
    logger.warn("Some components failed to close: " .. table.concat(close_errors, ", "))
  end

  self.is_open = false

  logger.debug("StoreModal closed successfully")

  return true
end

---Refresh the modal by clearing caches and refetching data
---@return nil
function StoreModal:refresh()
  if self.state.is_refreshing then
    logger.debug("Refresh already in progress, ignoring")
    return
  end

  logger.debug("Starting refresh")
  self.state.is_refreshing = true

  -- Show refreshing state in header
  self.heading:render({
    filter_query = self.state.filter_query,
    sort_type = self.state.sort_config.type,
    state = "loading",
    filtered_count = 0,
    total_count = 0,
  })

  -- Clear all caches
  local cache_cleared = cache.clear_all_caches()
  if not cache_cleared then
    logger.warn("Some cache files could not be cleared during refresh")
  end

  -- Force refresh plugins data
  database.fetch_plugins(function(data, err)
    self.state.is_refreshing = false

    if err then
      logger.error("Failed to refresh plugins data: " .. tostring(err))
      -- Show error state
      self.heading:render({
        filter_query = self.state.filter_query,
        sort_type = self.state.sort_config.type,
        state = "error",
        filtered_count = 0,
        total_count = 0,
      })
      self.list:render({ state = "error" })
      self.preview:render({
        state = "error",
        content = { "Failed to refresh: " .. tostring(err) },
        readme_id = nil,
      })
      return
    end

    if not data then
      logger.error("No plugins data received during refresh")
      -- Show error state
      self.heading:render({
        filter_query = self.state.filter_query,
        sort_type = self.state.sort_config.type,
        state = "error",
        filtered_count = 0,
        total_count = 0,
      })
      self.list:render({ state = "error" })
      self.preview:render({
        state = "error",
        content = { "No plugins data received during refresh" },
        readme_id = nil,
      })
      return
    end

    -- Update state with new data
    self.state.repos = data.items or {}

    -- Update list component max_lengths with actual data from meta (only for configured fields)
    if data.meta then
      -- Only update max_lengths for fields that are actually configured to display
      local config_updates = { max_lengths = {} }
      if vim.tbl_contains(self.config.list_fields, "full_name") then
        config_updates.max_lengths.full_name =
          math.min(data.meta.max_full_name_length or self.config.full_name_limit, self.config.full_name_limit)
      end
      if vim.tbl_contains(self.config.list_fields, "stars") then
        config_updates.max_lengths.pretty_stargazers_count = data.meta.max_pretty_stargazers_length or 8
      end
      if vim.tbl_contains(self.config.list_fields, "forks") then
        config_updates.max_lengths.pretty_forks_count = data.meta.max_pretty_forks_length or 8
      end
      if vim.tbl_contains(self.config.list_fields, "issues") then
        config_updates.max_lengths.pretty_open_issues_count = data.meta.max_pretty_issues_length or 8
      end
      if vim.tbl_contains(self.config.list_fields, "pushed_at") then
        config_updates.max_lengths.pretty_pushed_at = 13 + (data.meta.max_pretty_pushed_at_length or 14)
      end

      -- Apply config updates using public API
      self.list:update_config(config_updates)
    end

    -- Re-apply existing filter
    self:_apply_filter()

    -- Re-render all components
    self:_render_after_refresh()

    logger.debug("Refresh completed successfully")
  end, true) -- true = force refresh
end

---Apply current filter query to repositories
---@return nil
function StoreModal:_apply_filter()
  if self.state.filter_query == "" then
    self.state.filtered_repos = self.state.repos
    -- Reset to total installable count when filter is cleared
    self.state.current_installable_count = self.state.installable_count
  else
    local filter_predicate, error_msg = utils.create_advanced_filter(self.state.filter_query)
    if error_msg then
      logger.error("Invalid filter query during refresh: " .. error_msg)
      -- Fallback to showing all repositories if filter is invalid
      self.state.filtered_repos = self.state.repos
      return
    end

    local filtered_installable_count = 0
    self.state.filtered_repos = {}
    for _, repo in ipairs(self.state.repos) do
      if filter_predicate(repo) then
        table.insert(self.state.filtered_repos, repo)
        -- if filtered repo is installable, count it for heading
        if repo.install then
          filtered_installable_count = filtered_installable_count + 1
        end
      end
    end
    self.state.current_installable_count = filtered_installable_count
  end

  -- After filtering, re-apply current sort
  local sort = require("store.sort")
  self.state.filtered_repos = sort.sort_repositories(self.state.filtered_repos, self.state.sort_config.type)
end

---Re-render all components after refresh
---@return nil
function StoreModal:_render_after_refresh()
  -- Re-render heading with new stats
  self.heading:render({
    filter_query = self.state.filter_query,
    sort_type = self.state.sort_config.type,
    state = "ready",
    filtered_count = #self.state.filtered_repos,
    total_count = #self.state.repos,
    installable_count = self.state.current_installable_count,
    installed_count = self.state.total_installed_count,
  })

  -- Re-render list with filtered results
  self.list:render({
    state = "ready",
    items = self.state.filtered_repos,
  })

  -- Clear preview since repository data has changed
  -- User will need to select a repository again to see its README
  self.preview:render({
    state = "loading",
    readme_id = nil,
  })

  -- Clear current repository selection since data has changed
  self.state.current_repository = nil
end

return M
