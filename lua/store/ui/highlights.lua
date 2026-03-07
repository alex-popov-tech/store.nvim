local M = {}

-- Theme-aware highlights: colorschemes can override these
local theme_highlights = {
  StoreTabActive = { link = "FloatBorder" },
  StoreTabInactive = { link = "Comment" },
  StoreTabIcon = { fg = "#73daca", bold = true },
}

-- Brand highlights: always use exact hex values
local brand_highlights = {
  StoreUABlue = { fg = "#0057b7", bold = true },
  StoreUAYellow = { fg = "#ffd700", bold = true },
  StoreWaveBlue1 = { fg = "#4d7fce", bold = true },
  StoreWaveBlue2 = { fg = "#1a6bc4", bold = true },
  StoreWaveBlue3 = { fg = "#0057b7", bold = true },
  StoreWaveYellow1 = { fg = "#ffe680", bold = true },
  StoreWaveYellow2 = { fg = "#ffd940", bold = true },
  StoreWaveYellow3 = { fg = "#ffd700", bold = true },
}

local function apply()
  for name, hl in pairs(theme_highlights) do
    vim.api.nvim_set_hl(0, name, vim.tbl_extend("force", hl, { default = true }))
  end
  for name, hl in pairs(brand_highlights) do
    vim.api.nvim_set_hl(0, name, hl)
  end
end

function M.setup()
  apply()
  vim.api.nvim_create_autocmd("ColorScheme", {
    group = vim.api.nvim_create_augroup("store_highlights", { clear = true }),
    callback = apply,
  })
end

return M
