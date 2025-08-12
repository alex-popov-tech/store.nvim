local github_client = require("store.database.github_client")
local cache = require("store.database.cache")
local logger = require("store.logger").createLogger({ context = "database" })

---@module "store.database"
---Database facade that orchestrates GitHub client and caching operations
---Maintains the same public API as the original database module

local M = {}

---Fetch plugins from the gist URL, with caching support
---@param callback fun(data: Database|nil, error: string|nil) Callback function with plugins data or error
function M.fetch_plugins(callback)
  logger.debug("fetch_plugins called")

  logger.debug("Checking cache first")
  local cached_data, cache_error = cache.get_db()
  if cache_error then
    logger.warn("Cache error during fetch_plugins: " .. cache_error)
  end
  if cached_data then
    logger.debug("Using cached database data")
    callback(cached_data, nil)
    return
  end

  logger.debug("No cached data available, fetching from network")
  logger.info("Fetching plugin database")
  github_client.fetch_plugins(function(data, error)
    if error then
      logger.debug("Network fetch failed: " .. error)
      callback(nil, error)
      return
    end

    logger.info("Database loaded: " .. #data .. " plugins")
    local save_error = cache.save_db(data)
    if save_error then
      logger.warn("Failed to save database to cache: " .. save_error)
    end
    callback(data, nil)
  end)
end

---Get README content for a repository, with caching support
---@param repo Repository
---@param callback fun(data: string[]|nil, error: string|nil) Callback function with README lines or error
function M.get_readme(repo, callback)
  logger.debug("get_readme called for " .. repo.full_name)

  local cached_readme, cache_error = cache.get_readme(repo.full_name)
  if cached_readme and not cache_error then
    logger.debug("Using cached README for " .. repo.full_name)
    callback(cached_readme, nil)
    return
  end
  if cache_error then
    logger.warn("Cache error during get_readme for " .. repo.full_name .. ": " .. cache_error)
  end

  logger.debug("Fetching README from network for " .. repo.full_name)
  github_client.get_readme(repo, function(data, error)
    if error then
      logger.debug("README fetch failed for " .. repo.full_name .. ": " .. error)
      callback(nil, error)
      return
    end

    -- Save to cache for future requests
    local save_error = cache.save_readme(repo.full_name, data)
    if save_error then
      logger.warn("Failed to save README to cache for " .. repo.full_name .. ": " .. save_error)
    end
    callback(data, nil)
  end)
end

---Get list of installed plugins from lazy-lock.json
---@param callback fun(data: table<string, boolean>|nil, error: string|nil) Callback function with plugin lookup table or error
function M.get_installed_plugins(callback)
  local config_path = vim.fn.stdpath("config")
  local lazy_lock_path = config_path .. "/lazy-lock.json"

  -- Check if file exists
  if vim.fn.filereadable(lazy_lock_path) == 0 then
    logger.debug("lazy-lock.json not found at: " .. lazy_lock_path)
    callback({}, nil) -- Return empty table, not an error
    return
  end

  -- Read and parse the file
  local success, content = pcall(vim.fn.readfile, lazy_lock_path)
  if not success then
    callback(nil, "Failed to read lazy-lock.json: " .. tostring(content))
    return
  end

  local json_content = table.concat(content, "\n")
  local json_success, data = pcall(vim.json.decode, json_content)
  if not json_success then
    callback(nil, "Failed to parse lazy-lock.json: " .. tostring(data))
    return
  end

  -- Convert to lookup table (just set all keys to true)
  local plugin_lookup = {}
  local count = 0
  for plugin_name, _ in pairs(data) do
    plugin_lookup[plugin_name] = true
    count = count + 1
  end

  callback(plugin_lookup, nil)
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
