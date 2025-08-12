local db_utils = require("store.database.utils")
local validators = require("store.validators")
local Path = require("store.plenary.path")
local config = require("store.config")
local logger = require("store.logger").createLogger({ context = "cache" })

local M = {}

-- In-memory cache storage (no timestamps, just recent data)
---@type Database|nil
local db_memory_cache = nil

---@type table<string, string[]> -- maps plugin full_name to README content lines
local readmes_memory_cache = {}

---Save README content to cache
---@param full_name string The repository full_name (e.g., "owner/repo")
---@param content string[] The processed README content lines
---@return string|nil error Error message if save failed, nil on success
function M.save_readme(full_name, content)
  local err = validators.should_be_string(full_name, "full_name must be a string")
  if err then
    return err
  end
  err = validators.should_be_table(content, "content must be a table of string")
  if err then
    return err
  end

  -- Update memory cache
  readmes_memory_cache[full_name] = content

  -- Update file cache
  local cache_dir = db_utils.get_cache_dir()
  local readme_key = db_utils.repository_to_readme_key(full_name)
  local readme_file = cache_dir / readme_key

  -- Ensure cache directory exists
  if not cache_dir:exists() then
    cache_dir:mkdir({ parents = true })
  end

  -- Write README content
  vim.schedule(function()
    local success, err = pcall(function()
      readme_file:write(table.concat(content, "\n"), "w")
    end)

    if not success then
      logger.error("Failed to save README cache for " .. full_name .. ": " .. tostring(err))
    end
  end)

  return nil -- Success
end

---Save database to cache
---@param content Database The database to save
---@return string|nil error Error message if save failed, nil on success
function M.save_db(content)
  local err = validators.should_be_table(content, "content must be a table of string")
  if err then
    return err
  end

  -- Update memory cache
  db_memory_cache = content

  -- Update file cache
  local cache_dir = db_utils.get_cache_dir()
  local db_file = cache_dir / "db.json"

  -- Ensure cache directory exists
  if not cache_dir:exists() then
    cache_dir:mkdir({ parents = true })
  end

  vim.schedule(function()
    local success, err = pcall(function()
      db_file:write(vim.json.encode(content), "w")
    end)
    if not success then
      return logger.error("Failed to save database cache: " .. tostring(err))
    end
  end)

  return nil -- Success
end

---Get cached README content
---@param full_name string The repository full_name (e.g., "owner/repo")
---@return string[]|nil content The README content as array of lines, nil if not cached or stale
---@return string|nil error Error message if an error occurred
function M.get_readme(full_name)
  if not full_name then
    return nil, "get_readme: missing required parameter 'full_name'"
  end

  -- Check memory cache first
  local memory_content = readmes_memory_cache[full_name]
  if memory_content then
    logger.debug("Cache hit (memory): " .. full_name)
    return memory_content, nil
  end

  -- Check file cache second
  local cache_dir = db_utils.get_cache_dir()
  local readme_key = db_utils.repository_to_readme_key(full_name)
  local readme_file = cache_dir / readme_key

  -- Check if file exists
  if not readme_file:exists() then
    logger.debug("Cache miss: " .. full_name)
    return nil, nil
  end

  -- Check if file is not stale
  local max_age_seconds = config.get().cache_duration
  local stat, err = vim.loop.fs_stat(readme_file:absolute())
  if not stat then
    return nil, "Could not stat README cache file: " .. readme_file:absolute() .. ", error - " .. err
  end

  local age = os.time() - stat.mtime.sec
  if age > max_age_seconds then
    logger.debug("Stale cache removed: " .. age .. "s old")
    -- Delete stale file
    vim.schedule(function()
      local ok, del_err = pcall(function()
        readme_file:rm()
      end)
      if not ok then
        logger.warn("Failed to delete stale README cache file: " .. tostring(del_err))
      end
    end)
    return nil, nil -- Not an error, just needs refresh
  end

  -- Read content from file
  local success, file_content = pcall(function()
    local raw_content = readme_file:read()
    return vim.split(raw_content, "\n", { plain = true })
  end)

  if not success then
    return nil, "Failed to read README cache file: " .. readme_file:absolute() .. " - " .. tostring(file_content)
  end

  -- Update memory cache with file content
  readmes_memory_cache[full_name] = file_content
  logger.debug("Cache hit (file): " .. full_name)
  return file_content, nil
end

---Get cached database
---@return Database|nil content The database, nil if not cached or stale
---@return string|nil error Error message if an error occurred
function M.get_db()
  -- Check memory cache first
  if db_memory_cache then
    logger.debug("Database cache hit (memory)")
    return db_memory_cache, nil
  end

  -- Check file cache second
  local cache_dir = db_utils.get_cache_dir()
  local db_file = cache_dir / "db.json"

  if not db_file:exists() then
    logger.debug("Database cache miss")
    return nil, nil
  end

  -- Check if file exists and is not stale
  local max_age_seconds = config.get().cache_duration

  local stat, err = vim.loop.fs_stat(db_file:absolute())
  if not stat or err ~= nil then
    return nil, "Could not stat database cache file: " .. db_file:absolute() .. ", error - " .. err
  end

  local age = os.time() - stat.mtime.sec
  if age > max_age_seconds then
    logger.debug("Stale cache removed: " .. age .. "s old")
    -- Delete stale file
    vim.schedule(function()
      local ok, del_err = pcall(function()
        db_file:rm()
      end)
      if not ok then
        logger.warn("Failed to delete stale database cache file: " .. tostring(del_err))
      end
    end)
    return nil, nil
  end

  -- Read and parse content
  local success, content = pcall(function()
    return vim.json.decode(db_file:read())
  end)

  if not success then
    return nil, "Failed to read database cache file: " .. db_file:absolute() .. " - " .. tostring(content)
  end

  -- Update memory cache with file content
  db_memory_cache = content
  logger.debug("Database cache hit (file)")
  return content, nil
end

---Clear all in-memory caches
function M.clear_memory_cache()
  readmes_memory_cache = {}
  db_memory_cache = nil
end

---Clear all file caches
---@return string|nil error Error message if clear failed, nil on success
function M.clear_file_cache()
  local cache_dir = db_utils.get_cache_dir()

  if not cache_dir:exists() then
    return nil -- Success, nothing to clear
  end

  -- Delete entire cache directory
  local ok, err = pcall(function()
    cache_dir:rm({ recursive = true })
  end)

  if not ok then
    return "Failed to delete cache directory: " .. tostring(err)
  end

  -- Recreate empty cache directory
  local create_ok, create_err = pcall(function()
    cache_dir:mkdir({ parents = true })
  end)

  if not create_ok then
    return "Failed to recreate cache directory: " .. tostring(create_err)
  end

  return nil -- Success
end

---Clear all caches (memory + file)
---@return string|nil error Error message if clear failed, nil on success
function M.clear_all_caches()
  logger.debug("Clearing all caches")
  M.clear_memory_cache()

  local file_error = M.clear_file_cache()
  if file_error then
    return file_error
  end

  logger.info("Cache cleared")
  return nil -- Success
end

return M
