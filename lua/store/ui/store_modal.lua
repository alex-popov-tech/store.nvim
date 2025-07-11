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
    window_manager = WindowManager:new(),
    state = {
      filter_query = "",
      repos = {},
      filtered_repos = {},
      current_focus = "list", -- Track current focused component: "list" or "preview"
      current_repository = nil, -- Track currently selected repository
      is_refreshing = false, -- Track refresh state to prevent concurrent refreshes
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

          -- Filter repositories based on query (case-insensitive)
          if input == "" then
            instance.state.filtered_repos = instance.state.repos
            logger.debug("Filter cleared, showing all repositories")
          else
            local query_lower = input:lower()
            instance.state.filtered_repos = {}
            for _, repo in ipairs(instance.state.repos) do
              if
                repo.full_name:lower():find(query_lower)
                or (repo.description and repo.description:lower():find(query_lower))
              then
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
            state = "ready",
            filtered_count = #instance.state.filtered_repos,
            total_count = #instance.state.repos,
          })

          -- Re-render list with filtered results
          instance.list:render({
            state = "ready",
            repositories = instance.state.filtered_repos,
          })
        end
      end)
    end,
    [config.keybindings.help] = function()
      local help = require("store.ui.help")
      help.open()
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
  }

  -- Update component configs with keymaps
  instance.list.config.keymap = modal_keymaps
  instance.list.config.on_repo = function(repository)
    -- Track current repository for keybinding handlers
    instance.state.current_repository = repository

    http.get_readme(repository.full_name, function(data)
      if data.error then
        logger.error("Error fetching README for " .. repository.full_name .. ": " .. data.error)
        instance.preview:render({
          state = "error",
          error_message = data.error,
          error_stack = data.stack,
          readme_id = repository.full_name,
        })
      else
        instance.preview:render({
          state = "ready",
          content = data.body,
          readme_id = repository.full_name,
        })
      end
    end)
  end
  instance.preview.config.keymap = modal_keymaps

  -- Re-create buffers with new keymaps
  instance.list.buf_id = instance.list:_create_buffer()
  instance.preview.buf_id = instance.preview:_create_buffer()

  setmetatable(instance, StoreModal)
  return instance
end

---Open the modal and render all components
---@return boolean Success status
function StoreModal:open()
  if self.is_open then
    logger.warn("Attempted to open modal that is already open")
    return false
  end

  logger.debug("Opening StoreModal")

  self.heading:open()
  self.list:open()
  self.preview:open()
  self.is_open = true

  -- Register all windows with the window manager for coordinated closing
  self.window_manager:register_window(self.heading.win_id, "heading")
  self.window_manager:register_window(self.list.win_id, "list")
  self.window_manager:register_window(self.preview.win_id, "preview")

  logger.debug("StoreModal components opened successfully")

  -- Focus the list component by default
  self.list:focus()

  http.fetch_plugins(function(data, err)
    if err then
      -- Log the error and show user-friendly message
      logger.error("Failed to fetch plugin data: " .. tostring(err))
      self.heading:render({
        query = "",
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
    self.state.repos = data.repositories or {}
    self.state.filtered_repos = data.repositories or {}

    logger.log("Plugin data loaded successfully: " .. tostring(data.total_repositories) .. " repositories")

    self.heading:render({
      query = "",
      state = "ready",
      filtered_count = data.total_repositories,
      total_count = data.total_repositories,
    })

    -- Render repositories in list component
    self.list:render({
      state = "ready",
      repositories = data.repositories or {},
    })
  end)

  return true
end

---Close the modal and all components
---@return boolean Success status
function StoreModal:close()
  if not self.is_open then
    logger.warn("Attempted to close modal that is not open")
    return false
  end

  logger.debug("Closing StoreModal")

  -- Clean up window manager first
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
    self.state.repos = data.repositories or {}

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
    local query_lower = self.state.filter_query:lower()
    self.state.filtered_repos = {}
    for _, repo in ipairs(self.state.repos) do
      if
        repo.full_name:lower():find(query_lower)
        or (repo.description and repo.description:lower():find(query_lower))
      then
        table.insert(self.state.filtered_repos, repo)
      end
    end
  end
end

---Re-render all components after refresh
---@return nil
function StoreModal:_render_after_refresh()
  -- Re-render heading with new stats
  self.heading:render({
    query = self.state.filter_query,
    state = "ready",
    filtered_count = #self.state.filtered_repos,
    total_count = #self.state.repos,
  })

  -- Re-render list with filtered results
  self.list:render({
    state = "ready",
    repositories = self.state.filtered_repos,
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
