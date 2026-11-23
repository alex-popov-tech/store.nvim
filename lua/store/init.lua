local config = require("store.config")
local highlights = require("store.ui.highlights")
local logger = require("store.logger").createLogger({ context = "init" })

local M = {}

---@type StoreModal|nil
local current_modal = nil

local setup_error
---Setup the store.nvim plugin with configuration
---@param args? UserConfig User configuration to merge with defaults
M.setup = function(args)
  local err = config.setup(args)
  -- nil on success: a later good setup must clear an earlier error,
  -- or the store stays locked out of a mistake that was already fixed
  setup_error = err
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

  local cfg = config.get()
  if type(cfg) ~= "table" then
    -- belt and braces: config.get() is never supposed to return nil, and
    -- a nil here used to surface as a cryptic `tbl_deep_extend: expected
    -- table, got nil` traceback from this very spot
    vim.notify("Cannot open store modal: the configuration is not ready", vim.log.levels.ERROR)
    return
  end

  highlights.setup()

  local StoreModal = require("store.ui.store_modal")
  local modal_config = vim.tbl_deep_extend("force", cfg, {
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
