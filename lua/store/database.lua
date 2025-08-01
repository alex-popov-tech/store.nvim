local curl = require("store.plenary.curl")
local cache = require("store.cache")
local config = require("store.config")
local utils = require("store.utils")
local logger = require("store.logger")

local M = {}

---Fetch plugins from the gist URL, with caching support
---@param callback fun(data: Database|nil, error: string|nil) Callback function with plugins data or error
---@param force_refresh? boolean Optional flag to bypass cache and force network request
function M.fetch_plugins(callback, force_refresh)
  -- Check cache first unless force refresh is requested
  if not force_refresh then
    local cached_data, is_valid = cache.list_plugins()
    if is_valid then
      -- Check if version field exists in meta
      if cached_data.meta and cached_data.meta.version then
        callback(cached_data, nil)
        return
      else
        -- Version field missing, force refresh
        logger.debug("Cache missing version field, forcing refresh")
        -- Continue to network fetch below
      end
    end
  end

  -- Fallback to network request
  curl.get(config.get().data_source_url, {
    headers = {
      ["Accept"] = "application/json",
      ["User-Agent"] = "store.nvim",
    },
    timeout = 10000,
    callback = function(response)
      if response.status ~= 200 then
        logger.error("Failed to fetch data: HTTP " .. response.status .. " " .. response.body)
        callback(nil, "Failed to fetch data: HTTP " .. response.status)
        return
      end

      local success, data = pcall(vim.json.decode, response.body)
      if not success then
        logger.error("Failed to fetch data: HTTP " .. data)
        callback(nil, "Failed to parse JSON: " .. data)
        return
      end

      -- Save to cache for future requests (includes memory + file internally)
      vim.schedule(function()
        cache.save_plugins(data)
      end)
      callback(data, nil)
    end,
  })
end

-- Process README content in a single pass: clean HTML tags, filter images, and collapse empty lines
---@param lines string[] Array of raw README lines
---@return string[] Processed lines with HTML tags removed, images filtered, and empty lines collapsed
local function process_readme_content(lines)
  local processed = {}
  local count = 0
  local prev_was_empty = false
  local in_code_block = false

  for i = 1, #lines do
    local line = lines[i]

    -- Check for fenced code block markers (```)
    local code_fence_match = line:match("^%s*```")
    if code_fence_match then
      in_code_block = not in_code_block
      -- Process the fence line normally (trim it)
      local trimmed_line = line:match("^%s*(.-)%s*$")
      count = count + 1
      processed[count] = trimmed_line
      prev_was_empty = false
    elseif in_code_block then
      -- Inside code block - preserve original whitespace
      count = count + 1
      processed[count] = line
      prev_was_empty = false
    else
      -- Outside code block - apply normal processing
      -- OPTIMIZATION: Early empty line detection - trim both leading and trailing whitespace
      local trimmed_line = line:match("^%s*(.-)%s*$")
      if trimmed_line == "" then
        -- Skip expensive processing for empty lines - go directly to step 3
        if not prev_was_empty then
          count = count + 1
          processed[count] = ""
        end
        prev_was_empty = true
      elseif trimmed_line:match("^!%[[^%]]*%]%(.-%)$") then
        -- OPTIMIZATION: Early image detection (before HTML processing) - skip images
        -- Treat skipped images as empty content for empty line collapsing
        if not prev_was_empty then
          count = count + 1
          processed[count] = ""
        end
        prev_was_empty = true
      else
        -- OPTIMIZATION: Conditional HTML tag processing - check for '<' first (cheaper)
        if trimmed_line:find("<", 1, true) then
          if trimmed_line:find("<%s*[^>]*>") then
            trimmed_line = utils.strip_html_tags(trimmed_line)
          end
        end

        -- Check if after processing, the line became empty
        if trimmed_line == "" then
          -- Treat processed-to-empty lines like empty lines for collapsing
          if not prev_was_empty then
            count = count + 1
            processed[count] = ""
          end
          prev_was_empty = true
        else
          -- Step 3: Add non-empty line to processed output
          count = count + 1
          processed[count] = trimmed_line
          prev_was_empty = false
        end
      end
    end
  end

  return processed
end

---Get README content for a repository, with caching support
---@param repo_path string Repository path in format 'owner/repo'
---@param callback fun(data: string[]|nil, error: string|nil) Callback function with README lines or error
---@param force_refresh? boolean Optional flag to bypass cache and force network request
function M.get_readme(repo_path, callback, force_refresh)
  if not repo_path or not repo_path:match("^[^/]+/[^/]+$") then
    logger.error("Invalid repository path format. Expected 'owner/repo'")
    callback(nil, "Invalid repository path format. Expected 'owner/repo'")
    return
  end

  -- Check cache first unless force refresh is requested
  local plugin_url = "https://github.com/" .. repo_path
  if not force_refresh then
    local cached_readme, is_valid = cache.get_readme(plugin_url)
    if is_valid then
      callback(cached_readme, nil)
      return
    end
  end

  -- Fallback to network request
  local api_url = "https://api.github.com/repos/" .. repo_path .. "/readme"
  local headers = {
    ["User-Agent"] = "store.nvim",
    ["Accept"] = "application/vnd.github.v3+json",
  }

  -- Add GitHub token to headers if provided
  local github_token = config.get().github_token
  if github_token then
    headers["Authorization"] = "Bearer " .. github_token
  end

  curl.get(api_url, {
    headers = headers,
    timeout = 10000,
    callback = function(response)
      local success = response.status >= 200 and response.status < 300
      if not success then
        logger.error("Failed to fetch README from GitHub API: HTTP " .. response.status .. " " .. response.body)
        callback(nil, response.body or "Failed to fetch README from GitHub API")
        return
      end

      local json_success, json_data = pcall(vim.json.decode, response.body)
      if not json_success or not json_data then
        logger.error("Failed to parse GitHub API response")
        callback(nil, "Failed to parse GitHub API response")
        return
      end

      local clean_content = json_data.content:gsub("\n", "")
      local content = vim.base64.decode(clean_content)
      local split_lines = vim.split(content, "\n", { plain = true })

      -- Process/clean README content in a single optimized pass
      local lines = process_readme_content(split_lines)

      -- Save to cache for future requests (includes memory + file internally)
      vim.schedule(function()
        cache.save_readme(plugin_url, lines)
      end)

      callback(lines, nil)
    end,
  })
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
    logger.error("Failed to read lazy-lock.json: " .. tostring(content))
    callback(nil, "Failed to read lazy-lock.json: " .. tostring(content))
    return
  end

  local json_content = table.concat(content, "\n")
  local json_success, data = pcall(vim.json.decode, json_content)
  if not json_success then
    logger.error("Failed to parse lazy-lock.json: " .. tostring(data))
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

  logger.debug("Found " .. count .. " installed plugins")
  callback(plugin_lookup, nil)
end

return M
