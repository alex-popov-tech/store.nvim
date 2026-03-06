local M = {}

---Fire-and-forget telemetry event
---@param event_type string "view" or "install"
---@param plugin_full_name string e.g. "nvim-telescope/telescope.nvim"
function M.track(event_type, plugin_full_name)
  if not require("store.config").get().telemetry then
    return
  end
  pcall(function()
    require("store.plenary.curl").post("https://store-nvim-telemetry.alex-popov-tech.workers.dev/events", {
      body = vim.json.encode({ event_type = event_type, plugin_full_name = plugin_full_name }),
      headers = { content_type = "application/json" },
      timeout = 5000,
      callback = function() end,
    })
  end)
end

return M
