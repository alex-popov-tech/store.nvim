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

  local renderer_err =
    validators.should_be_function(config.repository_renderer, "list.repository_renderer must be a function")
  if renderer_err then
    return renderer_err
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

  -- Validate grouped window state
  if state.win ~= nil then
    local win_tbl_err = validators.should_be_table(state.win, "list.win must be a table")
    if win_tbl_err then
      return win_tbl_err
    end

    if state.win.id ~= nil then
      local win_err = validators.should_be_number(state.win.id, "list.win.id must be nil or a number")
      if win_err then
        return win_err
      end
    end

    if state.win.is_open ~= nil then
      if type(state.win.is_open) ~= "boolean" then
        return "list.win.is_open must be nil or a boolean, got: " .. type(state.win.is_open)
      end
    end

    if state.win.active_tab ~= nil then
      local tab_err = validators.should_be_string(state.win.active_tab, "list.win.active_tab must be nil or a string")
      if tab_err then
        return tab_err
      end
    end
  end

  -- Validate grouped buffer state
  if state.buf ~= nil then
    local buf_tbl_err = validators.should_be_table(state.buf, "list.buf must be a table")
    if buf_tbl_err then
      return buf_tbl_err
    end

    if state.buf.id ~= nil then
      local buf_err = validators.should_be_number(state.buf.id, "list.buf.id must be nil or a number")
      if buf_err then
        return buf_err
      end
    end

    if state.buf.install_id ~= nil then
      local install_err =
        validators.should_be_number(state.buf.install_id, "list.buf.install_id must be nil or a number")
      if install_err then
        return install_err
      end
    end
  end

  return nil
end

return M
