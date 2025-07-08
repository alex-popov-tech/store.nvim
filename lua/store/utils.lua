local M = {}

---Create a formatted line with left and right content, properly spaced and padded
---@param width number Total width of the line
---@param left string|nil Left-aligned content
---@param right string|nil Right-aligned content
---@return string Formatted line with proper spacing
function M.format_line(width, left, right)
  left = left or ""
  right = right or ""

  -- If both left and right content fit with at least 1 space between
  local min_spacing = 1
  local available_space = width - #left - #right - min_spacing

  if available_space >= 0 then
    -- Normal case: both fit with proper spacing
    local spacing = min_spacing + available_space
    return left .. string.rep(" ", spacing) .. right
  else
    -- Content is too long for the width, truncate right content
    local max_right_length = width - #left - min_spacing
    if max_right_length > 0 then
      local truncated_right = string.sub(right, 1, max_right_length - 3) .. "..."
      return left .. string.rep(" ", min_spacing) .. truncated_right
    else
      -- Even left content is too long, just return left content truncated
      return string.sub(left, 1, width)
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

---Open a URL in the default browser (cross-platform)
---@param url string URL to open
---@return boolean Success status
function M.open_url(url)
  if not url or type(url) ~= "string" then
    return false
  end

  local cmd
  if vim.fn.has("mac") == 1 then
    cmd = "open"
  elseif vim.fn.has("unix") == 1 then
    cmd = "xdg-open"
  elseif vim.fn.has("win32") == 1 then
    cmd = "start"
  else
    return false
  end

  local success = vim.fn.system(cmd .. " " .. vim.fn.shellescape(url))
  return vim.v.shell_error == 0
end

return M
