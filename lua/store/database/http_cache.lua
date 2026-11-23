local Path = require("store.plenary.path")
local curl = require("store.plenary.curl")
local db_utils = require("store.database.utils")
local net = require("store.database.net")
local logger = require("store.logger").createLogger({ context = "http-cache" })

---@module "store.database.http_cache"
---A browser-style HTTP cache, the way browsers and Emacs keep what you
---fetched: one entry per URL on disk, served without any request while it
---is fresh (the max-age window), revalidated with If-None-Match /
---If-Modified-Since when it goes stale (304 keeps the copy and is free,
---200 replaces it), and served stale when the network is down - the
---offline behavior that keeps the store usable on a train. Everything a
---session views lands here, so the second view never downloads.

local M = {}
M.VERSION = "swr-onerror-v3"

local HTTP_DIR = nil ---@type Path|nil set lazily (tests swap the cache root)
---@type table<string, { etag: string|nil, last_modified: string|nil, fetched_at: number, body: string }>
local memory = {}
---@type table<string, true>
local warned_offline = {}
---@type table<string, { callbacks: function[] }>
local inflight = {}
---One revalidation per URL: while a conditional request runs, a stale
---entry keeps being served from the cache — every preview that lands on
---it during that window would otherwise start its own request, and a
---fast cycle over stale pages becomes a storm of doomed-or-wasteful
---curls (the "it never stops loading" feeling). The slot holds the
---non-SWR waiters, which must hear the network's answer before they
---deliver anything.
---@type table<string, { callbacks: function[] }>
local revalidating = {}
---@type table<string, string> url -> its sha256, computed once per
---url in the main context (vim.fn is off-limits inside curl callbacks)
local hashes = {}

---@return Path dir the http/ directory inside the store cache
local function http_dir()
  if not HTTP_DIR then
    HTTP_DIR = db_utils.get_cache_dir() / "http"
  end
  return HTTP_DIR
end

---Allow tests (or other embedders) to point the cache somewhere else.
---@param dir Path
function M.set_dir(dir)
  HTTP_DIR = dir
  memory = {}
end

local function hash(url)
  return vim.fn.sha256(url)
end

local function entry_paths(url)
  local dir = http_dir()
  local h = hashes[url] or hash(url)
  hashes[url] = h
  return dir / (h .. ".meta"), dir / (h .. ".body")
end

---@param url string
---@return { etag: string|nil, last_modified: string|nil, fetched_at: number, body: string }|nil entry
local function read_entry(url)
  if memory[url] then
    return memory[url]
  end
  local meta_path, body_path = entry_paths(url)
  if not body_path:exists() then
    return nil
  end
  local ok_meta, meta = pcall(function()
    return vim.json.decode(meta_path:read())
  end)
  if not ok_meta or type(meta) ~= "table" then
    return nil
  end
  local ok_body, body = pcall(function()
    return body_path:read()
  end)
  if not ok_body then
    return nil
  end
  local entry = {
    etag = meta.etag,
    last_modified = meta.last_modified,
    fetched_at = tonumber(meta.fetched_at) or 0,
    body = body,
  }
  memory[url] = entry
  return entry
end

---@param url string
---@param entry table
local function write_entry(url, entry)
  memory[url] = entry
  local dir = http_dir()
  if not dir:exists() then
    local ok, err = pcall(function()
      dir:mkdir({ parents = true })
    end)
    if not ok then
      logger.error("Cannot create the http cache directory: " .. tostring(err))
      return
    end
  end
  local meta_path, body_path = entry_paths(url)
  local meta = {
    url = url,
    etag = entry.etag,
    last_modified = entry.last_modified,
    fetched_at = entry.fetched_at,
  }
  vim.schedule(function()
    pcall(function()
      meta_path:write(vim.json.encode(meta), "w")
      body_path:write(entry.body, "w")
    end)
    logger.debug("cached " .. url .. " (" .. #entry.body .. " bytes)")
  end)
end

---Seed an entry from pre-existing files (the db.json + db.etag a previous
---version of the plugin kept, a README left in the temp dir): the old
---cache becomes the new cache for free.
---@param url string
---@param body string
---@param etag string|nil
---@param fetched_at number|nil unix seconds
function M.seed(url, body, etag, fetched_at)
  hashes[url] = hashes[url] or hash(url)
  if read_entry(url) then
    return
  end
  write_entry(url, {
    etag = etag,
    last_modified = nil,
    fetched_at = fetched_at or os.time(),
    body = body,
  })
  logger.debug("seeded cache for " .. url)
end

---@param url string
---@param entry table
---@param callback function
local function deliver(url, entry, callback, source)
  ---@diagnostic disable-next-line: redundant-parameter
  callback(entry.body, nil, { source = source, etag = entry.etag, fetched_at = entry.fetched_at })
end

--- The offline serve is SILENT: the cached copy opens, and that is the
--- whole message - a notice per URL while cycling a list is noise the
--- user asked to never see ("network unreachable" x N). The log keeps a
--- debug line for whoever looks.
---@param url string
---@param age number seconds
local function age_notice(url, age)
  if warned_offline[url] then
    return
  end
  warned_offline[url] = true
  local mins = math.floor(age / 60)
  local age_s = mins >= 60 and string.format("%dh%02dm", math.floor(mins / 60), mins % 60) or (mins .. "m")
  logger.debug("offline: serving the cached copy of " .. url .. " (" .. age_s .. " old)")
end

---@param url string
---@param entry table
---@param opts table
---@param callback function
local function revalidate(url, entry, opts, callback)
  local headers = {}
  for k, v in pairs(opts.headers or {}) do
    headers[k] = v
  end
  if entry.etag then
    headers["If-None-Match"] = entry.etag
  end
  if entry.last_modified then
    headers["If-Modified-Since"] = entry.last_modified
  end

  local ok, err = pcall(curl.get, url, {
    headers = headers,
    timeout = opts.timeout or 10000,
    on_error = function(e)
      -- curl could not even speak (no internet, dead proxy): the cached
      -- copy is the best answer there is, and the network is latched
      -- offline so the next uncached page does not even try
      net.mark_offline(e.message)
      if entry.body ~= nil and #entry.body > 0 then
        age_notice(url, os.time() - entry.fetched_at)
        deliver(url, entry, callback, "stale")
        return
      end
      callback(nil, "not connected")
    end,
    callback = function(response)
      if response.status == 304 then
        entry.fetched_at = os.time()
        write_entry(url, entry)
        deliver(url, entry, callback, "revalidated")
        return
      end
      if response.status >= 200 and response.status < 300 then
        local etag, last_modified
        if response.headers then
          for _, header in ipairs(response.headers) do
            local key, value = header:match("^([^:]+):%s*(.+)$")
            if key and value then
              local k = key:lower()
              if k == "etag" then
                etag = vim.trim(value)
              elseif k == "last-modified" then
                last_modified = vim.trim(value)
              end
            end
          end
        end
        write_entry(url, {
          etag = etag,
          last_modified = last_modified,
          fetched_at = os.time(),
          body = response.body or "",
        })
        deliver(url, memory[url], callback, "network")
        return
      end
      -- 4xx/5xx: the resource is unhappy; what we have is better than nothing
      if entry.body ~= nil and #entry.body > 0 then
        age_notice(url, os.time() - entry.fetched_at)
        deliver(url, entry, callback, "stale")
        return
      end
      callback(nil, "HTTP " .. response.status .. " for " .. url)
    end,
  })
  if not ok then
    -- curl itself raised: connection refused, a dead proxy, no route -
    -- the cached copy is the best answer there is
    net.mark_offline(tostring(err))
    if entry.body ~= nil and #entry.body > 0 then
      age_notice(url, os.time() - entry.fetched_at)
      deliver(url, entry, callback, "stale")
      return
    end
    callback(nil, "not connected")
  end
end

---Get a URL through the cache.
---@param url string
---@param opts { ttl?: number, parse?: "json"|"lines"|nil, headers?: table, force?: boolean, timeout?: number }
---   ttl: seconds the entry stays trusted without a request (the browser's
---   max-age); 0 = revalidate on every call; nil = never stale
---   force: skip the cache entirely, fetch and overwrite
---@param callback fun(data: any|nil, error: string|nil, meta: { source: string, etag: string|nil, fetched_at: number }|nil)
---   data is the parsed body (json table / line array / raw string)
function M.get(url, opts, callback)
  opts = opts or {}
  hashes[url] = hashes[url] or hash(url) -- main context: vim.fn is fine here

  if opts.force then
    -- an explicit refresh: the latch is lifted (the user may have just
    -- re-connected, and they asked for the network), then fetch and
    -- keep whatever came back
    net.mark_online()
    local ok, curl_err = pcall(curl.get, url, {
      headers = opts.headers or { ["Accept"] = "application/json", ["User-Agent"] = "store.nvim" },
      timeout = opts.timeout or 10000,
      on_error = function(e)
        local entry = read_entry(url)
        if entry and #entry.body > 0 then
          age_notice(url, os.time() - entry.fetched_at)
          deliver(url, entry, callback, "stale")
          return
        end
        net.mark_offline(e.message)
        callback(nil, "not connected")
      end,
      callback = function(response)
        if response.status >= 200 and response.status < 300 then
          local etag, last_modified
          if response.headers then
            for _, header in ipairs(response.headers) do
              local key, value = header:match("^([^:]+):%s*(.+)$")
              if key and value then
                local k = key:lower()
                if k == "etag" then
                  etag = vim.trim(value)
                elseif k == "last-modified" then
                  last_modified = vim.trim(value)
                end
              end
            end
          end
          write_entry(url, {
            etag = etag,
            last_modified = last_modified,
            fetched_at = os.time(),
            body = response.body or "",
          })
          deliver(url, memory[url], callback, "network")
          return
        end
        local entry = read_entry(url)
        if entry and #entry.body > 0 then
          age_notice(url, os.time() - entry.fetched_at)
          deliver(url, entry, callback, "stale")
          return
        end
        callback(nil, "HTTP " .. response.status .. " for " .. url)
      end,
    })
    if not ok then
      local entry = read_entry(url)
      if entry and #entry.body > 0 then
        age_notice(url, os.time() - entry.fetched_at)
        deliver(url, entry, callback, "stale")
        return
      end
      net.mark_offline(tostring(curl_err))
      callback(nil, "not connected")
    end
    return
  end

  -- inflight dedup: concurrent gets for one URL share the fetch. The
  -- waiters are captured per generation: `finish` may be called twice
  -- by design (stale-while-revalidate delivers the stale copy first and
  -- the refreshed one second), and the second call must not look the
  -- waiters up again - the inflight entry is gone by then, and a fresh
  -- get may already own the slot. Every call delivers to this
  -- generation's callbacks, exactly once each.
  local pending = inflight[url]
  if pending then
    table.insert(pending.callbacks, callback)
    return
  end
  local waiters = { callbacks = { callback } }
  inflight[url] = waiters
  local function finish(data, err, meta)
    if inflight[url] == waiters then
      inflight[url] = nil
    end
    for _, cb in ipairs(waiters.callbacks) do
      pcall(cb, data, err, meta)
    end
  end
  -- the network latch: while a recent request failed at the network
  -- level, no request is started at all - a cached copy is served, and
  -- with none the caller is told "not connected" immediately (the
  -- preview says it, instead of timing out a request per keystroke)
  local offline, why = net.is_offline()
  if offline then
    local entry = read_entry(url)
    if entry and #entry.body > 0 then
      age_notice(url, os.time() - entry.fetched_at)
      finish(entry.body, nil, { source = "stale", etag = entry.etag, fetched_at = entry.fetched_at })
      return
    end
    finish(nil, "not connected")
    return
  end

  local entry = read_entry(url)
  if not entry then
    local ok, curl_err = pcall(curl.get, url, {
      headers = opts.headers or { ["Accept"] = "application/json", ["User-Agent"] = "store.nvim" },
      timeout = opts.timeout or 10000,
      on_error = function(e)
        net.mark_offline(e.message)
        finish(nil, "not connected")
      end,
      callback = function(response)
        if response.status >= 200 and response.status < 300 then
          net.mark_online()
          local etag, last_modified
          if response.headers then
            for _, header in ipairs(response.headers) do
              local key, value = header:match("^([^:]+):%s*(.+)$")
              if key and value then
                local k = key:lower()
                if k == "etag" then
                  etag = vim.trim(value)
                elseif k == "last-modified" then
                  last_modified = vim.trim(value)
                end
              end
            end
          end
          write_entry(url, {
            etag = etag,
            last_modified = last_modified,
            fetched_at = os.time(),
            body = response.body or "",
          })
          finish(memory[url].body, nil, { source = "network", etag = etag, fetched_at = memory[url].fetched_at })
          return
        end
        finish(nil, "HTTP " .. response.status .. " for " .. url)
      end,
    })
    if not ok then
      net.mark_offline(tostring(curl_err))
      finish(nil, "not connected")
    end
    return
  end

  local ttl = opts.ttl
  local age = os.time() - entry.fetched_at
  if ttl == nil or age < ttl then
    -- fresh (or never-stale): no request at all
    finish(entry.body, nil, { source = "cache", etag = entry.etag, fetched_at = entry.fetched_at })
    return
  end

  -- stale. With stale_while_revalidate the copy goes out right away and
  -- the caller hears a second time only when the body actually changed;
  -- without it the caller waits for the network's answer. Either way at
  -- most ONE conditional request runs per URL at a time - later gets
  -- that land on the same stale entry serve the copy (SWR) or join the
  -- waiters (no SWR), never another request.
  if opts.stale_while_revalidate then
    deliver(url, entry, finish, "cache")
    local running = revalidating[url]
    if running then
      return -- a revalidation is already in flight for this URL
    end
    revalidating[url] = { callbacks = {} }
    revalidate(url, entry, opts, function(body, err, meta)
      revalidating[url] = nil
      if meta and meta.source == "network" and body ~= entry.body then
        meta.updated = true -- a stale copy went out first; this one replaces it
        finish(body, err, meta)
      end
      -- a 304 or an unchanged body: the caller already has it
    end)
    return
  end

  local running = revalidating[url]
  if running then
    table.insert(running.callbacks, finish)
    return
  end
  revalidating[url] = { callbacks = { finish } }
  revalidate(url, entry, opts, function(body, err, meta)
    local w = revalidating[url]
    revalidating[url] = nil
    for _, cb in ipairs((w and w.callbacks) or {}) do
      pcall(cb, body, err, meta)
    end
  end)
end

---Drop everything (called by database.clear / :Store reset - the explicit
---"forget it all" action).
---@return string|nil error
function M.clear()
  memory = {}
  warned_offline = {}
  revalidating = {}
  local dir = http_dir()
  if dir:exists() then
    local ok, err = pcall(function()
      dir:rm({ recursive = true })
    end)
    if not ok then
      return "Failed to delete the http cache: " .. tostring(err)
    end
  end
  return nil
end

---Parse a cached/fetched body the way the caller asked.
---@param body string
---@param parse "json"|"lines"|nil
---@return any
function M.parse_body(body, parse)
  if parse == "json" then
    local ok, data = pcall(vim.json.decode, body)
    if not ok then
      return nil, "Failed to parse JSON: " .. tostring(data)
    end
    return data
  end
  if parse == "lines" then
    return vim.split(body, "\n", { plain = true })
  end
  return body
end

return M
