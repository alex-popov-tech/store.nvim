local config = require("store.config")
local logger = require("store.logger").createLogger({ context = "init" })
local StoreModal = require("store.ui.store_modal")

local M = {}

---@type StoreModal|nil
local current_modal = nil

local setup_error
---Setup the store.nvim plugin with configuration
---@param args? UserConfig User configuration to merge with defaults
M.setup = function(args)
  local err = config.setup(args)
  if err ~= nil then
    setup_error = err
  end
end

---Open the store modal interface
M.open = function()
  if setup_error then
    vim.notify("Cannot open store modal: " .. setup_error, vim.log.levels.ERROR)
    return
  end
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
    error("Can't open store modal: " .. modal_error)
    return
  end
  current_modal = modal_instance
  current_modal:open()
end

return M
