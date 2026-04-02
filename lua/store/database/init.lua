local github_client = require("store.database.github_client")
local gitlab_client = require("store.database.gitlab_client")
local cache = require("store.database.cache")
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

local function fetch_etag(url, callback)
  curl.head(url, {
    headers = HTTP_HEADERS,
    timeout = 5000,
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
  curl.get(url, {
    headers = HTTP_HEADERS,
    timeout = 10000,
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


---@module "store.database"
---Database facade that orchestrates GitHub client and caching operations
---Maintains the same public API as the original database module

local M = {}

---Fetch plugins with HEAD-based cache validation
---@param callback fun(data: Database|nil, error: string|nil) Callback function with plugins data or error
function M.fetch_plugins(callback)
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
      logger.warn("HEAD request failed, using cached data: " .. head_error)
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

    local save_error = cache.save_install_catalogue(manager, data)
    if save_error then
      logger.warn("Failed to persist install catalogue for " .. manager .. ": " .. save_error)
    end

    callback(data, nil)
  end)
end

---Fetch install catalogue for detected plugin manager with cache validation
---@param manager string Plugin manager identifier
---@param callback fun(data: table|nil, error: string|nil) Callback with catalogue JSON or error
function M.fetch_install_catalogue(manager, callback)
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
      fetch_install_catalogue_from_network(manager, source, callback)
      -- Save etag after fetch
      vim.schedule(function()
        if not cache_dir:exists() then cache_dir:mkdir({ parents = true }) end
        pcall(function() etag_file:write(server_etag, "w") end)
      end)
    end
  end)
end

---Get README content for a repository, with caching support
---@param repo Repository
---@param callback fun(data: string[]|nil, error: string|nil) Callback function with README lines or error
function M.get_readme(repo, callback)
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

  local source = repo.source or "github"
  local url = db_utils.build_worker_readme_url(config.get().readme_cache_url, source, repo.full_name, repo.readme)

  curl.get(url, {
    timeout = 10000,
    callback = function(response)
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

---Get documentation content for a specific doc file, with caching support
---@param repo Repository
---@param doc_path string Specific doc reference from repo.doc array (e.g., "main/doc/help.txt")
---@param callback fun(data: string[]|nil, error: string|nil) Callback function with doc lines or error
function M.get_doc(repo, doc_path, callback)
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
