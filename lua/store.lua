---@module "store"
---Main entry point for the store.nvim plugin
---Provides the public API for setting up and opening the store modal

local module = require("store.init")

---@class Store
---@field setup fun(config?: UserConfig) Setup function for store.nvim with optional configuration
---@field open fun() Open the store modal interface
local M = {}

function M.setup(config)
  module.setup(config)
end

function M.open()
  module.open()
end

return M
