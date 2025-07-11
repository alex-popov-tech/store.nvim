local WindowManager = {}

---@class WindowManager
---@field windows table<number, string> Map of window IDs to component names
---@field augroup number Autocmd group ID for cleanup
---@field is_closing boolean Flag to prevent recursive closing

---Create a new WindowManager instance
---@return WindowManager
function WindowManager:new()
  local instance = {
    windows = {},
    augroup = vim.api.nvim_create_augroup("StoreWindowManager", { clear = true }),
    is_closing = false,
  }
  return setmetatable(instance, { __index = self })
end

---Register a window for coordinated closing
---@param win_id number Window ID to register
---@param component_name string Name of the component (for debugging)
function WindowManager:register_window(win_id, component_name)
  if not win_id or not vim.api.nvim_win_is_valid(win_id) then
    return
  end

  self.windows[win_id] = component_name

  -- Set up WinClosed autocmd for this window
  vim.api.nvim_create_autocmd("WinClosed", {
    group = self.augroup,
    once = true,
    pattern = tostring(win_id),
    callback = function()
      self:close_all_windows(win_id)
    end,
  })
end

---Close all registered windows when one is closed
---@param closed_win_id number The window ID that was closed
function WindowManager:close_all_windows(closed_win_id)
  if self.is_closing then
    return
  end

  self.is_closing = true

  -- Close all other registered windows
  for win_id, component_name in pairs(self.windows) do
    if win_id ~= closed_win_id and vim.api.nvim_win_is_valid(win_id) then
      vim.api.nvim_win_close(win_id, true)
    end
  end

  -- Clean up and reset
  self:cleanup()
end

---Clean up all resources
function WindowManager:cleanup()
  if self.augroup then
    vim.api.nvim_del_augroup_by_id(self.augroup)
  end
  self.windows = {}
  self.is_closing = false
end

return WindowManager
