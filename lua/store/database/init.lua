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

local function fetch_content_length(url, callback)
  curl.head(url, {
    headers = HTTP_HEADERS,
    timeout = 5000,
    callback = function(response)
      if response.status ~= 200 then
        callback(nil, "Failed to HEAD check: HTTP " .. response.status)
        return
      end

      local content_length = nil
      if response.headers then
        for _, header in ipairs(response.headers) do
          local key, value = header:match("^([^:]+):%s*(.+)$")
          if key and key:lower() == "content-length" then
            content_length = tonumber(value)
            break
          end
        end
      end

      if not content_length then
        callback(nil, "No content-length header found in HEAD response")
        return
      end

      callback(content_length, nil)
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
    github_client.fetch_plugins(function(data, error)
      if error then
        callback(nil, error)
        return
      end
      logger.info("✅ Fresh DB: " .. #data.items .. " plugins")
      cache.save_db(data)
      callback(data, nil)
    end)
    return
  end

  -- FILE CACHE: Validate with HEAD request (content-length comparison)
  github_client.fetch_plugins_content_length(function(server_content_length, head_error)
    if head_error then
      -- HEAD request failed, fallback to cached data
      logger.warn("HEAD request failed, using cached data: " .. head_error)
      callback(cached_data, nil)
      return
    end

    -- Get local file size for comparison
    local cache_dir = db_utils.get_cache_dir()
    local db_file = cache_dir / "db.json"
    local stat, stat_err = vim.loop.fs_stat(db_file:absolute())

    if not stat or stat_err then
      logger.warn("Cannot read local file stats, fetching fresh data")
      github_client.fetch_plugins(function(data, error)
        if error then
          callback(nil, error)
          return
        end
        logger.info("✅ Fresh DB: " .. #data.items .. " plugins")
        cache.save_db(data)
        callback(data, nil)
      end)
      return
    end

    local local_file_size = stat.size
    logger.debug(
      "HEAD validation - Server: " .. server_content_length .. " bytes, Local: " .. local_file_size .. " bytes"
    )

    -- Compare sizes
    if server_content_length == local_file_size then
      logger.debug("✅ File cache valid (sizes match) - using cached data")
      callback(cached_data, nil)
    else
      utils.tryNotify("[store.nvim] Newer database found, updating...", vim.log.levels.INFO)
      logger.debug("🔄 File cache stale (sizes differ) - fetching fresh data")
      github_client.fetch_plugins(function(data, error)
        if error then
          callback(nil, error)
          return
        end
        logger.info("✅ Updated DB: " .. #data.items .. " plugins")
        cache.save_db(data)
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

  fetch_content_length(source.url, function(content_length, head_error)
    if head_error then
      logger.warn("Install catalogue HEAD request failed for " .. manager .. ": " .. head_error)
      callback(cached_catalogue, nil)
      return
    end

    local cache_dir = db_utils.get_cache_dir()
    local cache_file = cache_dir / source.cache_filename
    local stat, stat_err = vim.loop.fs_stat(cache_file:absolute())

    if not stat or stat_err then
      logger.warn("Cannot read install catalogue cache stats for " .. manager .. ": " .. tostring(stat_err))
      fetch_install_catalogue_from_network(manager, source, callback)
      return
    end

    if content_length == stat.size then
      logger.debug("✅ Install catalogue cache valid for " .. manager .. " (" .. content_length .. " bytes)")
      callback(cached_catalogue, nil)
    else
      logger.debug("🔄 Install catalogue cache stale for " .. manager .. " - fetching fresh copy")
      fetch_install_catalogue_from_network(manager, source, callback)
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

---Internal helper to fetch README from network and update cache
---@param repo Repository Repository object
---@param callback fun(data: string[]|nil, error: string|nil) Callback function
function M._fetch_readme_from_network(repo, callback)
  logger.debug("📥 Fetching README from network for " .. repo.full_name)

  -- Choose the appropriate client based on the repository source
  local client
  if repo.source == "gitlab" then
    client = gitlab_client
  else
    -- Default to GitHub client for "github" source or any other source
    client = github_client
  end

  client.get_readme(repo, function(data, error)
    if error then
      callback(nil, error)
      return
    end

    logger.debug("✅ README Downloaded: " .. repo.full_name .. " (" .. #data .. " lines)")

    -- Save to cache for future requests
    local save_error = cache.save_readme(repo.full_name, data)
    if save_error then
      logger.warn("Failed to save README to cache for " .. repo.full_name .. ": " .. save_error)
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
