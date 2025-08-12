local validators = require("store.validators")
local sort = require("store.sort")

local M = {}

---Validate sort select configuration
---@param config SortSelectConfig|nil
---@return string|nil Error message or nil if valid
function M.validate_config(config)
  if not config then
    return "sort_select.config must be a table, got: nil"
  end

  local width_error =
    validators.should_be_positive_number(config.width, "sort_select.config.width must be a positive number")
  if width_error then
    return width_error
  end

  local height_error =
    validators.should_be_positive_number(config.height, "sort_select.config.height must be a positive number")
  if height_error then
    return height_error
  end

  local row_error = validators.should_be_number(config.row, "sort_select.config.row must be a number")
  if row_error then
    return row_error
  end

  local col_error = validators.should_be_number(config.col, "sort_select.config.col must be a number")
  if col_error then
    return col_error
  end

  local current_sort_error =
    validators.should_be_string(config.current_sort, "sort_select.config.current_sort must be a string")
  if current_sort_error then
    return current_sort_error
  end

  if not config.on_value or type(config.on_value) ~= "function" then
    return "sort_select.config.on_value must be a function, got: " .. type(config.on_value)
  end

  if not config.on_exit or type(config.on_exit) ~= "function" then
    return "sort_select.config.on_exit must be a function, got: " .. type(config.on_exit)
  end

  if config.sort_types and type(config.sort_types) ~= "table" then
    return "sort_select.config.sort_types must be a table or nil, got: " .. type(config.sort_types)
  end

  return nil
end

---Validate sort select state
---@param state SortSelectState
---@return string|nil Error message or nil if valid
function M.validate_state(state)
  if not state then
    return "sort_select.state must be a table, got: nil"
  end

  local is_open_error = validators.should_be_boolean(state.is_open, "sort_select.state.is_open must be a boolean")
  if is_open_error then
    return is_open_error
  end

  local state_error = validators.should_be_string(state.state, "sort_select.state.state must be a string")
  if state_error then
    return state_error
  end

  if state.sort_types and type(state.sort_types) ~= "table" then
    return "sort_select.state.sort_types must be a table, got: " .. type(state.sort_types)
  end

  local current_sort_error =
    validators.should_be_string(state.current_sort, "sort_select.state.current_sort must be a string")
  if current_sort_error then
    return current_sort_error
  end

  return nil
end

---Validate sort types integration
---@param sort_types string[]|nil
---@return string[]|nil, string|nil Sort types array or nil, error message
function M.validate_sort_types(sort_types)
  if sort_types then
    if type(sort_types) ~= "table" then
      return nil, "sort_types must be a table, got: " .. type(sort_types)
    end

    if #sort_types == 0 then
      return nil, "sort_types cannot be empty"
    end

    -- Validate each sort type exists in store.sort
    for i, sort_type in ipairs(sort_types) do
      if type(sort_type) ~= "string" then
        return nil, "sort_types[" .. i .. "] must be a string, got: " .. type(sort_type)
      end

      if not sort.sorts[sort_type] then
        return nil, "sort_types[" .. i .. "] '" .. sort_type .. "' not found in store.sort.sorts"
      end
    end

    return sort_types, nil
  else
    -- Use store.sort.get_sort_types() as fallback
    local store_sort_types = sort.get_sort_types()
    if not store_sort_types or #store_sort_types == 0 then
      return nil, "No sort types available from store.sort"
    end
    return store_sort_types, nil
  end
end

return M
