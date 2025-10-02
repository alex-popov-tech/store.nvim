---@class Repository
---@field source string Repository source (e.g., "github")
---@field author string Repository author/owner
---@field name string Repository name
---@field full_name string Repository full name (author/name)
---@field url string Repository URL
---@field description string Repository description
---@field tags string[] Array of topic tags
---@field stars number Number of stars
---@field issues number Number of open issues
---@field created_at string Creation timestamp (ISO format)
---@field updated_at string Last update timestamp (ISO format)
---@field pretty {stars: string, issues: string, created_at: string, updated_at: string} Formatted display values
---@field readme? string README reference in the form "branch/path"

---@class Meta
---@field created_at number Unix timestamp of database creation

---@class Database
---@field meta Meta Metadata about the dataset
---@field items Repository[] Array of repository objects

---@class RepositoryField
---@field content string Display content for this field
---@field limit number Maximum display width for this field

---@alias RepositoryRenderer fun(repo: Repository, isInstalled: boolean): RepositoryField[]
