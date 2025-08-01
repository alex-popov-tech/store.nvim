local logger = require("store.logger")
local utils = require("store.utils")

local M = {}

-- Action labels for help display and descriptions
local labels = {
  close = "Close the modal",
  filter = "Filter repositories",
  help = "Show help",
  refresh = "Refresh plugin data",
  open = "Open repository in browser",
  switch_focus = "Switch focus between panes",
  sort = "Sort repositories",
  install = "Install plugin to lazy.nvim",
}

-- Get label for an action
---@param action string Action name
---@return string|nil Label for the action
function M.get_label(action)
  return labels[action]
end

-- Action descriptions for better fuzzy finder integration
local descriptions = {}
for action, label in pairs(labels) do
  descriptions[action] = "store.nvim - " .. label
end

-- Handler functions for each action
local handlers = {
  close = function(instance)
    instance:close()
    if instance.config.on_close then
      instance.config.on_close()
    end
  end,

  filter = function(instance)
    local filter = require("store.ui.filter")

    -- Store current focus for restoration
    local previous_focus = instance.state.current_focus

    -- Use centralized layout calculations
    local filter_layout = instance.config.layout.filter

    local filter_component, error_msg = filter.new({
      width = filter_layout.width,
      height = filter_layout.height,
      row = filter_layout.row,
      col = filter_layout.col,
      current_query = instance.state.filter_query or "",
      on_value = function(query)
        -- Update filter query in state
        instance.state.filter_query = query

        logger.debug("Filter query updated: '" .. query .. "'")

        -- Apply filter and re-sort using existing method
        instance:_apply_filter()

        logger.debug(
          "Filter applied: "
            .. #instance.state.filtered_repos
            .. " of "
            .. #instance.state.repos
            .. " repositories match"
        )

        -- Update heading with new filter stats
        instance.heading:render({
          filter_query = instance.state.filter_query,
          sort_type = instance.state.sort_config.type,
          state = "ready",
          filtered_count = #instance.state.filtered_repos,
          total_count = #instance.state.repos,
          installable_count = instance.state.current_installable_count,
          installed_count = instance.state.total_installed_count,
        })

        -- Re-render list with filtered results
        instance.list:render({
          state = "ready",
          items = instance.state.filtered_repos,
        })

        -- Restore focus to previous component
        vim.cmd("stopinsert")
        if previous_focus == "list" then
          instance.list:focus()
        elseif previous_focus == "preview" then
          instance.preview:focus()
        end
      end,
      on_exit = function()
        -- Restore focus to previous component
        vim.cmd("stopinsert")
        if previous_focus == "list" then
          instance.list:focus()
        elseif previous_focus == "preview" then
          instance.preview:focus()
        end
      end,
    })

    if error_msg then
      logger.error("Failed to create filter component: " .. error_msg)
      return
    end

    local open_error = filter_component:open()
    if open_error then
      logger.error("Failed to open filter component: " .. open_error)
    end
  end,

  help = function(instance)
    local help = require("store.ui.help")

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
  end,

  refresh = function(instance)
    instance:refresh()
  end,

  open = function(instance)
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

  switch_focus = function(instance)
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

  sort = function(instance)
    local sort_select = require("store.ui.sort_select")

    -- Store current focus for restoration
    local previous_focus = instance.state.current_focus

    -- Use centralized layout calculations
    local sort_layout = instance.config.layout.sort

    local sort_component, error_msg = sort_select.new({
      width = sort_layout.width,
      height = sort_layout.height,
      row = sort_layout.row,
      col = sort_layout.col,
      current_sort = instance.state.sort_config.type,
      on_value = function(selected_sort)
        if selected_sort ~= instance.state.sort_config.type then
          instance:apply_sort(selected_sort)
        end
      end,
      on_exit = function()
        -- Restore focus
        vim.cmd("stopinsert")
        if previous_focus == "list" then
          instance.list:focus()
        elseif previous_focus == "preview" then
          instance.preview:focus()
        end
      end,
    })

    if error_msg then
      logger.error("Failed to create sort component: " .. error_msg)
      return
    end

    local open_error = sort_component:open()
    if open_error then
      logger.error("Failed to open sort component: " .. open_error)
    end
  end,

  install = function(instance)
    local repo = instance.state.current_repository
    if not repo then
      logger.warn("No repository selected")
      return
    end

    if not repo.install or not repo.install.lazyConfig or repo.install.lazyConfig == "" then
      logger.warn("Plugin '" .. repo.full_name .. "' is not installable")
      return
    end

    -- Phase 1: Show confirmation popup
    local confirm_install = require("store.ui.confirm_install")
    local component, err = confirm_install.new({
      repository = repo,
      on_confirm = function(edited_config)
        -- Use the edited configuration from the popup
        local filename = repo.name .. ".lua"
        local config_dir = vim.fn.stdpath("config")
        local plugins_dir = config_dir .. "/lua/plugins"
        local filepath = plugins_dir .. "/" .. filename

        if vim.fn.filereadable(filepath) == 1 then
          logger.warn("Plugin file '" .. filename .. "' already exists")
          return
        end

        if vim.fn.isdirectory(plugins_dir) == 0 then
          vim.fn.mkdir(plugins_dir, "p")
        end

        local file = io.open(filepath, "w")
        if not file then
          logger.error("Failed to create plugin file: " .. filepath)
          return
        end

        file:write("-- Plugin: " .. repo.full_name .. "\n")
        file:write("-- Installed via store.nvim\n")
        file:write("\n")

        -- Write the edited configuration directly (it already has return prefix)
        file:write(edited_config)
        file:close()

        vim.notify("Plugin '" .. repo.full_name .. "' configuration created at " .. filename)
        vim.notify("Run :Lazy sync to complete installation")
      end,
      on_cancel = function()
        logger.debug("Installation cancelled")
      end,
    })

    if err then
      logger.error("Failed to create confirm install component: " .. err)
      return
    end

    local open_err = component:open()
    if open_err then
      logger.error("Failed to open confirm install popup: " .. open_err)
    end
  end,
}

-- Private function to create keymap applier for specific actions
---@param instance StoreModal Modal instance
---@param actions string[] List of action names to apply
---@return fun(buf_id: number) Function to apply keymaps to buffer
local function make_keymaps_for_actions(instance, actions)
  return function(buf_id)
    local config = instance.config

    for _, action in ipairs(actions) do
      local keys = config.keybindings[action]
      local handler = handlers[action]

      for _, key in ipairs(keys) do
        vim.keymap.set("n", key, function()
          local success, err = pcall(handler, instance)
          if not success then
            logger.error("Keymap handler error for " .. action .. " on key " .. key .. ": " .. tostring(err))
          end
        end, {
          buffer = buf_id,
          desc = descriptions[action] or ("store.nvim - " .. action),
          silent = true,
          nowait = true,
        })
      end
    end
  end
end

-- Public function to create keymap applier for list component
---@param instance StoreModal Modal instance
---@return fun(buf_id: number) Function to apply list keymaps to buffer
function M.make_keymaps_for_list(instance)
  return make_keymaps_for_actions(
    instance,
    { "close", "help", "switch_focus", "filter", "refresh", "sort", "open", "install" }
  )
end

-- Public function to create keymap applier for preview component
---@param instance StoreModal Modal instance
---@return fun(buf_id: number) Function to apply preview keymaps to buffer
function M.make_keymaps_for_preview(instance)
  return make_keymaps_for_actions(instance, { "close", "help", "switch_focus", "filter", "refresh", "sort" })
end

return M
