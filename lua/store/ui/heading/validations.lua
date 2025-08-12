local validators = require("store.validators")

local M = {}

---Validate heading window configuration
---@param config HeadingConfig Heading window configuration to validate
---@return string|nil error_message Error message if validation fails, nil if valid
function M.validate_config(config)
  local err = validators.should_be_table(config, "heading window config must be a table")
  if err then
    return err
  end

  local width_err = validators.should_be_number(config.width, "heading.width must be a number")
  if width_err then
    return width_err
  end

  local height_err = validators.should_be_number(config.height, "heading.height must be a number")
  if height_err then
    return height_err
  end

  local row_err = validators.should_be_number(config.row, "heading.row must be a number")
  if row_err then
    return row_err
  end

  local col_err = validators.should_be_number(config.col, "heading.col must be a number")
  if col_err then
    return col_err
  end

  return nil
end

---Validate heading state for consistency and safety
---@param state HeadingState Heading state to validate
---@return string|nil error_message Error message if validation fails, nil if valid
function M.validate_state(state)
  local err = validators.should_be_table(state, "heading state must be a table")
  if err then
    return err
  end

  -- Validate state field
  if state.state ~= nil then
    local state_err = validators.should_be_string(state.state, "heading.state must be a string")
    if state_err then
      return state_err
    end

    local valid_states = { loading = true, ready = true, error = true }
    if not valid_states[state.state] then
      return "heading.state must be one of 'loading', 'ready', 'error', got: " .. state.state
    end
  end

  -- Validate window state fields
  if state.win_id ~= nil then
    local win_err = validators.should_be_number(state.win_id, "heading.win_id must be nil or a number")
    if win_err then
      return win_err
    end
  end

  if state.buf_id ~= nil then
    local buf_err = validators.should_be_number(state.buf_id, "heading.buf_id must be nil or a number")
    if buf_err then
      return buf_err
    end
  end

  if state.is_open ~= nil then
    if type(state.is_open) ~= "boolean" then
      return "heading.is_open must be nil or a boolean, got: " .. type(state.is_open)
    end
  end

  -- Validate UI state fields
  if state.filter_query ~= nil then
    local filter_err = validators.should_be_string(state.filter_query, "heading.filter_query must be nil or a string")
    if filter_err then
      return filter_err
    end
  end

  if state.sort_type ~= nil then
    local sort_err = validators.should_be_string(state.sort_type, "heading.sort_type must be nil or a string")
    if sort_err then
      return sort_err
    end
  end

  if state.filtered_count ~= nil then
    local filtered_err =
      validators.should_be_number(state.filtered_count, "heading.filtered_count must be nil or a number")
    if filtered_err then
      return filtered_err
    end

    if state.filtered_count < 0 then
      return "heading.filtered_count must be non-negative, got: " .. state.filtered_count
    end
  end

  if state.total_count ~= nil then
    local total_err = validators.should_be_number(state.total_count, "heading.total_count must be nil or a number")
    if total_err then
      return total_err
    end

    if state.total_count < 0 then
      return "heading.total_count must be non-negative, got: " .. state.total_count
    end
  end

  if state.installable_count ~= nil then
    local installable_err =
      validators.should_be_number(state.installable_count, "heading.installable_count must be nil or a number")
    if installable_err then
      return installable_err
    end

    if state.installable_count < 0 then
      return "heading.installable_count must be non-negative, got: " .. state.installable_count
    end
  end

  if state.installed_count ~= nil then
    local installed_err =
      validators.should_be_number(state.installed_count, "heading.installed_count must be nil or a number")
    if installed_err then
      return installed_err
    end

    if state.installed_count < 0 then
      return "heading.installed_count must be non-negative, got: " .. state.installed_count
    end
  end

  return nil
end

return M
