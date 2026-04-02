local logger = require("store.logger").createLogger({ context = "layout_modal" })

local M = {}

local ModalLayout = {}
ModalLayout.__index = ModalLayout

function M.new()
  local instance = {
    mode = "modal",
  }
  setmetatable(instance, ModalLayout)
  return instance
end

--- Open all component windows using their existing :open() methods
--- @param heading table Heading component instance
--- @param list table List component instance
--- @param preview table Preview component instance
--- @return string|nil error
function ModalLayout:open(heading, list, preview)
  local heading_error = heading:open()
  if heading_error then
    return "Failed to open heading: " .. heading_error
  end
  local list_error = list:open()
  if list_error then
    return "Failed to open list: " .. list_error
  end
  local preview_error = preview:open()
  if preview_error then
    return "Failed to open preview: " .. preview_error
  end
  return nil
end

--- Close all component windows using their existing :close() methods
--- @param heading table Heading component instance
--- @param list table List component instance
--- @param preview table Preview component instance
--- @return string|nil error
function ModalLayout:close(heading, list, preview)
  local err
  err = heading:close()
  if err then
    logger.warn("Failed to close heading: " .. err)
  end
  err = list:close()
  if err then
    logger.warn("Failed to close list: " .. err)
  end
  err = preview:close()
  if err then
    logger.warn("Failed to close preview: " .. err)
  end
  return nil
end

--- Resize all component windows using their existing :resize() methods
--- @param heading table Heading component instance
--- @param list table List component instance
--- @param preview table Preview component instance
--- @param layout StoreModalLayout Computed layout dimensions
--- @return string|nil error
function ModalLayout:resize(heading, list, preview, layout)
  local err
  err = heading:resize(layout.header)
  if err then
    return "Failed to resize heading: " .. err
  end
  err = list:resize(layout.list)
  if err then
    return "Failed to resize list: " .. err
  end
  err = preview:resize(layout.preview)
  if err then
    return "Failed to resize preview: " .. err
  end
  return nil
end

--- Resize only list and preview (for focus swap proportions)
--- @param list table List component instance
--- @param preview table Preview component instance
--- @param layout StoreModalLayout Computed layout dimensions
--- @return string|nil error
function ModalLayout:resize_content(list, preview, layout)
  local err
  err = list:resize(layout.list)
  if err then
    return "Failed to resize list: " .. err
  end
  err = preview:resize(layout.preview)
  if err then
    return "Failed to resize preview: " .. err
  end
  return nil
end

--- Update floating window titles with plugin count right-aligned
--- @param list table List component instance
--- @param preview table Preview component instance
function ModalLayout:update_winbar(list, preview)
  local tabs = require("store.ui.tabs")
  if list.state.win.id and vim.api.nvim_win_is_valid(list.state.win.id) then
    local active_tab = list.state.win.active_tab or "list"
    local left_title = tabs.build_title(tabs.LEFT_TABS, active_tab)

    if list.state.items and #list.state.items > 0 then
      local count_text = string.format("%d/%d", #list.state.items, list.state.total_items_count or #list.state.items)
      -- Calculate left title width
      local left_width = 0
      for _, chunk in ipairs(left_title) do
        left_width = left_width + vim.fn.strdisplaywidth(chunk[1])
      end
      -- Pad to push count to right edge (window width minus borders)
      local win_width = vim.api.nvim_win_get_width(list.state.win.id)
      local pad = win_width - left_width - #count_text - 3 -- borders + space before count
      if pad > 0 then
        table.insert(left_title, { string.rep("─", pad), "FloatBorder" })
      end
      table.insert(left_title, { " " .. count_text .. " ", "FloatBorder" })
    end

    pcall(vim.api.nvim_win_set_config, list.state.win.id, {
      title = left_title,
      title_pos = "left",
    })
  end

  -- Update preview floating window title with dynamic tabs
  if preview.state.win.id and vim.api.nvim_win_is_valid(preview.state.win.id) then
    local right_tabs = tabs.build_right_tabs(preview.state.doc_paths, preview.state.doc_index)
    pcall(vim.api.nvim_win_set_config, preview.state.win.id, {
      title = tabs.build_title(right_tabs, preview.state.win.active_tab or "readme"),
      title_pos = "left",
    })
  end
end

return M
