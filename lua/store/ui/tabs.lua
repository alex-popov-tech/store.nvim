local M = {}

--- Build title array for nvim_open_win / nvim_win_set_config
--- @param tabs {id: string, label: string}[]
--- @param active_id string
--- @param right_text? string Optional right-side text appended after separator
--- @return table[] title_chunks Array of {text, hl_group} tuples
function M.build_title(tabs, active_id, right_text)
  local result = {}
  for i, tab in ipairs(tabs) do
    if i > 1 then
      table.insert(result, { "─", "FloatBorder" })
    end
    local hl = tab.id == active_id and "StoreTabActive" or "StoreTabInactive"
    table.insert(result, { " ", hl })
    table.insert(result, { tab.label:sub(1, 1), "StoreTabIcon" })
    table.insert(result, { tab.label:sub(2) .. " ", hl })
  end
  if right_text then
    table.insert(result, { " " .. "─" .. " ", "FloatBorder" })
    table.insert(result, { right_text .. " ", "FloatBorder" })
  end
  return result
end

--- Build winbar string for split windows (tab layout mode)
--- @param tab_defs {id: string, label: string}[]
--- @param active_id string
--- @param right_text? string Optional right-aligned text
--- @return string winbar Statusline-format string for vim.wo[win].winbar
function M.build_winbar(tab_defs, active_id, right_text)
  local parts = {}
  for i, tab in ipairs(tab_defs) do
    if i > 1 then
      table.insert(parts, "%#FloatBorder# | ")
    end
    local hl = tab.id == active_id and "StoreTabActive" or "StoreTabInactive"
    table.insert(parts, "%#" .. hl .. "# ")
    table.insert(parts, "%#StoreTabIcon#" .. tab.label:sub(1, 1))
    table.insert(parts, "%#" .. hl .. "#" .. tab.label:sub(2) .. " ")
  end
  if right_text then
    table.insert(parts, "%=%#FloatBorder# " .. right_text .. " ")
  end
  return table.concat(parts)
end

M.LEFT_TABS = { { id = "list", label = "List" }, { id = "install", label = "Install" } }
M.RIGHT_TABS = { { id = "readme", label = "Readme" }, { id = "docs", label = "Docs" } }

--- Truncate a filename to fit within max_len display width (UTF-8 safe with ellipsis)
--- @param filename string
--- @param max_len number Maximum display width
--- @return string
local function truncate_filename(filename, max_len)
  if vim.fn.strdisplaywidth(filename) <= max_len then
    return filename
  end
  return vim.fn.strcharpart(filename, 0, max_len - 1) .. "\226\128\166"
end

--- Build dynamic right tab definitions based on doc availability
--- @param doc_paths string[]|nil Array of doc paths from repo.doc
--- @param doc_index number Current doc index (1-based when viewing, 0 when not viewing docs)
--- @param available_width? number Optional window width for filename truncation
--- @return {id: string, label: string}[]
function M.build_right_tabs(doc_paths, doc_index, available_width)
  local result = { { id = "readme", label = "Readme" } }

  if not doc_paths or #doc_paths == 0 then
    return result
  end

  if #doc_paths == 1 then
    table.insert(result, { id = "docs", label = "Docs" })
    return result
  end

  -- 2+ docs: show filename and counter
  local label = "Docs"
  if type(doc_index) == "number" and doc_index > 0 and doc_index <= #doc_paths then
    local filename = doc_paths[doc_index]:match("([^/]+)$") or "unknown"
    local counter = string.format(" %d/%d", doc_index, #doc_paths)
    if available_width then
      -- Budget: available_width - "Docs " (5) - counter width - tab chrome estimate (6)
      local budget = available_width - 5 - vim.fn.strdisplaywidth(counter) - 6
      if budget > 0 then
        filename = truncate_filename(filename, budget)
      end
    end
    label = "Docs " .. filename .. counter
  end

  table.insert(result, { id = "docs", label = label })
  return result
end

return M
