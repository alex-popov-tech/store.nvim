local validators = require("store.validators")

local M = {}

---Validate filter configuration
---@param config FilterConfig|nil
---@return string|nil Error message or nil if valid
function M.validate_config(config)
  if not config then
    return "filter.config must be a table, got: nil"
  end

  local width_error =
    validators.should_be_positive_number(config.width, "filter.config.width must be a positive number")
  if width_error then
    return width_error
  end

  local height_error =
    validators.should_be_positive_number(config.height, "filter.config.height must be a positive number")
  if height_error then
    return height_error
  end

  local row_error = validators.should_be_number(config.row, "filter.config.row must be a number")
  if row_error then
    return row_error
  end

  local col_error = validators.should_be_number(config.col, "filter.config.col must be a number")
  if col_error then
    return col_error
  end

  local current_query_error =
    validators.should_be_string(config.current_query, "filter.config.current_query must be a string")
  if current_query_error then
    return current_query_error
  end

  if not config.on_value or type(config.on_value) ~= "function" then
    return "filter.config.on_value must be a function, got: " .. type(config.on_value)
  end

  if not config.on_exit or type(config.on_exit) ~= "function" then
    return "filter.config.on_exit must be a function, got: " .. type(config.on_exit)
  end

  return nil
end

---Validate filter state
---@param state FilterState
---@return string|nil Error message or nil if valid
function M.validate_state(state)
  if not state then
    return "filter.state must be a table, got: nil"
  end

  local is_open_error = validators.should_be_boolean(state.is_open, "filter.state.is_open must be a boolean")
  if is_open_error then
    return is_open_error
  end

  local state_error = validators.should_be_string(state.state, "filter.state.state must be a string")
  if state_error then
    return state_error
  end

  return nil
end

return M
