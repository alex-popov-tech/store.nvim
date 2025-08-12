local utils = require("store.utils")
local Path = require("store.plenary.path")

---@module "store.database.utils"
---Utility functions for database operations, README processing, and cache operations

local M = {}

---Get the cache directory path
---@return Path cache_dir The cache directory path object
function M.get_cache_dir()
  return Path:new(vim.fn.stdpath("cache"), "store.nvim")
end

---Generate README cache key/filename from repository full_name
---@param full_name string Repository full_name (e.g., "owner/repo")
---@return string key The cache key/filename for the README
function M.repository_to_readme_key(full_name)
  return full_name:gsub("/", "-") .. ".md"
end


-- Process README content in a single pass: clean HTML tags, filter images, and collapse empty lines
---@param content string Raw README content as string
---@return string[] Processed lines with HTML tags removed, images filtered, and empty lines collapsed
function M.process_readme_content(content)
  local lines = vim.split(content, "\n", { plain = true })
  local processed = {}
  local count = 0
  local prev_was_empty = false
  local in_code_block = false

  for i = 1, #lines do
    local line = lines[i]

    -- Check for fenced code block markers (```)
    local code_fence_match = line:match("^%s*```")
    if code_fence_match then
      in_code_block = not in_code_block
      -- Process the fence line normally (trim it)
      local trimmed_line = line:match("^%s*(.-)%s*$")
      count = count + 1
      processed[count] = trimmed_line
      prev_was_empty = false
    elseif in_code_block then
      -- Inside code block - preserve original whitespace
      count = count + 1
      processed[count] = line
      prev_was_empty = false
    else
      -- Outside code block - apply normal processing
      -- OPTIMIZATION: Early empty line detection - trim both leading and trailing whitespace
      local trimmed_line = line:match("^%s*(.-)%s*$")
      if trimmed_line == "" then
        -- Skip expensive processing for empty lines - go directly to step 3
        if not prev_was_empty then
          count = count + 1
          processed[count] = ""
        end
        prev_was_empty = true
      elseif trimmed_line:match("^!%[[^%]]*%]%(.-%)$") then
        -- OPTIMIZATION: Early image detection (before HTML processing) - skip images
        -- Treat skipped images as empty content for empty line collapsing
        if not prev_was_empty then
          count = count + 1
          processed[count] = ""
        end
        prev_was_empty = true
      else
        -- OPTIMIZATION: Conditional HTML tag processing - check for '<' first (cheaper)
        if trimmed_line:find("<", 1, true) then
          if trimmed_line:find("<%s*[^>]*>") then
            trimmed_line = utils.strip_html_tags(trimmed_line)
          end
        end

        -- Check if after processing, the line became empty
        if trimmed_line == "" then
          -- Treat processed-to-empty lines like empty lines for collapsing
          if not prev_was_empty then
            count = count + 1
            processed[count] = ""
          end
          prev_was_empty = true
        else
          -- Step 3: Add non-empty line to processed output
          count = count + 1
          processed[count] = trimmed_line
          prev_was_empty = false
        end
      end
    end
  end

  return processed
end

return M
