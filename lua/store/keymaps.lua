local logger = require("store.logger")
local utils = require("store.utils")

local M = {}

-- Action descriptions for better fuzzy finder integration
local descriptions = {
  close = "store.nvim - Close the modal",
  filter = "store.nvim - Filter repositories",
  help = "store.nvim - Show help",
  refresh = "store.nvim - Refresh plugin data",
  open = "store.nvim - Open repository in browser",
  switch_focus = "store.nvim - Switch focus between panes",
  sort = "store.nvim - Sort repositories",
}

-- Handler functions for each action
local handlers = {
  close = function(instance)
    instance:close()
    if instance.config.on_close then
      instance.config.on_close()
    end
  end,

  filter = function(instance)
    vim.ui.input({ prompt = "Filter repositories: ", default = instance.state.filter_query }, function(input)
      if input ~= nil then
        -- Update filter query in state
        instance.state.filter_query = input

        logger.debug("Filter query updated: '" .. input .. "'")

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
        })

        -- Re-render list with filtered results
        instance.list:render({
          state = "ready",
          items = instance.state.filtered_repos,
        })
      end
    end)
  end,

  help = function(instance)
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

    sort_select.open({
      current_sort = instance.state.sort_config.type,
      on_value = function(selected_sort)
        if selected_sort ~= instance.state.sort_config.type then
          instance:apply_sort(selected_sort)
        end
      end,
      on_exit = function()
        -- Restore focus
        if previous_focus == "list" then
          instance.list:focus()
        elseif previous_focus == "preview" then
          instance.preview:focus()
        end
      end,
    })
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
  return make_keymaps_for_actions(instance, { "close", "help", "switch_focus", "filter", "refresh", "sort", "open" })
end

-- Public function to create keymap applier for preview component
---@param instance StoreModal Modal instance
---@return fun(buf_id: number) Function to apply preview keymaps to buffer
function M.make_keymaps_for_preview(instance)
  return make_keymaps_for_actions(instance, { "close", "help", "switch_focus", "filter", "refresh", "sort" })
end

return M
