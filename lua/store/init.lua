local config = require("store.config")
local StoreModal = require("store.ui.store_modal")
local logger = require("store.logger")

local M = {}

---@type StoreModal|nil
local current_modal = nil

---Setup the store.nvim plugin with configuration
---@param args? UserConfig User configuration to merge with defaults
M.setup = function(args)
  local setup_error = config.setup(args)
  if setup_error then
    error(setup_error)
  end
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
  -- If modal is already open, focus it instead of creating a new one
  if current_modal then
    current_modal:focus()
    return
  end

  logger.debug("Opening store modal")

  local modal_config = vim.tbl_deep_extend("force", config.get(), {
    on_close = function()
      logger.debug("Modal closed via keybinding, clearing reference")
      current_modal = nil
    end,
  })
  local modal_instance, modal_error = StoreModal.new(modal_config)
  if modal_error then
    logger.error("Failed to create store modal: " .. modal_error)
    error("Failed to create store modal: " .. modal_error)
  end
  current_modal = modal_instance
  current_modal:open()
end

return M
