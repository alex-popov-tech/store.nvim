local logger = require("store.logger").createLogger({ context = "keymaps" })

local M = {}

-- Action labels for help display and descriptions
local labels = {
  close = "Close the modal",
  filter = "Filter repositories",
  help = "Show help",
  reset = "Reset plugin data",
  open = "Open repository in browser",
  sort = "Sort repositories",
  hover = "Show repository details",
  switch_list = "Switch to List tab",
  switch_install = "Switch to Install tab",
  switch_readme = "Switch to Readme tab",
  switch_docs = "Switch to Docs tab",
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
    sort = actions.sort,
    reset = actions.reset,
    hover = actions.hover,
    switch_list = actions.switch_list,
    switch_install = actions.switch_install,
    switch_readme = actions.switch_readme,
    switch_docs = actions.switch_docs,
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

local ALL_TAB_ACTIONS = {
  "close",
  "help",
  "filter",
  "reset",
  "sort",
  "open",
  "hover",
  "switch_list",
  "switch_install",
  "switch_readme",
  "switch_docs",
}

-- Public function to create keymap applier for list component
---@param instance StoreModal Modal instance
---@return fun(buf_id: number) Function to apply list keymaps to buffer
function M.make_keymaps_for_list(instance)
  return make_keymaps_for_actions(instance, ALL_TAB_ACTIONS)
end

-- Public function to create keymap applier for preview component
---@param instance StoreModal Modal instance
---@return fun(buf_id: number) Function to apply preview keymaps to buffer
function M.make_keymaps_for_preview(instance)
  return make_keymaps_for_actions(instance, ALL_TAB_ACTIONS)
end

-- Public function to create keymap applier for install buffer
---@param instance StoreModal Modal instance
---@return fun(buf_id: number) Function to apply install keymaps to buffer
function M.make_keymaps_for_install(instance)
  return make_keymaps_for_actions(instance, ALL_TAB_ACTIONS)
end

-- Public function to create keymap applier for docs buffer
---@param instance StoreModal Modal instance
---@return fun(buf_id: number) Function to apply docs keymaps to buffer
function M.make_keymaps_for_docs(instance)
  return make_keymaps_for_actions(instance, ALL_TAB_ACTIONS)
end

return M
