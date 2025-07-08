---Store modal command - unified entry point
---Creates a user command "Store" that opens the store modal interface
---@usage :Store
vim.api.nvim_create_user_command("Store", function()
  require("store").open()
end, {
  desc = "Open store modal",
})

