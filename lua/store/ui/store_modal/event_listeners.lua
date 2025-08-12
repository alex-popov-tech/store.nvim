local config = require("store.config")
local event_handlers = require("store.ui.store_modal.event_handlers")
local utils = require("store.utils")

local M = {}

---@param modal StoreModal The modal instance
---@return number autocmd_id to be deleted
function M.listen_for_focus_change(modal)
  return vim.api.nvim_create_autocmd("WinEnter", {
    callback = function()
      event_handlers.on_focus_change(modal)
    end,
  })
end

---@param modal StoreModal The modal instance
---@return number autocmd_id to be deleted
function M.listen_for_resize(modal)
  local plugin_config = config.get()
  local debounce_delay = plugin_config.resize_debounce

  local debounced_resize = utils.debounce(function()
    event_handlers.on_terminal_resize(modal)
  end, debounce_delay)

  return vim.api.nvim_create_autocmd("VimResized", {
    callback = function()
      debounced_resize()
    end,
    desc = "Handle terminal resize for store.nvim modal",
  })
end

---@param modal StoreModal The modal instance
function M.listen_for_window_close(modal)
  local heading_win_id_str = tostring(modal.heading:get_window_id())
  local list_win_id_str = tostring(modal.list:get_window_id())
  local preview_win_id_str = tostring(modal.preview:get_window_id())

  local autocmd_id = 0
  autocmd_id = vim.api.nvim_create_autocmd("WinClosed", {
    desc = "Handle unexpected window close for store.nvim modal",
    callback = function(args)
      -- if closed as intented to, ignore this autocmd and delete it
      if modal.state.is_closing then
        vim.api.nvim_del_autocmd(tonumber(autocmd_id))
        return
      end

      local win_id_str = args.match
      if win_id_str == heading_win_id_str or win_id_str == list_win_id_str or win_id_str == preview_win_id_str then
        modal:close()
        vim.api.nvim_del_autocmd(tonumber(autocmd_id))
      end
    end,
  })
end

return M
