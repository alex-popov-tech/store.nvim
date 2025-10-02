local M = {}

M.sorts = {
  default = { label = "Default", fn = nil },
  most_stars = {
    label = "Most Stars",
    fn = function(a, b, _)
      return (a.stars or 0) > (b.stars or 0)
    end,
  },
  recently_updated = {
    label = "Recently Updated",
    fn = function(a, b, _)
      -- Compare ISO date strings directly
      return (a.updated_at or "") > (b.updated_at or "")
    end,
  },
  recently_created = {
    label = "Recently Created",
    fn = function(a, b, _)
      -- Compare ISO date strings directly
      return (a.created_at or "") > (b.created_at or "")
    end,
  },
  installed = {
    label = "Installed",
    fn = function(a, b, installed_items)
      local a_installed = installed_items and installed_items[a.name] == true
      local b_installed = installed_items and installed_items[b.name] == true

      if a_installed and not b_installed then
        return true -- a comes first
      elseif not a_installed and b_installed then
        return false -- b comes first
      else
        -- Both have same installation status, maintain original order
        return false
      end
    end,
  },
}

---Get available sort types
---@return string[] Array of sort type keys
function M.get_sort_types()
  return { "default", "most_stars", "recently_updated", "recently_created", "installed" }
end

return M
