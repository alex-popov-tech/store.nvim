local http = require("store.http")
local cache = require("store.cache")
local validators = require("store.validators")
local utils = require("store.utils")
local heading = require("store.ui.heading")
local list = require("store.ui.list")
local preview = require("store.ui.preview")
local logger = require("store.logger")
local WindowManager = require("store.ui.window_manager")

local M = {}

-- Internal UI configuration (zindex, border, etc.)
local UI_CONFIG = {
  border = "rounded",
  zindex = 50,
}

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
---@param config ComputedConfig|nil Modal configuration to validate
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

---@class StoreModal
---@field config ComputedConfig Complete computed configuration
---@field layout ComputedLayout Window layout calculations
---@field is_open boolean Modal open status
---@field state table Modal state (filter_query, repos, etc.)
---@field heading HeadingWindow Header component instance
---@field list ListWindow List component instance
---@field preview PreviewWindow Preview component instance
---@field open fun(): boolean Open the modal and render all components
---@field close fun(): boolean Close the modal and all components

-- StoreModal class - stateful orchestrator for UI components
local StoreModal = {}
StoreModal.__index = StoreModal

---Create a new modal instance
---@param config ComputedConfig Complete computed configuration from config.lua
---@return StoreModal StoreModal instance
function M.new(config)
  if not config then
    error("Configuration required. StoreModal expects config from config.lua")
  end

  logger.debug("Creating new StoreModal instance")

  -- Validate configuration first
  local error_msg = validate(config)
  if error_msg then
    logger.error("Modal configuration validation failed: " .. error_msg)
    error("Modal configuration validation failed: " .. error_msg)
  end

  -- Initialize list component with calculated config.computed_layout
  local instance = {
    config = config,
    layout = config.computed_layout,
    is_open = false,
    window_manager = nil, -- Will be set after instance is created
    state = {
      filter_query = "",
      sort_config = {
        type = "default", -- Current sort type
      },
      repos = {},
      filtered_repos = {},
      current_focus = "list", -- Track current focused component: "list" or "preview"
      current_repository = nil, -- Track currently selected repository
      is_refreshing = false, -- Track refresh state to prevent concurrent refreshes
      focus_resize_timer = nil, -- Timer for debouncing focus-based resize
      focus_augroup = nil, -- Autocmd group for focus detection
    },

    -- UI component instances (ready for rendering)
    heading = heading.new({
      width = config.computed_layout.header.width,
      height = config.computed_layout.header.height,
      row = config.computed_layout.header.row,
      col = config.computed_layout.header.col,
      border = UI_CONFIG.border,
      zindex = UI_CONFIG.zindex,
    }),

    preview = preview.new({
      width = config.computed_layout.preview.width,
      height = config.computed_layout.preview.height,
      row = config.computed_layout.preview.row,
      col = config.computed_layout.preview.col,
      border = UI_CONFIG.border,
      zindex = UI_CONFIG.zindex,
      keymap = {}, -- Will be populated below
    }),

    list = list.new({
      width = config.computed_layout.list.width,
      height = config.computed_layout.list.height,
      row = config.computed_layout.list.row,
      col = config.computed_layout.list.col,
      border = UI_CONFIG.border,
      zindex = UI_CONFIG.zindex,
      keymap = {}, -- Will be populated below
      cursor_debounce_delay = config.preview_debounce,
      max_lengths = {
        full_name = config.full_name_limit,
        pretty_stargazers_count = 8,
        pretty_forks_count = 8,
        pretty_open_issues_count = 8,
      },
      list_fields = config.list_fields,
    }),
  }

  -- Create modal keymaps with access to instance
  local modal_keymaps = {
    [config.keybindings.close] = function()
      instance:close()
      if config.on_close then
        config.on_close()
      end
    end,
    ["<esc>"] = function()
      instance:close()
      if config.on_close then
        config.on_close()
      end
    end,
    [config.keybindings.switch_focus] = function()
      if instance.state.current_focus == "list" then
        instance.preview:focus()
        instance.state.current_focus = "preview"
      else
        -- Save cursor position when switching away from preview
        instance.preview:save_cursor_on_blur()
        instance.list:focus()
        instance.state.current_focus = "list"
      end
    end,
    [config.keybindings.filter] = function()
      vim.ui.input({ prompt = "Filter repositories: ", default = instance.state.filter_query }, function(input)
        if input ~= nil then
          -- Update filter query in state
          instance.state.filter_query = input

          logger.debug("Filter query updated: '" .. input .. "'")

          -- Filter repositories using advanced filter
          if input == "" then
            instance.state.filtered_repos = instance.state.repos
            logger.debug("Filter cleared, showing all repositories")
          else
            local filter_predicate, error_msg = utils.create_advanced_filter(input)
            if error_msg then
              logger.error("Invalid filter query: " .. error_msg)
              vim.notify("Invalid filter query: " .. error_msg, vim.log.levels.ERROR)
              return
            end

            instance.state.filtered_repos = {}
            for _, repo in ipairs(instance.state.repos) do
              if filter_predicate(repo) then
                table.insert(instance.state.filtered_repos, repo)
              end
            end
          end

          logger.debug(
            "Filter applied: "
              .. #instance.state.filtered_repos
              .. " of "
              .. #instance.state.repos
              .. " repositories match"
          )

          -- Update heading with new filter stats
          instance.heading:render({
            query = instance.state.filter_query,
            sort_type = instance.state.sort_config.type,
            state = "ready",
            filtered_count = #instance.state.filtered_repos,
            total_count = #instance.state.repos,
          })

          -- Re-render list with filtered results
          instance.list:render({
            state = "ready",
            items = instance.state.filtered_repos,
          })
        end
      end)
    end,
    [config.keybindings.help] = function()
      local help = require("store.ui.help")
      
      -- Store current focus for restoration
      local previous_focus = instance.state.current_focus
      
      help.open({
        on_exit = function()
          -- Restore focus after closing help
          if previous_focus == "list" then
            instance.list:focus()
          elseif previous_focus == "preview" then
            instance.preview:focus()
          end
        end,
      })
    end,
    [config.keybindings.refresh] = function()
      instance:refresh()
    end,
    [config.keybindings.open] = function()
      if instance.state.current_repository and instance.state.current_repository.html_url then
        local success = utils.open_url(instance.state.current_repository.html_url)
        if not success then
          logger.error("Failed to open URL: " .. instance.state.current_repository.html_url)
        else
          logger.debug("Opened repository URL: " .. instance.state.current_repository.html_url)
        end
      else
        logger.warn("No repository selected")
      end
    end,
    [config.keybindings.sort] = function()
      local sort_select = require("store.ui.sort_select")

      -- Store current focus for restoration
      local previous_focus = instance.state.current_focus

      sort_select.open({
        current_sort = instance.state.sort_config.type,
        on_value = function(selected_sort)
          if selected_sort ~= instance.state.sort_config.type then
            instance:apply_sort(selected_sort)
          end
          -- Restore focus after selection
          if previous_focus == "list" then
            instance.list:focus()
          elseif previous_focus == "preview" then
            instance.preview:focus()
          end
        end,
        on_exit = function()
          -- Restore focus after cancellation
          if previous_focus == "list" then
            instance.list:focus()
          elseif previous_focus == "preview" then
            instance.preview:focus()
          end
        end,
      })
    end,
  }

  -- Update component configs with keymaps
  instance.list.config.keymap = modal_keymaps
  instance.list.config.on_repo = function(repository)
    -- Track current repository for keybinding handlers
    instance.state.current_repository = repository

    local repo_path = repository.author .. "/" .. repository.name
    http.get_readme(repo_path, function(data)
      if data.error then
        logger.error("Error fetching README for " .. repo_path .. ": " .. data.error)
        instance.preview:render({
          state = "error",
          error_message = data.error,
          error_stack = data.stack,
          readme_id = repo_path,
        })
      else
        instance.preview:render({
          state = "ready",
          content = data.body,
          readme_id = repo_path,
        })
      end
    end)
  end
  instance.preview.config.keymap = modal_keymaps

  -- Re-create buffers with new keymaps
  instance.list.buf_id = instance.list:_create_buffer()
  instance.preview.buf_id = instance.preview:_create_buffer()

  -- Create WindowManager after instance is fully constructed
  instance.window_manager = WindowManager:new(function()
    -- Modal-level cleanup: reset state and call on_close callback
    instance.is_open = false
    if config.on_close then
      config.on_close()
    end
  end)

  setmetatable(instance, StoreModal)
  return instance
end

---Setup focus detection for auto-resize functionality
---@return nil
function StoreModal:_setup_focus_detection()
  if not self.config.auto_resize_on_focus then
    logger.debug("Auto-resize disabled, skipping focus detection setup")
    return
  end

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

  if not self.is_open or not self.config.auto_resize_on_focus then
    logger.debug(
      "Focus change ignored: is_open="
        .. tostring(self.is_open)
        .. ", auto_resize="
        .. tostring(self.config.auto_resize_on_focus)
    )
    return
  end

  -- Validate that components and window IDs exist
  if not self.list or not self.preview or not self.list.win_id or not self.preview.win_id then
    logger.warn("Cannot handle focus change: components or window IDs not initialized")
    return
  end

  local current_win = vim.api.nvim_get_current_win()
  local focused_component = nil

  logger.debug(
    "Current window: "
      .. current_win
      .. ", list window: "
      .. (self.list.win_id or "nil")
      .. ", preview window: "
      .. (self.preview.win_id or "nil")
  )

  -- Determine which component has focus with nil-safe comparisons
  if current_win == self.list.win_id then
    focused_component = "list"
  elseif current_win == self.preview.win_id then
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

  -- Cancel existing timer
  if self.state.focus_resize_timer then
    vim.fn.timer_stop(self.state.focus_resize_timer)
    self.state.focus_resize_timer = nil
  end

  -- Set new timer with debounce delay and additional validation
  self.state.focus_resize_timer = vim.fn.timer_start(self.config.focus_resize_debounce or 100, function()
    self.state.focus_resize_timer = nil
    vim.schedule(function()
      -- Re-validate modal state before resizing (race condition protection)
      if self.is_open and self.config.auto_resize_on_focus then
        self:_resize_windows_for_focus(focused_component)
      end
    end)
  end)
end

---Resize windows based on focused component
---@param focused_component string Component that should be focused ("list" or "preview")
---@return nil
function StoreModal:_resize_windows_for_focus(focused_component)
  logger.debug("_resize_windows_for_focus called with: " .. focused_component)

  if not self.is_open or not self.config.auto_resize_on_focus then
    logger.debug(
      "Resize aborted: is_open="
        .. tostring(self.is_open)
        .. ", auto_resize="
        .. tostring(self.config.auto_resize_on_focus)
    )
    return
  end

  local config = require("store.config")
  local new_layout = config.calculate_layout_with_focus(focused_component)

  if not new_layout then
    logger.error("Failed to calculate new layout for focus: " .. focused_component)
    return
  end

  local resize_errors = {}

  -- Resize list window with consistent error handling
  if self.list.win_id and vim.api.nvim_win_is_valid(self.list.win_id) then
    local success = safe_cleanup(function()
      vim.api.nvim_win_set_config(self.list.win_id, {
        relative = "editor",
        width = new_layout.list.width,
        height = new_layout.list.height,
        row = new_layout.list.row,
        col = new_layout.list.col,
        style = "minimal",
        border = self.list.config.border or "rounded",
        zindex = self.list.config.zindex or 50,
      })
    end, "Failed to resize list window")

    if not success then
      table.insert(resize_errors, "list: resize failed")
    end
  else
    table.insert(resize_errors, "list: window invalid or missing")
  end

  -- Resize preview window with consistent error handling
  if self.preview.win_id and vim.api.nvim_win_is_valid(self.preview.win_id) then
    local success = safe_cleanup(function()
      vim.api.nvim_win_set_config(self.preview.win_id, {
        relative = "editor",
        width = new_layout.preview.width,
        height = new_layout.preview.height,
        row = new_layout.preview.row,
        col = new_layout.preview.col,
        style = "minimal",
        border = self.preview.config.border or "rounded",
        zindex = self.preview.config.zindex or 50,
      })
    end, "Failed to resize preview window")

    if not success then
      table.insert(resize_errors, "preview: resize failed")
    end
  else
    table.insert(resize_errors, "preview: window invalid or missing")
  end

  -- Update component configs even if some resize operations failed
  self:_update_component_configs(new_layout)

  if #resize_errors == 0 then
    logger.debug("Successfully resized windows for focus: " .. focused_component)
  else
    logger.warn("Partial resize failure for focus " .. focused_component .. ": " .. table.concat(resize_errors, ", "))
  end
end

---Update component internal configs after window resize
---@param new_layout ComputedLayout New layout calculations
---@return nil
function StoreModal:_update_component_configs(new_layout)
  -- Validate layout structure
  if not new_layout or not new_layout.list or not new_layout.preview then
    logger.warn("Invalid layout structure provided to _update_component_configs")
    return
  end

  -- Validate components exist and have config
  if not self.list or not self.list.config then
    logger.warn("List component or config not available for update")
  else
    self.list.config.width = new_layout.list.width
    self.list.config.height = new_layout.list.height
    self.list.config.row = new_layout.list.row
    self.list.config.col = new_layout.list.col
  end

  if not self.preview or not self.preview.config then
    logger.warn("Preview component or config not available for update")
  else
    self.preview.config.width = new_layout.preview.width
    self.preview.config.height = new_layout.preview.height
    self.preview.config.row = new_layout.preview.row
    self.preview.config.col = new_layout.preview.col
  end
end

---Cleanup focus detection resources
---@return nil
function StoreModal:_cleanup_focus_detection()
  -- Cancel debounce timer with consistent error handling
  if self.state.focus_resize_timer then
    safe_cleanup(function()
      vim.fn.timer_stop(self.state.focus_resize_timer)
    end, "Failed to stop focus resize timer during cleanup")
    self.state.focus_resize_timer = nil
  end

  -- Clean up autocmd group with consistent error handling
  if self.state.focus_augroup then
    safe_cleanup(function()
      vim.api.nvim_del_augroup_by_id(self.state.focus_augroup)
    end, "Failed to delete focus detection augroup during cleanup")
    self.state.focus_augroup = nil
  end
end

---Open the modal and render all components
---@return boolean Success status
function StoreModal:open()
  if self.is_open then
    logger.warn("Attempted to open modal that is already open")
    return false
  end

  logger.debug("Opening StoreModal")
  logger.debug("Auto-resize config: " .. tostring(self.config.auto_resize_on_focus))

  self.heading:open()
  self.list:open()
  self.preview:open()
  self.is_open = true

  -- Register all components with the window manager for coordinated closing
  self.window_manager:register_component(self.heading.win_id, function()
    self.heading:close()
  end, "heading")
  self.window_manager:register_component(self.list.win_id, function()
    self.list:close()
  end, "list")
  self.window_manager:register_component(self.preview.win_id, function()
    self.preview:close()
  end, "preview")

  logger.debug("StoreModal components opened successfully")

  -- Setup focus detection for auto-resize first
  self:_setup_focus_detection()

  -- Focus the list component by default
  self.list:focus()

  -- Trigger initial resize for list focus if auto-resize is enabled
  if self.config.auto_resize_on_focus then
    logger.debug("Triggering initial resize for list focus")
    vim.schedule(function()
      self:_resize_windows_for_focus("list")
    end)
  else
    logger.debug("Auto-resize disabled, skipping initial resize")
  end

  http.fetch_plugins(function(data, err)
    if err then
      -- Log the error and show user-friendly message
      logger.error("Failed to fetch plugin data: " .. tostring(err))
      self.heading:render({
        query = "",
        sort_type = self.state.sort_config.type,
        state = "error",
        filtered_count = 0,
        total_count = 0,
      })
      self.list:render({ state = "error" })
      self.preview:render({
        state = "error",
        error_message = tostring(err),
        readme_id = nil,
      })
      return
    end
    if not data then
      logger.error("No plugin data received from server")
      self.heading:render({
        query = "",
        sort_type = self.state.sort_config.type,
        state = "error",
        filtered_count = 0,
        total_count = 0,
      })
      self.list:render({ state = "error" })
      self.preview:render({
        state = "error",
        error_message = "No plugin data received from server",
        readme_id = nil,
      })
      return
    end

    -- Store repositories in modal state
    self.state.repos = data.items or {}
    self.state.filtered_repos = data.items or {}

    -- Update list component max_lengths with actual data from meta (only for configured fields)
    if data.meta then
      -- Only update max_lengths for fields that are actually configured to display
      if vim.tbl_contains(self.config.list_fields, "full_name") then
        self.list.config.max_lengths.full_name =
          math.min(data.meta.max_full_name_length or self.config.full_name_limit, self.config.full_name_limit)
      end
      if vim.tbl_contains(self.config.list_fields, "stars") then
        self.list.config.max_lengths.pretty_stargazers_count = data.meta.max_pretty_stargazers_length or 8
      end
      if vim.tbl_contains(self.config.list_fields, "forks") then
        self.list.config.max_lengths.pretty_forks_count = data.meta.max_pretty_forks_length or 8
      end
      if vim.tbl_contains(self.config.list_fields, "issues") then
        self.list.config.max_lengths.pretty_open_issues_count = data.meta.max_pretty_issues_length or 8
      end
      if vim.tbl_contains(self.config.list_fields, "pushed_at") then
        self.list.config.max_lengths.pretty_pushed_at = 13 + (data.meta.max_pretty_pushed_at_length or 14)
      end
    end

    logger.log("Plugin data loaded successfully: " .. tostring(data.meta.total_count) .. " repositories")

    self.heading:render({
      query = "",
      sort_type = self.state.sort_config.type,
      state = "ready",
      filtered_count = data.meta.total_count,
      total_count = data.meta.total_count,
    })

    -- Render repositories in list component
    self.list:render({
      state = "ready",
      items = data.items or {},
    })
  end)

  return true
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
  self.heading:render({
    query = self.state.filter_query,
    sort_type = sort_type,
    state = "ready",
    filtered_count = #self.state.filtered_repos,
    total_count = #self.state.repos,
  })

  -- Re-render list with sorted data
  self.list:render({
    state = "ready",
    items = self.state.filtered_repos,
  })

  logger.debug("Applied sort: " .. sort_type)
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

  -- Close all components
  if self.heading then
    self.heading:close()
  end

  if self.list then
    self.list:close()
  end

  if self.preview then
    self.preview:close()
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
    query = self.state.filter_query,
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
  http.fetch_plugins(function(data, err)
    self.state.is_refreshing = false

    if err then
      logger.error("Failed to refresh plugins data: " .. tostring(err))
      -- Show error state
      self.heading:render({
        query = self.state.filter_query,
        sort_type = self.state.sort_config.type,
        state = "error",
        filtered_count = 0,
        total_count = 0,
      })
      self.list:render({ state = "error" })
      self.preview:render({
        state = "error",
        error_message = "Failed to refresh: " .. tostring(err),
        readme_id = nil,
      })
      return
    end

    if not data then
      logger.error("No plugins data received during refresh")
      -- Show error state
      self.heading:render({
        query = self.state.filter_query,
        sort_type = self.state.sort_config.type,
        state = "error",
        filtered_count = 0,
        total_count = 0,
      })
      self.list:render({ state = "error" })
      self.preview:render({
        state = "error",
        error_message = "No plugins data received during refresh",
        readme_id = nil,
      })
      return
    end

    -- Update state with new data
    self.state.repos = data.items or {}

    -- Update list component max_lengths with actual data from meta (only for configured fields)
    if data.meta then
      -- Only update max_lengths for fields that are actually configured to display
      if vim.tbl_contains(self.config.list_fields, "full_name") then
        self.list.config.max_lengths.full_name =
          math.min(data.meta.max_full_name_length or self.config.full_name_limit, self.config.full_name_limit)
      end
      if vim.tbl_contains(self.config.list_fields, "stars") then
        self.list.config.max_lengths.pretty_stargazers_count = data.meta.max_pretty_stargazers_length or 8
      end
      if vim.tbl_contains(self.config.list_fields, "forks") then
        self.list.config.max_lengths.pretty_forks_count = data.meta.max_pretty_forks_length or 8
      end
      if vim.tbl_contains(self.config.list_fields, "issues") then
        self.list.config.max_lengths.pretty_open_issues_count = data.meta.max_pretty_issues_length or 8
      end
      if vim.tbl_contains(self.config.list_fields, "pushed_at") then
        self.list.config.max_lengths.pretty_pushed_at = 13 + (data.meta.max_pretty_pushed_at_length or 14)
      end
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
  else
    local filter_predicate, error_msg = utils.create_advanced_filter(self.state.filter_query)
    if error_msg then
      logger.error("Invalid filter query during refresh: " .. error_msg)
      -- Fallback to showing all repositories if filter is invalid
      self.state.filtered_repos = self.state.repos
      return
    end

    self.state.filtered_repos = {}
    for _, repo in ipairs(self.state.repos) do
      if filter_predicate(repo) then
        table.insert(self.state.filtered_repos, repo)
      end
    end
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
    query = self.state.filter_query,
    sort_type = self.state.sort_config.type,
    state = "ready",
    filtered_count = #self.state.filtered_repos,
    total_count = #self.state.repos,
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
