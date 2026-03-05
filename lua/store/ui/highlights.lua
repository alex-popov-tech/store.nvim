local M = {}

function M.setup()
  vim.api.nvim_set_hl(0, "StoreTabActive", { link = "FloatBorder", bold = true })
  vim.api.nvim_set_hl(0, "StoreTabInactive", { link = "Comment" })
  vim.api.nvim_set_hl(0, "StoreTabIcon", { fg = "#73daca", bold = true })
  vim.api.nvim_set_hl(0, "StoreUABlue", { fg = "#0057b7", bold = true })
  vim.api.nvim_set_hl(0, "StoreUAYellow", { fg = "#ffd700", bold = true })
  -- Wave animation gradient highlights
  vim.api.nvim_set_hl(0, "StoreWaveBlue1", { fg = "#4d7fce", bold = true })
  vim.api.nvim_set_hl(0, "StoreWaveBlue2", { fg = "#1a6bc4", bold = true })
  vim.api.nvim_set_hl(0, "StoreWaveBlue3", { fg = "#0057b7", bold = true })
  vim.api.nvim_set_hl(0, "StoreWaveYellow1", { fg = "#ffe680", bold = true })
  vim.api.nvim_set_hl(0, "StoreWaveYellow2", { fg = "#ffd940", bold = true })
  vim.api.nvim_set_hl(0, "StoreWaveYellow3", { fg = "#ffd700", bold = true })
end

return M
