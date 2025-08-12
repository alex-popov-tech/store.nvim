local M = {}

---Format a value for error messages with type information
---@param value any The value to format
---@return string formatted The formatted value with type information
local function format_actual(value)
  if type(value) == "string" then
    return '"' .. value .. '" (string)'
  elseif type(value) == "nil" then
    return "nil (nil)"
  else
    return tostring(value) .. " (" .. type(value) .. ")"
  end
end

---Validate that a value is a number
---@param value any The value to validate
---@param custom_error_message? string Custom error message to use
---@return string|nil error_message Error message if validation fails, nil if valid
function M.should_be_number(value, custom_error_message)
  if type(value) ~= "number" then
    return custom_error_message or ("expected to be a number but actual: " .. format_actual(value))
  end
  return nil
end

---Validate that a value is a boolean
---@param value any The value to validate
---@param custom_error_message? string Custom error message to use
---@return string|nil error_message Error message if validation fails, nil if valid
function M.should_be_boolean(value, custom_error_message)
  if type(value) ~= "boolean" then
    return custom_error_message or ("expected to be a boolean but actual: " .. format_actual(value))
  end
  return nil
end

---Validate that a value is a string
---@param value any The value to validate
---@param custom_error_message? string Custom error message to use
---@return string|nil error_message Error message if validation fails, nil if valid
function M.should_be_string(value, custom_error_message)
  if type(value) ~= "string" then
    return custom_error_message or ("expected to be a string but actual: " .. format_actual(value))
  end
  return nil
end

---Validate that a value is a table
---@param value any The value to validate
---@param custom_error_message? string Custom error message to use
---@return string|nil error_message Error message if validation fails, nil if valid
function M.should_be_table(value, custom_error_message)
  if type(value) ~= "table" then
    return custom_error_message or ("expected to be a table but actual: " .. format_actual(value))
  end
  return nil
end

---Validate that a value is a function
---@param value any The value to validate
---@param custom_error_message? string Custom error message to use
---@return string|nil error_message Error message if validation fails, nil if valid
function M.should_be_function(value, custom_error_message)
  if type(value) ~= "function" then
    return custom_error_message or ("expected to be a function but actual: " .. format_actual(value))
  end
  return nil
end

---Validate that a value is a positive number
---@param value any The value to validate
---@param custom_error_message? string Custom error message to use
---@return string|nil error_message Error message if validation fails, nil if valid
function M.should_be_positive_number(value, custom_error_message)
  local err = M.should_be_number(value, custom_error_message)
  if err then
    return err
  end

  if value <= 0 then
    return custom_error_message or ("expected to be a positive number but actual: " .. format_actual(value))
  end

  return nil
end

---Validate that a value is a number within a specified range
---@param value any The value to validate
---@param min number Minimum allowed value (inclusive)
---@param max number Maximum allowed value (inclusive)
---@param custom_error_message? string Custom error message to use
---@return string|nil error_message Error message if validation fails, nil if valid
function M.should_be_number_in_range(value, min, max, custom_error_message)
  local err = M.should_be_number(value, custom_error_message)
  if err then
    return err
  end

  if value < min or value > max then
    return custom_error_message
      or ("expected to be a number between " .. min .. " and " .. max .. " but actual: " .. format_actual(value))
  end

  return nil
end

---Validate that a value is one of the allowed string values
---@param value any The value to validate
---@param allowed_values string[] Array of allowed string values
---@param custom_error_message? string Custom error message to use
---@return string|nil error_message Error message if validation fails, nil if valid
function M.should_be_string_enum(value, allowed_values, custom_error_message)
  local err = M.should_be_string(value, custom_error_message)
  if err then
    return err
  end

  for _, allowed_value in ipairs(allowed_values) do
    if value == allowed_value then
      return nil
    end
  end

  return custom_error_message
    or ("expected to be one of {" .. table.concat(allowed_values, ", ") .. "} but actual: " .. format_actual(value))
end

---Validate that a value is either a string or a table
---@param value any The value to validate
---@param custom_error_message? string Custom error message to use
---@return string|nil error_message Error message if validation fails, nil if valid
function M.should_be_string_or_table(value, custom_error_message)
  if type(value) == "string" or type(value) == "table" then
    return nil
  end

  return custom_error_message or ("expected to be a string or table but actual: " .. format_actual(value))
end

---Validate that a value is a valid Neovim border specification
---@param value any The value to validate
---@param custom_error_message? string Custom error message to use
---@return string|nil error_message Error message if validation fails, nil if valid
function M.should_be_valid_border(value, custom_error_message)
  local err = M.should_be_string_or_table(value, custom_error_message)
  if err then
    return err
  end

  if type(value) == "string" then
    local valid_borders = { "none", "single", "double", "rounded", "solid", "shadow" }
    return M.should_be_string_enum(value, valid_borders, custom_error_message)
  end

  return nil
end

---Validate that a value is a valid keybindings table
---@param value any The value to validate
---@param custom_error_message? string Custom error message to use
---@return string|nil error_message Error message if validation fails, nil if valid
function M.should_be_valid_keybindings(value, custom_error_message)
  local err = M.should_be_table(value, custom_error_message)
  if err then
    return err
  end

  for key, binding in pairs(value) do
    local binding_err =
      M.should_be_string(binding, custom_error_message and (custom_error_message .. " (keybinding '" .. key .. "')"))
    if binding_err then
      return custom_error_message and (custom_error_message .. " - keybinding '" .. key .. "' is invalid")
        or ("keybinding '" .. key .. "' " .. binding_err)
    end
  end

  return nil
end

---Validate that a value is a valid buffer ID
---@param value any The value to validate
---@param custom_error_message? string Custom error message to use
---@return string|nil error_message Error message if validation fails, nil if valid
function M.should_be_valid_buffer(value, custom_error_message)
  local err = M.should_be_number(value)
  if err then
    return custom_error_message or ("buffer ID " .. err)
  end

  if not vim.api.nvim_buf_is_valid(value) then
    return custom_error_message or ("buffer ID " .. value .. " is not valid")
  end

  return nil
end

return M
