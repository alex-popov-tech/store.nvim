local validators = require("store.validators")
local logger = require("store.logger")

local M = {}

-- Logger instance (will be initialized in build function)
M.log = nil

local default_config_template = {
  modal = {
    width = 0.7,
    height = 0.7,
    border = "rounded",
    zindex = 45,
    backdrop_opacity = 20,
  },
  debug = false,
  logger = {
    notify = false,
    file = false,
  },
  keybindings = {
    close = "q",
    close_alt = "<Esc>",
    help = "?",
  },
}

-- Logger is now handled by plenary.log

local function validate_config(config)
  -- Skip logger validation here as it's handled separately
  if config.modal then
    local modal = config.modal
    if modal.width then
      local err = validators.should_be_positive_number(modal.width, "modal.width must be a positive number")
      if err then
        return false, err
      end
    end
    if modal.height then
      local err = validators.should_be_positive_number(modal.height, "modal.height must be a positive number")
      if err then
        return false, err
      end
    end
    if modal.border then
      local err = validators.should_be_valid_border(modal.border, "modal.border must be a valid border style")
      if err then
        return false, err
      end
    end
    if modal.zindex then
      local err = validators.should_be_positive_number(modal.zindex, "modal.zindex must be a positive number")
      if err then
        return false, err
      end
    end
    if modal.backdrop_opacity then
      local err = validators.should_be_number_in_range(
        modal.backdrop_opacity,
        0,
        100,
        "modal.backdrop_opacity must be between 0 and 100"
      )
      if err then
        return false, err
      end
    end
  end

  if config.debug ~= nil then
    local err = validators.should_be_boolean(config.debug, "debug must be a boolean value")
    if err then
      return false, err
    end
  end

  if config.keybindings then
    local err =
      validators.should_be_valid_keybindings(config.keybindings, "keybindings must be a table with string values")
    if err then
      return false, err
    end
    if config.keybindings.help then
      local help_err = validators.should_be_string(config.keybindings.help, "keybindings.help must be a string")
      if help_err then
        return false, help_err
      end
    end
  end

  return true, nil
end

local function calculate_window_layout(width_config, height_config)
  local screen_width = vim.o.columns
  local screen_height = vim.o.lines

  local width = width_config <= 1 and math.floor(screen_width * width_config) or math.min(width_config, screen_width)
  local height = height_config <= 1 and math.floor(screen_height * height_config)
    or math.min(height_config, screen_height)

  local row = math.floor((screen_height - height) / 2)
  local col = math.floor((screen_width - width) / 2)

  return width, height, row, col
end

function M.build(user_config)
  user_config = user_config or {}

  -- Extract logger config and initialize logger (following mermaid diagram)
  local logger_config = user_config.logger or {}
  M.log = logger.new(logger_config)

  local is_valid, error_msg = validate_config(user_config)
  if not is_valid then
    M.log.error("Configuration error: " .. error_msg)
    user_config = {}
  end

  local merged_config = vim.tbl_deep_extend("force", default_config_template, user_config)
  local width, height, row, col = calculate_window_layout(merged_config.modal.width, merged_config.modal.height)

  local built_config = {
    modal = {
      width = width,
      height = height,
      row = row,
      col = col,
      border = merged_config.modal.border,
      zindex = merged_config.modal.zindex,
      backdrop_opacity = merged_config.modal.backdrop_opacity,
    },
    debug = merged_config.debug,
    logger = merged_config.logger,
    keybindings = merged_config.keybindings,
  }

  if built_config.debug then
    M.log.info("Configuration loaded successfully")
  end

  return built_config
end

return M
