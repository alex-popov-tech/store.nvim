local logger = require("store.logger").createLogger({ context = "keymaps" })

local M = {}

-- Action labels for help display and descriptions
local labels = {
  close = "Close the modal",
  filter = "Filter repositories",
  help = "Show help",
  reset = "Reset plugin data",
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
local function get_handler(name)
  local actions = require("store.actions")
  local handlers = {
    close = actions.close,
    filter = actions.filter,
    help = actions.help,
    open = actions.open,
    switch_focus = actions.switch_focus,
    sort = actions.sort,
    install = actions.install,
    reset = actions.reset,
  }
  return handlers[name]
end

-- Private function to create keymap applier for specific actions
---@param instance StoreModal Modal instance
---@param actions string[] List of action names to apply
---@return fun(buf_id: number) Function to apply keymaps to buffer
local function make_keymaps_for_actions(instance, actions)
  return function(buf_id)
    local config = instance.config

    for _, action in ipairs(actions) do
      local keys = config.keybindings[action]
      local handler = get_handler(action)

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
    { "close", "help", "switch_focus", "filter", "reset", "sort", "open", "install" }
  )
end

-- Public function to create keymap applier for preview component
---@param instance StoreModal Modal instance
---@return fun(buf_id: number) Function to apply preview keymaps to buffer
function M.make_keymaps_for_preview(instance)
  return make_keymaps_for_actions(instance, { "close", "help", "switch_focus", "filter", "reset", "sort", "install" })
end

return M
