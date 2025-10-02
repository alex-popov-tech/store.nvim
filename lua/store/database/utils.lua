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

---Resolve README branch/path reference into components
---@param readme string|nil README reference in form "branch/path"
---@return string branch
---@return string filepath
function M.parse_readme_reference(readme)
  if type(readme) == "string" and readme ~= "" then
    local branch, path = readme:match("^([^/]+)/(.+)$")
    if branch and path then
      return branch, path
    end
  end

  -- Fall back to HEAD/README.md when metadata is missing or malformed
  return "HEAD", "README.md"
end

---Build GitHub raw URL for README based on repository metadata
---@param full_name string Repository full name
---@param readme string|nil README reference (branch/path)
---@return string url Fully qualified raw README URL
function M.build_github_readme_url(full_name, readme)
  local branch, path = M.parse_readme_reference(readme)
  return string.format("https://raw.githubusercontent.com/%s/%s/%s", full_name, branch, path)
end

---Build GitLab raw URL for README based on repository metadata
---@param full_name string Repository full name
---@param readme string|nil README reference (branch/path)
---@return string url Fully qualified raw README URL
function M.build_gitlab_readme_url(full_name, readme)
  local branch, path = M.parse_readme_reference(readme)
  return string.format("https://gitlab.com/%s/-/raw/%s/%s?ref_type=heads", full_name, branch, path)
end

-- Process README content optimally: clean HTML tags, filter images, and collapse empty lines
---@param content string Raw README content as string
---@return string[] Processed lines with HTML tags removed, images filtered, and empty lines collapsed
function M.process_readme_content(content)
  -- Single regex pass for image removal (combined patterns for better performance)
  content = content:gsub("<%s*[Ii][Mm][Gg][^>]*/?%s*>", "")

  local lines = vim.split(content, "\n", { plain = true })
  local result = {}
  local result_count = 0
  local in_code_block = false
  local prev_was_empty = false

  -- Pre-compile pattern to avoid recompilation in loop
  local code_fence_pattern = "^%s*```"

  for i = 1, #lines do
    local line = lines[i]

    -- Check for fenced code block markers (```)
    if line:match(code_fence_pattern) then
      in_code_block = not in_code_block
      -- Single gsub operation for trim
      local trimmed = line:gsub("^%s*(.-)%s*$", "%1")
      result_count = result_count + 1
      result[result_count] = trimmed
      prev_was_empty = false
    elseif in_code_block then
      -- Inside code block - preserve original whitespace
      result_count = result_count + 1
      result[result_count] = line
      prev_was_empty = false
    else
      -- Outside code block - apply normal processing
      -- Single trim operation
      local trimmed = line:gsub("^%s*(.-)%s*$", "%1")

      if trimmed == "" then
        -- Handle empty lines with collapsing
        if not prev_was_empty then
          result_count = result_count + 1
          result[result_count] = ""
        end
        prev_was_empty = true
      else
        -- Optimized HTML detection: check for '<' first (cheaper operation)
        if trimmed:find("<", 1, true) then
          -- Only run expensive regex if '<' is found
          if trimmed:match("<%s*[^>]*>") then
            trimmed = utils.strip_html_tags(trimmed)
            -- Re-check if empty after HTML removal
            if trimmed == "" then
              if not prev_was_empty then
                result_count = result_count + 1
                result[result_count] = ""
              end
              prev_was_empty = true
            else
              result_count = result_count + 1
              result[result_count] = trimmed
              prev_was_empty = false
            end
          else
            result_count = result_count + 1
            result[result_count] = trimmed
            prev_was_empty = false
          end
        else
          result_count = result_count + 1
          result[result_count] = trimmed
          prev_was_empty = false
        end
      end
    end
  end

  -- Strip leading empty lines
  local start_idx = 1
  while start_idx <= result_count and result[start_idx] == "" do
    start_idx = start_idx + 1
  end

  if start_idx > result_count then
    -- All lines were empty
    return {}
  end

  -- Create final result array
  local final_result = {}
  for i = start_idx, result_count do
    final_result[i - start_idx + 1] = result[i]
  end

  return final_result
end

return M
