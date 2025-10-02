local help = require("store.ui.help")
local event_handlers = require("store.ui.store_modal.event_handlers")
local database = require("store.database")
local sort = require("store.sort")
local filter = require("store.ui.filter")
local sort_select = require("store.ui.sort_select")
local plugin_utils = require("store.utils")
local utils = require("store.ui.store_modal.utils")
local logger = require("store.logger").createLogger({ context = "actions" })

local M = {}

---@param instance StoreModal instance of main modal
---@return string|nil error in case of failure
function M.close(instance)
  logger.debug("Action: close")
  local err = instance:close()
  if err then
    return err
  end
end

---@param instance StoreModal instance of main modal
---@return string|nil error in case of failure
function M.filter(instance)
  logger.info("Opening filter")
  local previous_focus = instance.state.current_focus

  local filter_component, error_msg = filter.new(vim.tbl_extend("force", instance.config.layout.filter, {
    current_query = instance.state.filter_query or "",
    on_value = function(query)
      -- there are 5 cases possible:
      -- 0. filter not changed - do nothing
      -- 1. filter is empty - DB data + sorting
      -- 2. filter is non-empty - apply filtering on DB data + sorting

      -- case 0
      if instance.state.filter_query == query then
        return
      end

      logger.debug("Applying filter: " .. query)

      -- case 1
      if query == "" then
        logger.debug("Filter cleared, showing all " .. #instance.state.repos .. " repositories")
        instance.state.currently_displayed_repos = vim.tbl_extend("force", {}, instance.state.repos)
        -- sort only if custom sort
        if instance.state.sort_config.type ~= "default" then
          logger.debug("Sorting " .. #instance.state.currently_displayed_repos .. " filtered repositories")
          local err = utils.sort(
            instance.state.currently_displayed_repos,
            instance.state.installed_items,
            instance.state.sort_config.type
          )
          if err ~= nil then
            logger.warn("Cannot sort repositories: " .. err)
            return
          end
        end
      end

      if query ~= "" then
        logger.debug("Filter is non-empty, applying filtering on " .. #instance.state.repos .. " repositories")
        local filtered, error = utils.filter(instance.state.repos, query)
        if error ~= nil then
          logger.error("Failed to filter repositories: " .. error)
          return
        end
        instance.state.currently_displayed_repos = filtered
      end
      instance.state.filter_query = query

      local error = instance.heading:render({
        filter_query = instance.state.filter_query,
        filtered_count = #instance.state.currently_displayed_repos,
      })
      if error ~= nil then
        logger.warn("Failed to re-render heading after filter: " .. error)
      end

      error = instance.list:render({ items = instance.state.currently_displayed_repos })
      if error ~= nil then
        logger.warn("Failed to re-render list after filter: " .. error)
      end
    end,
    on_exit = function()
      -- Restore focus to previous component
      if instance.list:get_window_id() == previous_focus then
        instance.list:focus()
      elseif instance.preview:get_window_id() == previous_focus then
        instance.preview:focus()
      end
    end,
  }))

  if error_msg then
    logger.warn("Failed to create filter component: " .. error_msg)
    return
  end
  logger.debug("Filter component created successfully")

  local open_error = filter_component:open()
  if open_error then
    logger.warn("Failed to open filter component: " .. open_error)
  end
end

function M.help(instance)
  logger.debug("Action: help")
  logger.info("Opening help")

  -- Store current focus for restoration
  local previous_focus = instance.state.current_focus
  -- Use centralized layout calculations
  local help_layout = instance.config.layout.help

  help.open({
    layout = help_layout,
    keybindings = instance.config.keybindings,
    on_exit = function()
      -- Restore focus after closing help
      if previous_focus == "list" then
        instance.list:focus()
      elseif previous_focus == "preview" then
        instance.preview:focus()
      end
    end,
  })
end

function M.open(instance)
  logger.debug("Action: open repository")
  if not instance.state.current_repository or not instance.state.current_repository.url then
    logger.warn("No repository selected")
    return
  end

  local error = plugin_utils.open_url(instance.state.current_repository.url)
  if error then
    logger.warn("Failed to open URL: " .. instance.state.current_repository.url)
  else
    logger.info("Opened repository: " .. instance.state.current_repository.full_name)
  end
end

function M.switch_focus(instance)
  logger.debug("Action: switch focus from " .. instance.state.current_focus)
  if instance.list:get_window_id() == instance.state.current_focus then
    instance.preview:focus()
    instance.state.current_focus = instance.preview:get_window_id()
    return
  end
  if instance.preview:get_window_id() == instance.state.current_focus then
    instance.preview:save_cursor_on_blur()
    instance.list:focus()
    instance.state.current_focus = instance.list:get_window_id()
    return
  end
  logger.warn("Unknown focus: " .. instance.state.current_focus)
end

function M.sort(instance)
  logger.debug("Action: sort")
  local previous_focus = instance.state.current_focus

  local sort_layout = instance.config.layout.sort

  local sort_component, error_msg = sort_select.new({
    width = sort_layout.width,
    height = sort_layout.height,
    row = sort_layout.row,
    col = sort_layout.col,
    current_sort = instance.state.sort_config.type,
    on_value = function(selected_sort)
      -- there are 5 cases possible:
      -- 0. sort not changed - do nothing
      -- 1. no filter + default sort = use db data
      -- 2. filter + default sort = filter db data
      -- 3. no filter + custom sort = sort curr filtered list
      -- 4. filter + custom sort = sort curr filtered list

      -- case 0
      if instance.state.sort_config.type == selected_sort then
        return
      end

      logger.debug("Applying sort: " .. selected_sort)

      -- case 1
      if selected_sort == "default" and instance.state.filter_query == "" then
        instance.state.currently_displayed_repos = vim.tbl_extend("force", {}, instance.state.repos)
      end

      -- case 2
      if selected_sort == "default" and instance.state.filter_query ~= "" then
        local filtered, err = utils.filter(instance.state.repos, instance.state.filter_query)
        if err ~= nil then
          logger.error("Failed to filter repositories: " .. err)
          return
        end
        instance.state.currently_displayed_repos = filtered
      end

      -- case 3, 4
      if selected_sort ~= "default" then
        logger.debug("Sorting " .. #instance.state.currently_displayed_repos .. " filtered(?) repositories")
        local sorting = sort.sorts[selected_sort]
        if not sorting then
          logger.warn("Unknown sort type: " .. selected_sort)
          return
        end
        table.sort(instance.state.currently_displayed_repos, function(a, b)
          return sorting.fn(a, b, instance.state.installed_items)
        end)
      end

      instance.state.sort_config.type = selected_sort

      -- re-render components
      local heading_error = instance.heading:render({ sort_type = selected_sort })
      if heading_error ~= nil then
        logger.warn("Failed to render heading after sort: " .. heading_error)
      end

      local list_error = instance.list:render({
        items = instance.state.currently_displayed_repos,
      })
      if list_error ~= nil then
        logger.warn("Failed to render heading after sort: " .. heading_error)
      end
      logger.debug("Sort operation completed")
    end,
    on_exit = function()
      -- Restore focus
      if instance.list:get_window_id() == previous_focus then
        instance.list:focus()
      elseif instance.preview:get_window_id() == previous_focus then
        instance.preview:focus()
      end
    end,
  })

  if error_msg then
    logger.warn("Failed to create sort component: " .. error_msg)
    return
  end

  local open_error = sort_component:open()
  if open_error then
    logger.warn("Failed to open sort component: " .. open_error)
  end
end

function M.install(instance)
  logger.debug("Action: install")
  local repo = instance.state.current_repository
  if not repo then
    logger.warn("No repository selected")
    return
  end

  local manager = instance.state.plugin_manager_mode
  if not manager or manager == "" then
    logger.warn("Plugin manager not detected; cannot prepare install snippet")
    vim.notify("store.nvim: Could not determine plugin manager for installation", vim.log.levels.WARN)
    return
  end

  local catalogue = instance.state.install_catalogue
  if not catalogue or type(catalogue) ~= "table" then
    local message = "Install catalogue is not available for " .. manager
    logger.warn(message)
    vim.notify("store.nvim: " .. message, vim.log.levels.WARN)
    return
  end

  local snippet = catalogue[repo.full_name]
  if not snippet then
    local message = "Install snippet not available for " .. repo.full_name .. " (" .. manager .. ")"
    logger.warn(message)
    vim.notify("store.nvim: " .. message, vim.log.levels.WARN)
    return
  end

  -- Phase 1: Show confirmation popup
  local install_modal = require("store.ui.install_modal")
  local component, err = install_modal.new({
    repository = repo,
    snippet = snippet,
    on_confirm = function(data)
      -- Use the edited configuration and filepath from the popup
      local filepath = vim.fn.expand(data.filepath)
      local dir = vim.fn.fnamemodify(filepath, ":h")
      local filename = vim.fn.fnamemodify(filepath, ":t")

      local file_exists = vim.fn.filereadable(filepath) == 1

      -- Handle existing file - append strategy
      if file_exists then
        local file = io.open(filepath, "a")
        if not file then
          logger.error("Failed to open existing file for append: " .. filepath)
          return
        end

        file:write("\n\n-- Plugin: " .. repo.full_name .. "\n")
        file:write("-- Added by store.nvim on " .. os.date("%Y-%m-%d %H:%M:%S") .. "\n")
        file:write(data.config)
        file:close()

        logger.info("Plugin appended: " .. repo.full_name .. " to " .. filepath)
        vim.notify("Plugin '" .. repo.full_name .. "' appended to " .. filename)
        if manager == "lazy.nvim" then
          vim.notify("Run :Lazy sync to complete installation")
        else
          vim.notify("Restart Neovim or re-source your config to load vim.pack changes")
        end
        return
      end

      -- Handle new file - create strategy
      if vim.fn.isdirectory(dir) == 0 then
        vim.fn.mkdir(dir, "p")
      end

      local file = io.open(filepath, "w")
      if not file then
        logger.error("Failed to create plugin file: " .. filepath)
        return
      end

      file:write("-- Plugin: " .. repo.full_name .. "\n")
      file:write("-- Installed via store.nvim\n")
      file:write("\n")
      file:write(data.config)
      file:close()

      logger.info("Plugin installed: " .. repo.full_name .. " at " .. filepath)
      vim.notify("Plugin '" .. repo.full_name .. "' configuration created at " .. filepath)
      if manager == "lazy.nvim" then
        vim.notify("Run :Lazy sync to complete installation")
      else
        vim.notify("Restart Neovim or re-source your config to load vim.pack changes")
      end
    end,
    on_cancel = function()
      logger.info("Installation cancelled")
    end,
  })

  if err then
    logger.warn("Failed to create confirm install component: " .. err)
    return
  end

  local open_err = component:open()
  if open_err then
    logger.warn("Failed to open confirm install popup: " .. open_err)
  end
end

function M.reset(instance)
  logger.info("Refreshing plugin database")

  instance.heading:render({ state = "loading" })
  instance.list:render({ state = "loading" })
  instance.preview:render({ state = "loading" })

  local err = database.clear()
  if err ~= nil then
    logger.warn("Failed to clear database: " .. err)
  end

  -- Concurrently fetch plugins data and installed plugins
  database.fetch_plugins(function(data, err)
    event_handlers.on_db(instance, data, err)
  end)

  -- Concurrently fetch installed plugins
  plugin_utils.get_installed_plugins(function(installed_data, mode, installed_err)
    event_handlers.on_installed_plugins(instance, installed_data, mode, installed_err)
  end)
end

function M.hover(instance)
  logger.debug("Action: hover")
  local repo = instance.state.current_repository
  if not repo then
    logger.warn("No repository selected for hover")
    return
  end

  local hover = require("store.ui.hover")
  local component, err = hover.new({ repository = repo })
  if err then
    logger.warn("Failed to create hover component: " .. err)
    return
  end

  local show_err = component:show()
  if show_err then
    logger.warn("Failed to show hover component: " .. show_err)
  else
    logger.debug("Hover displayed for repository: " .. repo.full_name)
  end
end

return M
