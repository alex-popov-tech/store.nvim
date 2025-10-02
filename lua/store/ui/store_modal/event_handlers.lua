local config = require("store.config")
local database = require("store.database")
local validators = require("store.ui.store_modal.validators")
local logger = require("store.logger").createLogger({ context = "modal_event_handlers" })

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
    plugin_manager_mode = modal.state.plugin_manager_mode or "",
  })

  logger.debug("Plugin data loaded successfully: " .. tostring(total_count) .. " repositories")
end

---Handle installed plugins data response from database fetch
---@param modal StoreModal The modal instance
---@param installed_data table|nil Installed plugins data
---@param mode string|nil Plugin manager mode ("lazy.nvim" or "vim.pack")
---@param installed_err string|nil Error message if fetch failed
function M.on_installed_plugins(modal, installed_data, mode, installed_err)
  if installed_err then
    vim.notify("[store.nvim] Failed to fetch installed plugins: " .. installed_err .. "\nInstallation is not available")
    -- Don't fail the entire modal, just continue without installed info
    return
  end

  -- Store installed plugins data in modal state
  modal.state.installed_items = installed_data or {}
  local installed_count = vim.tbl_count(installed_data or {})
  modal.state.total_installed_count = installed_count
  modal.state.plugin_manager_mode = mode or ""

  -- Update heading with counts and plugin manager mode
  modal.heading:render({ installed_count = installed_count, plugin_manager_mode = mode, state = "ready" })

  -- Update list component with installed plugins data
  modal.list:render({
    installed_items = installed_data,
  })

  if mode and mode ~= "" then
    if modal.state.install_catalogue_manager ~= mode or not modal.state.install_catalogue then
      modal.state.install_catalogue_manager = mode

      database.fetch_install_catalogue(mode, function(catalogue, catalogue_err)
        if catalogue_err then
          logger.error(
            "Failed to load install catalogue for "
              .. mode
              .. ": "
              .. catalogue_err
              .. "\nInstallation is not available"
          )
          return
        end

        local items = (catalogue and catalogue.items) or {}
        modal.state.install_catalogue = items
        logger.debug(string.format("Install catalogue ready for %s with %d entries", mode, vim.tbl_count(items)))
      end)
    end
  else
    modal.state.install_catalogue = nil
    modal.state.install_catalogue_manager = nil
  end
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
