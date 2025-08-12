local validators = require("store.validators")

local M = {}

---Validate preview window configuration
---@param config PreviewConfig Preview window configuration to validate
---@return string|nil error_message Error message if validation fails, nil if valid
function M.validate_config(config)
  local err = validators.should_be_table(config, "preview window config must be a table")
  if err then
    return err
  end

  local width_err = validators.should_be_number(config.width, "preview.width must be a number")
  if width_err then
    return width_err
  end

  local height_err = validators.should_be_number(config.height, "preview.height must be a number")
  if height_err then
    return height_err
  end

  local row_err = validators.should_be_number(config.row, "preview.row must be a number")
  if row_err then
    return row_err
  end

  local col_err = validators.should_be_number(config.col, "preview.col must be a number")
  if col_err then
    return col_err
  end

  return validators.should_be_function(config.keymaps_applier, "preview.keymaps_applier must be a function")
end

---Validate preview state for consistency and safety
---@param state PreviewState Preview state to validate
---@return string|nil error_message Error message if validation fails, nil if valid
function M.validate_state(state)
  local err = validators.should_be_table(state, "preview state must be a table")
  if err then
    return err
  end

  -- Validate state field
  if state.state ~= nil then
    local state_err = validators.should_be_string(state.state, "preview.state must be a string")
    if state_err then
      return state_err
    end

    local valid_states = { loading = true, ready = true, error = true }
    if not valid_states[state.state] then
      return "preview.state must be one of 'loading', 'ready', 'error', got: " .. state.state
    end
  end

  -- Validate content field
  if state.content ~= nil then
    if type(state.content) ~= "table" then
      return "preview.content must be nil or an array of strings, got: " .. type(state.content)
    end

    for i, line in ipairs(state.content) do
      if type(line) ~= "string" then
        return "preview.content[" .. i .. "] must be a string, got: " .. type(line)
      end
    end
  end

  -- Validate readme_id field
  if state.readme_id ~= nil then
    local readme_err = validators.should_be_string(state.readme_id, "preview.readme_id must be nil or a string")
    if readme_err then
      return readme_err
    end
  end

  -- Validate window state fields if present
  if state.win_id ~= nil then
    local win_err = validators.should_be_number(state.win_id, "preview.win_id must be nil or a number")
    if win_err then
      return win_err
    end
  end

  if state.buf_id ~= nil then
    local buf_err = validators.should_be_number(state.buf_id, "preview.buf_id must be nil or a number")
    if buf_err then
      return buf_err
    end
  end

  if state.is_open ~= nil then
    if type(state.is_open) ~= "boolean" then
      return "preview.is_open must be nil or a boolean, got: " .. type(state.is_open)
    end
  end

  -- Validate cursor state fields if present
  if state.cursor_positions ~= nil then
    if type(state.cursor_positions) ~= "table" then
      return "preview.cursor_positions must be nil or a table, got: " .. type(state.cursor_positions)
    end
  end

  if state.current_readme_id ~= nil then
    local current_readme_err =
      validators.should_be_string(state.current_readme_id, "preview.current_readme_id must be nil or a string")
    if current_readme_err then
      return current_readme_err
    end
  end

  return nil
end

return M
