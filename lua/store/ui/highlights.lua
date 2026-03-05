local M = {}

function M.setup()
  vim.api.nvim_set_hl(0, "StoreTabActive", { link = "FloatBorder", bold = true })
  vim.api.nvim_set_hl(0, "StoreTabInactive", { link = "Comment" })
  vim.api.nvim_set_hl(0, "StoreTabIcon", { fg = "#73daca", bold = true })
  vim.api.nvim_set_hl(0, "StoreUABlue", { fg = "#0057b7", bold = true })
  vim.api.nvim_set_hl(0, "StoreUAYellow", { fg = "#ffd700", bold = true })
end

return M
