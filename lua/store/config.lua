local validators = require("store.validators")
local utils = require("store.utils")
local keymaps = require("store.keymaps")
local sort = require("store.sort")

---@class UserConfig
---@field width? number Window width (0.0-1.0 as percentage of screen width)
---@field height? number Window height (0.0-1.0 as percentage of screen height)
---@field proportions? {list: number, preview: number} Layout proportions for panes (0.0-1.0)
---@field keybindings? {help: string[], close: string[], filter: string[], reset: string[], open: string[], switch_focus: string[], sort: string[], install: string[], hover: string[]} Key binding configuration
---@field preview_debounce? number Debounce delay for preview updates (ms)
---@field logging? string Logging level: "off"|"error"|"warn"|"info"|"debug" (default: "off")
---@field repository_renderer? RepositoryRenderer Function to render repository data for list display
---@field zindex? {base: number, backdrop: number, popup: number} Z-index configuration for modal layers
---@field resize_debounce? number Debounce delay for resize operations (ms, 10-200 range)
---@field plugins_folder? string Absolute path to plugins folder (defaults to ~/.config/nvim/lua/plugins)
---@field install_catalogue_urls? table<string, string> Mapping of plugin manager identifiers to catalogue URLs
---@field plugin_manager? string Preferred plugin manager selection ("not-selected"|"lazy.nvim"|"vim.pack")

---@class UserConfigWithDefaults
---@field width number Window width (0.0-1.0 as percentage of screen width)
---@field height number Window height (0.0-1.0 as percentage of screen height)
---@field proportions {list: number, preview: number} Layout proportions for panes (0.0-1.0)
---@field keybindings {help: string[], close: string[], filter: string[], reset: string[], open: string[], switch_focus: string[], sort: string[], install: string[], hover: string[]} Key binding configuration
---@field preview_debounce number Debounce delay for preview updates (ms)
---@field data_source_url string URL for fetching plugin data
---@field logging string Logging level: "off"|"error"|"warn"|"info"|"debug" (default: "off")
---@field repository_renderer RepositoryRenderer Function to render repository data for list display
---@field zindex {base: number, backdrop: number, popup: number} Z-index configuration for modal layers
---@field resize_debounce number Debounce delay for resize operations (ms, 10-200 range)
---@field plugins_folder? string Absolute path to plugins folder (defaults to ~/.config/nvim/lua/plugins)
---@field install_catalogue_urls table<string, string>
---@field plugin_manager string Preferred plugin manager selection

---@class ComponentLayout
---@field width number Window width
---@field height number Window height
---@field row number Window row position
---@field col number Window column position

---@class StoreModalLayout
---@field total_width number Total modal width
---@field total_height number Total modal height
---@field start_row number Starting row position
---@field start_col number Starting column position
---@field header_height number Header window height
---@field gap_between_windows number Gap between windows
---@field header ComponentLayout Header window layout
---@field list ComponentLayout List window layout
---@field preview ComponentLayout Preview window layout
---@field filter ComponentLayout Filter popup layout
---@field sort ComponentLayout Sort popup layout
---@field help ComponentLayout Help popup layout

---@class PluginConfig : UserConfigWithDefaults
---@field layout StoreModalLayout Window layout dimensions

local M = {}

---@type PluginConfig|nil
local plugin_config = nil

-- Calculate all layout dimensions and return complete layout
---@param config table Configuration with width, height, proportions, and keybindings
---@return StoreModalLayout|nil layout Complete layout if calculation succeeded, nil if failed
---@return string|nil error Error message if calculation failed
local function calculate_complete_layout(config)
  -- Calculate filter dimensions: half width of main modal, single line
  local screen_width = vim.o.columns
  local main_modal_width = math.floor(screen_width * config.width)
  local filter_width = math.floor(main_modal_width / 2)
  local filter_height = 1

  -- Calculate sort dimensions from sort module
  local sort_types = sort.get_sort_types()
  local sort_lines_count = #sort_types
  local sort_longest_line = 0
  local checkmark_space = 2 -- "✓ "

  for _, sort_type in ipairs(sort_types) do
    local label = sort.sorts[sort_type].label
    local line_length = checkmark_space + vim.fn.strchars(label)
    sort_longest_line = math.max(sort_longest_line, line_length)
  end

  -- Calculate help dimensions from keybindings and labels
  local help_lines_count = 2 -- header + separator
  local max_keybinding_length = 3 -- minimum for "Key" header
  local max_label_length = 6 -- minimum for "Action" header

  for action, keys in pairs(config.keybindings) do
    help_lines_count = help_lines_count + #keys
    for _, key in ipairs(keys) do
      max_keybinding_length = math.max(max_keybinding_length, vim.fn.strchars(key))
    end
    local label = keymaps.get_label(action)
    if not label then
      return nil, "No label found for action '" .. action .. "'"
    end
    max_label_length = math.max(max_label_length, vim.fn.strchars(label))
  end

  local column_spacing = 2
  local help_longest_line = max_keybinding_length + column_spacing + max_label_length

  -- Calculate complete layout
  return utils.calculate_layout({
    width = config.width,
    height = config.height,
    proportions = config.proportions,
  }, {
    filter = {
      width = filter_width,
      height = filter_height,
    },
    sort = {
      lines_count = sort_lines_count,
      longest_line = sort_longest_line,
    },
    help = {
      lines_count = help_lines_count,
      longest_line = help_longest_line,
    },
  })
end

---Default repository renderer that mimics the original behavior
---@param repo Repository Repository data to render
---@param isInstalled boolean Whether the repository is installed
---@return RepositoryField[] fields Array of field data for display
local function default_repository_renderer(repo, isInstalled)
  return {
    {
      content = isInstalled and "🏠" or " ",
      limit = 2,
    },
    {
      content = "⭐" .. repo.pretty.stars,
      limit = 10,
    },
    {
      content = repo.full_name,
      limit = 35,
    },
    {
      content = "Last updated " .. repo.pretty.updated_at,
      limit = 30,
    },
    {
      content = repo.tags and #repo.tags > 0 and table.concat(repo.tags, ", ") or "",
      limit = 100,
    },
    {
      content = repo.description,
      limit = 100,
    },
  }
end

local DEFAULT_USER_CONFIG = {
  -- Main window dimensions as percentage of the editor
  width = 0.8, -- 80% of screen width
  height = 0.8, -- 80% of screen height

  -- Window layout proportions (must sum to 1.0)
  proportions = {
    list = 0.5,
    preview = 0.5,
  },

  -- Keybindings configuration
  keybindings = {
    help = { "?" },
    close = { "q", "<esc>", "<c-c>" },
    filter = { "f" },
    reset = { "r" },
    open = { "<cr>", "o" },
    switch_focus = { "<tab>", "<s-tab>" },
    sort = { "s" },
    install = { "i" },
    hover = { "K" },
  },

  -- Behavior
  preview_debounce = 50, -- ms delay for preview updates
  data_source_url = "https://gist.githubusercontent.com/alex-popov-tech/92d1366bfeb168d767153a24be1475b5/raw/db.json", -- URL for plugin data
  install_catalogue_urls = {
    ["lazy.nvim"] = "https://gist.githubusercontent.com/alex-popov-tech/6629a59e7910aa08b1aa5cdc0519b8b4/raw/lazy.nvim.json",
    ["vim.pack"] = "https://gist.githubusercontent.com/alex-popov-tech/18a46177d6473e12bc2c854e2548f127/raw/vim.pack.json",
  },
  plugin_manager = "not-selected",

  -- Logging
  logging = "warn",

  -- List display settings
  repository_renderer = default_repository_renderer, -- Function to render repository data for list display

  -- Z-index configuration for modal layers
  zindex = {
    base = 10, -- Base modal components (heading, list, preview)
    backdrop = 15, -- Reserved for backdrop/dimming layer
    popup = 20, -- Popup modals (help, sort, filter)
  },

  -- Resize behavior
  resize_debounce = 30, -- ms delay for resize debouncing (10-200ms range)

  -- Plugins location (absolute path or starts with ~)
  -- Defaults to ~/.config/nvim/lua/plugins if not specified
  plugins_folder = nil,
}

---Validate merged configuration against expected structure
---@param config UserConfigWithDefaults Merged configuration with defaults
---@return string|nil error_message Error message if validation fails, nil if valid
local function validate_config(config)
  if not config then
    return nil
  end

  if config.width ~= nil then
    local err = validators.should_be_positive_number(config.width, "width must be a positive number")
    if err then
      return err
    end

    if config.width > 1 then
      return "width must be a percentage between 0 and 1"
    end
  end

  if config.height ~= nil then
    local err = validators.should_be_positive_number(config.height, "height must be a positive number")
    if err then
      return err
    end

    if config.height > 1 then
      return "height must be a percentage between 0 and 1"
    end
  end

  if config.proportions ~= nil then
    local err = validators.should_be_table(config.proportions, "proportions must be a table")
    if err then
      return err
    end

    if config.proportions.list ~= nil then
      local list_err =
        validators.should_be_positive_number(config.proportions.list, "proportions.list must be a positive number")
      if list_err then
        return list_err
      end
    end

    if config.proportions.preview ~= nil then
      local preview_err = validators.should_be_positive_number(
        config.proportions.preview,
        "proportions.preview must be a positive number"
      )
      if preview_err then
        return preview_err
      end
    end

    -- Validate proportions sum to 1.0
    local list_prop = config.proportions.list
    local preview_prop = config.proportions.preview
    if math.abs((list_prop + preview_prop) - 1.0) > 0.001 then
      return "proportions.list + proportions.preview must equal 1.0"
    end
  end

  if config.preview_debounce ~= nil then
    local err =
      validators.should_be_positive_number(config.preview_debounce, "preview_debounce must be a positive number")
    if err then
      return err
    end
  end

  if config.logging ~= nil then
    local err = validators.should_be_string(config.logging, "logging must be a string")
    if err then
      return err
    end

    -- Validate logging level value
    local valid_levels = { "off", "error", "warn", "info", "debug" }
    local is_valid_level = false
    for _, level in ipairs(valid_levels) do
      if config.logging == level then
        is_valid_level = true
        break
      end
    end

    if not is_valid_level then
      return "logging must be one of: off, error, warn, info, debug"
    end
  end

  if config.data_source_url ~= nil then
    local err = validators.should_be_string(config.data_source_url, "data_source_url must be a string")
    if err then
      return err
    end

    -- Basic URL validation
    if not config.data_source_url:match("^https?://") then
      return "data_source_url must be a valid HTTP(S) URL"
    end
  end

  if config.repository_renderer ~= nil then
    if type(config.repository_renderer) ~= "function" then
      return "repository_renderer must be a function"
    end
  end

  if config.install_catalogue_urls ~= nil then
    local err = validators.should_be_table(config.install_catalogue_urls, "install_catalogue_urls must be a table")
    if err then
      return err
    end

    for manager, url in pairs(config.install_catalogue_urls) do
      if type(manager) ~= "string" then
        return "install_catalogue_urls keys must be strings"
      end
      local url_err = validators.should_be_string(url, "install_catalogue_urls['" .. manager .. "'] must be a string")
      if url_err then
        return url_err
      end
      if not url:match("^https?://") then
        return "install_catalogue_urls['" .. manager .. "'] must be a valid HTTP(S) URL"
      end
    end
  end

  if config.plugin_manager ~= nil then
    local err = validators.should_be_string(config.plugin_manager, "plugin_manager must be a string")
    if err then
      return err
    end

    local allowed = {
      ["not-selected"] = true,
      ["lazy.nvim"] = true,
      ["vim.pack"] = true,
    }

    if not allowed[config.plugin_manager] then
      return "plugin_manager must be one of: not-selected, lazy.nvim, vim.pack"
    end
  end

  if config.keybindings ~= nil then
    local err = validators.should_be_table(config.keybindings, "keybindings must be a table")
    if err then
      return err
    end

    for action, keys in pairs(config.keybindings) do
      if type(keys) ~= "table" then
        return "keybindings." .. action .. " must be an array of strings"
      end

      if #keys == 0 then
        return "keybindings." .. action .. " must contain at least one key"
      end

      for i, key in ipairs(keys) do
        if type(key) ~= "string" then
          return "keybindings." .. action .. "[" .. i .. "] must be a string"
        end

        if key == "" then
          return "keybindings." .. action .. "[" .. i .. "] cannot be empty"
        end
      end
    end
  end

  if config.zindex ~= nil then
    local err = validators.should_be_table(config.zindex, "zindex must be a table")
    if err then
      return err
    end

    -- Validate each zindex value
    if config.zindex.base ~= nil then
      local base_err = validators.should_be_positive_number(config.zindex.base, "zindex.base must be a positive number")
      if base_err then
        return base_err
      end
    end

    if config.zindex.backdrop ~= nil then
      local backdrop_err =
        validators.should_be_positive_number(config.zindex.backdrop, "zindex.backdrop must be a positive number")
      if backdrop_err then
        return backdrop_err
      end
    end

    if config.zindex.popup ~= nil then
      local popup_err =
        validators.should_be_positive_number(config.zindex.popup, "zindex.popup must be a positive number")
      if popup_err then
        return popup_err
      end
    end

    -- Validate proper layering order
    if config.zindex.base and config.zindex.backdrop and config.zindex.base >= config.zindex.backdrop then
      return "zindex.base must be less than zindex.backdrop"
    end

    if config.zindex.backdrop and config.zindex.popup and config.zindex.backdrop >= config.zindex.popup then
      return "zindex.backdrop must be less than zindex.popup"
    end
  end

  if config.resize_debounce ~= nil then
    local err =
      validators.should_be_positive_number(config.resize_debounce, "resize_debounce must be a positive number")
    if err then
      return err
    end

    -- Validate reasonable bounds (20-50ms recommended)
    if config.resize_debounce < 10 then
      return "resize_debounce must be at least 10ms"
    end

    if config.resize_debounce > 200 then
      return "resize_debounce must be at most 200ms"
    end
  end

  if config.plugins_folder ~= nil then
    local err = validators.should_be_string(config.plugins_folder, "plugins_folder must be a string")
    if err then
      return err
    end

    -- Must be an absolute path or start with ~
    if not (config.plugins_folder:match("^/") or config.plugins_folder:match("^~")) then
      return "plugins_folder must be an absolute path (start with / or ~)"
    end

    -- Expand and check if parent directory exists
    local expanded_path = vim.fn.expand(config.plugins_folder)
    local parent_dir = vim.fn.fnamemodify(expanded_path, ":h")
    if vim.fn.isdirectory(parent_dir) == 0 then
      return "plugins_folder parent directory does not exist: " .. parent_dir
    end
  end

  return nil
end

---Setup the configuration with user-provided options
---@param user_config? UserConfig User configuration to merge with defaults
---@return string|nil error Error message if setup failed, nil if successful
function M.setup(user_config)
  local merged_config = vim.tbl_deep_extend("force", vim.deepcopy(DEFAULT_USER_CONFIG), user_config or {})

  local error_msg = validate_config(merged_config)
  if error_msg then
    return "Store.nvim configuration error: " .. error_msg
  end

  local computed_layout, layout_error = calculate_complete_layout(merged_config)
  if layout_error then
    return "Store.nvim layout calculation error: " .. layout_error
  end

  plugin_config = vim.tbl_deep_extend("force", merged_config, {
    layout = computed_layout,
  })

  return nil
end

---@return PluginConfig config The complete plugin configuration with computed layout
function M.get()
  if not plugin_config then
    M.setup({})
  end
  return plugin_config
end

---Update layout with new proportions and return computed layout
---@param proportions {list: number, preview: number} New proportions to use for layout
---@return StoreModalLayout|nil layout New layout if calculation succeeded, nil if failed
---@return string|nil error Error message if calculation failed
function M.update_layout(proportions)
  local config = M.get()

  -- Create config with new proportions for layout calculation
  local config_with_new_proportions = vim.tbl_deep_extend("force", config, {
    proportions = proportions,
  })

  -- Calculate complete layout with new proportions
  local new_layout, layout_error = calculate_complete_layout(config_with_new_proportions)

  if layout_error ~= nil then
    return nil, layout_error
  end

  plugin_config.proportions = proportions
  plugin_config.layout = new_layout
  return new_layout, nil
end

return M
