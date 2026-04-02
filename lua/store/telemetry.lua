local curl = require("store.plenary.curl")
local logger = require("store.utils").logger

local STATS_BASE_URL = "https://store-nvim-telemetry.alex-popov-tech.workers.dev/stats"

local M = {}

---@type table<string, true>
local viewed_plugins = {}
---@type table<string, true>
local installed_plugins = {}

---Fire-and-forget telemetry event (deduplicated per plugin per session)
---@param event_type string "view" or "install"
---@param plugin_full_name string e.g. "nvim-telescope/telescope.nvim"
function M.track(event_type, plugin_full_name)
  if not require("store.config").get().telemetry then
    return
  end
  local dedup_map = event_type == "view" and viewed_plugins or installed_plugins
  if dedup_map[plugin_full_name] then
    return
  end
  dedup_map[plugin_full_name] = true
  pcall(function()
    curl.post("https://store-nvim-telemetry.alex-popov-tech.workers.dev/events", {
      body = vim.json.encode({ event_type = event_type, plugin_full_name = plugin_full_name }),
      headers = { content_type = "application/json" },
      timeout = 5000,
      callback = function() end,
    })
  end)
end

---Fetch plugin install stats from telemetry API
---@param period string "month" or "week"
---@param callback fun(data: table|nil, error: string|nil) Callback with stats data or error
function M.fetch_stats(period, callback)
  if not require("store.config").get().telemetry then
    callback(nil, nil)
    return
  end
  local url = STATS_BASE_URL .. "?period=" .. period
  curl.get(url, {
    timeout = 10000,
    callback = function(response)
      if response.status ~= 200 then
        callback(nil, "Failed to fetch stats: HTTP " .. response.status .. " " .. (response.body or ""))
        return
      end
      local success, data = pcall(vim.json.decode, response.body)
      if not success then
        callback(nil, "Failed to parse stats JSON: " .. data)
        return
      end
      callback(data, nil)
    end,
  })
end

return M
