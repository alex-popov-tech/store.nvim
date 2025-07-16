local validators = require("store.validators")
local logger = require("store.logger")

---@class ModalConfig
---@field border string Border style (none, single, double, rounded, solid, shadow)
---@field zindex number Z-index for modal windows
---@field row number? Row position for modal (nil for centered)
---@field col number? Column position for modal (nil for centered)
---@field on_close fun()? Called on StoreModal:close()

---@class ProportionsConfig
---@field list number Proportion of width for list pane (0.0-1.0)
---@field preview number Proportion of width for preview pane (0.0-1.0)

---@class FocusProportionsConfig
---@field focused number Proportion of width for focused pane (0.0-1.0)
---@field unfocused number Proportion of width for unfocused pane (0.0-1.0)

---@class KeybindingsConfig
---@field help string Key to show help
---@field close string Key to close modal
---@field filter string Key to open filter input
---@field refresh string Key to refresh data
---@field open string Key to open selected repository
---@field switch_focus string Key to switch focus between panes
---@field sort string Key to open sort menu

---@class UserConfig
---@field width? number Window width (0.0-1.0 for percentage, >1 for absolute)
---@field height? number Window height (0.0-1.0 for percentage, >1 for absolute)
---@field proportions? ProportionsConfig Layout proportions for panes
---@field modal? ModalConfig Modal-specific configuration
---@field keybindings? KeybindingsConfig Key binding configuration
---@field preview_debounce? number Debounce delay for preview updates (ms)
---@field cache_duration? number Cache duration in seconds
---@field data_source_url? string URL for fetching plugin data
---@field logging? string Logging level: "off"|"error"|"warn"|"log"|"debug" (default: "off")
---@field auto_resize_on_focus? boolean Enable automatic window resizing when focus changes
---@field focus_proportions? FocusProportionsConfig Proportions when focused/unfocused
---@field focus_resize_debounce? number Debounce delay for focus-based resize (ms)
---@field github_token? string GitHub personal access token for API authentication
---@field full_name_limit? number Maximum character length for repository full_name display
---@field list_fields? string[] List of fields to display in order: "full_name"|"stars"|"forks"|"issues"|"tags"

---@class ComputedConfig : UserConfig
---@field computed_layout ComputedLayout Computed window layout dimensions
---@field screen_info ScreenInfo Screen dimensions at time of computation
---@field computed_at number Unix timestamp when config was computed

---@class ScreenInfo
---@field width number Screen width in columns
---@field height number Screen height in lines

local M = {}

---@type ComputedConfig|nil
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
    on_close = nil,
  },

  -- Keybindings configuration
  keybindings = {
    help = "?",
    close = "q",
    filter = "f",
    refresh = "r",
    open = "<cr>",
    switch_focus = "<tab>",
    sort = "s",
  },

  -- Behavior
  preview_debounce = 150, -- ms delay for preview updates
  cache_duration = 24 * 60 * 60, -- 24 hours
  data_source_url = "https://gist.githubusercontent.com/alex-popov-tech/dfb6adf1ee0506461d7dc029a28f851d/raw/store.nvim_db_1.1.0.json", -- URL for plugin data

  -- Logging
  logging = "off",

  -- Auto-resize on focus
  auto_resize_on_focus = true,
  focus_proportions = {
    focused = 0.7, -- Focused window gets 70%
    unfocused = 0.3, -- Unfocused window gets 30%
  },
  focus_resize_debounce = 100, -- 100ms debounce delay

  -- GitHub API authentication
  github_token = nil, -- GitHub personal access token for API authentication

  -- List display settings
  full_name_limit = 35, -- Maximum character length for repository full_name display
  list_fields = { "full_name", "pushed_at", "stars", "forks", "issues", "tags" }, -- Fields to display in order
}

---@class WindowLayout
---@field width number Window width
---@field height number Window height
---@field row number Window row position
---@field col number Window column position

---@class ComputedLayout
---@field total_width number Total modal width
---@field total_height number Total modal height
---@field start_row number Starting row position
---@field start_col number Starting column position
---@field header_height number Header window height
---@field gap_between_windows number Gap between windows
---@field header WindowLayout Header window layout
---@field list WindowLayout List window layout
---@field preview WindowLayout Preview window layout

---Calculate window dimensions and positions for 3-window layout
---@param config UserConfig Modal configuration with width, height, and proportions
---@param custom_proportions? ProportionsConfig Optional custom proportions to override config.proportions
---@return ComputedLayout layout Layout calculations for all windows
local function calculate_layout(config, custom_proportions)
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

  -- Use custom proportions if provided, otherwise use config proportions
  local proportions = custom_proportions or config.proportions

  -- Window splits using proportions
  local list_width = math.floor(total_width * proportions.list)
  -- Subtract gap to align with header
  local preview_width = math.floor(total_width * proportions.preview) - 2

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

---Validate user configuration against expected structure
---@param config UserConfig|nil User-provided configuration
---@param merged_config UserConfig Merged configuration with defaults
---@return boolean is_valid True if configuration is valid
---@return string|nil error_message Error message if validation fails
local function validate_config(config, merged_config)
  if not config then
    return true, nil
  end

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

  if config.logging ~= nil then
    local err = validators.should_be_string(config.logging, "logging must be a string")
    if err then
      return false, err
    end

    -- Validate logging level value
    local valid_levels = { "off", "error", "warn", "log", "debug" }
    local is_valid_level = false
    for _, level in ipairs(valid_levels) do
      if config.logging == level then
        is_valid_level = true
        break
      end
    end

    if not is_valid_level then
      return false, "logging must be one of: off, error, warn, log, debug"
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

  if config.auto_resize_on_focus ~= nil then
    local err = validators.should_be_boolean(config.auto_resize_on_focus, "auto_resize_on_focus must be a boolean")
    if err then
      return false, err
    end
  end

  if config.focus_proportions ~= nil then
    local err = validators.should_be_table(config.focus_proportions, "focus_proportions must be a table")
    if err then
      return false, err
    end

    if config.focus_proportions.focused ~= nil then
      local focused_err = validators.should_be_positive_number(
        config.focus_proportions.focused,
        "focus_proportions.focused must be a positive number"
      )
      if focused_err then
        return false, focused_err
      end
    end

    if config.focus_proportions.unfocused ~= nil then
      local unfocused_err = validators.should_be_positive_number(
        config.focus_proportions.unfocused,
        "focus_proportions.unfocused must be a positive number"
      )
      if unfocused_err then
        return false, unfocused_err
      end
    end

    -- Validate focus proportions sum to 1.0
    local focused_prop = merged_config.focus_proportions.focused
    local unfocused_prop = merged_config.focus_proportions.unfocused
    if math.abs((focused_prop + unfocused_prop) - 1.0) > 0.001 then
      return false, "focus_proportions.focused + focus_proportions.unfocused must equal 1.0"
    end
  end

  if config.focus_resize_debounce ~= nil then
    local err = validators.should_be_positive_number(
      config.focus_resize_debounce,
      "focus_resize_debounce must be a positive number"
    )
    if err then
      return false, err
    end
  end

  if config.github_token ~= nil then
    local err = validators.should_be_string(config.github_token, "github_token must be a string")
    if err then
      return false, err
    end
  end

  if config.full_name_limit ~= nil then
    local err =
      validators.should_be_positive_number(config.full_name_limit, "full_name_limit must be a positive number")
    if err then
      return false, err
    end
  end

  if config.list_fields ~= nil then
    local err = validators.should_be_table(config.list_fields, "list_fields must be an array")
    if err then
      return false, err
    end

    if #config.list_fields == 0 then
      return false, "list_fields must contain at least one field"
    end
  end

  return true, nil
end

---Setup the configuration with user-provided options
---@param user_config? UserConfig User configuration to merge with defaults
function M.setup(user_config)
  -- Merge user config with defaults
  local merged_config = vim.tbl_deep_extend("force", DEFAULT_USER_CONFIG, user_config or {})

  -- Validate the merged configuration
  local is_valid, error_msg = validate_config(user_config, merged_config)
  if not is_valid then
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
    computed_at = os.time(),
  })

  -- Setup highlight groups for bubble-style tags
  vim.api.nvim_set_hl(0, "StoreTagBorder", { fg = "#5E81AC" })
  vim.api.nvim_set_hl(0, "StoreTagText", { bg = "#5E81AC", fg = "#ECEFF4" })
end

---Get plugin configuration (with lazy initialization)
---@return ComputedConfig config The complete plugin configuration with computed layout
function M.get()
  if not plugin_config then
    -- Lazy initialization with default user config
    M.setup(DEFAULT_USER_CONFIG)
  end
  return plugin_config
end

---Calculate layout with focus-based proportions
---@param focused_component string Component that should be focused ("list" or "preview")
---@return ComputedLayout layout Layout calculations with focus proportions applied
function M.calculate_layout_with_focus(focused_component)
  local config = M.get()

  if not config.auto_resize_on_focus then
    -- Feature disabled, return current layout
    return config.computed_layout
  end

  -- Validate focus_proportions exists
  if not config.focus_proportions or not config.focus_proportions.focused or not config.focus_proportions.unfocused then
    logger.warn("focus_proportions not properly configured, returning current layout")
    return config.computed_layout
  end

  -- Create proportions based on focus
  local focus_proportions = {}
  if focused_component == "list" then
    focus_proportions.list = config.focus_proportions.focused
    focus_proportions.preview = config.focus_proportions.unfocused
  elseif focused_component == "preview" then
    focus_proportions.list = config.focus_proportions.unfocused
    focus_proportions.preview = config.focus_proportions.focused
  else
    -- Invalid component, return current layout
    return config.computed_layout
  end

  return calculate_layout(config, focus_proportions)
end

return M
