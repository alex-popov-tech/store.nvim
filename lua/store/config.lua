local validators = require("store.validators")
local logger = require("store.logger")

local M = {}

-- Logger instance (will be initialized in setup function)
M.log = nil

-- Internal storage for computed plugin config
local plugin_config = nil

local DEFAULT_USER_CONFIG = {
  -- Main window dimensions (percentages or absolute)
  width = 0.8, -- 80% of screen width
  height = 0.8, -- 80% of screen height

  -- Window layout proportions (must sum to 1.0)
  proportions = {
    list = 0.3, -- 30% for repository list
    preview = 0.7, -- 70% for preview pane
  },

  -- Modal-specific configuration
  modal = {
    border = "rounded",
    zindex = 50,
    row = nil,
    col = nil,
  },

  -- Keybindings configuration
  keybindings = {
    help = "?",
    close = "q",
    filter = "f",
    refresh = "r",
    open = "<cr>",
    switch_focus = "<tab>",
  },

  -- Behavior
  preview_debounce = 150, -- ms delay for preview updates
  cache_duration = 24 * 60 * 60, -- 24 hours
  data_source_url = "https://gist.githubusercontent.com/alex-popov-tech/93dcd3ce38cbc7a0b3245b9b59b56c9b/raw/store.nvim-repos.json", -- URL for plugin data

  -- Logging
  debug = false,
  logger = {
    notify = false,
    file = false,
  },
}

-- Calculate window dimensions and positions for 3-window layout
---@param config table Modal configuration
---@return table Layout calculations
local function calculate_layout(config)
  local screen_width = vim.o.columns
  local screen_height = vim.o.lines

  -- Convert percentages to absolute values
  local total_width = math.floor(screen_width * config.width)
  local total_height = math.floor(screen_height * config.height)

  -- Calculate positioning to center the modal
  local start_row = math.floor((screen_height - total_height) / 2)
  local start_col = math.floor((screen_width - total_width) / 2)

  -- Layout dimensions
  local header_height = 6
  local gap_between_windows = 2
  local content_height = total_height - header_height - gap_between_windows

  -- Window splits using proportions
  local list_width = math.floor(total_width * config.proportions.list)
  -- Subtract gap to align with header
  local preview_width = math.floor(total_width * config.proportions.preview) - 2

  return {
    total_width = total_width,
    total_height = total_height,
    start_row = start_row,
    start_col = start_col,
    header_height = header_height,
    gap_between_windows = gap_between_windows,

    -- Header window (full width at top)
    header = {
      width = total_width,
      height = header_height,
      row = start_row,
      col = start_col,
    },

    -- List window (left side, below header)
    list = {
      width = list_width,
      height = content_height,
      row = start_row + header_height + gap_between_windows,
      col = start_col,
    },

    -- Preview window (right side, below header)
    preview = {
      width = preview_width,
      height = content_height,
      row = start_row + header_height + gap_between_windows,
      col = start_col + list_width + 3, -- +3 for prettier gap
    },
  }
end

local function validate_config(config, merged_config)
  if config.width ~= nil then
    local err = validators.should_be_positive_number(config.width, "width must be a positive number")
    if err then
      return false, err
    end
  end

  if config.height ~= nil then
    local err = validators.should_be_positive_number(config.height, "height must be a positive number")
    if err then
      return false, err
    end
  end

  if config.proportions ~= nil then
    local err = validators.should_be_table(config.proportions, "proportions must be a table")
    if err then
      return false, err
    end

    if config.proportions.list ~= nil then
      local list_err =
        validators.should_be_positive_number(config.proportions.list, "proportions.list must be a positive number")
      if list_err then
        return false, list_err
      end
    end

    if config.proportions.preview ~= nil then
      local preview_err = validators.should_be_positive_number(
        config.proportions.preview,
        "proportions.preview must be a positive number"
      )
      if preview_err then
        return false, preview_err
      end
    end

    -- Validate proportions sum to 1.0
    local list_prop = merged_config.proportions.list
    local preview_prop = merged_config.proportions.preview
    if math.abs((list_prop + preview_prop) - 1.0) > 0.001 then
      return false, "proportions.list + proportions.preview must equal 1.0"
    end
  end

  if config.debug ~= nil then
    local err = validators.should_be_boolean(config.debug, "debug must be a boolean value")
    if err then
      return false, err
    end
  end

  if config.data_source_url ~= nil then
    local err = validators.should_be_string(config.data_source_url, "data_source_url must be a string")
    if err then
      return false, err
    end

    -- Basic URL validation
    if not config.data_source_url:match("^https?://") then
      return false, "data_source_url must be a valid HTTP(S) URL"
    end
  end

  return true, nil
end

function M.setup(user_config)
  -- Merge user config with defaults
  local merged_config = vim.tbl_deep_extend("force", DEFAULT_USER_CONFIG, user_config or {})

  -- Extract logger config and initialize logger
  local logger_config = merged_config.logger or {}
  M.log = logger.new(logger_config)

  -- Validate the merged configuration
  local is_valid, error_msg = validate_config(user_config, merged_config)
  if not is_valid then
    M.log.error("Configuration error: " .. error_msg)
    error("Store.nvim configuration error: " .. error_msg)
  end

  -- Calculate layout with final config
  local computed_layout = calculate_layout(merged_config)

  -- Build the full plugin config
  plugin_config = vim.tbl_deep_extend("force", merged_config, {
    computed_layout = computed_layout,
    screen_info = {
      width = vim.o.columns,
      height = vim.o.lines,
    },
    log = M.log,
    computed_at = os.time(),
  })

  if merged_config.debug then
    M.log.info("Configuration loaded successfully")
  end
end

-- Get plugin configuration (with lazy initialization)
function M.get()
  if not plugin_config then
    -- Lazy initialization with default user config
    M.setup(DEFAULT_USER_CONFIG)
  end
  return plugin_config
end

return M
