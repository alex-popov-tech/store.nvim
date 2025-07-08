---@module "store"
---Main entry point for the store.nvim plugin
---Provides the public API for setting up and opening the store modal

local module = require("store.init")

---@class Store
---@field setup fun(config?: UserConfig) Setup function for store.nvim
---@field open fun() Open the store modal interface
local M = {}

---Setup the store.nvim plugin with optional configuration
---@param config? UserConfig Optional configuration table
function M.setup(config)
  module.setup(config)
end

---Open the store modal interface
function M.open()
  module.open()
end

return M
