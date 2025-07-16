local M = {}

local SORT_FUNCTIONS = {
  default = nil, -- no sorting, preserve original order

  most_stars = function(a, b)
    return (a.stargazers_count or 0) > (b.stargazers_count or 0)
  end,

  recently_updated = function(a, b)
    return (a.pushed_at or 0) > (b.pushed_at or 0)
  end,
}

local SORT_LABELS = {
  default = "Default",
  most_stars = "Most Stars",
  recently_updated = "Recently Updated",
}

---Sort repositories by given type
---@param repos Repository[] Array of repositories to sort
---@param sort_type string Sort type: "default", "most_stars", "recently_updated"
---@return Repository[] Sorted array of repositories
function M.sort_repositories(repos, sort_type)
  if sort_type == "default" or not SORT_FUNCTIONS[sort_type] then
    return repos -- return original order
  end

  local sorted = vim.deepcopy(repos)
  table.sort(sorted, SORT_FUNCTIONS[sort_type])
  return sorted
end

---Get display label for sort type
---@param sort_type string Sort type
---@return string Display label
function M.get_sort_label(sort_type)
  return SORT_LABELS[sort_type] or "Default"
end

---Get available sort types
---@return string[] Array of sort type keys
function M.get_sort_types()
  return { "default", "most_stars", "recently_updated" }
end

return M
