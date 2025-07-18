local M = {}

-- Layout constants
local MIN_MODAL_WIDTH = 85
local MIN_MODAL_HEIGHT = 18
local HEADER_HEIGHT = 6
local GAP_BETWEEN_WINDOWS = 2

---Open a URL in the default browser (cross-platform)
---@param url string URL to open
function M.open_url(url)
  local logger = require("store.logger")

  if not url or type(url) ~= "string" then
    logger.error("Invalid URL: must be a non-empty string")
    return
  end

  -- Validate URL format for security
  if not url:match("^https?://[%w%-%.%_%~%:/%?%#%[%]%@%!%$%&%'%(%)%*%+%,%;%=]+$") then
    logger.error("Invalid URL format: " .. url)
    return
  end

  -- Use vim.ui.open for cross-platform URL opening (Neovim 0.10+)
  if vim.ui.open then
    vim.ui.open(url)
  else
    logger.error("vim.ui.open not available - please update to Neovim 0.10+")
  end
end

---@class FilterCriterion
---@field field string Field name to filter on
---@field value string Value to match against
---@field matcher fun(repo: Repository): boolean Function to test repository against criterion

---Validate if a field name is supported for filtering
---@param field string Field name to validate
---@return boolean True if field is supported
local function is_valid_field(field)
  local valid_fields = {
    full_name = true,
    author = true,
    name = true,
    description = true,
    tags = true,
    homepage = true,
  }
  return valid_fields[field] == true
end

---Create a matcher function for a specific field and value
---@param field string Field name to match against (already validated)
---@param value string Value to search for (already validated)
---@return fun(repo: Repository): boolean Matcher function
local function create_field_matcher(field, value)
  local value_lower = value:lower()

  if field == "full_name" then
    return function(repo)
      return repo.full_name:lower():find(value_lower, 1, true) ~= nil
    end
  end

  if field == "author" then
    return function(repo)
      return repo.author:lower():find(value_lower, 1, true) ~= nil
    end
  end

  if field == "name" then
    return function(repo)
      return repo.name:lower():find(value_lower, 1, true) ~= nil
    end
  end

  if field == "description" then
    return function(repo)
      if not repo.description then
        return false
      end
      return repo.description:lower():find(value_lower, 1, true) ~= nil
    end
  end

  if field == "tags" then
    return function(repo)
      if not repo.tags or #repo.tags == 0 then
        return false
      end

      local search_tags = vim.split(value, ",", { plain = true })

      for _, search_tag in ipairs(search_tags) do
        local search_tag_lower = vim.trim(search_tag):lower()
        if search_tag_lower == "" then
          goto continue
        end

        for _, repo_tag in ipairs(repo.tags) do
          if repo_tag:lower():find(search_tag_lower, 1, true) then
            return true
          end
        end

        ::continue::
      end
      return false
    end
  end

  if field == "homepage" then
    return function(repo)
      if not repo.homepage then
        return false
      end
      return repo.homepage:lower():find(value_lower, 1, true) ~= nil
    end
  end

  -- This should never happen due to validation, but added for safety
  error("Invalid field passed to create_field_matcher: " .. field)
end

---Parse a complex query string into structured filter criteria
---@param query_string string Query in format "foo;author:bar;tags:one,two,three;description:text"
---@return FilterCriterion[] Array of filter criteria
---@return string|nil Error message if parsing failed
local function parse_query(query_string)
  local criteria = {}

  if not query_string or query_string == "" then
    return criteria, nil
  end

  if type(query_string) ~= "string" then
    return {}, "Query must be a string"
  end

  local parts = vim.split(query_string, ";", { plain = true })

  for _, part in ipairs(parts) do
    local trimmed = vim.trim(part)
    if trimmed == "" then
      goto continue
    end

    local colon_pos = trimmed:find(":")

    if colon_pos then
      local field = vim.trim(trimmed:sub(1, colon_pos - 1)):lower()
      local value = vim.trim(trimmed:sub(colon_pos + 1))

      if field == "" then
        return {}, "Empty field name in query: '" .. part .. "'"
      end

      if value == "" then
        return {}, "Empty value for field '" .. field .. "' in query: '" .. part .. "'"
      end

      if not is_valid_field(field) then
        return {}, "Unknown field '" .. field .. "'. Valid fields: full_name, author, name, description, tags, homepage"
      end

      table.insert(criteria, {
        field = field,
        value = value,
        matcher = create_field_matcher(field, value),
      })
    else
      table.insert(criteria, {
        field = "full_name",
        value = trimmed,
        matcher = create_field_matcher("full_name", trimmed),
      })
    end

    ::continue::
  end

  return criteria, nil
end

---Create an advanced filter predicate function from a query string
---@param query_string string Query in format "foo;author:bar;tags:one,two,three;description:text"
---@return fun(repo: Repository): boolean|nil Predicate function that returns true if repository matches all criteria, nil if error
---@return string|nil Error message if parsing failed
function M.create_advanced_filter(query_string)
  local criteria, error_msg = parse_query(query_string)

  if error_msg then
    return nil, error_msg
  end

  if #criteria == 0 then
    return function(repo)
      return true
    end, nil
  end

  return function(repo)
    for _, criterion in ipairs(criteria) do
      if not criterion.matcher(repo) then
        return false
      end
    end
    return true
  end,
    nil
end

-- Function to strip HTML tags from markdown content while preserving markdown syntax
-- This function is only called when HTML tags are detected in the content
---@param content string The content to strip HTML tags from (guaranteed to contain HTML)
---@return string The content with HTML tags removed
function M.strip_html_tags(content)
  -- Don't process lines that are clearly markdown and should be preserved
  -- Skip code blocks (lines starting with ```)
  if content:match("^```") then
    return content
  end

  -- Skip markdown link syntax [text](url) at start of line
  if content:match("^%s*%[[^%]]*%]%(.-%)") then
    return content
  end

  -- Skip lines that are just ASCII art or similar (contain lots of special chars)
  -- But not if they contain HTML tags (< and >)
  local special_char_count = 0
  local total_chars = #content
  for char in content:gmatch("[^%w%s]") do
    special_char_count = special_char_count + 1
  end
  if total_chars > 0 and (special_char_count / total_chars) > 0.4 and not content:match("[<>]") then
    return content
  end

  -- Remove HTML tags while preserving the content inside them
  local cleaned = content:gsub("<%s*[^>]*>", "")

  -- Clean up extra whitespace that might be left behind
  cleaned = cleaned:gsub("%s+", " ")
  return vim.trim(cleaned)
end

---Calculate window dimensions and positions for 3-window layout
---@param layout_config {width: number, height: number, proportions: {list: number, preview: number}}
---@return StoreModalLayout|nil layout Layout calculations for all windows, nil if validation fails
---@return string|nil error Error message if validation fails
function M.calculate_layout(layout_config)
  -- Validate input config
  if not layout_config then
    return nil, "Layout config is required"
  end

  if not layout_config.width or not layout_config.height then
    return nil, "Layout config must have width and height"
  end

  if not layout_config.proportions or not layout_config.proportions.list or not layout_config.proportions.preview then
    return nil, "Layout config must have proportions with list and preview"
  end

  local screen_width = vim.o.columns
  local screen_height = vim.o.lines

  -- Validate screen dimensions
  if screen_width <= 0 or screen_height <= 0 then
    return nil, "Invalid screen dimensions"
  end

  -- Convert percentages to absolute values
  local total_width = math.floor(screen_width * layout_config.width)
  local total_height = math.floor(screen_height * layout_config.height)

  -- Validate minimum dimensions using constants
  if total_width < MIN_MODAL_WIDTH or total_height < MIN_MODAL_HEIGHT then
    return nil, string.format("Modal dimensions too small (minimum: %dx%d)", MIN_MODAL_WIDTH, MIN_MODAL_HEIGHT)
  end

  -- Calculate positioning to center the modal
  local start_row = math.floor((screen_height - total_height) / 2)
  local start_col = math.floor((screen_width - total_width) / 2)

  -- Layout dimensions
  local content_height = total_height - HEADER_HEIGHT - GAP_BETWEEN_WINDOWS

  -- Validate content area
  if content_height <= 0 then
    return nil, "Content height too small after header and gaps"
  end

  -- Use proportions from config
  local proportions = layout_config.proportions

  -- Window splits using proportions
  local list_width = math.floor(total_width * proportions.list)
  -- Subtract gap to align with header
  local preview_width = math.floor(total_width * proportions.preview) - 2

  -- Validate calculated widths
  if list_width <= 0 or preview_width <= 0 then
    return nil, "Calculated window widths are invalid"
  end

  local layout = {
    total_width = total_width,
    total_height = total_height,
    start_row = start_row,
    start_col = start_col,
    header_height = HEADER_HEIGHT,
    gap_between_windows = GAP_BETWEEN_WINDOWS,

    -- Header window (full width at top)
    header = {
      width = total_width,
      height = HEADER_HEIGHT,
      row = start_row,
      col = start_col,
    },

    -- List window (left side, below header)
    list = {
      width = list_width,
      height = content_height,
      row = start_row + HEADER_HEIGHT + GAP_BETWEEN_WINDOWS,
      col = start_col,
    },

    -- Preview window (right side, below header)
    preview = {
      width = preview_width,
      height = content_height,
      row = start_row + HEADER_HEIGHT + GAP_BETWEEN_WINDOWS,
      col = start_col + list_width + 3, -- +3 for prettier gap
    },
  }

  return layout, nil
end

---Create a scratch buffer with standard options for UI components
---@param opts? {filetype?: string, buftype?: string, name?: string} Optional buffer configuration
---@return number Buffer ID
function M.create_scratch_buffer(opts)
  opts = opts or {}
  local buf_id = vim.api.nvim_create_buf(false, true)

  local buf_opts = {
    modifiable = false,
    swapfile = false,
    buftype = opts.buftype or "nofile",
    bufhidden = "wipe",
    buflisted = false,
    filetype = opts.filetype or "text",
    undolevels = -1,
  }

  for option, value in pairs(buf_opts) do
    vim.api.nvim_set_option_value(option, value, { buf = buf_id })
  end

  if opts.name then
    vim.api.nvim_buf_set_name(buf_id, opts.name)
  end

  return buf_id
end

---Create a floating window with standard configuration
---@param params {buf_id: number, config: table, opts: table} Window creation parameters
---@param params.buf_id number Buffer ID for the window
---@param params.config table Window configuration (width, height, row, col, focusable)
---@param params.opts table Window options to set with nvim_set_option_value
---@return number|nil win_id Window ID on success, nil on error
---@return string|nil error_message Error message on failure, nil on success
function M.create_floating_window(params)
  local logger = require("store.logger")

  if not params or type(params) ~= "table" then
    return nil, "Parameters must be a table"
  end

  if not params.buf_id or not vim.api.nvim_buf_is_valid(params.buf_id) then
    return nil, "buf_id must be a valid buffer ID"
  end

  if not params.config or type(params.config) ~= "table" then
    return nil, "config must be a table"
  end

  if not params.opts or type(params.opts) ~= "table" then
    return nil, "opts must be a table"
  end

  local config = params.config

  -- Build window configuration with standard values
  local win_config = {
    relative = "editor",
    style = "minimal",
    width = config.width,
    height = config.height,
    row = config.row,
    col = config.col,
    border = "rounded",
    zindex = 50,
    focusable = config.focusable,
  }

  -- Create the window
  local win_id = vim.api.nvim_open_win(params.buf_id, false, win_config)
  if not win_id then
    return nil, "Failed to create window"
  end

  -- Common window options shared across UI components
  local common_opts = {
    number = false,
    relativenumber = false,
    signcolumn = "no",
    foldcolumn = "0",
    colorcolumn = "",
  }

  -- Merge common options with component-specific options
  local final_opts = vim.tbl_deep_extend("force", common_opts, params.opts)

  -- Set window options
  for option, value in pairs(final_opts) do
    local success, err = pcall(vim.api.nvim_set_option_value, option, value, { win = win_id })
    if not success then
      logger.warn(string.format("Failed to set window option %s: %s", option, err))
    end
  end

  return win_id, nil
end

---Set lines in a buffer, handling modifiable state automatically
---@param buf_id number Buffer ID
---@param lines string[] Lines to set in the buffer
function M.set_lines(buf_id, lines)
  vim.api.nvim_set_option_value("modifiable", true, { buf = buf_id })
  vim.api.nvim_buf_set_lines(buf_id, 0, -1, false, lines)
  vim.api.nvim_set_option_value("modifiable", false, { buf = buf_id })
end

return M
