local M = {}

local function format_actual(value)
  if type(value) == "string" then
    return '"' .. value .. '" (string)'
  elseif type(value) == "nil" then
    return "nil (nil)"
  else
    return tostring(value) .. " (" .. type(value) .. ")"
  end
end

function M.should_be_number(value, custom_error_message)
  if type(value) ~= "number" then
    return custom_error_message or ("expected to be a number but actual: " .. format_actual(value))
  end
  return nil
end

function M.should_be_boolean(value, custom_error_message)
  if type(value) ~= "boolean" then
    return custom_error_message or ("expected to be a boolean but actual: " .. format_actual(value))
  end
  return nil
end

function M.should_be_string(value, custom_error_message)
  if type(value) ~= "string" then
    return custom_error_message or ("expected to be a string but actual: " .. format_actual(value))
  end
  return nil
end

function M.should_be_table(value, custom_error_message)
  if type(value) ~= "table" then
    return custom_error_message or ("expected to be a table but actual: " .. format_actual(value))
  end
  return nil
end

function M.should_be_function(value, custom_error_message)
  if type(value) ~= "function" then
    return custom_error_message or ("expected to be a function but actual: " .. format_actual(value))
  end
  return nil
end

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

function M.should_be_string_or_table(value, custom_error_message)
  if type(value) == "string" or type(value) == "table" then
    return nil
  end

  return custom_error_message or ("expected to be a string or table but actual: " .. format_actual(value))
end

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

return M
