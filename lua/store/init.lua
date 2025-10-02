local config = require("store.config")
local logger = require("store.logger").createLogger({ context = "init" })
local StoreModal = require("store.ui.store_modal")

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
end

---Open the store modal interface
M.open = function()
  if current_modal then
    logger.info("Store modal is already opened")
    return
  end

  local modal_config = vim.tbl_deep_extend("force", config.get(), {
    on_close = function()
      current_modal = nil
    end,
  })
  local modal_instance, modal_error = StoreModal.new(modal_config)
  if modal_error then
    error("Failed to create store modal: " .. modal_error)
  end
  current_modal = modal_instance
  current_modal:open()
end

return M
