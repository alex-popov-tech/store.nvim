local Path = require("plenary.path")
local log = require('plenary.log').new({
  plugin = 'store.nvim',
  level = 'debug',
  use_console = false,
})

local M = {}

-- Default cache duration: 24 hours
local DEFAULT_CACHE_MAX_AGE = 24 * 60 * 60

-- In-memory cache storage
local readmes_memory_cache = {}
local plugins_memory_cache = {}

-- Get the cache directory path
local function get_cache_dir()
  return Path:new(vim.fn.stdpath("cache"), "store.nvim")
end

-- Convert GitHub URL to unique filename
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

-- Check if a file is stale based on modification time
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

-- Check if a memory cached item is stale based on timestamp
local function is_memory_cache_stale(cache_item, max_age_seconds)
  max_age_seconds = max_age_seconds or DEFAULT_CACHE_MAX_AGE

  if not cache_item or not cache_item.timestamp then
    return true
  end

  local age = os.time() - cache_item.timestamp
  return age > max_age_seconds
end

-- Read the readmes mapping file
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

-- Write the readmes mapping file
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
    log.warn("Failed to write readmes cache: " .. tostring(err))
  end

  return success
end

-- Public API: Save README content and update mapping
function M.save_readme(plugin_url, content)
  if not plugin_url or not content then
    return false
  end

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
    log.warn("Failed to save README cache: " .. tostring(err))
    return false
  end

  -- Update readmes mapping
  local mapping = read_readmes_mapping()
  mapping[plugin_url] = {
    filename = filename,
    updated_at = os.time(),
  }

  return write_readmes_mapping(mapping)
end

-- Public API: Save plugins data
function M.save_plugins(content)
  if not content then
    return false
  end

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
    log.warn("Failed to save plugins cache: " .. tostring(err))
  end

  return success
end

-- Public API: Get cached README content
function M.get_readme(plugin_url)
  if not plugin_url then
    return {}, false
  end

  -- Check memory cache first
  local memory_item = readmes_memory_cache[plugin_url]
  if memory_item and not is_memory_cache_stale(memory_item) then
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
    return {}, false
  end

  local readme_file = cache_dir / readme_info.filename

  -- Check if file exists and is not stale
  if is_file_stale(readme_file) then
    return {}, false
  end

  -- Read content from file
  local success, content = pcall(function()
    local raw_content = readme_file:read()
    return vim.split(raw_content, "\n", { plain = true })
  end)

  if success then
    -- Update memory cache with file content
    readmes_memory_cache[plugin_url] = {
      content = content,
      timestamp = os.time(),
    }
    return content, true
  else
    return {}, false
  end
end

-- Public API: Get cached plugins data
function M.list_plugins()
  -- Check memory cache first
  if plugins_memory_cache and not is_memory_cache_stale(plugins_memory_cache) then
    return plugins_memory_cache.content, true
  end

  -- Check file cache second
  local cache_dir = get_cache_dir()
  local plugins_file = cache_dir / "plugins.json"

  -- Check if file exists and is not stale
  if is_file_stale(plugins_file) then
    return {}, false
  end

  -- Read and parse content
  local success, content = pcall(function()
    return vim.json.decode(plugins_file:read())
  end)

  if success then
    -- Update memory cache with file content
    plugins_memory_cache = {
      content = content,
      timestamp = os.time(),
    }
    return content, true
  else
    return {}, false
  end
end

return M

