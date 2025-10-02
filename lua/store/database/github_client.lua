local curl = require("store.plenary.curl")
local config = require("store.config")
local db_utils = require("store.database.utils")
local logger = require("store.logger").createLogger({ context = "github" })

---@module "store.database.github_client"
---GitHub HTTP client responsible for fetching data and returning it in parsed state
---Handles URL construction, HTTP requests, and JSON parsing

local M = {}

---Check database content length using HEAD request
---@param callback fun(content_length: number|nil, error: string|nil) Callback function with content length or error
function M.fetch_plugins_content_length(callback)
  local url = config.get().data_source_url
  logger.debug("HEAD request to check database size: " .. url)

  curl.head(url, {
    headers = {
      ["Accept"] = "application/json",
      ["User-Agent"] = "store.nvim",
    },
    timeout = 5000, -- Shorter timeout for HEAD requests
    callback = function(response)
      if response.status ~= 200 then
        callback(nil, "Failed to HEAD check: HTTP " .. response.status)
        return
      end

      -- Extract content-length from headers
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

      logger.debug("Database content length: " .. content_length .. " bytes")
      callback(content_length, nil)
    end,
  })
end

---Fetch plugins from the gist URL
---@param callback fun(data: Database|nil, error: string|nil) Callback function with plugins data or error
function M.fetch_plugins(callback)
  local url = config.get().data_source_url
  logger.info("Fetching from GitHub: " .. url)
  curl.get(url, {
    headers = {
      ["Accept"] = "application/json",
      ["User-Agent"] = "store.nvim",
    },
    timeout = 10000,
    callback = function(response)
      if response.status ~= 200 then
        callback(nil, "Failed to fetch data: HTTP " .. response.status .. " " .. response.body)
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

---Get README content for a repository
---@param repo Repository
---@param callback fun(data: string[]|nil, error: string|nil) Callback function with README lines or error
function M.get_readme(repo, callback)
  local plugin_url = db_utils.build_github_readme_url(repo.full_name, repo.readme)
  logger.debug("Fetching README: " .. repo.full_name)

  curl.get(plugin_url, {
    timeout = 10000,
    callback = function(response)
      local success = response.status >= 200 and response.status < 300
      if not success then
        local errorBody = response.body or "Failed to fetch README from GitHub API"
        local error = response.status .. " " .. errorBody
        callback(nil, error)
        return
      end

      -- Process/clean README content using database utils
      local lines = db_utils.process_readme_content(response.body)

      logger.debug("📥 README FETCHED: " .. repo.full_name .. " (" .. #lines .. " lines)")

      callback(lines, nil)
    end,
  })
end

return M
