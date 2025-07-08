-- Store modal command - unified entry point
vim.api.nvim_create_user_command("Store", function()
  require("store").toggle()
end, {
  desc = "Toggle store modal",
})

