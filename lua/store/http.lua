local curl = require("plenary.curl")
local cache = require("store.cache")
local config = require("store.config")

---@class Repository
---@field author string Repository author/owner
---@field name string Repository name
---@field full_name string Repository full name (author/name)
---@field description string Repository description
---@field homepage string Repository homepage URL
---@field html_url string Repository GitHub URL
---@field tags string[] Array of topic tags
---@field pretty_stargazers_count string Formatted number of stars
---@field pretty_forks_count string Formatted number of forks
---@field pretty_open_issues_count string Formatted number of open issues
---@field pretty_pushed_at string Formatted last push time

---@class PluginsDataMeta
---@field total_count number Total number of repositories
---@field max_full_name_length number Maximum length of full name
---@field max_pretty_stargazers_length number Maximum length of formatted stars
---@field max_pretty_forks_length number Maximum length of formatted forks
---@field max_pretty_issues_length number Maximum length of formatted issues
---@field max_pretty_pushed_at_length number Maximum length of formatted push time

---@class PluginsData
---@field meta PluginsDataMeta Metadata about the dataset
---@field items Repository[] Array of repository objects

---@class ReadmeResult
---@field body string[]|nil README content as table of lines
---@field error string|nil Error message if request failed

local M = {}

-- Function to strip HTML tags from markdown content while preserving markdown syntax
-- This function is only called when HTML tags are detected in the content
---@param content string The content to strip HTML tags from (guaranteed to contain HTML)
---@return string The content with HTML tags removed
local function strip_html_tags(content)
  -- Don't process lines that are clearly markdown and should be preserved
  -- Skip code blocks (lines starting with ```)
  if content:match("^```") then
    return content
  end

  -- Skip markdown link syntax [text](url) at start of line
  if content:match("^%s*%[[^%]]*%]%(.-%)") then
    return content
  end

  -- Skip lines that are just ASCII art or similar (contain lots of special chars)
  -- But not if they contain HTML tags (< and >)
  local special_char_count = 0
  local total_chars = #content
  for char in content:gmatch("[^%w%s]") do
    special_char_count = special_char_count + 1
  end
  if total_chars > 0 and (special_char_count / total_chars) > 0.4 and not content:match("[<>]") then
    return content
  end

  -- Remove HTML tags while preserving the content inside them
  local cleaned = content:gsub("<%s*[^>]*>", "")

  -- Clean up extra whitespace that might be left behind
  cleaned = cleaned:gsub("%s+", " ")
  return vim.trim(cleaned)
end

-- Process README lines by cleaning HTML tags and trimming whitespace
---@param lines string[] Array of raw README lines
---@return string[] Processed lines with HTML tags removed and whitespace trimmed
local function process_readme_lines(lines)
  local processed = {}
  for i = 1, #lines do
    local line = lines[i]
    -- Only remove trailing whitespace, preserve leading whitespace (indentation)
    local trimmed_line = line:gsub("%s+$", "")

    -- Only call strip_html_tags if the line contains HTML-like content
    if trimmed_line:find("<%s*[^>]*>") then
      processed[i] = strip_html_tags(trimmed_line)
    else
      processed[i] = trimmed_line
    end
  end
  return processed
end

-- Filter out standalone markdown image lines
---@param lines string[] Array of processed README lines
---@return string[] Lines with standalone images removed
local function filter_standalone_images(lines)
  local filtered = {}
  local count = 0
  for i = 1, #lines do
    local line = lines[i]
    if not line:match("^%s*!%[[^%]]*%]%(.-%)%s*$") then
      count = count + 1
      filtered[count] = line
    end
  end
  return filtered
end

-- Collapse consecutive empty lines into single empty lines
---@param lines string[] Array of README lines
---@return string[] Lines with consecutive empty lines collapsed
local function collapse_empty_lines(lines)
  local collapsed = {}
  local count = 0
  local prev_was_empty = false

  for i = 1, #lines do
    local line = lines[i]
    local is_empty = line == ""

    if not (is_empty and prev_was_empty) then
      count = count + 1
      collapsed[count] = line
    end

    prev_was_empty = is_empty
  end

  return collapsed
end

---Fetch plugins from the gist URL, with caching support
---@param callback fun(data: PluginsData|nil, error: string|nil) Callback function with plugins data or error
---@param force_refresh? boolean Optional flag to bypass cache and force network request
function M.fetch_plugins(callback, force_refresh)
  -- Check cache first unless force refresh is requested
  if not force_refresh then
    local cached_data, is_valid = cache.list_plugins()
    if is_valid then
      callback(cached_data, nil)
      return
    end
  end

  -- Fallback to network request
  local data_source_url = config.get().data_source_url
  curl.get(data_source_url, {
    headers = {
      ["Accept"] = "application/json",
      ["User-Agent"] = "store.nvim/1.0.0",
    },
    timeout = 10000,
    callback = function(response)
      if response.status ~= 200 then
        callback(nil, "Failed to fetch data: HTTP " .. response.status)
        return
      end

      local success, data = pcall(vim.json.decode, response.body)
      if not success then
        callback(nil, "Failed to parse JSON: " .. data)
        return
      end

      -- Save to cache for future requests (includes memory + file internally)
      cache.save_plugins(data)
      callback(data, nil)
    end,
  })
end

---Get README content for a repository, with caching support
---@param repo_path string Repository path in format 'owner/repo'
---@param callback fun(result: ReadmeResult) Callback function with README result (either body or error)
---@param force_refresh? boolean Optional flag to bypass cache and force network request
function M.get_readme(repo_path, callback, force_refresh)
  if not repo_path or not repo_path:match("^[^/]+/[^/]+$") then
    callback({ error = "Invalid repository path format. Expected 'owner/repo'" })
    return
  end

  -- Check cache first unless force refresh is requested
  local plugin_url = "https://github.com/" .. repo_path
  if not force_refresh then
    local cached_readme, is_valid = cache.get_readme(plugin_url)
    if is_valid then
      callback({ body = cached_readme })
      return
    end
  end

  -- Fallback to async network request
  local api_url = string.format("https://api.github.com/repos/%s/readme", repo_path)
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
      if success then
        local json_success, json_data = pcall(vim.json.decode, response.body)
        if json_success and json_data.content then
          local clean_content = json_data.content:gsub("\n", "")
          local content = vim.base64.decode(clean_content)
          local split_lines = vim.split(content, "\n", { plain = true })

          -- Process README content through pipeline
          local lines = process_readme_lines(split_lines)
          lines = filter_standalone_images(lines)
          lines = collapse_empty_lines(lines)

          -- Save to cache for future requests (includes memory + file internally)
          cache.save_readme(plugin_url, lines)

          callback({ body = lines })
        else
          callback({ error = "Failed to parse GitHub API response" })
        end
      else
        callback({ error = response.body or "Failed to fetch README from GitHub API" })
      end
    end,
  })
end

return M
