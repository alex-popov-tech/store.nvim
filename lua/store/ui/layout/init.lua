local M = {}

--- Create a layout provider based on config
--- @param layout_mode string "modal" or "tab"
--- @return table provider Layout provider instance with :open(), :close(), :resize(), :update_winbar() methods
function M.create(layout_mode)
  if layout_mode == "tab" then
    return require("store.ui.layout.tab").new()
  end
  return require("store.ui.layout.modal").new()
end

return M
