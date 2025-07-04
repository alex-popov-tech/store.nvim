local http = require("store.http")
local validators = require("store.validators")
local heading_window = require("store.ui.heading_window")
local list_window = require("store.ui.list_window")
local preview_window = require("store.ui.preview_window")

local M = {}

-- Default modal configuration
local DEFAULT_CONFIG = {
  width = 0.6, -- Percentage of screen width
  height = 0.8, -- Percentage of screen height
  proportions = {
    list = 0.3, -- 30% for list window
    preview = 0.7, -- 70% for preview window
  },
}

-- Validate modal configuration
local function validate(config)
  if config == nil then
    return nil
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

    -- Validate proportions sum to 1
    local list_prop = config.proportions.list or DEFAULT_CONFIG.proportions.list
    local preview_prop = config.proportions.preview or DEFAULT_CONFIG.proportions.preview
    if math.abs((list_prop + preview_prop) - 1.0) > 0.001 then
      return "modal.proportions.list + modal.proportions.preview must equal 1.0"
    end
  end

  return nil
end

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

-- Modal2 class - stateful orchestrator for UI components
local Modal2 = {}
Modal2.__index = Modal2

---Create a new modal instance
---@param config table|nil Modal configuration with width/height/proportions
---@return table Modal2 instance
function M.new(config)
  -- Validate configuration first
  local error_msg = validate(config)
  if error_msg then
    error("Modal configuration validation failed: " .. error_msg)
  end

  -- Merge with defaults
  local merged_config = vim.tbl_deep_extend("force", DEFAULT_CONFIG, config or {})

  -- Calculate layout with final config
  local layout = calculate_layout(merged_config)

  -- Initialize list component with calculated layout
  local instance = {
    config = merged_config,
    layout = layout,
    is_open = false,
    state = {
      filter_query = "",
      repos = {},
      filtered_repos = {},
      current_focus = "list", -- Track current focused component: "list" or "preview"
    },

    -- UI component instances (ready for rendering)
    heading = heading_window.new({
      width = layout.header.width,
      height = layout.header.height,
      row = layout.header.row,
      col = layout.header.col,
      border = "rounded",
      zindex = 50,
    }),

    preview = preview_window.new({
      width = layout.preview.width,
      height = layout.preview.height,
      row = layout.preview.row,
      col = layout.preview.col,
      border = "rounded",
      zindex = 50,
      keymap = {}, -- Will be populated below
    }),

    list = list_window.new({
      width = layout.list.width,
      height = layout.list.height,
      row = layout.list.row,
      col = layout.list.col,
      border = "rounded",
      zindex = 50,
      keymap = {}, -- Will be populated below
    }),
  }

  -- Create modal keymaps with access to instance
  local modal_keymaps = {
    ["q"] = function()
      instance:close()
    end,
    ["<Tab>"] = function()
      if instance.state.current_focus == "list" then
        instance.preview:focus()
        instance.state.current_focus = "preview"
      else
        instance.list:focus()
        instance.state.current_focus = "list"
      end
    end,
  }

  -- Update component configs with keymaps
  instance.list.config.keymap = modal_keymaps
  instance.list.config.on_repo = function(repository)
    http.get_readme(repository.full_name, function(data)
      if data.error then
        print("Error fetching README:", data.error)
      end
      instance.preview:render(data.body)
    end)
  end
  instance.preview.config.keymap = modal_keymaps

  -- Re-create buffers with new keymaps
  instance.list.buf_id = instance.list:_create_buffer()
  instance.preview.buf_id = instance.preview:_create_buffer()

  setmetatable(instance, Modal2)
  return instance
end

---Open the modal and render all components
---@return boolean Success status
function Modal2:open()
  if self.is_open then
    return false
  end

  self.heading:open()
  self.list:open()
  self.preview:open()
  self.is_open = true

  -- Focus the list component by default
  self.list:focus()

  http.fetch_plugins(function(data, err)
    if err then
      error(err)
    end
    if not data then
      error("Failed to fetch plugin data")
    end

    -- Store repositories in modal state
    self.state.repos = data.repositories or {}
    self.state.filtered_repos = data.repositories or {}

    self.heading:render({
      query = "",
      state = "ready",
      filtered_count = data.total_repositories,
      total_count = data.total_repositories,
    })

    -- Render repositories in list component
    self.list:render({
      state = "ready",
      repositories = data.repositories or {},
    })
  end)

  return true
end

---Close the modal and all components
---@return boolean Success status
function Modal2:close()
  if not self.is_open then
    return false
  end

  -- Close all components
  if self.heading then
    self.heading:close()
  end

  if self.list then
    self.list:close()
  end

  if self.preview then
    self.preview:close()
  end

  self.is_open = false

  return true
end

return M
