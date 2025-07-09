local config = require("store.config")
local StoreModal = require("store.ui.store_modal")
local logger = require("store.logger")

local M = {}

---@type StoreModal|nil
local current_modal = nil

---Setup the store.nvim plugin with configuration
---@param args? UserConfig User configuration to merge with defaults
M.setup = function(args)
  config.setup(args)
  -- Setup logger with logging level from configuration
  logger.setup({ logging = config.get().logging })
end

---Close the currently open store modal
M.close = function()
  if current_modal then
    logger.debug("Closing store modal")
    current_modal:close()
    current_modal = nil
  end
end

---Open the store modal interface
M.open = function()
  -- Atomic check and set to prevent race conditions
  if current_modal then
    return
  end

  logger.debug("Opening store modal")

  local modal_config = config.get()
  modal_config.on_close = function()
    -- Clear current_modal reference when modal is closed via keybinding
    logger.debug("Modal closed via keybinding, clearing reference")
    current_modal = nil
  end

  -- Create modal and immediately set reference to prevent race conditions
  local modal = StoreModal.new(modal_config)
  current_modal = modal -- Set reference immediately after creation

  local success = modal:open()
  if success then
    logger.debug("Store modal opened successfully")
  else
    logger.error("Failed to open modal")
    current_modal = nil -- Clear reference on failure
  end
end

return M
