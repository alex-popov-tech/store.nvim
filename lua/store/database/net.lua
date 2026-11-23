---@module "store.database.net"
---The network latch. When a request fails at the network level — curl
---cannot speak, the connection resets, the name does not resolve — the
---rest of the session should not keep trying: every preview of an
---uncached page would fire another doomed request, another error, another
---timeout. So the first failure latches "offline" for a short while
---(OFFLINE_COOLDOWN), and everything that is about to hit the network
---asks `is_offline()` first:
---   * a cached copy exists — it is served (stale is fine; the age
---     notice says so once);
---   * nothing is cached — the caller hears "not connected" right away,
---     no request at all: the preview shows the message instead of an
---     error.
---Any successful request unlatches. A `force` refresh (the explicit
---"try again") unlatches too — the user may have just plugged the cable
---back in, and they asked for it.

local M = {}

local OFFLINE_COOLDOWN = 60 -- seconds

local until_ = 0 ---@type number unix seconds; offline until then
local reason = nil ---@type string|nil
local noticed = false ---@type boolean kept for API compat; nothing notifies anymore

---Note that the network is down (or a specific endpoint unreachable in a
---way that looks like it). Idempotent within a cooldown window. The
---latch itself is silent: the store serves its cache without a word - a
---"not connected" notice on top of every offline view is noise, not
---information.
---@param why string|nil
function M.mark_offline(why)
  local now = os.time()
  reason = why or reason
  if now < until_ then
    return
  end
  until_ = now + OFFLINE_COOLDOWN
end

---The network is reachable again (a request went through).
function M.mark_online()
  until_ = 0
  reason = nil
end

---True while the latch holds: callers should not start requests, and
---should serve cache or "not connected" instead.
---@return boolean offline
---@return string|nil why
function M.is_offline()
  if os.time() < until_ then
    return true, reason
  end
  return false, nil
end

---For tests: reset the latch.
function M.reset()
  until_ = 0
  reason = nil
  noticed = false
end

return M
