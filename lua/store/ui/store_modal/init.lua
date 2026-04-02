local database = require("store.database")
local telemetry = require("store.telemetry")
local validators = require("store.ui.store_modal.validators")
local event_handlers = require("store.ui.store_modal.event_handlers")
local event_listeners = require("store.ui.store_modal.event_listeners")
local heading = require("store.ui.heading")
local list = require("store.ui.list")
local preview = require("store.ui.preview")
local layout = require("store.ui.layout")
local keymaps = require("store.keymaps")
local utils = require("store.utils")
local logger = require("store.logger").createLogger({ context = "modal" })

local ns_id = vim.api.nvim_create_namespace("store.modal")

local M = {}

-- StoreModal class - stateful orchestrator for UI components
local StoreModal = {}
StoreModal.__index = StoreModal

---Create a new modal instance
---@param config StoreModalConfig Complete computed configuration with on_close callback
---@return StoreModal|nil instance StoreModal instance on success, nil on error
---@return string|nil error Error message on failure, nil on success
function M.new(config)
  local error_msg = validators.validate(config)
  if error_msg then
    return nil, "Modal configuration validation failed: " .. error_msg
  end

  local instance = {
    config = config,
    state = {
      filter_query = "",
      sort_config = {
        type = "recently_updated", -- Current sort type
      },
      repos = {},
      currently_displayed_repos = {},

      total_installed_count = 0, -- Total installed plugins from lock file (static)
      installed_items = {}, -- Lookup table of installed plugin names for O(1) checks
      download_stats_monthly = nil, -- Lookup table of monthly plugin install counts from telemetry API
      download_stats_weekly = nil, -- Lookup table of weekly plugin install counts from telemetry API
      view_stats_monthly = nil, -- Lookup table of monthly plugin view counts from telemetry API
      view_stats_weekly = nil, -- Lookup table of weekly plugin view counts from telemetry API
      install_catalogue = nil, -- Cached install catalogue data for detected plugin manager
      install_catalogue_manager = nil, -- Detected plugin manager identifier
      plugin_manager_mode = config.plugin_manager or "not-selected",
      plugin_manager_overview = {},

      current_focus = nil, -- Track current focused component win_id
      current_repository = nil, -- Track currently selected repository

      is_closing = false, -- for graceful closing on unexpected close attempt
      autocmds = {}, -- listeners to delete on close
    },
  }

  local heading_instance, heading_error = heading.new(vim.tbl_extend("force", {}, config.layout.header or {}))
  if heading_error then
    return nil, "Failed to create heading component: " .. heading_error
  end
  instance.heading = heading_instance

  local preview_instance, preview_error = preview.new(vim.tbl_extend("force", config.layout.preview or {}, {
    keymaps_applier = keymaps.make_keymaps_for_preview(instance),
    keymaps_applier_docs = keymaps.make_keymaps_for_docs(instance),
    on_tab_change = function()
      if instance.layout_provider then
        instance.layout_provider:update_winbar(instance.list, instance.preview)
      end
    end,
  }))
  if preview_error then
    return nil, "Failed to create preview component: " .. preview_error
  end
  instance.preview = preview_instance

  local list_instance, list_error = list.new(vim.tbl_extend("force", config.layout.list or {}, {
    cursor_debounce_delay = config.preview_debounce,
    repository_renderer = config.repository_renderer,
    keymaps_applier = keymaps.make_keymaps_for_list(instance),
    keymaps_applier_install = keymaps.make_keymaps_for_install(instance),
    get_install_context = function()
      return {
        repository = instance.state.current_repository,
        install_catalogue = instance.state.install_catalogue,
        plugin_manager_mode = instance.state.plugin_manager_mode,
      }
    end,
    on_repo = function(repository)
      event_handlers.on_repo_selected(instance, repository)
    end,
    on_tab_change = function()
      if instance.layout_provider then
        instance.layout_provider:update_winbar(instance.list, instance.preview)
      end
    end,
  }))
  if list_error then
    return nil, "Failed to create list component: " .. list_error
  end
  instance.list = list_instance

  instance.layout_provider = layout.create(config.layout_mode or "modal")

  setmetatable(instance, StoreModal)
  return instance, nil
end

function StoreModal:open()
  local open_error = self.layout_provider:open(self.heading, self.list, self.preview)
  if open_error then
    logger.warn("Failed to open layout: " .. open_error)
    return
  end

  -- Focus the list component by default
  local focus_error = self.list:focus()
  if focus_error then
    logger.warn("Failed to focus list component: " .. focus_error)
    return
  end

  -- update state after all components successfully opened
  self.state.current_focus = self.list:get_window_id()

  -- listen for events
  table.insert(self.state.autocmds, event_listeners.listen_for_focus_change(self))
  table.insert(self.state.autocmds, event_listeners.listen_for_resize(self))
  event_listeners.listen_for_window_close(self) -- will close itself on proc

  -- Concurrently fetch plugins data and installed plugins
  database.fetch_plugins(function(data, err)
    event_handlers.on_db(self, data, err)
  end)

  -- Concurrently fetch installed plugins
  utils.get_installed_plugins(
    { preferred_manager = self.config.plugin_manager },
    function(installed_data, mode, installed_err, overview)
      event_handlers.on_installed_plugins(self, installed_data, mode, installed_err, overview)
    end
  )

  -- Concurrently fetch download stats from telemetry (both periods)
  telemetry.fetch_stats("month", function(data, err)
    event_handlers.on_stats(self, "month", data, err)
  end)
  telemetry.fetch_stats("week", function(data, err)
    event_handlers.on_stats(self, "week", data, err)
  end)
end

function StoreModal:close()
  self.state.is_closing = true

  -- close listeners
  for _, autocmd_id in pairs(self.state.autocmds) do
    vim.api.nvim_del_autocmd(autocmd_id)
  end

  self.layout_provider:close(self.heading, self.list, self.preview)

  if self.config.on_close then
    self.config.on_close()
  end
end

return M
