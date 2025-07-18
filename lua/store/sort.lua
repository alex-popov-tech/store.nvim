local logger = require("store.logger")

local M = {}

M.sorts = {
  default = { label = "Default", fn = nil },
  most_stars = {
    label = "Most Stars",
    fn = function(a, b)
      return (a.stargazers_count or 0) > (b.stargazers_count or 0)
    end,
  },
  recently_updated = {
    label = "Recently Updated",
    fn = function(a, b)
      return (a.pushed_at or 0) > (b.pushed_at or 0)
    end,
  },
}

---Sort repositories by given type
---@param repos Repository[] Array of repositories to sort
---@param sort_type string Sort type: "default", "most_stars", "recently_updated"
---@return Repository[] Sorted array of repositories
function M.sort_repositories(repos, sort_type)
  if not M.sorts[sort_type] then
    logger.error("Invalid sort type: " .. sort_type)
    return repos
  end

  if sort_type == "default" then
    return repos -- return original order
  end

  local sorted = vim.deepcopy(repos)
  table.sort(sorted, M.sorts[sort_type].fn)
  return sorted
end

---Get available sort types
---@return string[] Array of sort type keys
function M.get_sort_types()
  return { "default", "most_stars", "recently_updated" }
end

return M
