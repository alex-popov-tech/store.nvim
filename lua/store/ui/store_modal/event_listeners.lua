local config = require("store.config")
local event_handlers = require("store.ui.store_modal.event_handlers")
local utils = require("store.utils")

local M = {}

local augroup = vim.api.nvim_create_augroup("StoreNvim", { clear = true })

---@param modal StoreModal The modal instance
---@return number autocmd_id to be deleted
function M.listen_for_focus_change(modal)
  return vim.api.nvim_create_autocmd("WinEnter", {
    group = augroup,
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
    group = augroup,
    callback = function()
      debounced_resize()
    end,
    desc = "Handle terminal resize for store.nvim modal",
  })
end

---@param modal StoreModal The modal instance
function M.listen_for_window_close(modal)
  local heading_win = modal.heading:get_window_id()
  local list_win = modal.list:get_window_id()
  local preview_win = modal.preview:get_window_id()

  -- If any component window is missing, skip listener (modal is in broken state)
  if not heading_win or not list_win or not preview_win then
    return
  end

  local function on_unexpected_close()
    if modal.state.is_closing then
      return
    end
    modal:close()
  end

  local win_ids = {
    tostring(heading_win),
    tostring(list_win),
    tostring(preview_win),
  }

  for _, win_id_str in ipairs(win_ids) do
    local id = vim.api.nvim_create_autocmd("WinClosed", {
      group = augroup,
      pattern = win_id_str,
      desc = "Handle unexpected window close for store.nvim modal (win " .. win_id_str .. ")",
      callback = on_unexpected_close,
    })
    table.insert(modal.state.autocmds, id)
  end
end

return M
