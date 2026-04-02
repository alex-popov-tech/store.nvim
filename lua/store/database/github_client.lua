local curl = require("store.plenary.curl")
local config = require("store.config")
local db_utils = require("store.database.utils")
local logger = require("store.logger").createLogger({ context = "github" })

---@module "store.database.github_client"
---GitHub HTTP client responsible for fetching data and returning it in parsed state
---Handles URL construction, HTTP requests, and JSON parsing

local M = {}

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

      callback(data, nil, response.body)
    end,
  })
end

---Get doc content for a specific doc file
---@param repo Repository
---@param doc_path string Specific doc reference (e.g., "main/doc/help.txt")
---@param callback fun(data: string[]|nil, error: string|nil) Callback function with doc lines or error
function M.get_doc(repo, doc_path, callback)
  local plugin_url = db_utils.build_github_doc_url(repo.full_name, doc_path)
  logger.debug("Fetching doc: " .. repo.full_name .. " [" .. doc_path .. "]")

  curl.get(plugin_url, {
    timeout = 10000,
    callback = function(response)
      local success = response.status >= 200 and response.status < 300
      if not success then
        local errorBody = response.body or "Failed to fetch doc from GitHub"
        local error = response.status .. " " .. errorBody
        callback(nil, error)
        return
      end

      local lines = vim.split(response.body, "\n", { plain = true })

      logger.debug("📥 DOC FETCHED: " .. repo.full_name .. " (" .. #lines .. " lines)")

      callback(lines, nil)
    end,
  })
end

return M
