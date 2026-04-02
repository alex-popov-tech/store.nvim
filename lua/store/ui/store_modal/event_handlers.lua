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
  vim.schedule(function()
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
    modal.list:render({
      state = "ready",
      items = modal.state.currently_displayed_repos,
      sort_type = modal.state.sort_config.type,
      download_stats_monthly = modal.state.download_stats_monthly,
      view_stats_monthly = modal.state.view_stats_monthly,
    })

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

    if modal.layout_provider then
      modal.layout_provider:update_winbar(modal.list, modal.preview)
    end

    logger.debug("Plugin data loaded successfully: " .. tostring(total_count) .. " repositories")
  end)
end

---Handle installed plugins data response from database fetch
---@param modal StoreModal The modal instance
---@param installed_data table|nil Installed plugins data for the active manager
---@param mode string|nil Selected plugin manager mode
---@param installed_err string|nil Error message if detection failed
---@param overview table|nil Summary of all detected managers
function M.on_installed_plugins(modal, installed_data, mode, installed_err, overview)
  vim.schedule(function()
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
  end)
end

---Handle stats data response from telemetry API fetch
---@param modal StoreModal The modal instance
---@param period string "month" or "week"
---@param data table|nil Stats data: { installs: map<string,number>, views: map<string,number> }
---@param err string|nil Error message if fetch failed
function M.on_stats(modal, period, data, err)
  if err or not data or (not data.installs and not data.views) then
    logger.warn("Stats fetch failed or empty (" .. period .. "): " .. tostring(err))
    return
  end
  local suffix = period == "week" and "weekly" or "monthly"
  modal.state["download_stats_" .. suffix] = data.installs or {}
  modal.state["view_stats_" .. suffix] = data.views or {}
  logger.debug("Stats loaded (" .. period .. "): "
    .. vim.tbl_count(data.installs or {}) .. " installs, "
    .. vim.tbl_count(data.views or {}) .. " views")

  -- Re-render list if current sort depends on stats data
  local sort_type = modal.state.sort_config.type
  if sort_type == "most_downloads_monthly" or sort_type == "most_views_monthly" then
    vim.schedule(function()
      if modal.state.currently_displayed_repos and #modal.state.currently_displayed_repos > 0 then
        modal.list:render({
          items = modal.state.currently_displayed_repos,
          sort_type = sort_type,
          download_stats_monthly = modal.state.download_stats_monthly,
          view_stats_monthly = modal.state.view_stats_monthly,
        })
      end
    end)
  end
end

---@param modal StoreModal
---@param repository Repository
function M.on_repo_selected(modal, repository)
  modal.state.current_repository = repository
  require("store.telemetry").track("view", repository.full_name)

  -- Always reset to readme on plugin change (locked decision)
  modal.preview.state.doc_paths = repository.doc or {}
  modal.preview.state.doc_index = 0

  -- Switch to readme tab if not already there
  local active_tab = modal.preview:get_active_tab()
  if active_tab ~= "readme" then
    modal.preview:set_active_tab("readme")
  else
    -- Already on readme — still need to rebuild tab label with new doc_paths
    modal.preview:update_doc_label()
  end

  database.get_readme(repository, function(content, error)
    vim.schedule(function()
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
  end)
end

---Handle focus change events with validation and early returns
---@param modal StoreModal
function M.on_focus_change(modal)
  local focused_win = vim.api.nvim_get_current_win()

  -- In tab mode, redirect focus away from header split
  if modal.layout_provider.mode == "tab" and modal.layout_provider.header_win then
    if focused_win == modal.layout_provider.header_win then
      local target = modal.list:get_window_id() or modal.layout_provider.list_win
      if target and vim.api.nvim_win_is_valid(target) then
        pcall(vim.api.nvim_set_current_win, target)
      end
      return
    end
  end

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

  local error = modal.layout_provider:resize_content(modal.list, modal.preview, new_layout)
  if error then
    logger.error("Failed to resize content for focus: " .. error)
    return
  end

  modal.layout_provider:update_winbar(modal.list, modal.preview)
end

---Handle terminal resize by recalculating layout and updating components
---@param modal StoreModal
function M.on_terminal_resize(modal)
  local screen_width, screen_height = vim.o.columns, vim.o.lines

  local err = validators.validate_screen_dimensions(screen_width, screen_height)
  if err then
    logger.warn("Resize failed: " .. err)
    utils.tryNotify("[store.nvim] Terminal too small for Store modal. " .. err, vim.log.levels.WARN)
    if not modal.state.is_closing then
      modal:close()
    end
    return
  end

  local new_layout, layout_error = config.update_layout(config.get().proportions)
  if layout_error then
    logger.error("Failed to calculate new layout for resize: " .. (layout_error or "unknown error"))
    utils.tryNotify("[store.nvim] Terminal too small for Store modal. " .. layout_error, vim.log.levels.WARN)
    if not modal.state.is_closing then
      modal:close()
    end
    return
  end

  local resize_error = modal.layout_provider:resize(modal.heading, modal.list, modal.preview, new_layout)
  if resize_error then
    logger.error("Failed to resize layout: " .. resize_error)
    return
  end
end

return M
