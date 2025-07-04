local curl = require("plenary.curl")
local cache = require("store.cache")

---@class Repository
---@field full_name string Repository full name (owner/repo)
---@field description string Repository description
---@field homepage string Repository homepage URL
---@field html_url string Repository GitHub URL
---@field stargazers_count number Number of stars
---@field watchers_count number Number of watchers
---@field fork_count number Number of forks
---@field updated_at string Last updated timestamp (ISO 8601)
---@field topics string[] Array of topic tags

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

M.gist_url =
  "https://gist.githubusercontent.com/alex-popov-tech/93dcd3ce38cbc7a0b3245b9b59b56c9b/raw/store.nvim-repos.json"

---Fetch plugins from the gist URL, with caching support
---@param callback fun(data: PluginsData|nil, error: string|nil) Callback function with plugins data or error
function M.fetch_plugins(callback)
  -- Check cache first (now includes memory + file internally)
  local cached_data, is_valid = cache.list_plugins()
  if is_valid then
    callback(cached_data, nil)
    return
  end

  -- Fallback to network request
  curl.get(M.gist_url, {
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
function M.get_readme(repo_path, callback)
  if not repo_path or not repo_path:match("^[^/]+/[^/]+$") then
    callback({ error = "Invalid repository path format. Expected 'owner/repo'" })
    return
  end

  -- Check cache first (now includes memory + file internally)
  local plugin_url = "https://github.com/" .. repo_path
  local cached_readme, is_valid = cache.get_readme(plugin_url)
  if is_valid then
    callback({ body = cached_readme })
    return
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
          local lines = {}
          for _, line in ipairs(vim.split(content, "\n", { plain = true })) do
            -- Only remove trailing whitespace, preserve leading whitespace (indentation)
            local trimmed_line = line:gsub("%s+$", "")
            local cleaned_line = strip_html_tags(trimmed_line)
            table.insert(lines, cleaned_line)
          end

          -- Post-process to remove standalone markdown inline images
          local image_filtered_lines = {}
          for _, line in ipairs(lines) do
            -- Skip lines that are just markdown images (![alt](url))
            -- Match lines that start with ![, contain ](, and end with )
            if line:match("^%s*!%[[^%]]*%]%(.-%)%s*$") then
              -- Skip this line as it's a standalone markdown image
            else
              table.insert(image_filtered_lines, line)
            end
          end
          lines = image_filtered_lines

          -- Post-process to collapse multiple consecutive empty lines
          local collapsed_lines = {}
          local prev_was_empty = false

          for _, line in ipairs(lines) do
            local is_empty = line == ""

            if is_empty and prev_was_empty then
              -- Skip this empty line since previous was also empty
            else
              table.insert(collapsed_lines, line)
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
