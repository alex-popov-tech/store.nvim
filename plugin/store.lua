---Store modal command - unified entry point
---Creates a user command "Store" that shows the store modal interface
---@usage :Store
vim.api.nvim_create_user_command("Store", function()
  require("store").open()
end, {
  desc = "Show store modal",
})

