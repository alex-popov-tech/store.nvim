local curl = require("store.plenary.curl")
local db_utils = require("store.database.utils")
local logger = require("store.logger").createLogger({ context = "gitlab" })

---@module "store.database.gitlab_client"
---GitLab HTTP client responsible for fetching doc content from GitLab repositories
---Handles URL construction, HTTP requests, and response processing

local M = {}

---Get doc content for a specific doc file from a GitLab repository
---@param repo Repository Repository object with GitLab source
---@param doc_path string Specific doc reference (e.g., "main/doc/help.txt")
---@param callback fun(data: string[]|nil, error: string|nil) Callback function with doc lines or error
function M.get_doc(repo, doc_path, callback)
  local plugin_url = db_utils.build_gitlab_doc_url(repo.full_name, doc_path)
  logger.debug("Fetching doc: " .. repo.full_name .. " [" .. doc_path .. "]")

  curl.get(plugin_url, {
    timeout = 10000,
    callback = function(response)
      local success = response.status >= 200 and response.status < 300
      if not success then
        local errorBody = response.body or "Failed to fetch doc from GitLab"
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
