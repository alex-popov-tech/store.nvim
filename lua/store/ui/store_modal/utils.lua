local sort = require("store.sort")
local utils = require("store.utils")

local M = {}

---Apply sorting to current filtered repositories
---@param repos Repository[] Repositories for sorting
---@param installed_items table Installed plugins by full_name
---@param sort_type string Sort type to apply
---@return string? error
function M.sort(repos, installed_items, sort_type)
  if sort_type == "default" then
    return "Cannot apply default sort, initial table should be used with optional filtering"
  end

  local sorting_func = sort.sorts[sort_type]
  if not sorting_func then
    return "Unknown sort type: " .. sort_type
  end

  table.sort(repos, function(a, b)
    return sorting_func.fn(a, b, installed_items)
  end)
end

---@param repos Repository[] DB repositories
---@param query string non-empty filter query
---@return Repository[]? filtered repositories
---@return number installable count
---@return string? error message
function M.filter(repos, query)
  if query == nil or query == "" then
    return nil, 0, "Cannot filter with empty query"
  end

  local filter_predicate, error_msg = utils.create_advanced_filter(query)
  if error_msg then
    return nil, 0, error_msg
  end

  local filtered = {}
  local filtered_installable_count = 0
  for _, repo in ipairs(repos) do
    if filter_predicate(repo) then
      table.insert(filtered, repo)
      if repo.install then
        filtered_installable_count = filtered_installable_count + 1
      end
    end
  end
  return filtered, filtered_installable_count, nil
end

return M
