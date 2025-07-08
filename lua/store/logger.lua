local validators = require("store.validators")

local M = {}

-- Default logger configuration (private)
local DEFAULT_LOGGER_CONFIG = {
  file = false,
  notify = false,
}

---Validate logger configuration (consistent with existing validators pattern)
---@param config LoggerConfig|nil Logger configuration to validate
---@return string|nil error_message Error message if validation fails, nil if valid
local function validate(config)
  if config == nil then
    return nil
  end

  local err = validators.should_be_table(config, "logger config must be a table")
  if err then
    return err
  end

  if config.file ~= nil then
    local file_err = validators.should_be_boolean(config.file, "logger.file must be a boolean")
    if file_err then
      return file_err
    end
  end

  if config.notify ~= nil then
    local notify_err = validators.should_be_boolean(config.notify, "logger.notify must be a boolean")
    if notify_err then
      return notify_err
    end
  end

  return nil
end

---@class PlenaryLogger
---@field debug fun(self: PlenaryLogger, ...: any)
---@field info fun(self: PlenaryLogger, ...: any)
---@field warn fun(self: PlenaryLogger, ...: any)
---@field error fun(self: PlenaryLogger, ...: any)

---Create new logger instance following the mermaid diagram pattern
---@param logger_config LoggerConfig|nil Logger configuration
---@return PlenaryLogger logger Plenary logger instance with debug, info, warn, error methods
function M.new(logger_config)
  -- Validate configuration first (as shown in mermaid diagram)
  local error_msg = validate(logger_config)
  if error_msg then
    error("Logger configuration validation failed: " .. error_msg)
  end

  -- Merge with defaults
  local config = vim.tbl_deep_extend("force", DEFAULT_LOGGER_CONFIG, logger_config or {})

  -- Create plenary logger instance
  local plenary_logger = require("plenary.log").new({
    plugin = "store.nvim",
    level = "debug",
    use_console = config.notify,
    use_file = config.file,
  })

  return plenary_logger
end

return M
