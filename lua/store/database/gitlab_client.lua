local curl = require("store.plenary.curl")
local config = require("store.config")
local db_utils = require("store.database.utils")
local logger = require("store.logger").createLogger({ context = "gitlab" })

---@module "store.database.gitlab_client"
---GitLab HTTP client responsible for fetching README content from GitLab repositories
---Handles URL construction, HTTP requests, and response processing

local M = {}

---Get README content for a GitLab repository
---@param repo Repository Repository object with GitLab source
---@param callback fun(data: string[]|nil, error: string|nil) Callback function with README lines or error
function M.get_readme(repo, callback)
  -- GitLab raw URL format: https://gitlab.com/{full_name}/-/raw/{branch}/{path}?ref_type=heads
  local plugin_url = db_utils.build_gitlab_readme_url(repo.full_name, repo.readme)
  logger.debug("Fetching README: " .. repo.full_name)

  curl.get(plugin_url, {
    timeout = 10000,
    callback = function(response)
      local success = response.status >= 200 and response.status < 300
      if not success then
        local errorBody = response.body or "Failed to fetch README from GitLab"
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
