local M = {}

---@class LoggerConfig
---@field logging? string Logging level: "off"|"error"|"warn"|"log"|"debug" (default: "off")

---@class Logger
---@field debug fun(message: string): nil
---@field warn fun(message: string): nil
---@field error fun(message: string): nil
---@field log fun(level: string?, message: string): nil

-- Internal configuration state
local config = {
  logging = "off",
}

-- Define logging levels and their numeric values for comparison
local log_levels = {
  off = 0,
  error = 1,
  warn = 2,
  log = 3,
  debug = 4,
}

---Format log message with timestamp and level
---@param level string Log level (debug, warn, error, log)
---@param message string Log message
---@return string formatted_message
local function format_message(level, message)
  local timestamp = os.date("%H:%M:%S")
  return string.format("[%s] [store.nvim] [%s] %s", timestamp, level:upper(), message)
end

---Check if a log level should be shown based on current configuration
---@param level string The log level to check
---@return boolean should_log True if the log level should be shown
local function should_log(level)
  local current_level = log_levels[config.logging] or 0
  local message_level = log_levels[level] or 0
  return message_level <= current_level and message_level > 0
end

---Main log function that handles all logging
---@param level string? Log level (defaults to "log")
---@param message string Log message
function M.log(level, message)
  -- Handle case where level is omitted (level becomes message, message becomes nil)
  if message == nil then
    message = level
    level = "log"
  end

  -- Early return if logging is disabled or level is too low
  if not should_log(level) then
    return
  end

  -- Format and send to vim.notify
  local formatted = format_message(level, message)
  vim.notify(formatted)
end

---Debug level logging
---@param message string Log message
function M.debug(message)
  M.log("debug", message)
end

---Warning level logging
---@param message string Log message
function M.warn(message)
  M.log("warn", message)
end

---Error level logging
---@param message string Log message
function M.error(message)
  M.log("error", message)
end

---Setup logger with configuration
---@param logger_config LoggerConfig? Configuration object
function M.setup(logger_config)
  if logger_config and logger_config.logging ~= nil then
    -- Validate logging level
    if log_levels[logger_config.logging] then
      config.logging = logger_config.logging
    else
      vim.notify(
        "[store.nvim] Invalid logging level: " .. tostring(logger_config.logging) .. ". Using 'off'.",
        vim.log.levels.WARN
      )
      config.logging = "off"
    end
  end
end

return M
