local tabs = require("store.ui.tabs")
local logger = require("store.logger").createLogger({ context = "layout_tab" })

local M = {}

local HEADER_HEIGHT = 5

local TabLayout = {}
TabLayout.__index = TabLayout

function M.new()
  local instance = {
    mode = "tab",
    tabpage = nil,
    prev_tabpage = nil,
    header_win = nil,
    list_win = nil,
    preview_win = nil,
  }
  setmetatable(instance, TabLayout)
  return instance
end

--- Apply window options appropriate for split windows (not floating)
--- @param win_id number Window ID
--- @param opts table Window options to set
local function apply_win_opts(win_id, opts)
  for opt, value in pairs(opts) do
    vim.wo[win_id][opt] = value
  end
end

--- Open all component windows as splits in a new tab page
--- @param heading table Heading component instance
--- @param list table List component instance
--- @param preview table Preview component instance
--- @return string|nil error
function TabLayout:open(heading, list, preview)
  -- Save current tab to return to on close
  self.prev_tabpage = vim.api.nvim_get_current_tabpage()

  -- Create fresh tab page
  vim.cmd.tabnew()
  self.tabpage = vim.api.nvim_get_current_tabpage()

  -- Capture the empty buffer created by tabnew before replacing it
  local orphan_buf = vim.api.nvim_get_current_buf()

  -- Temporarily disable equalalways to prevent size redistribution during setup
  local saved_ea = vim.o.equalalways
  vim.o.equalalways = false

  -- First window (from tabnew) becomes header
  self.header_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_var(self.header_win, "store_window", true)
  if not heading.state.buf.id or not vim.api.nvim_buf_is_valid(heading.state.buf.id) then
    vim.o.equalalways = saved_ea
    return "Tab layout: heading buffer is invalid"
  end
  vim.api.nvim_win_set_buf(self.header_win, heading.state.buf.id)

  -- Delete the orphaned empty buffer from tabnew
  if orphan_buf ~= heading.state.buf.id then
    pcall(vim.api.nvim_buf_delete, orphan_buf, { force = true })
  end

  -- Create list split below header
  self.list_win = vim.api.nvim_open_win(list.state.buf.id, true, {
    split = "below",
    win = self.header_win,
  })
  vim.api.nvim_win_set_var(self.list_win, "store_window", true)

  -- Create preview split right of list
  self.preview_win = vim.api.nvim_open_win(preview.state.buf.id, false, {
    split = "right",
    win = self.list_win,
  })
  vim.api.nvim_win_set_var(self.preview_win, "store_window", true)

  -- Set sizes
  if not vim.api.nvim_win_is_valid(self.header_win) then
    vim.o.equalalways = saved_ea
    return "Tab layout: header window became invalid"
  end
  local tabline_visible = vim.o.showtabline == 2
    or (vim.o.showtabline == 1 and #vim.api.nvim_list_tabpages() > 1)
  vim.api.nvim_win_set_height(self.header_win, HEADER_HEIGHT + (tabline_visible and 1 or 0))
  vim.wo[self.header_win].winfixheight = true

  -- Apply proportional widths
  local store_config = package.loaded["store.config"]
  if not store_config then
    vim.o.equalalways = saved_ea
    return "Tab layout: store.config not loaded"
  end
  local config = store_config.get()
  local total_width = vim.o.columns
  local list_width = math.floor(total_width * config.proportions.list)
  if vim.api.nvim_win_is_valid(self.list_win) then
    vim.api.nvim_win_set_width(self.list_win, list_width)
  end

  -- Restore equalalways
  vim.o.equalalways = saved_ea

  -- Common options for all store windows
  local common_opts = {
    number = false,
    relativenumber = false,
    signcolumn = "no",
    foldcolumn = "0",
    colorcolumn = "",
    cursorcolumn = false,
    list = true,
    listchars = "space: ,eol: ",
  }

  -- Apply window options for header (non-interactive display)
  apply_win_opts(self.header_win, vim.tbl_extend("force", common_opts, {
    cursorline = false,
    wrap = false,
    linebreak = false,
    statusline = " ",
    winhl = "StatusLine:Normal,StatusLineNC:Normal",
  }))

  -- Apply window options for list (interactive, cursorline for selection)
  apply_win_opts(self.list_win, vim.tbl_extend("force", common_opts, {
    cursorline = true,
    wrap = false,
    linebreak = false,
    sidescrolloff = 0,
  }))

  -- Apply window options for preview (markdown rendering)
  apply_win_opts(self.preview_win, vim.tbl_extend("force", common_opts, {
    conceallevel = 3,
    concealcursor = "nvc",
    wrap = false,
    cursorline = false,
  }))

  -- Inject window state into components (bypass their _win_open which creates floats)
  heading.state.win.id = self.header_win
  heading.state.win.is_open = true

  list.state.win.id = self.list_win
  list.state.win.is_open = true

  preview.state.win.id = self.preview_win
  preview.state.win.is_open = true

  -- Set winbar labels for list and preview
  self:update_winbar(list, preview)

  -- Render initial content into buffers
  heading:render(heading.state)
  heading:_buf_start_wave()
  list:render({ state = "loading" })
  preview:render({ state = "loading" })

  -- Re-render via markview after window is available
  local markview_ok, markview = pcall(require, "markview")
  if markview_ok and markview.strict_render then
    markview.strict_render:render(preview.state.buf.id)
  end

  -- Focus list by default
  if vim.api.nvim_win_is_valid(self.list_win) then
    vim.api.nvim_set_current_win(self.list_win)
  end

  -- Persistent winbar enforcement: vim.wo[win].winbar is scoped to window+buffer pair,
  -- so it resets when the buffer changes (tab switch) or plugin autocommands fire.
  -- This autocmd re-applies winbar on every BufEnter for our tracked buffers.
  local tracked_bufs = {
    [list.state.buf.id] = true,
    [list.state.buf.install_id] = true,
    [preview.state.buf.id] = true,
    [preview.state.buf.docs_id] = true,
  }
  self._winbar_augroup = vim.api.nvim_create_augroup("StoreTabWinbar", { clear = true })
  self._winbar_autocmd = vim.api.nvim_create_autocmd("BufEnter", {
    group = self._winbar_augroup,
    callback = function(args)
      if not self.tabpage or not vim.api.nvim_tabpage_is_valid(self.tabpage) then
        return
      end
      if not tracked_bufs[args.buf] then
        return
      end
      self:update_winbar(list, preview)
      if self.header_win and vim.api.nvim_win_is_valid(self.header_win) then
        vim.wo[self.header_win].statusline = " "
        vim.wo[self.header_win].winhl = "StatusLine:Normal,StatusLineNC:Normal"
      end
    end,
  })

  return nil
end

--- Close all component windows and the tab page
--- @param heading table Heading component instance
--- @param list table List component instance
--- @param preview table Preview component instance
--- @return string|nil error
function TabLayout:close(heading, list, preview)
  -- Clean up winbar enforcement autocmd
  if self._winbar_augroup then
    pcall(vim.api.nvim_del_augroup_by_id, self._winbar_augroup)
    self._winbar_augroup = nil
    self._winbar_autocmd = nil
  end

  -- Close components (destroys buffers, sets win.is_open = false)
  heading:close()
  list:close()
  preview:close()

  -- Close the tab page (returns user to previous tab)
  if self.tabpage and vim.api.nvim_tabpage_is_valid(self.tabpage) then
    local current_tab = vim.api.nvim_get_current_tabpage()
    if current_tab == self.tabpage then
      pcall(vim.cmd.tabclose)
    else
      local ok, tab_nr = pcall(vim.api.nvim_tabpage_get_number, self.tabpage)
      if ok then
        pcall(vim.cmd, tab_nr .. "tabclose")
      end
    end
  end

  self.tabpage = nil
  self.header_win = nil
  self.list_win = nil
  self.preview_win = nil

  return nil
end

--- Resize all component windows by updating split dimensions
--- @param heading table Heading component instance (unused, header is fixed height)
--- @param list table List component instance
--- @param preview table Preview component instance
--- @param _layout table Layout dimensions (unused for tab mode -- we compute from screen)
--- @return string|nil error
function TabLayout:resize(heading, list, preview, _layout)
  if not self.header_win or not vim.api.nvim_win_is_valid(self.header_win) then
    return "Tab layout: header window invalid"
  end

  -- Header stays fixed height
  vim.api.nvim_win_set_height(self.header_win, HEADER_HEIGHT)

  -- Apply proportional widths based on current config
  local store_config = package.loaded["store.config"]
  if not store_config then return "Tab layout: store.config not loaded" end
  local config = store_config.get()
  local total_width = vim.o.columns
  local list_width = math.floor(total_width * config.proportions.list)

  if self.list_win and vim.api.nvim_win_is_valid(self.list_win) then
    vim.api.nvim_win_set_width(self.list_win, list_width)
  end

  -- Update heading config width for content formatting
  heading.config.width = total_width

  -- Re-render heading with new width
  heading:_buf_render()

  return nil
end

--- Resize only list and preview for focus swap proportions
--- @param list table List component instance
--- @param preview table Preview component instance
--- @param _layout table Layout dimensions (unused for tab mode)
--- @return string|nil error
function TabLayout:resize_content(list, preview, _layout)
  local store_config = package.loaded["store.config"]
  if not store_config then return "Tab layout: store.config not loaded" end
  local config = store_config.get()
  local total_width = vim.o.columns
  local list_width = math.floor(total_width * config.proportions.list)

  if self.list_win and vim.api.nvim_win_is_valid(self.list_win) then
    vim.api.nvim_win_set_width(self.list_win, list_width)
  end
  -- Preview gets remainder automatically in split layout

  return nil
end

--- Apply winbar and winhl to a split window (re-applies after buffer swaps)
--- @param win_id number Window ID
--- @param winbar_str string Winbar format string
local function apply_winbar(win_id, winbar_str)
  if not win_id or not vim.api.nvim_win_is_valid(win_id) then
    return
  end
  vim.wo[win_id].winbar = winbar_str
  vim.wo[win_id].winhl = "WinBar:Normal,WinBarNC:Normal"
end

--- Update winbar labels on list and preview windows
--- @param list table List component instance
--- @param preview table Preview component instance
function TabLayout:update_winbar(list, preview)
  if self.list_win and vim.api.nvim_win_is_valid(self.list_win) then
    local list_active_tab = list.state.win.active_tab or "list"
    local count_text
    if list.state.items and #list.state.items > 0 then
      count_text = string.format("%d/%d", #list.state.items, list.state.total_items_count or #list.state.items)
    end
    apply_winbar(self.list_win, tabs.build_winbar(tabs.LEFT_TABS, list_active_tab, count_text))
  end
  if self.preview_win and vim.api.nvim_win_is_valid(self.preview_win) then
    local preview_active_tab = preview.state.win.active_tab or "readme"
    local right_tabs = tabs.build_right_tabs(preview.state.doc_paths, preview.state.doc_index)
    apply_winbar(self.preview_win, tabs.build_winbar(right_tabs, preview_active_tab))
    -- Re-apply conceallevel for markview rendering (can be lost on buffer/window events)
    vim.wo[self.preview_win].conceallevel = 3
    vim.wo[self.preview_win].concealcursor = "nvc"
  end
end

return M
