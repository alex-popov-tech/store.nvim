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

return M