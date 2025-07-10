local Path = require("plenary.path")
local logger = require("store.logger")

---@class CacheItem
---@field content any The cached content
---@field timestamp number Unix timestamp when the item was cached

---@class ReadmeCacheItem
---@field content string[] README content as array of lines
---@field timestamp number Unix timestamp when the item was cached

---@class PluginsCacheItem
---@field content PluginsData Plugin data structure
---@field timestamp number Unix timestamp when the item was cached

---@class ReadmeInfo
---@field filename string The filename where the README is stored
---@field updated_at number Unix timestamp when the README was last updated

---@class ReadmesMapping
---@field [string] ReadmeInfo Mapping from plugin URL to ReadmeInfo

local M = {}

-- Default cache duration: 24 hours
local DEFAULT_CACHE_MAX_AGE = 24 * 60 * 60

-- In-memory cache storage
---@type table<string, ReadmeCacheItem>
local readmes_memory_cache = {}
---@type PluginsCacheItem
local plugins_memory_cache = {
  content = { crawled_at = "", total_repositories = 0, repositories = {} },
  timestamp = 0,
}

---Get the cache directory path
---@return Path cache_dir The cache directory path object
local function get_cache_dir()
  return Path:new(vim.fn.stdpath("cache"), "store.nvim")
end

---Convert GitHub URL to unique filename
---@param url string GitHub repository URL
---@return string filename Unique filename for the repository
local function url_to_filename(url)
  -- Extract owner/repo from https://github.com/owner/repo
  local owner_repo = url:match("github%.com/([^/]+/[^/]+)")
  if owner_repo then
    return "readme-" .. owner_repo:gsub("/", "-") .. ".md"
  else
    -- Fallback to hash if URL format is unexpected
    local hash = 0
    for i = 1, string.len(url) do
      hash = hash + string.byte(url, i) * i
    end
    return "readme-" .. tostring(hash) .. ".md"
  end
end

---Check if a file is stale based on modification time
---@param file_path Path The file path to check
---@param max_age_seconds? number Maximum age in seconds (default: 24 hours)
---@return boolean is_stale True if file is stale or doesn't exist
local function is_file_stale(file_path, max_age_seconds)
  max_age_seconds = max_age_seconds or DEFAULT_CACHE_MAX_AGE

  if not file_path:exists() then
    return true
  end

  local stat = vim.loop.fs_stat(file_path:absolute())
  if not stat then
    return true
  end

  local age = os.time() - stat.mtime.sec
  return age > max_age_seconds
end

---Check if a memory cached item is stale based on timestamp
---@param cache_item ReadmeCacheItem|PluginsCacheItem|nil The cache item to check
---@param max_age_seconds? number Maximum age in seconds (default: 24 hours)
---@return boolean is_stale True if item is stale or doesn't exist
local function is_memory_cache_stale(cache_item, max_age_seconds)
  max_age_seconds = max_age_seconds or DEFAULT_CACHE_MAX_AGE

  if not cache_item or not cache_item.timestamp then
    return true
  end

  local age = os.time() - cache_item.timestamp
  return age > max_age_seconds
end

---Read the readmes mapping file
---@return ReadmesMapping mapping The readmes mapping or empty table if not found
local function read_readmes_mapping()
  local cache_dir = get_cache_dir()
  local readmes_file = cache_dir / "readmes.json"

  if not readmes_file:exists() then
    return {}
  end

  local success, content = pcall(function()
    return vim.json.decode(readmes_file:read())
  end)

  return success and content or {}
end

---Write the readmes mapping file
---@param mapping ReadmesMapping The mapping to write
---@return boolean success True if successfully written
local function write_readmes_mapping(mapping)
  local cache_dir = get_cache_dir()

  -- Ensure cache directory exists
  if not cache_dir:exists() then
    cache_dir:mkdir({ parents = true })
  end

  local readmes_file = cache_dir / "readmes.json"
  local success, err = pcall(function()
    readmes_file:write(vim.json.encode(mapping), "w")
  end)

  if not success then
    logger.warn("Failed to write readmes cache: " .. tostring(err))
  end

  return success
end

---Save README content and update mapping
---@param plugin_url string The GitHub repository URL
---@param content string|string[] The README content (string or array of lines)
---@return boolean success True if successfully saved
function M.save_readme(plugin_url, content)
  if not plugin_url or not content then
    logger.warn("save_readme called with missing parameters")
    return false
  end

  logger.debug("Saving README to cache for: " .. plugin_url)

  -- Update memory cache first
  readmes_memory_cache[plugin_url] = {
    content = content,
    timestamp = os.time(),
  }

  -- Then update file cache
  local cache_dir = get_cache_dir()
  local filename = url_to_filename(plugin_url)
  local readme_file = cache_dir / filename

  -- Ensure cache directory exists
  if not cache_dir:exists() then
    cache_dir:mkdir({ parents = true })
  end

  -- Write README content
  local lines = type(content) == "table" and content or { tostring(content) }
  local success, err = pcall(function()
    readme_file:write(table.concat(lines, "\n"), "w")
  end)

  if not success then
    logger.error("Failed to save README cache: " .. tostring(err))
    return false
  end

  logger.debug("README saved successfully to: " .. readme_file:absolute())

  -- Update readmes mapping
  local mapping = read_readmes_mapping()
  mapping[plugin_url] = {
    filename = filename,
    updated_at = os.time(),
  }

  return write_readmes_mapping(mapping)
end

---Save plugins data to cache
---@param content PluginsData The plugins data to save
---@return boolean success True if successfully saved
function M.save_plugins(content)
  if not content then
    logger.warn("save_plugins called with missing content")
    return false
  end

  logger.debug("Saving plugins data to cache")

  -- Update memory cache first
  plugins_memory_cache = {
    content = content,
    timestamp = os.time(),
  }

  -- Then update file cache
  local cache_dir = get_cache_dir()
  local plugins_file = cache_dir / "plugins.json"

  -- Ensure cache directory exists
  if not cache_dir:exists() then
    cache_dir:mkdir({ parents = true })
  end

  local success, err = pcall(function()
    plugins_file:write(vim.json.encode(content), "w")
  end)

  if not success then
    logger.error("Failed to save plugins cache: " .. tostring(err))
  else
    logger.debug("Plugins data saved successfully")
  end

  return success
end

---Get cached README content
---@param plugin_url string The GitHub repository URL
---@return string[] content The README content as array of lines
---@return boolean is_valid True if cache hit and content is valid
function M.get_readme(plugin_url)
  if not plugin_url then
    logger.warn("get_readme called with missing plugin_url")
    return {}, false
  end

  -- Check memory cache first
  local memory_item = readmes_memory_cache[plugin_url]
  if memory_item and not is_memory_cache_stale(memory_item) then
    logger.debug("README cache hit (memory) for: " .. plugin_url)
    local content = memory_item.content
    if type(content) == "table" then
      return content, true
    else
      return vim.split(tostring(content), "\n", { plain = true }), true
    end
  end

  -- Check file cache second
  local cache_dir = get_cache_dir()
  local mapping = read_readmes_mapping()
  local readme_info = mapping[plugin_url]

  if not readme_info then
    logger.debug("No cache entry found for: " .. plugin_url)
    return {}, false
  end

  local readme_file = cache_dir / readme_info.filename

  -- Check if file exists and is not stale
  if is_file_stale(readme_file) then
    logger.debug("README cache file is stale: " .. readme_file:absolute())
    return {}, false
  end

  -- Read content from file
  local success, content = pcall(function()
    local raw_content = readme_file:read()
    return vim.split(raw_content, "\n", { plain = true })
  end)

  if success then
    logger.debug("README cache hit (file) for: " .. plugin_url)
    -- Update memory cache with file content
    readmes_memory_cache[plugin_url] = {
      content = content,
      timestamp = os.time(),
    }
    return content, true
  else
    logger.error("Failed to read README cache file: " .. readme_file:absolute())
    return {}, false
  end
end

---Get cached plugins data
---@return PluginsData content The plugins data
---@return boolean is_valid True if cache hit and content is valid
function M.list_plugins()
  -- Check memory cache first
  if not is_memory_cache_stale(plugins_memory_cache) then
    logger.debug("Plugins cache hit (memory)")
    return plugins_memory_cache.content, true
  end

  -- Check file cache second
  local cache_dir = get_cache_dir()
  local plugins_file = cache_dir / "plugins.json"

  -- Check if file exists and is not stale
  if is_file_stale(plugins_file) then
    logger.debug("Plugins cache file is stale: " .. plugins_file:absolute())
    return {}, false
  end

  -- Read and parse content
  local success, content = pcall(function()
    return vim.json.decode(plugins_file:read())
  end)

  if success then
    logger.debug("Plugins cache hit (file)")
    -- Update memory cache with file content
    plugins_memory_cache = {
      content = content,
      timestamp = os.time(),
    }
    return content, true
  else
    logger.error("Failed to read plugins cache file: " .. plugins_file:absolute())
    return {}, false
  end
end

---Clear all in-memory caches
function M.clear_memory_cache()
  logger.debug("Clearing memory cache")
  readmes_memory_cache = {}
  plugins_memory_cache = {
    content = { crawled_at = "", total_repositories = 0, repositories = {} },
    timestamp = 0,
  }
end

---Clear all file caches
function M.clear_file_cache()
  logger.debug("Clearing file cache")
  local cache_dir = get_cache_dir()
  
  if not cache_dir:exists() then
    logger.debug("Cache directory doesn't exist, nothing to clear")
    return true
  end
  
  local success = true
  
  -- Delete plugins.json file
  local plugins_file = cache_dir / "plugins.json"
  if plugins_file:exists() then
    local ok, err = pcall(function() plugins_file:rm() end)
    if not ok then
      logger.warn("Failed to delete plugins cache file: " .. tostring(err))
      success = false
    end
  end
  
  -- Delete readmes.json file
  local readmes_file = cache_dir / "readmes.json"
  if readmes_file:exists() then
    local ok, err = pcall(function() readmes_file:rm() end)
    if not ok then
      logger.warn("Failed to delete readmes mapping file: " .. tostring(err))
      success = false
    end
  end
  
  -- Delete all README files
  local readme_pattern = cache_dir / "readme-*.md"
  local readme_files = vim.fn.glob(readme_pattern:absolute(), false, true)
  for _, file_path in ipairs(readme_files) do
    local readme_file = Path:new(file_path)
    local ok, err = pcall(function() readme_file:rm() end)
    if not ok then
      logger.warn("Failed to delete README cache file " .. file_path .. ": " .. tostring(err))
      success = false
    end
  end
  
  return success
end

---Clear all caches (memory + file)
---@return boolean success True if all caches were cleared successfully
function M.clear_all_caches()
  logger.debug("Clearing all caches")
  M.clear_memory_cache()
  local file_success = M.clear_file_cache()
  
  if file_success then
    logger.debug("All caches cleared successfully")
  else
    logger.warn("Some cache files could not be cleared")
  end
  
  return file_success
end

return M
