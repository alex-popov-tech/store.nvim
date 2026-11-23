local github_client = require("store.database.github_client")
local gitlab_client = require("store.database.gitlab_client")
local cache = require("store.database.cache")
local http_cache = require("store.database.http_cache")
local net = require("store.database.net")
local logger = require("store.logger").createLogger({ context = "database" })
local db_utils = require("store.database.utils")
local utils = require("store.utils")
local curl = require("store.plenary.curl")
local config = require("store.config")

local HTTP_HEADERS = {
  ["Accept"] = "application/json",
  ["User-Agent"] = "store.nvim",
}

local INSTALL_CACHE_FILES = {
  ["lazy.nvim"] = "lazy.nvim.json",
  ["vim.pack"] = "vim.pack.json",
}

---@module "store.database"
---Database facade that orchestrates GitHub client and caching operations
---Maintains the same public API as the original database module

local M = {}

---The cache options, flattened: enabled / update_interval /
---implicit_updates, plus the per-section switches (`cache.sections` —
---list, install_catalogue, readme, docs; all on by default, so what you
---view is on disk and opens offline). A section switched off is fetched
---live every time — and offline it says "not connected" instead of
---erroring, the same as an uncached page.
---@return { enabled: boolean, interval: number, implicit: boolean, sections: table }
local function cache_opts()
  local conf = config.get().cache or {}
  local sections = vim.tbl_extend("force", {
    list = true,
    install_catalogue = true,
    readme = true,
    docs = true,
  }, conf.sections or {})
  return {
    enabled = conf.enabled ~= false,
    interval = tonumber(conf.update_interval) or 1800,
    implicit = conf.implicit_updates ~= false,
    sections = sections,
  }
end

---Seed the http cache from the files an earlier store.nvim version kept,
---so an upgrade keeps its cache: db.json + db.etag become the entry for
---the data source URL.
---@param url string
local function seed_db_from_legacy(url)
  local cache_dir = db_utils.get_cache_dir()
  local db_file = cache_dir / "db.json"
  if not db_file:exists() then
    return
  end
  local ok, body = pcall(function()
    return db_file:read()
  end)
  if not ok or not body or body == "" then
    return
  end
  local etag = nil
  local etag_file = cache_dir / "db.etag"
  if etag_file:exists() then
    pcall(function()
      etag = vim.trim(etag_file:read())
    end)
  end
  local fetched_at = nil
  local stat = vim.loop.fs_stat(db_file:absolute())
  if stat and stat.mtime and stat.mtime.sec then
    fetched_at = stat.mtime.sec
  end
  http_cache.seed(url, body, etag, fetched_at)
end

---Seed the http cache from the temp-dir copies (READMEs, docs) an earlier
---store.nvim version kept in /tmp: they survive the upgrade.
---@param url string
---@param key string cache file name in the temp dir
local function seed_tmp_from_legacy(url, key)
  local tmp_dir = db_utils.get_tmp_cache_dir()
  local file = tmp_dir / key
  if not file:exists() then
    return
  end
  local ok, body = pcall(function()
    return file:read()
  end)
  if not ok or not body or body == "" then
    return
  end
  local fetched_at = nil
  local stat = vim.loop.fs_stat(file:absolute())
  if stat and stat.mtime and stat.mtime.sec then
    fetched_at = stat.mtime.sec
  end
  http_cache.seed(url, body, nil, fetched_at)
end

---Fetch the database through the http cache (enabled) or the legacy
---etag-validated flow (disabled). The callback gets (data, error) as
---before - and, when an implicit background update swaps in a newer list
---after a stale one was served, a second (data, error) call.
---@param callback fun(data: Database|nil, error: string|nil)
---@param opts { force?: boolean }|nil force = an explicit refresh
function M.fetch_plugins(callback, opts)
  opts = opts or {}
  local conf = config.get()
  local c = cache_opts()
  local url = conf.data_source_url

  if not c.enabled or not c.sections.list then
    -- the raw fetch: while the network is latched offline, do not even
    -- start - nothing is cached by choice here, so the answer is the
    -- message, not a timeout
    if net.is_offline() then
      callback(nil, "not connected")
      return
    end
    github_client.fetch_plugins(function(data, error, raw_json)
      if error then
        callback(nil, error)
        return
      end
      cache.save_db(data, raw_json)
      callback(data, nil)
    end)
    return
  end

  seed_db_from_legacy(url)
  http_cache.get(url, {
    ttl = c.interval,
    headers = HTTP_HEADERS,
    force = opts.force,
    stale_while_revalidate = c.implicit and not opts.force,
  }, function(body, err, meta)
    if err then
      callback(nil, err)
      return
    end
    local ok, data = pcall(vim.json.decode, body)
    if not ok then
      callback(nil, "Failed to parse the database: " .. tostring(data))
      return
    end
    callback(data, nil)
    -- NOTE: an implicit background update re-delivers on its own - the
    -- stale-while-revalidate finish calls this callback a second time,
    -- with meta.updated set, when the newer list lands; no extra push
    -- needed here (a scheduled third call would just re-render twice)
  end)
end

local function fetch_etag(url, callback)
  if net.is_offline() then
    callback(nil, "not connected")
    return
  end
  curl.head(url, {
    headers = HTTP_HEADERS,
    timeout = 5000,
    on_error = function(e)
      net.mark_offline(e.message)
      callback(nil, "not connected")
    end,
    callback = function(response)
      if response.status ~= 200 then
        callback(nil, "Failed to HEAD check: HTTP " .. response.status)
        return
      end

      local etag = nil
      if response.headers then
        for _, header in ipairs(response.headers) do
          local key, value = header:match("^([^:]+):%s*(.+)$")
          if key and key:lower() == "etag" then
            etag = vim.trim(value)
          end
        end
      end

      if not etag then
        callback(nil, "No etag header found in HEAD response")
        return
      end

      callback(etag, nil)
    end,
  })
end

local function fetch_remote_json(url, callback)
  if net.is_offline() then
    callback(nil, "not connected")
    return
  end
  curl.get(url, {
    headers = HTTP_HEADERS,
    timeout = 10000,
    on_error = function(e)
      net.mark_offline(e.message)
      callback(nil, "not connected")
    end,
    callback = function(response)
      if response.status ~= 200 then
        callback(nil, "Failed to fetch data: HTTP " .. response.status .. " " .. (response.body or ""))
        return
      end

      local success, data = pcall(vim.json.decode, response.body)
      if not success then
        callback(nil, "Failed to parse JSON: " .. data)
        return
      end

      callback(data, nil)
    end,
  })
end


---The legacy HEAD-validated fetch, kept for cache.enabled = false.
---@param callback fun(data: Database|nil, error: string|nil) Callback function with plugins data or error
function M.fetch_plugins_legacy(callback)
  logger.debug("🚀 Starting plugin fetch")

  local cache_type, cached_data = cache.get_db()

  -- EARLY RETURN: Memory cache - use immediately, no validation needed
  if cache_type == "memory" then
    logger.debug("📦 Memory cache hit - using immediately")
    callback(cached_data, nil)
    return
  end

  -- EARLY RETURN: No cache - fetch directly
  if cache_type == "none" then
    logger.debug("📭 No cache - fetching from network")
    utils.tryNotify("[store.nvim] No cache found, fetching database...", vim.log.levels.INFO)
    github_client.fetch_plugins(function(data, error, raw_json)
      if error then
        callback(nil, error)
        return
      end
      logger.info("✅ Fresh DB: " .. #data.items .. " plugins")
      cache.save_db(data, raw_json)
      -- Fetch and save etag for future staleness checks
      local data_url = config.get().data_source_url
      fetch_etag(data_url, function(etag)
        if etag then
          local cache_dir = db_utils.get_cache_dir()
          vim.schedule(function()
            if not cache_dir:exists() then cache_dir:mkdir({ parents = true }) end
            pcall(function() (cache_dir / "db.etag"):write(etag, "w") end)
          end)
        end
      end)
      callback(data, nil)
    end)
    return
  end

  -- FILE CACHE: Validate with HEAD request (etag comparison)
  local data_url = config.get().data_source_url
  fetch_etag(data_url, function(server_etag, head_error)
    if head_error then
      -- quiet: the cached data serves, and a network problem is a state
      -- the user already knows about - not a message per open
      logger.debug("HEAD request failed, using cached data: " .. head_error)
      callback(cached_data, nil)
      return
    end

    -- Compare with saved etag
    local cache_dir = db_utils.get_cache_dir()
    local etag_file = cache_dir / "db.etag"
    local local_etag = nil
    if etag_file:exists() then
      pcall(function() local_etag = vim.trim(etag_file:read()) end)
    end

    logger.debug("Etag validation - Server: " .. server_etag .. ", Local: " .. tostring(local_etag))

    if server_etag == local_etag then
      logger.debug("✅ File cache valid (etag matches) - using cached data")
      callback(cached_data, nil)
    else
      utils.tryNotify("[store.nvim] Newer database found, updating...", vim.log.levels.INFO)
      logger.debug("🔄 File cache stale (etag differs) - fetching fresh data")
      github_client.fetch_plugins(function(data, error, raw_json)
        if error then
          callback(nil, error)
          return
        end
        logger.info("✅ Updated DB: " .. #data.items .. " plugins")
        cache.save_db(data, raw_json)
        -- Save etag for next session
        vim.schedule(function()
          if not cache_dir:exists() then cache_dir:mkdir({ parents = true }) end
          pcall(function() etag_file:write(server_etag, "w") end)
        end)
        callback(data, nil)
      end)
    end
  end)
end

local function fetch_install_catalogue_from_network(manager, source, callback)
  logger.info("Fetching install catalogue for " .. manager)
  fetch_remote_json(source.url, function(data, error)
    if error then
      callback(nil, error)
      return
    end

    local items = data and data.items or {}
    utils.tryNotify("✅ Install catalogue updated for " .. manager .. ": " .. vim.tbl_count(items) .. " entries")

    local save_error = cache.save_install_catalogue(manager, data, function()
      if source.etag then
        local cache_dir = db_utils.get_cache_dir()
        local etag_file = cache_dir / (source.cache_filename .. ".etag")
        pcall(function() etag_file:write(source.etag, "w") end)
      end
    end)
    if save_error then
      logger.warn("Failed to persist install catalogue for " .. manager .. ": " .. save_error)
    end

    callback(data, nil)
  end)
end

---Fetch install catalogue for the detected plugin manager: through the
---http cache when it is enabled (fresh window, then one conditional
---request), the legacy etag flow when it is not.
---@param manager string Plugin manager identifier
---@param callback fun(data: table|nil, error: string|nil) Callback with catalogue JSON or error
function M.fetch_install_catalogue(manager, callback)
  local c = cache_opts()
  if c.enabled and c.sections.install_catalogue then
    local urls = config.get().install_catalogue_urls or {}
    local url = urls[manager]
    if not url or url == "" then
      callback(nil, "Install catalogue URL not configured for " .. manager)
      return
    end
    local cache_dir = db_utils.get_cache_dir()
    local legacy_file = cache_dir / (INSTALL_CACHE_FILES[manager] or "")
    local legacy_etag = cache_dir / ((INSTALL_CACHE_FILES[manager] or "") .. ".etag")
    if legacy_file:exists() then
      local ok, body = pcall(function()
        return legacy_file:read()
      end)
      local etag = nil
      if legacy_etag:exists() then
        pcall(function()
          etag = vim.trim(legacy_etag:read())
        end)
      end
      if ok and body and body ~= "" then
        local fetched_at = nil
        local stat = vim.loop.fs_stat(legacy_file:absolute())
        if stat and stat.mtime and stat.mtime.sec then
          fetched_at = stat.mtime.sec
        end
        http_cache.seed(url, body, etag, fetched_at)
      end
    end
    http_cache.get(url, {
      ttl = c.interval,
      headers = HTTP_HEADERS,
      stale_while_revalidate = c.implicit,
    }, function(body, err)
      if err then
        callback(nil, err)
        return
      end
      local ok, data = pcall(vim.json.decode, body)
      if not ok then
        callback(nil, "Failed to parse the catalogue: " .. tostring(data))
        return
      end
      callback(data, nil)
    end)
    return
  end
  return M.fetch_install_catalogue_legacy(manager, callback)
end

---The legacy etag-validated catalogue fetch, kept for cache.enabled = false.
---@param manager string Plugin manager identifier
---@param callback fun(data: table|nil, error: string|nil) Callback with catalogue JSON or error
function M.fetch_install_catalogue_legacy(manager, callback)
  local cache_filename = INSTALL_CACHE_FILES[manager]
  if not cache_filename then
    callback(nil, "Unsupported plugin manager: " .. tostring(manager))
    return
  end

  local urls = config.get().install_catalogue_urls or {}
  local url = urls[manager]
  if not url or url == "" then
    callback(nil, "Install catalogue URL not configured for " .. manager)
    return
  end

  local source = {
    cache_filename = cache_filename,
    url = url,
  }

  local cache_type, cached_catalogue = cache.get_install_catalogue(manager)

  if cache_type == "memory" then
    logger.debug("📦 Install catalogue memory cache hit for " .. manager)
    callback(cached_catalogue, nil)
    return
  end

  if cache_type == "none" then
    logger.debug("📭 No install catalogue cache for " .. manager .. " - fetching from network")
    fetch_install_catalogue_from_network(manager, source, callback)
    return
  end

  fetch_etag(source.url, function(server_etag, head_error)
    if head_error then
      logger.warn("Install catalogue HEAD request failed for " .. manager .. ": " .. head_error)
      callback(cached_catalogue, nil)
      return
    end

    local cache_dir = db_utils.get_cache_dir()
    local etag_file = cache_dir / (source.cache_filename .. ".etag")
    local local_etag = nil
    if etag_file:exists() then
      pcall(function() local_etag = vim.trim(etag_file:read()) end)
    end

    if server_etag == local_etag then
      logger.debug("✅ Install catalogue cache valid for " .. manager .. " (etag matches)")
      callback(cached_catalogue, nil)
    else
      logger.debug("🔄 Install catalogue cache stale for " .. manager .. " - fetching fresh copy")
      source.etag = server_etag
      fetch_install_catalogue_from_network(manager, source, callback)
    end
  end)
end

---Get README content for a repository: through the http cache when it is
---enabled (what you viewed is on disk and opens offline), the temp-dir
---cache when it is not.
---@param repo Repository
---@param callback fun(data: string[]|nil, error: string|nil) Callback function with README lines or error
function M.get_readme(repo, callback)
  local c = cache_opts()
  if c.enabled and c.sections.readme then
    local url = db_utils.build_worker_readme_url(config.get().readme_cache_url, repo.source or "github", repo.full_name, repo.readme)
    seed_tmp_from_legacy(url, db_utils.repository_to_readme_key(repo.full_name))
    -- stale_while_revalidate: a stale copy shows the instant the cursor
    -- lands on the entry - cycling must never wait on the network - and
    -- one conditional request refreshes it in the background
    http_cache.get(url, {
      ttl = c.interval,
      stale_while_revalidate = c.implicit,
    }, function(body, err, meta)
      if err then
        callback(nil, err)
        return
      end
      callback(vim.split(body, "\n", { plain = true }), nil)
      -- a background refresh re-delivers here on its own (the
      -- stale-while-revalidate second call, meta.updated): the preview
      -- swaps silently, nothing extra to push
    end)
    return
  end
  return M.get_readme_legacy(repo, callback)
end

---The legacy README flow, kept for cache.enabled = false.
---@param repo Repository
---@param callback fun(data: string[]|nil, error: string|nil) Callback function with README lines or error
function M.get_readme_legacy(repo, callback)
  logger.debug("get_readme called for " .. repo.full_name)

  local cache_type, cached_readme = cache.get_readme(repo.full_name)

  -- EARLY RETURN: Memory cache - use immediately, no validation needed
  if cache_type == "memory" then
    logger.debug("📦 README Memory cache - using immediately for " .. repo.full_name)
    callback(cached_readme, nil)
    return
  end

  -- EARLY RETURN: No cache - fetch directly
  if cache_type == "none" then
    logger.debug("📭 No README cache - fetching from network for " .. repo.full_name)
    return M._fetch_readme_from_network(repo, callback)
  end

  -- FILE CACHE: Use cached README directly (HEAD-based cache)
  logger.debug("✅ README File cache hit - using cached data for " .. repo.full_name)
  callback(cached_readme, nil)
  return
end

---Internal helper to fetch README from worker cache and update local cache
---@param repo Repository Repository object
---@param callback fun(data: string[]|nil, error: string|nil) Callback function
function M._fetch_readme_from_network(repo, callback)
  logger.debug("📥 Fetching README from worker for " .. repo.full_name)

  if net.is_offline() then
    callback(nil, "not connected")
    return
  end
  local source = repo.source or "github"
  local url = db_utils.build_worker_readme_url(config.get().readme_cache_url, source, repo.full_name, repo.readme)

  curl.get(url, {
    timeout = 10000,
    on_error = function(e)
      net.mark_offline(e.message)
      callback(nil, "not connected")
    end,
    callback = function(response)
      if response.status == 0 then
        callback(nil, "not connected")
        return
      end
      if response.status < 200 or response.status >= 300 then
        local errorBody = response.body or "Failed to fetch README from worker"
        callback(nil, response.status .. " " .. errorBody)
        return
      end

      local lines = vim.split(response.body, "\n", { plain = true })

      logger.debug("✅ README Downloaded: " .. repo.full_name .. " (" .. #lines .. " lines)")

      -- Save to cache for future requests
      local save_error = cache.save_readme(repo.full_name, lines)
      if save_error then
        logger.warn("Failed to save README to cache for " .. repo.full_name .. ": " .. save_error)
      end
      callback(lines, nil)
    end,
  })
end

---Get documentation content for a specific doc file: through the http
---cache when it is enabled, the temp-dir cache when it is not.
---@param repo Repository
---@param doc_path string Specific doc reference from repo.doc array (e.g., "main/doc/help.txt")
---@param callback fun(data: string[]|nil, error: string|nil) Callback function with doc lines or error
function M.get_doc(repo, doc_path, callback)
  if not doc_path or doc_path == "" then
    callback(nil, "No documentation available for " .. repo.full_name)
    return
  end
  local c = cache_opts()
  if c.enabled and c.sections.docs then
    local client = (repo.source == "gitlab") and gitlab_client or github_client
    local url = (repo.source == "gitlab") and db_utils.build_gitlab_doc_url(repo.full_name, doc_path)
      or db_utils.build_github_doc_url(repo.full_name, doc_path)
    seed_tmp_from_legacy(url, db_utils.repository_to_doc_key(repo.full_name, doc_path))
    -- same as the readmes: a stale doc shows instantly, one conditional
    -- request refreshes it behind the preview
    http_cache.get(url, {
      ttl = c.interval,
      stale_while_revalidate = c.implicit,
    }, function(body, err, meta)
      if err then
        callback(nil, err)
        return
      end
      callback(vim.split(body, "\n", { plain = true }), nil)
      -- same as the readmes: the refresh re-delivers on its own
    end)
    return
  end
  return M.get_doc_legacy(repo, doc_path, callback)
end

---The legacy doc flow, kept for cache.enabled = false.
---@param repo Repository
---@param doc_path string Specific doc reference from repo.doc array (e.g., "main/doc/help.txt")
---@param callback fun(data: string[]|nil, error: string|nil) Callback function with doc lines or error
function M.get_doc_legacy(repo, doc_path, callback)
  logger.debug("get_doc called for " .. repo.full_name .. " [" .. tostring(doc_path) .. "]")

  if not doc_path or doc_path == "" then
    callback(nil, "No documentation available for " .. repo.full_name)
    return
  end

  local cache_type, cached_doc = cache.get_doc(repo.full_name, doc_path)

  -- EARLY RETURN: Memory cache - use immediately
  if cache_type == "memory" then
    logger.debug("📦 DOC Memory cache - using immediately for " .. repo.full_name .. " [" .. doc_path .. "]")
    callback(cached_doc, nil)
    return
  end

  -- EARLY RETURN: No cache - fetch directly
  if cache_type == "none" then
    logger.debug("📭 No DOC cache - fetching from network for " .. repo.full_name .. " [" .. doc_path .. "]")
    return M._fetch_doc_from_network(repo, doc_path, callback)
  end

  -- FILE CACHE: Use cached doc directly
  logger.debug("✅ DOC File cache hit - using cached data for " .. repo.full_name .. " [" .. doc_path .. "]")
  callback(cached_doc, nil)
end

---Internal helper to fetch doc from network and update cache
---@param repo Repository Repository object
---@param doc_path string Specific doc reference (e.g., "main/doc/help.txt")
---@param callback fun(data: string[]|nil, error: string|nil) Callback function
function M._fetch_doc_from_network(repo, doc_path, callback)
  logger.debug("📥 Fetching doc from network for " .. repo.full_name .. " [" .. doc_path .. "]")

  if net.is_offline() then
    callback(nil, "not connected")
    return
  end

  -- Choose the appropriate client based on the repository source
  local client
  if repo.source == "gitlab" then
    client = gitlab_client
  else
    client = github_client
  end

  client.get_doc(repo, doc_path, function(data, error)
    if error then
      callback(nil, error)
      return
    end

    logger.debug("✅ DOC Downloaded: " .. repo.full_name .. " [" .. doc_path .. "] (" .. #data .. " lines)")

    -- Save to cache for future requests
    local save_error = cache.save_doc(repo.full_name, doc_path, data)
    if save_error then
      logger.warn("Failed to save doc to cache for " .. repo.full_name .. " [" .. doc_path .. "]: " .. save_error)
    end
    callback(data, nil)
  end)
end

---Reset all plugin caches and log the time taken
---@return string|nil error Error message if reset failed, nil on success
function M.clear()
  logger.debug("Starting database clear")
  local start_time = vim.loop.hrtime()

  local error = cache.clear_all_caches()
  local http_error = http_cache.clear()
  if http_error then
    error = error or http_error
  end

  local end_time = vim.loop.hrtime()
  local duration_ms = (end_time - start_time) / 1000000 -- Convert nanoseconds to milliseconds

  if error then
    logger.error("Database reset failed: " .. error .. " (took " .. string.format("%.1f", duration_ms) .. "ms)")
    return error
  else
    logger.info("Database reset completed in " .. string.format("%.1f", duration_ms) .. "ms")
    return nil
  end
end

return M
