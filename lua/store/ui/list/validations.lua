local validators = require("store.validators")

local M = {}

---Validate list window configuration
---@param config ListConfig List window configuration to validate
---@return string|nil error_message Error message if validation fails, nil if valid
function M.validate_config(config)
  local err = validators.should_be_table(config, "list window config must be a table")
  if err then
    return err
  end

  local width_err = validators.should_be_number(config.width, "list.width must be a number")
  if width_err then
    return width_err
  end

  local height_err = validators.should_be_number(config.height, "list.height must be a number")
  if height_err then
    return height_err
  end

  local row_err = validators.should_be_number(config.row, "list.row must be a number")
  if row_err then
    return row_err
  end

  local col_err = validators.should_be_number(config.col, "list.col must be a number")
  if col_err then
    return col_err
  end

  local callback_err = validators.should_be_function(config.on_repo, "list.on_repo must be a function")
  if callback_err then
    return callback_err
  end

  local keymaps_err = validators.should_be_function(config.keymaps_applier, "list.keymaps_applier must be a function")
  if keymaps_err then
    return keymaps_err
  end

  local debounce_err =
    validators.should_be_number(config.cursor_debounce_delay, "list.cursor_debounce_delay must be a number")
  if debounce_err then
    return debounce_err
  end

  local list_fields_err = validators.should_be_table(config.list_fields, "list.list_fields must be an array")
  if list_fields_err then
    return list_fields_err
  end

  return nil
end

---Validate list state for consistency and safety
---@param state ListStateUpdate List state to validate
---@return string|nil error_message Error message if validation fails, nil if valid
function M.validate_state(state)
  local err = validators.should_be_table(state, "list state must be a table")
  if err then
    return err
  end

  -- Validate state field
  if state.state ~= nil then
    local state_err = validators.should_be_string(state.state, "list.state must be a string")
    if state_err then
      return state_err
    end

    local valid_states = { loading = true, ready = true, error = true }
    if not valid_states[state.state] then
      return "list.state must be one of 'loading', 'ready', 'error', got: " .. state.state
    end
  end

  -- Validate items field
  if state.items ~= nil then
    if type(state.items) ~= "table" then
      return "list.items must be nil or an array of repositories, got: " .. type(state.items)
    end

    for i, item in ipairs(state.items) do
      if type(item) ~= "table" then
        return "list.items[" .. i .. "] must be a repository table, got: " .. type(item)
      end
    end
  end

  -- Validate window state fields if present
  if state.win_id ~= nil then
    local win_err = validators.should_be_number(state.win_id, "list.win_id must be nil or a number")
    if win_err then
      return win_err
    end
  end

  if state.buf_id ~= nil then
    local buf_err = validators.should_be_number(state.buf_id, "list.buf_id must be nil or a number")
    if buf_err then
      return buf_err
    end
  end

  if state.is_open ~= nil then
    if type(state.is_open) ~= "boolean" then
      return "list.is_open must be nil or a boolean, got: " .. type(state.is_open)
    end
  end

  -- Validate operational state fields if present

  -- Validate cursor state fields if present
  if state.cursor_autocmd_id ~= nil then
    local autocmd_err =
      validators.should_be_number(state.cursor_autocmd_id, "list.cursor_autocmd_id must be nil or a number")
    if autocmd_err then
      return autocmd_err
    end
  end

  if state.cursor_debounce_timer ~= nil then
    local timer_err =
      validators.should_be_number(state.cursor_debounce_timer, "list.cursor_debounce_timer must be nil or a number")
    if timer_err then
      return timer_err
    end
  end

  return nil
end

return M
