local db_utils = require("store.database.utils")
local validators = require("store.validators")
local logger = require("store.logger").createLogger({ context = "cache" })

local M = {}

local INSTALL_CACHE_FILES = {
  ["lazy.nvim"] = "lazy.nvim.json",
  ["vim.pack"] = "vim.pack.json",
}

-- In-memory cache storage (no timestamps, just recent data)
---@type Database|nil
local db_memory_cache = nil

---@type table<string, string[]> -- maps plugin full_name to README content lines
local readmes_memory_cache = {}

---@type table<string, table|nil>
local install_catalogue_memory_cache = {}

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
  local processed_content = table.concat(content, "\n")

  vim.schedule(function()
    local success, err = pcall(function()
      readme_file:write(processed_content, "w")
    end)

    if not success then
      logger.error("Failed to save README cache for " .. full_name .. ": " .. tostring(err))
      return
    end

    logger.debug("💾 README SAVED: " .. full_name .. " (" .. #processed_content .. " bytes)")
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

---Persist install catalogue for a specific plugin manager
---@param manager string Plugin manager identifier ("lazy.nvim"|"vim.pack")
---@param content table Catalogue JSON payload
---@return string|nil error Error message if save failed, nil on success
function M.save_install_catalogue(manager, content)
  local cache_filename = INSTALL_CACHE_FILES[manager]
  if not cache_filename then
    return "Unknown plugin manager: " .. tostring(manager)
  end

  local err = validators.should_be_table(content, "content must be a table")
  if err then
    return err
  end

  install_catalogue_memory_cache[manager] = content

  local cache_dir = db_utils.get_cache_dir()
  local cache_file = cache_dir / cache_filename

  if not cache_dir:exists() then
    cache_dir:mkdir({ parents = true })
  end

  vim.schedule(function()
    local success, write_err = pcall(function()
      cache_file:write(vim.json.encode(content), "w")
    end)
    if not success then
      logger.error("Failed to save install catalogue for " .. manager .. ": " .. tostring(write_err))
    end
  end)

  return nil
end

---Get cached README content with cache type
---@param full_name string The repository full_name (e.g., "owner/repo")
---@return "memory"|"file"|"none" cache_type Type of cache found
---@return string[]|nil content The README content as array of lines, nil if not cached
function M.get_readme(full_name)
  if not full_name then
    return "none", nil
  end

  -- Check memory cache first
  local memory_content = readmes_memory_cache[full_name]
  if memory_content then
    logger.debug("📦 README Memory cache hit: " .. full_name)
    return "memory", memory_content
  end

  -- Check file cache second
  local cache_dir = db_utils.get_cache_dir()
  local readme_key = db_utils.repository_to_readme_key(full_name)
  local readme_file = cache_dir / readme_key

  -- Check if file exists
  if not readme_file:exists() then
    logger.debug("❌ README Cache miss: " .. full_name)
    return "none", nil
  end

  -- Read content from file
  local success, file_content = pcall(function()
    local raw_content = readme_file:read()
    return vim.split(raw_content, "\n", { plain = true })
  end)

  if not success then
    return "none", nil
  end

  -- Update memory cache with file content
  readmes_memory_cache[full_name] = file_content
  logger.debug("📁 README File cache hit: " .. full_name)
  return "file", file_content
end

---Get cached database with cache type
---@return "memory"|"file"|"none" cache_type Type of cache found
---@return Database|nil data The database, nil if not cached
function M.get_db()
  -- Check memory cache first
  if db_memory_cache then
    logger.debug("📦 Memory cache hit")
    return "memory", db_memory_cache
  end

  -- Check file cache second
  local cache_dir = db_utils.get_cache_dir()
  local db_file = cache_dir / "db.json"

  if not db_file:exists() then
    logger.debug("❌ No cache file")
    return "none", nil
  end

  -- Get file stats and read content
  local stat, err = vim.loop.fs_stat(db_file:absolute())
  if not stat or err ~= nil then
    return "none", nil
  end

  -- Read and parse content
  local success, content = pcall(function()
    return vim.json.decode(db_file:read())
  end)

  if not success then
    return "none", nil
  end

  -- Update memory cache with file content
  db_memory_cache = content
  logger.debug("📁 File cache hit: " .. stat.size .. " bytes")
  return "file", content
end

---Retrieve cached install catalogue for a plugin manager
---@param manager string Plugin manager identifier
---@return "memory"|"file"|"none" cache_type Cache source type
---@return table|nil content Catalogue payload or nil
function M.get_install_catalogue(manager)
  local cache_filename = INSTALL_CACHE_FILES[manager]
  if not cache_filename then
    return "none", nil
  end

  local memory_catalogue = install_catalogue_memory_cache[manager]
  if memory_catalogue then
    logger.debug("📦 Install catalogue memory cache hit for manager: " .. manager)
    return "memory", memory_catalogue
  end

  local cache_dir = db_utils.get_cache_dir()
  local cache_file = cache_dir / cache_filename

  if not cache_file:exists() then
    logger.debug("❌ Install catalogue cache miss for manager: " .. manager)
    return "none", nil
  end

  local success, content = pcall(function()
    return vim.json.decode(cache_file:read())
  end)

  if not success then
    logger.warn("Failed to read install catalogue cache for " .. manager .. ": " .. tostring(content))
    return "none", nil
  end

  install_catalogue_memory_cache[manager] = content
  logger.debug("📁 Install catalogue file cache hit for manager: " .. manager)
  return "file", content
end

---Clear all in-memory caches
function M.clear_memory_cache()
  readmes_memory_cache = {}
  db_memory_cache = nil
  install_catalogue_memory_cache = {}
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
