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

  modal.state.repos = data.items or {}
  modal.state.installable_count = data.meta.installable_count or 0

  -- make full copy, so mutational actions like sorting won't affect the original
  modal.state.currently_displayed_repos = vim.tbl_extend("force", {}, modal.state.repos)
  modal.state.current_installable_count = modal.state.installable_count

  -- Update list component configuration using public API
  modal.list:update_config({
    max_lengths = {
      author = math.min(data.meta.max_author_length or modal.config.author_limit, modal.config.author_limit),
      name = math.min(data.meta.max_name_length or modal.config.name_limit, modal.config.name_limit),
      full_name = math.min(
        data.meta.max_full_name_length or modal.config.full_name_limit,
        modal.config.full_name_limit
      ),
      pretty_stargazers_count = data.meta.max_pretty_stargazers_length or 8,
      pretty_forks_count = data.meta.max_pretty_forks_length or 8,
      pretty_open_issues_count = data.meta.max_pretty_issues_length or 8,
      pretty_pushed_at = 13 + (data.meta.max_pretty_pushed_at_length or 14),
    },
  })
  modal.list:render({ state = "ready", items = modal.state.currently_displayed_repos })

  modal.heading:render({
    state = "ready",
    filtered_count = data.meta.total_count,
    total_count = data.meta.total_count,
    installable_count = modal.state.current_installable_count,
    installed_count = 0, -- Will be updated when installed plugins data loads
  })

  logger.debug("Plugin data loaded successfully: " .. tostring(data.meta.total_count) .. " repositories")
end

---Handle installed plugins data response from database fetch
---@param modal StoreModal The modal instance
---@param installed_data table|nil Installed plugins data
---@param installed_err string|nil Error message if fetch failed
function M.on_installed_plugins(modal, installed_data, installed_err)
  if installed_err then
    logger.error("Failed to fetch installed plugins: " .. installed_err)
    -- Don't fail the entire modal, just continue without installed info
    return
  end

  logger.debug("Installed plugins loaded successfully: " .. vim.tbl_count(installed_data) .. " plugins")

  -- Store installed plugins data in modal state
  modal.state.installed_items = installed_data or {}

  -- Calculate total installed count from ALL installed plugins (static)
  local total_installed_count = 0
  for _ in pairs(modal.state.installed_items) do
    total_installed_count = total_installed_count + 1
  end
  modal.state.total_installed_count = total_installed_count

  -- Update heading with counts
  modal.heading:render({
    installable_count = modal.state.current_installable_count,
    installed_count = modal.state.total_installed_count,
  })

  -- Update list component with installed plugins data
  modal.list:render({
    installed_items = installed_data,
  })
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
