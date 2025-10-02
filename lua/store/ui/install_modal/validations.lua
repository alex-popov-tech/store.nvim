local validators = require("store.validators")

local M = {}

---Validate configuration
---@param config InstallModalConfig|nil
---@return string|nil Error message or nil if valid
function M.validate_config(config)
  if not config then
    return "install_modal.config must be a table, got: nil"
  end

  if not config.repository then
    return "install_modal.config.repository is required"
  end

  local snippet_error = validators.should_be_string(config.snippet, "install_modal.config.snippet must be a string")
  if snippet_error then
    return snippet_error
  end

  local on_confirm_error =
    validators.should_be_function(config.on_confirm, "install_modal.config.on_confirm must be a function")
  if on_confirm_error then
    return on_confirm_error
  end

  local on_cancel_error =
    validators.should_be_function(config.on_cancel, "install_modal.config.on_cancel must be a function")
  if on_cancel_error then
    return on_cancel_error
  end

  return nil
end

return M
