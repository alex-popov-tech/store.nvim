local curl = require("store.plenary.curl")
local http_cache = require("store.database.http_cache")
local net = require("store.database.net")
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
  -- the network is latched offline: do not even start the POST - a doomed
  -- curl per event is exactly the exit_code=56 spam this must not be
  if net.is_offline() then
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
      -- fire-and-forget: a failed POST (offline, most often) must be
      -- silent - it is not an error the user can act on, and without a
      -- handler here the curl wrapper raises from the job callback
      on_error = function(e)
        -- the first network-level failure latches offline: the events
        -- that follow in this session skip their curls entirely
        net.mark_offline(e and e.message)
      end,
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
  -- the stats ride the http cache too: served from disk while fresh, one
  -- conditional request when stale, the cached numbers shown offline
  http_cache.get(url, { ttl = (require("store.config").get().cache or {}).update_interval or 1800 }, function(body, err)
    if err then
      callback(nil, err)
      return
    end
    local success, data = pcall(vim.json.decode, body)
    if not success then
      callback(nil, "Failed to parse stats JSON: " .. tostring(data))
      return
    end
    callback(data, nil)
  end)
end

return M
