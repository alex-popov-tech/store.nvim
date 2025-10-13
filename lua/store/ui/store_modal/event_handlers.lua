local config = require("store.config")
local database = require("store.database")
local validators = require("store.ui.store_modal.validators")
local logger = require("store.logger").createLogger({ context = "modal_event_handlers" })
local utils = require("store.utils")

local M = {}

---Handle plugins data response from database fetch
---@param modal StoreModal The modal instance
---@param data table|nil Plugin data from database
---@param err string|nil Error message if fetch failed
function M.on_db(modal, data, err)
  if err then
    logger.error("Failed to fetch plugin data: " .. err)
    modal.heading:render({ state = "error" })
    modal.list:render({ state = "error" })
    modal.preview:render({ state = "error", content = { err } })
    return
  end

  if not data then
    logger.error("No plugin data received from server")
    modal.heading:render({ state = "error" })
    modal.list:render({ state = "error" })
    modal.preview:render({ state = "error", content = { "No plugin data received from server" } })
    return
  end

  -- Use the items array from the new database schema
  local repos = data.items or {}
  local total_count = #repos

  modal.state.repos = repos
  -- make full copy, so mutational actions like sorting won't affect the original
  modal.state.currently_displayed_repos = vim.tbl_extend("force", {}, modal.state.repos)

  -- No need to update config - renderer function handles display limits internally
  modal.list:render({ state = "ready", items = modal.state.currently_displayed_repos })

  modal.heading:render({
    state = "ready",
    filtered_count = total_count,
    total_count = total_count,
    -- Preserve existing installed_count if already set, otherwise default to 0
    installed_count = modal.state.total_installed_count or 0,
    -- Preserve existing plugin_manager_mode if already set
    plugin_manager_mode = modal.state.plugin_manager_mode or "not-selected",
    plugin_manager_overview = modal.state.plugin_manager_overview or {},
  })

  logger.debug("Plugin data loaded successfully: " .. tostring(total_count) .. " repositories")
end

---Handle installed plugins data response from database fetch
---@param modal StoreModal The modal instance
---@param installed_data table|nil Installed plugins data for the active manager
---@param mode string|nil Selected plugin manager mode
---@param installed_err string|nil Error message if detection failed
---@param overview table|nil Summary of all detected managers
function M.on_installed_plugins(modal, installed_data, mode, installed_err, overview)
  local installed_lookup = installed_data or {}
  local plugin_overview = overview or {}
  local active_mode = mode or (modal.config.plugin_manager or "not-selected")

  if installed_err then
    if modal.config.plugin_manager and modal.config.plugin_manager ~= "not-selected" then
      local message = "Preferred plugin manager '"
        .. modal.config.plugin_manager
        .. "' is unavailable: "
        .. installed_err
      logger.error(message)
      utils.tryNotify("[store.nvim] " .. message, vim.log.levels.ERROR)
      if not modal.state.is_closing then
        modal:close()
      end
      return
    end

    utils.tryNotify("[store.nvim] " .. installed_err .. "\nInstallation is not available", vim.log.levels.ERROR)
    modal.state.installed_items = {}
    modal.state.total_installed_count = 0
    modal.state.plugin_manager_mode = "not-selected"
    modal.state.plugin_manager_overview = plugin_overview
    modal.state.install_catalogue = nil
    modal.state.install_catalogue_manager = nil

    modal.heading:render({
      state = "ready",
      installed_count = 0,
      plugin_manager_mode = "not-selected",
      plugin_manager_overview = plugin_overview,
    })

    modal.list:render({
      installed_items = {},
    })
    return
  end

  modal.state.installed_items = installed_lookup
  modal.state.total_installed_count = vim.tbl_count(installed_lookup)
  modal.state.plugin_manager_mode = active_mode
  modal.state.plugin_manager_overview = plugin_overview

  modal.heading:render({
    state = "ready",
    installed_count = modal.state.total_installed_count,
    plugin_manager_mode = active_mode,
    plugin_manager_overview = plugin_overview,
  })

  modal.list:render({
    installed_items = installed_lookup,
  })

  if active_mode and active_mode ~= "" and active_mode ~= "not-selected" then
    if modal.state.install_catalogue_manager ~= active_mode or not modal.state.install_catalogue then
      modal.state.install_catalogue_manager = active_mode

      database.fetch_install_catalogue(active_mode, function(catalogue, catalogue_err)
        if catalogue_err then
          logger.error(
            "Failed to load install catalogue for "
              .. active_mode
              .. ": "
              .. catalogue_err
              .. "\nInstallation is not available"
          )
          return
        end

        local items = (catalogue and catalogue.items) or {}
        modal.state.install_catalogue = items
        logger.debug(string.format("Install catalogue ready for %s with %d entries", active_mode, vim.tbl_count(items)))
      end)
    end
    return
  end

  modal.state.install_catalogue = nil
  modal.state.install_catalogue_manager = nil
end

---@param modal StoreModal
---@param repository Repository
function M.on_repo_selected(modal, repository)
  modal.state.current_repository = repository

  database.get_readme(repository, function(content, error)
    if error then
      local render_error = modal.preview:render({ state = "error", content = { error } })
      if render_error then
        logger.error("Failed to render preview error state: " .. render_error)
      end
      return
    end

    local render_error = modal.preview:render({ state = "ready", content = content, readme_id = repository.full_name })
    if render_error then
      logger.error("Failed to render preview ready state: " .. render_error)
    end
  end)
end

---Handle focus change events with validation and early returns
---@param modal StoreModal
function M.on_focus_change(modal)
  local focused_win = vim.api.nvim_get_current_win()
  -- mouse click on current component
  if focused_win == modal.state.current_focus then
    return
  end

  local list_win_id = modal.list:get_window_id()
  local preview_win_id = modal.preview:get_window_id()

  if focused_win ~= list_win_id and focused_win ~= preview_win_id then
    -- if focused outside of modal, do nothing
    logger.debug("Focus not on modal components")
    return
  end

  modal.state.current_focus = focused_win

  local current_proportions = config.get().proportions
  local new_proportions = {
    list = current_proportions.preview,
    preview = current_proportions.list,
  }
  local new_layout, layout_error = config.update_layout(new_proportions)
  if layout_error then
    logger.error("Failed to calculate new layout for focus: " .. (layout_error or "unknown error"))
    return
  end

  local error = modal.list:resize(new_layout.list)
  if error then
    logger.error("Failed to resize list component: " .. error)
    return
  end

  error = modal.preview:resize(new_layout.preview)
  if error then
    logger.error("Failed to resize preview component: " .. error)
    return
  end
end

---Handle terminal resize by recalculating layout and updating components
---@param modal StoreModal
function M.on_terminal_resize(modal)
  local screen_width, screen_height = vim.o.columns, vim.o.lines

  local err = validators.validate_screen_dimensions(screen_width, screen_height)
  if err then
    logger.warn("Resize failed: " .. err)
    return
  end

  local new_layout, layout_error = config.update_layout(config.get().proportions)
  if layout_error then
    logger.error("Failed to calculate new layout for resize: " .. (layout_error or "unknown error"))
    return
  end

  local heading_error = modal.heading:resize(new_layout.header)
  if heading_error then
    logger.error("Failed to resize heading: " .. heading_error)
    return
  end

  local list_error = modal.list:resize(new_layout.list)
  if list_error then
    logger.error("Failed to resize list: " .. heading_error)
    return
  end

  local preview_error = modal.preview:resize(new_layout.preview)
  if preview_error then
    logger.error("Failed to resize preview: " .. heading_error)
    return
  end
end

return M
