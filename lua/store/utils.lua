local M = {}

---Create a formatted line with left and right content, properly spaced and padded
---@param width number Total width of the line
---@param left string|nil Left-aligned content
---@param right string|nil Right-aligned content
---@return string Formatted line with proper spacing and 1 column right padding
function M.format_line(width, left, right)
  left = left or ""
  right = right or ""

  -- Reserve 1 column for right padding
  local right_padding = 1
  local usable_width = width - right_padding

  -- If both left and right content fit with at least 1 space between
  local min_spacing = 1
  local available_space = usable_width - #left - #right - min_spacing

  if available_space >= 0 then
    -- Normal case: both fit with proper spacing
    local spacing = min_spacing + available_space
    return left .. string.rep(" ", spacing) .. right .. string.rep(" ", right_padding)
  else
    -- Content is too long for the width, truncate right content
    local max_right_length = usable_width - #left - min_spacing
    if max_right_length > 0 then
      local truncated_right = string.sub(right, 1, max_right_length - 3) .. "..."
      return left .. string.rep(" ", min_spacing) .. truncated_right .. string.rep(" ", right_padding)
    else
      -- Even left content is too long, just return left content truncated
      return string.sub(left, 1, usable_width) .. string.rep(" ", right_padding)
    end
  end
end

---Create a formatted line with left and right content, prioritizing right content visibility
---@param width number Total width of the line
---@param left string|nil Left-aligned content
---@param right string|nil Right-aligned content
---@return string Formatted line with proper spacing, truncating left content if necessary
function M.format_line_priority_right(width, left, right)
  left = left or ""
  right = right or ""

  -- Use display width instead of character count for Unicode characters
  local left_width = vim.fn.strdisplaywidth(left)
  local right_width = vim.fn.strdisplaywidth(right)

  -- If right content is longer than the width, just return right content truncated
  if right_width >= width then
    -- Truncate by characters until display width fits
    local truncated = right
    while vim.fn.strdisplaywidth(truncated) > width and #truncated > 0 do
      truncated = string.sub(truncated, 1, #truncated - 1)
    end
    return truncated
  end

  -- If both left and right content fit with at least 1 space between
  local min_spacing = 1
  local available_space = width - left_width - right_width - min_spacing

  if available_space >= 0 then
    -- Normal case: both fit with proper spacing
    local spacing = min_spacing + available_space
    return left .. string.rep(" ", spacing) .. right
  else
    -- Content is too long for the width, truncate left content to prioritize right
    local max_left_width = width - right_width - min_spacing
    if max_left_width > 3 then
      -- Truncate left content with ellipsis
      local truncated_left = left
      -- Keep truncating until the content + ellipsis fits in the available space
      while vim.fn.strdisplaywidth(truncated_left) + 3 > max_left_width and #truncated_left > 0 do
        truncated_left = string.sub(truncated_left, 1, #truncated_left - 1)
      end
      truncated_left = truncated_left .. "..."
      return truncated_left .. string.rep(" ", min_spacing) .. right
    else
      -- Not enough space for meaningful left content, just show right
      return string.rep(" ", width - right_width) .. right
    end
  end
end

---Format a number with appropriate suffix (1.2k, 3.4M) with 1 decimal precision
---@param num number Number to format
---@return string Formatted number with suffix
function M.format_number(num)
  if type(num) ~= "number" then
    return "0"
  end

  if num < 1000 then
    return tostring(num)
  elseif num < 1000000 then
    local formatted = num / 1000
    return string.format("%.1fk", formatted)
  elseif num < 1000000000 then
    local formatted = num / 1000000
    return string.format("%.1fM", formatted)
  else
    local formatted = num / 1000000000
    return string.format("%.1fB", formatted)
  end
end

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

---Format tags with bubble-style highlighting and apply highlights directly
---@param tags string[] Array of tag strings
---@param buf_id number Buffer ID
---@param ns_id number Namespace ID for highlights
---@param line_num number Line number (0-indexed)
---@param start_col number Starting column position for tags
---@return string formatted_text The formatted text with bubble characters
---@return number end_col The ending column position after all tags
function M.format_and_highlight_bubble_tags(tags, buf_id, ns_id, line_num, start_col)
  if not tags or #tags == 0 then
    return "", start_col
  end

  local text_parts = {}
  local current_col = start_col

  for i, tag in ipairs(tags) do
    local left_border = "▌"
    local right_border = "▐"
    local tag_with_borders = left_border .. tag .. right_border

    -- Add to text parts
    table.insert(text_parts, tag_with_borders)

    -- Apply highlights immediately
    -- Left border
    vim.api.nvim_buf_set_extmark(buf_id, ns_id, line_num, current_col, {
      end_col = current_col + vim.fn.strdisplaywidth(left_border),
      hl_group = "StoreTagBorder",
    })
    current_col = current_col + vim.fn.strdisplaywidth(left_border)

    -- Tag text
    vim.api.nvim_buf_set_extmark(buf_id, ns_id, line_num, current_col, {
      end_col = current_col + vim.fn.strdisplaywidth(tag),
      hl_group = "StoreTagText",
    })
    current_col = current_col + vim.fn.strdisplaywidth(tag)

    -- Right border
    vim.api.nvim_buf_set_extmark(buf_id, ns_id, line_num, current_col, {
      end_col = current_col + vim.fn.strdisplaywidth(right_border),
      hl_group = "StoreTagBorder",
    })
    current_col = current_col + vim.fn.strdisplaywidth(right_border)

    -- Add space between tags (except for last tag)
    if i < #tags then
      table.insert(text_parts, " ")
      current_col = current_col + 1
    end
  end

  return table.concat(text_parts, ""), current_col
end

---Format a list of string-length pairs into a table-like line with consistent column widths
---@param pairs table[] List of {string, number} pairs where string is content and number is column width
---@return string Formatted line with space-separated columns of fixed widths
function M.format_table_line(pairs)
  local logger = require("store.logger")

  if type(pairs) ~= "table" then
    logger.error("format_table_line: expected table, got " .. type(pairs))
    return ""
  end

  if #pairs == 0 then
    return ""
  end

  local columns = {}

  for i, pair in ipairs(pairs) do
    if type(pair) ~= "table" or #pair ~= 2 then
      logger.error("format_table_line: pair " .. i .. " is not a valid {string, number} pair")
      table.insert(columns, "")
    else
      local str, length = pair[1], pair[2]
      local formatted = M.pad_or_truncate(str, length)
      table.insert(columns, formatted)
    end
  end

  return table.concat(columns, " ")
end

---Pad or truncate a string to a fixed length with ellipsis
---@param str string String to process
---@param max_length number Maximum length of the result
---@return string Fixed-length string, either padded with spaces or truncated with ellipsis
function M.pad_or_truncate(str, max_length)
  local logger = require("store.logger")

  if type(str) ~= "string" then
    logger.error("pad_or_truncate: expected string, got " .. type(str))
    str = tostring(str or "")
  end

  if max_length <= 0 then
    return ""
  end

  local char_count = vim.fn.strchars(str)

  if char_count == max_length then
    return str
  end

  if char_count < max_length then
    local spaces_needed = max_length - char_count
    return str .. string.rep(" ", spaces_needed)
  end

  -- char_count > max_length, truncate and add ellipsis
  if max_length == 1 then
    return "…"
  end

  local truncated = vim.fn.strcharpart(str, 0, max_length - 1)
  return truncated .. "…"
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

return M
