local config = require("store.config")
local Modal2 = require("store.modal2")

local M = {}

local current_modal = nil

M.setup = function(args)
  config.setup(args)
end

M.close = function()
  if current_modal then
    config.get().log.debug("Closing store modal")
    current_modal:close()
    current_modal = nil
    return true
  end
  return false
end

M.toggle = function()
  if current_modal then
    return M.close()
  else
    return M.open()
  end
end

-- Main function to open modal using new modal2 architecture
M.open = function()
  -- Use atomic check and set to prevent race conditions
  if current_modal then
    return false
  end

  config.get().log.debug("Opening store modal")

  local modal = Modal2.new(config.get())
  local success = modal:open()
  if success then
    current_modal = modal
    config.get().log.debug("Store modal opened successfully")
    return true
  else
    config.get().log.error("Failed to open modal")
  end

  return false
end

return M
