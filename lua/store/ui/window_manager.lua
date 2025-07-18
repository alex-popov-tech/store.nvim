local logger = require("store.logger")
local WindowManager = {}

---@class WindowManager
---@field components table<number, {close: function, name: string}> Map of window IDs to component close methods
---@field augroup number Autocmd group ID for cleanup
---@field is_closing boolean Flag to prevent recursive closing
---@field on_modal_cleanup function|nil Callback for modal-level cleanup

---Create a new WindowManager instance
---@param on_modal_cleanup function|nil Optional callback for modal-level cleanup
---@return WindowManager
function WindowManager:new(on_modal_cleanup)
  local instance = {
    components = {},
    augroup = vim.api.nvim_create_augroup("StoreWindowManager", { clear = true }),
    is_closing = false,
    on_modal_cleanup = on_modal_cleanup,
  }
  return setmetatable(instance, { __index = self })
end

---Register a component for coordinated closing
---@param win_id number Window ID to monitor
---@param close_fn function Component's close method
---@param component_name string Name of the component (for logging)
function WindowManager:register_component(win_id, close_fn, component_name)
  if not win_id or not vim.api.nvim_win_is_valid(win_id) then
    return
  end

  self.components[win_id] = {
    close = close_fn,
    name = component_name,
  }

  -- Set up WinClosed autocmd for this window
  vim.api.nvim_create_autocmd("WinClosed", {
    group = self.augroup,
    once = true,
    pattern = tostring(win_id),
    callback = function()
      self:on_window_closed()
    end,
  })
end

---Handle when any monitored window is closed
function WindowManager:on_window_closed()
  if self.is_closing then
    return
  end

  self.is_closing = true

  logger.debug("Window closed, initiating graceful shutdown")

  -- Close all components with individual error handling
  for win_id, component in pairs(self.components) do
    local success, err = pcall(component.close)
    if not success then
      logger.error("Failed to close component " .. component.name .. ": " .. tostring(err))
    else
      logger.debug("Successfully closed component: " .. component.name)
    end
  end

  -- Call modal-level cleanup if provided
  if self.on_modal_cleanup then
    local success, err = pcall(self.on_modal_cleanup)
    if not success then
      logger.error("Failed modal cleanup: " .. tostring(err))
    else
      logger.debug("Modal cleanup completed successfully")
    end
  end

  self:cleanup()
end

---Clean up all resources
function WindowManager:cleanup()
  if self.augroup then
    vim.api.nvim_del_augroup_by_id(self.augroup)
  end
  self.components = {}
  self.is_closing = false
end

return WindowManager
