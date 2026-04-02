local Path = require("store.plenary.path")

---@module "store.database.utils"
---Utility functions for database operations, README processing, and cache operations

local M = {}

-- Resolve paths once at load time (vim.env/vim.fn can't be called from libuv fast event callbacks)
local _cache_dir = Path:new(vim.fn.stdpath("cache"), "store.nvim")
local _tmp_cache_dir = Path:new((vim.env.TMPDIR or vim.env.TMP or vim.env.TEMP or "/tmp"), "store.nvim")

---Get the persistent cache directory path (for db.json, install catalogues)
---@return Path cache_dir The cache directory path object
function M.get_cache_dir()
  return _cache_dir
end

---Get the temporary cache directory path (for READMEs, docs — cleaned by OS on reboot)
---@return Path tmp_cache_dir The temp cache directory path object
function M.get_tmp_cache_dir()
  return _tmp_cache_dir
end

---Generate README cache key/filename from repository full_name
---@param full_name string Repository full_name (e.g., "owner/repo")
---@return string key The cache key/filename for the README
function M.repository_to_readme_key(full_name)
  return full_name:gsub("/", "-") .. ".md"
end

---Generate doc cache key/filename from repository full_name and doc_path
---@param full_name string Repository full_name (e.g., "owner/repo")
---@param doc_path? string Specific doc reference (e.g., "main/doc/help.txt")
---@return string key The cache key/filename for the doc
function M.repository_to_doc_key(full_name, doc_path)
  if not doc_path then
    return full_name:gsub("/", "-") .. ".txt"
  end
  return full_name:gsub("/", "-") .. "--" .. doc_path:gsub("/", "-") .. ".txt"
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

---Build worker URL for pre-processed README content
---@param base_url string Worker base URL (e.g., "https://store-nvim-readme.oleksandrp.com")
---@param source string Repository source ("github" or "gitlab")
---@param full_name string Repository full name (e.g., "owner/repo")
---@param readme string|nil README reference (branch/path)
---@return string url Fully qualified worker README URL
function M.build_worker_readme_url(base_url, source, full_name, readme)
  local branch, path = M.parse_readme_reference(readme)
  local owner, repo = full_name:match("^([^/]+)/(.+)$")
  return string.format("%s/readme/%s/%s/%s/%s/%s", base_url, source, owner, repo, branch, path)
end

---Build GitHub raw URL for doc file based on repository metadata
---@param full_name string Repository full name
---@param doc string|nil Doc reference (branch/path)
---@return string url Fully qualified raw doc URL
function M.build_github_doc_url(full_name, doc)
  local branch, path = M.parse_readme_reference(doc)
  return string.format("https://raw.githubusercontent.com/%s/%s/%s", full_name, branch, path)
end

---Build GitLab raw URL for doc file based on repository metadata
---@param full_name string Repository full name
---@param doc string|nil Doc reference (branch/path)
---@return string url Fully qualified raw doc URL
function M.build_gitlab_doc_url(full_name, doc)
  local branch, path = M.parse_readme_reference(doc)
  return string.format("https://gitlab.com/%s/-/raw/%s/%s?ref_type=heads", full_name, branch, path)
end

return M
