local M = {}

M.sorts = {
  most_stars = {
    label = "Most Stars",
    key = "s",
    key_col = 5,
    fn = function(a, b, _)
      return (a.stars.curr or 0) > (b.stars.curr or 0)
    end,
  },
  rising_stars_monthly = {
    label = "Rising Stars (monthly)",
    key = "m",
    key_col = 14,
    fn = function(a, b, _)
      return (a.stars.monthly or 0) > (b.stars.monthly or 0)
    end,
  },
  rising_stars_weekly = {
    label = "Rising Stars (weekly)",
    key = "w",
    key_col = 14,
    fn = function(a, b, _)
      return (a.stars.weekly or 0) > (b.stars.weekly or 0)
    end,
  },
  recently_updated = {
    label = "Recently Updated",
    key = "u",
    key_col = 9,
    fn = function(a, b, _)
      return (a.updated_at or "") > (b.updated_at or "")
    end,
  },
  recently_created = {
    label = "Recently Created",
    key = "c",
    key_col = 9,
    fn = function(a, b, _)
      return (a.created_at or "") > (b.created_at or "")
    end,
  },
  most_downloads_monthly = {
    label = "Most Downloads (monthly)",
    key = "d",
    key_col = 5,
    fn = function(a, b, ctx)
      if not ctx or not ctx.download_stats_monthly then
        return false
      end
      local a_count = ctx.download_stats_monthly[a.full_name] or 0
      local b_count = ctx.download_stats_monthly[b.full_name] or 0
      return a_count > b_count
    end,
  },
  most_views_monthly = {
    label = "Most Views (monthly)",
    key = "v",
    key_col = 5,
    fn = function(a, b, ctx)
      if not ctx or not ctx.view_stats_monthly then
        return false
      end
      local a_count = ctx.view_stats_monthly[a.full_name] or 0
      local b_count = ctx.view_stats_monthly[b.full_name] or 0
      return a_count > b_count
    end,
  },
}

---Get available sort types
---@return string[] Array of sort type keys
function M.get_sort_types()
  return { "most_stars", "rising_stars_monthly", "rising_stars_weekly", "recently_updated", "recently_created", "most_downloads_monthly", "most_views_monthly" }
end

return M
