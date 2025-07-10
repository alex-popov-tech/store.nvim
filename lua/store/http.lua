local curl = require("plenary.curl")
local cache = require("store.cache")
local config = require("store.config")

---@class Repository
---@field full_name string Repository full name (owner/repo)
---@field description string|nil Repository description
---@field homepage string|nil Repository homepage URL
---@field html_url string Repository GitHub URL
---@field stargazers_count number|nil Number of stars
---@field watchers_count number|nil Number of watchers
---@field fork_count number|nil Number of forks
---@field updated_at string|nil Last updated timestamp (ISO 8601)
---@field topics string[]|nil Array of topic tags

---@class PluginsData
---@field crawled_at string Timestamp when data was crawled
---@field total_repositories number Total number of repositories
---@field repositories Repository[] Array of repository objects

---@class ReadmeResult
---@field body string[]|nil README content as table of lines
---@field error string|nil Error message if request failed

local M = {}

-- Function to strip HTML tags from markdown content while preserving markdown syntax
---@param content string|nil The content to strip HTML tags from
---@return string|nil The content with HTML tags removed
local function strip_html_tags(content)
  if not content then
    return content
  end

  -- Don't process lines that are clearly markdown and should be preserved
  -- Skip code blocks (lines starting with ```)
  if content:match("^```") then
    return content
  end

  -- Note: We'll handle markdown images in a separate post-processing step

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

  -- Only strip HTML tags from lines that likely contain HTML
  if content:match("<%s*[^>]*>") then
    -- Remove HTML tags while preserving the content inside them
    local cleaned = content:gsub("<%s*[^>]*>", "")

    -- Clean up extra whitespace that might be left behind
    cleaned = cleaned:gsub("%s+", " ")
    cleaned = vim.trim(cleaned)

    return cleaned
  end

  -- Return original content if no HTML tags found
  return content
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
          local lines = {}

          -- Pre-allocate table for better performance
          local line_count = #split_lines
          for i = 1, line_count do
            local line = split_lines[i]
            -- Only remove trailing whitespace, preserve leading whitespace (indentation)
            local trimmed_line = line:gsub("%s+$", "")
            local cleaned_line = strip_html_tags(trimmed_line)
            lines[i] = cleaned_line -- Direct assignment instead of table.insert
          end

          -- Post-process to remove standalone markdown inline images
          local image_filtered_lines = {}
          local filtered_count = 0
          for i = 1, line_count do
            local line = lines[i]
            -- Skip lines that are just markdown images (![alt](url))
            -- Match lines that start with ![, contain ](, and end with )
            if not line:match("^%s*!%[[^%]]*%]%(.-%)%s*$") then
              filtered_count = filtered_count + 1
              image_filtered_lines[filtered_count] = line -- Direct assignment
            end
          end
          lines = image_filtered_lines

          -- Post-process to collapse multiple consecutive empty lines
          local collapsed_lines = {}
          local collapsed_count = 0
          local prev_was_empty = false

          for i = 1, filtered_count do
            local line = lines[i]
            local is_empty = line == ""

            if not (is_empty and prev_was_empty) then
              collapsed_count = collapsed_count + 1
              collapsed_lines[collapsed_count] = line -- Direct assignment
            end

            prev_was_empty = is_empty
          end

          lines = collapsed_lines

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
