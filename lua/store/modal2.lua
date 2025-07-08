local http = require("store.http")
local validators = require("store.validators")
local utils = require("store.utils")
local heading_window = require("store.ui.heading_window")
local list_window = require("store.ui.list_window")
local preview_window = require("store.ui.preview_window")

local M = {}

-- Internal UI configuration (zindex, border, etc.)
local UI_CONFIG = {
  border = "rounded",
  zindex = 50,
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

    -- Note: proportions validation is handled in config.lua
  end

  return nil
end

-- Modal2 class - stateful orchestrator for UI components
local Modal2 = {}
Modal2.__index = Modal2

---Create a new modal instance
---@param config table Modal configuration with width/height/proportions (from config.lua)
---@return table Modal2 instance
function M.new(config)
  if not config then
    error("Configuration required. Modal2 expects config from config.lua")
  end

  -- Validate configuration first
  local error_msg = validate(config)
  if error_msg then
    error("Modal configuration validation failed: " .. error_msg)
  end

  -- Initialize list component with calculated config.computed_layout
  local instance = {
    config = config,
    layout = config.computed_layout,
    is_open = false,
    state = {
      filter_query = "",
      repos = {},
      filtered_repos = {},
      current_focus = "list", -- Track current focused component: "list" or "preview"
      current_repository = nil, -- Track currently selected repository
    },

    -- UI component instances (ready for rendering)
    heading = heading_window.new({
      width = config.computed_layout.header.width,
      height = config.computed_layout.header.height,
      row = config.computed_layout.header.row,
      col = config.computed_layout.header.col,
      border = UI_CONFIG.border,
      zindex = UI_CONFIG.zindex,
    }),

    preview = preview_window.new({
      width = config.computed_layout.preview.width,
      height = config.computed_layout.preview.height,
      row = config.computed_layout.preview.row,
      col = config.computed_layout.preview.col,
      border = UI_CONFIG.border,
      zindex = UI_CONFIG.zindex,
      keymap = {}, -- Will be populated below
    }),

    list = list_window.new({
      width = config.computed_layout.list.width,
      height = config.computed_layout.list.height,
      row = config.computed_layout.list.row,
      col = config.computed_layout.list.col,
      border = UI_CONFIG.border,
      zindex = UI_CONFIG.zindex,
      keymap = {}, -- Will be populated below
      cursor_debounce_delay = config.preview_debounce,
    }),
  }

  -- Create modal keymaps with access to instance
  local modal_keymaps = {
    [config.keybindings.close] = function()
      instance:close()
    end,
    ["<esc>"] = function()
      instance:close()
    end,
    [config.keybindings.switch_focus] = function()
      if instance.state.current_focus == "list" then
        instance.preview:focus()
        instance.state.current_focus = "preview"
      else
        -- Save cursor position when switching away from preview
        instance.preview:save_cursor_on_blur()
        instance.list:focus()
        instance.state.current_focus = "list"
      end
    end,
    [config.keybindings.filter] = function()
      vim.ui.input({ prompt = "Filter repositories: ", default = instance.state.filter_query }, function(input)
        if input ~= nil then
          -- Update filter query in state
          instance.state.filter_query = input

          -- Filter repositories based on query (case-insensitive)
          if input == "" then
            instance.state.filtered_repos = instance.state.repos
          else
            local query_lower = input:lower()
            instance.state.filtered_repos = {}
            for _, repo in ipairs(instance.state.repos) do
              if
                repo.full_name:lower():find(query_lower)
                or (repo.description and repo.description:lower():find(query_lower))
              then
                table.insert(instance.state.filtered_repos, repo)
              end
            end
          end

          -- Update heading with new filter stats
          instance.heading:render({
            query = instance.state.filter_query,
            state = "ready",
            filtered_count = #instance.state.filtered_repos,
            total_count = #instance.state.repos,
          })

          -- Re-render list with filtered results
          instance.list:render({
            state = "ready",
            repositories = instance.state.filtered_repos,
          })
        end
      end)
    end,
    [config.keybindings.help] = function()
      local help_modal = require("store.ui.help_modal")
      help_modal.open()
    end,
    [config.keybindings.open] = function()
      if instance.state.current_repository and instance.state.current_repository.html_url then
        local success = utils.open_url(instance.state.current_repository.html_url)
        if not success then
          config.log.error("Failed to open URL: " .. instance.state.current_repository.html_url)
        else
          config.log.debug("Opened repository URL: " .. instance.state.current_repository.html_url)
        end
      else
        config.log.warn("No repository selected")
      end
    end,
  }

  -- Update component configs with keymaps
  instance.list.config.keymap = modal_keymaps
  instance.list.config.on_repo = function(repository)
    -- Track current repository for keybinding handlers
    instance.state.current_repository = repository
    
    http.get_readme(repository.full_name, function(data)
      if data.error then
        config.log.error("Error fetching README for " .. repository.full_name .. ": " .. data.error)
      end
      -- Pass repository.full_name as identifier for cursor position tracking
      instance.preview:render(data.body, repository.full_name)
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

  -- Save cursor position before closing
  if self.preview then
    self.preview:save_cursor_on_blur()
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
