local validators = require("store.validators")

local M = {}

---Validate configuration
---@param config ConfirmInstallConfig|nil
---@return string|nil Error message or nil if valid
function M.validate_config(config)
  if not config then
    return "confirm_install.config must be a table, got: nil"
  end

  if not config.repository then
    return "confirm_install.config.repository is required"
  end

  local on_confirm_error =
    validators.should_be_function(config.on_confirm, "confirm_install.config.on_confirm must be a function")
  if on_confirm_error then
    return on_confirm_error
  end

  local on_cancel_error =
    validators.should_be_function(config.on_cancel, "confirm_install.config.on_cancel must be a function")
  if on_cancel_error then
    return on_cancel_error
  end

  return nil
end

return M
