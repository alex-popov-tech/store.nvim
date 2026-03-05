local M = {}

--- Build title array for nvim_open_win / nvim_win_set_config
--- @param tabs {id: string, label: string}[]
--- @param active_id string
--- @return table[] title_chunks Array of {text, hl_group} tuples
function M.build_title(tabs, active_id)
  local result = {}
  for i, tab in ipairs(tabs) do
    if i > 1 then
      table.insert(result, { " " .. "─" .. " ", "FloatBorder" })
    end
    local hl = tab.id == active_id and "StoreTabActive" or "StoreTabInactive"
    table.insert(result, { " ", hl })
    table.insert(result, { tab.label:sub(1, 1), "StoreTabIcon" })
    table.insert(result, { tab.label:sub(2) .. " ", hl })
  end
  return result
end

M.LEFT_TABS = { { id = "list", label = "List" }, { id = "install", label = "Install" } }
M.RIGHT_TABS = { { id = "readme", label = "Readme" }, { id = "docs", label = "Docs" } }

return M
