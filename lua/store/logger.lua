local M = {}

---@class Logger
---@field debug fun(message: string): nil
---@field warn fun(message: string): nil
---@field info fun(message: string): nil
---@field error fun(message: string): nil
---@field log fun(level: string?, message: string): nil

---@class LoggerOptions
---@field context? string Module context for log messages (optional)

-- Define logging levels and their numeric values for comparison
local log_levels = {
  off = 0,
  error = 1,
  warn = 2,
  info = 3,
  debug = 4,
}

---Create a new logger instance with options
---@param options LoggerOptions Configuration for the logger instance
---@return Logger logger Logger instance
function M.createLogger(options)
  options = options or {}
  local context = options.context
  local instance = {}

  ---Format log message with timestamp, optional context and level
  ---@param level string Log level (debug, warn, error, log)
  ---@param message string Log message
  ---@return string formatted_message
  local function format_message(level, message)
    local timestamp = os.date("%H:%M:%S")
    if context then
      return string.format("[%s] [store.nvim] [%s] [%s] %s", timestamp, context, level:upper(), message)
    else
      return string.format("[%s] [store.nvim] [%s] %s", timestamp, level:upper(), message)
    end
  end

  ---Check if a log level should be shown based on current configuration
  ---@param level string The log level to check
  ---@return boolean should_log True if the log level should be shown
  local function should_log(level)
    local logging_level = require("store.config").get().logging
    local current_level = log_levels[logging_level] or 0
    local message_level = log_levels[level] or 0
    return message_level <= current_level and message_level > 0
  end

  ---Main log function that handles all logging
  ---@param level string? Log level (defaults to "log")
  ---@param message string Log message
  function instance.log(level, message)
    -- Handle case where level is omitted (level becomes message, message becomes nil)
    if message == nil then
      message = level
      level = "log"
    end

    -- Early return if logging is disabled or level is too low
    if not should_log(level) then
      return
    end

    -- Format and send to tryNotify
    local formatted = format_message(level, message)
    require("store.utils").tryNotify(formatted)
  end

  ---Debug level logging
  ---@param message string Log message
  function instance.debug(message)
    instance.log("debug", message)
  end

  ---Warning level logging
  ---@param message string Log message
  function instance.warn(message)
    instance.log("warn", message)
  end

  ---Info level logging
  ---@param message string Log message
  function instance.info(message)
    instance.log("info", message)
  end

  ---Error level logging
  ---@param message string Log message
  function instance.error(message)
    instance.log("error", message)
  end

  return instance
end

return M
