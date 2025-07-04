-- Store modal command
vim.api.nvim_create_user_command("StoreOpen", function()
  require("store").open()
end, {
  desc = "Open store modal with preview",
})

vim.api.nvim_create_user_command("StoreClose", function()
  require("store").close()
end, {
  desc = "Close store modal",
})

vim.api.nvim_create_user_command("StoreToggle", function()
  require("store").toggle()
end, {
  desc = "Toggle store modal",
})

vim.api.nvim_create_user_command("StoreOpen2", function()
  local modal2 = require("store.modal2")
  local modal = modal2.new()
  modal:open()
end, {
  desc = "Open store modal2 (new architecture)",
})

