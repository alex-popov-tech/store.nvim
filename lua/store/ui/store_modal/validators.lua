local validators = require("store.validators")

local M = {}

-- Validate modal configuration
---@param config StoreModalConfig|nil Modal configuration to validate
---@return string|nil error_message Error message if validation fails, nil if valid
function M.validate(config)
  if config == nil then
    return "Configuration required. StoreModal expects config from config.lua"
  end

  local err = validators.should_be_table(config, "modal config must be a table")
  if err then
    return err
  end

  if config.width ~= nil then
    local width_err = validators.should_be_number(config.width, "modal.width must be a number")
    if width_err then
      return width_err
    end
  end

  if config.height ~= nil then
    local height_err = validators.should_be_number(config.height, "modal.height must be a number")
    if height_err then
      return height_err
    end
  end

  if config.proportions ~= nil then
    local proportions_err = validators.should_be_table(config.proportions, "modal.proportions must be a table")
    if proportions_err then
      return proportions_err
    end

    if config.proportions.list ~= nil then
      local list_err = validators.should_be_number(config.proportions.list, "modal.proportions.list must be a number")
      if list_err then
        return list_err
      end
    end

    if config.proportions.preview ~= nil then
      local preview_err =
        validators.should_be_number(config.proportions.preview, "modal.proportions.preview must be a number")
      if preview_err then
        return preview_err
      end
    end

    -- Note: proportions validation is handled in config.lua
  end

  return nil
end

---Validate that the modal is open
---@param modal StoreModal The modal instance
---@return string|nil error Error message if validation failed, nil if valid
function M.validate_modal_open(modal)
  if not modal.is_open then
    return "Modal is not open"
  end
  return nil
end

---Validate that modal components are initialized
---@param modal StoreModal The modal instance
---@return string|nil error Error message if validation failed, nil if valid
function M.validate_components(modal)
  if not modal.heading or not modal.list or not modal.preview then
    return "Modal components not initialized"
  end
  return nil
end

---Validate that component windows are available and valid
---@param modal StoreModal The modal instance
---@return string|nil error Error message if validation failed, nil if valid
function M.validate_component_windows(modal)
  local list_win_id = modal.list:get_window_id()
  local preview_win_id = modal.preview:get_window_id()

  if not list_win_id or not preview_win_id then
    return "Component window IDs not available"
  end

  if not vim.api.nvim_win_is_valid(list_win_id) or not vim.api.nvim_win_is_valid(preview_win_id) then
    return "Component windows are invalid"
  end

  return nil
end

---Validate screen dimensions for modal display
---@param width number Screen width
---@param height number Screen height
---@return string|nil error Error message if validation failed, nil if valid
function M.validate_screen_dimensions(width, height)
  if width <= 0 or height <= 0 then
    return "Invalid screen dimensions: " .. width .. "x" .. height
  end

  local MIN_MODAL_WIDTH, MIN_MODAL_HEIGHT = 85, 18
  if width < MIN_MODAL_WIDTH or height < MIN_MODAL_HEIGHT then
    return "Screen too small for modal (minimum: " .. MIN_MODAL_WIDTH .. "x" .. MIN_MODAL_HEIGHT .. ")"
  end

  return nil
end

---Validate that modal state is consistent
---@param modal StoreModal The modal instance
---@return string|nil error Error message if validation failed, nil if valid
function M.validate_modal_state(modal)
  if not modal.state then
    return "Modal state not initialized"
  end

  -- Check for required state fields
  local required_fields = { "repos", "filtered_repos", "current_focus" }
  for _, field in ipairs(required_fields) do
    if modal.state[field] == nil then
      return "Modal state missing required field: " .. field
    end
  end

  return nil
end

---Validate repository data structure
---@param repo table Repository data
---@return string|nil error Error message if validation failed, nil if valid
function M.validate_repository(repo)
  if not repo then
    return "Repository data is nil"
  end

  if type(repo) ~= "table" then
    return "Repository data must be a table"
  end

  local required_fields = { "full_name", "html_url" }
  for _, field in ipairs(required_fields) do
    if not repo[field] then
      return "Repository missing required field: " .. field
    end
  end

  return nil
end

return M
