local module = require("store.module")

local M = {}

-- Public API functions
M.setup = function(config)
  module.setup(config)
end
M.open = module.open
M.close = module.close
M.toggle = module.toggle

return M
