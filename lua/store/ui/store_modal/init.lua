local database = require("store.database")
local validators = require("store.ui.store_modal.validators")
local event_handlers = require("store.ui.store_modal.event_handlers")
local event_listeners = require("store.ui.store_modal.event_listeners")
local heading = require("store.ui.heading")
local list = require("store.ui.list")
local preview = require("store.ui.preview")
local keymaps = require("store.keymaps")
local utils = require("store.utils")
local logger = require("store.logger").createLogger({ context = "modal" })

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
        type = "default", -- Current sort type
      },
      repos = {},
      currently_displayed_repos = {},

      total_installed_count = 0, -- Total installed plugins from lock file (static)
      installed_items = {}, -- Lookup table of installed plugin names for O(1) checks
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

  local heading_instance, heading_error = heading.new(vim.tbl_extend("force", {}, config.layout.header))
  if heading_error then
    return nil, "Failed to create heading component: " .. heading_error
  end
  instance.heading = heading_instance

  local preview_instance, preview_error = preview.new(vim.tbl_extend("force", config.layout.preview, {
    keymaps_applier = keymaps.make_keymaps_for_preview(instance),
  }))
  if preview_error then
    return nil, "Failed to create preview component: " .. preview_error
  end
  instance.preview = preview_instance

  local list_instance, list_error = list.new(vim.tbl_extend("force", config.layout.list, {
    cursor_debounce_delay = config.preview_debounce,
    repository_renderer = config.repository_renderer,
    keymaps_applier = keymaps.make_keymaps_for_list(instance),
    on_repo = function(repository)
      event_handlers.on_repo_selected(instance, repository)
    end,
  }))
  if list_error then
    return nil, "Failed to create list component: " .. list_error
  end
  instance.list = list_instance

  setmetatable(instance, StoreModal)
  return instance, nil
end

function StoreModal:open()
  local heading_error = self.heading:open()
  if heading_error then
    logger.warn("Failed to open heading component: " .. heading_error)
    return
  end
  local list_error = self.list:open()
  if list_error then
    logger.warn("Failed to open list component: " .. list_error)
    return
  end
  local preview_error = self.preview:open()
  if preview_error then
    logger.warn("Failed to open preview component: " .. preview_error)
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

  -- telemetry: track store open
  if require("store.config").get().telemetry then
    pcall(function()
      require("store.plenary.curl").get("https://api.counterapi.dev/v1/oleksandr-popovs-team-2754/open-store/up", {
        timeout = 5000,
        callback = function(response)
          if response.status ~= 200 then
            logger.debug("telemetry: open-store failed: " .. response.status)
          end
        end,
      })
    end)
  end

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
end

function StoreModal:close()
  self.state.is_closing = true

  -- close listeners
  for _, autocmd_id in pairs(self.state.autocmds) do
    vim.api.nvim_del_autocmd(autocmd_id)
  end

  local error = self.heading:close()
  if error then
    logger.warn("Failed to close heading component: " .. error)
  end

  error = self.list:close()
  if error then
    logger.warn("Failed to close list component: " .. error)
  end

  error = self.preview:close()
  if error then
    logger.warn("Failed to close preview component: " .. error)
  end

  if self.config.on_close then
    self.config.on_close()
  end
end

return M
