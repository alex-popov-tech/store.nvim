---@class Repository
---@field source string Repository source (e.g., "github")
---@field author string Repository author/owner
---@field name string Repository name
---@field full_name string Repository full name (author/name)
---@field url string Repository URL
---@field description string Repository description
---@field tags string[] Array of topic tags
---@field stars {curr: number, weekly: number, monthly: number} Star counts
---@field issues number Number of open issues
---@field created_at string Creation timestamp (ISO format)
---@field updated_at string Last update timestamp (ISO format)
---@field pretty {stars: string, issues: string, created_at: string, updated_at: string} Formatted display values
---@field readme? string README reference in the form "branch/path"
---@field doc? string[] Array of documentation references, each in "branch/path" form

---@class Meta
---@field created_at number Unix timestamp of database creation

---@class Database
---@field meta Meta Metadata about the dataset
---@field items Repository[] Array of repository objects

---@class RepositoryField
---@field content string Display content for this field
---@field limit number Maximum display width for this field

---@alias SortType "most_stars"|"rising_stars_monthly"|"rising_stars_weekly"|"recently_updated"|"recently_created"|"most_downloads_monthly"|"most_views_monthly"

---@class RendererOpts
---@field is_installed boolean Whether the repository is installed
---@field sort_type SortType The active sort type
---@field downloads number Monthly download count for this repo (0 if unavailable)
---@field views number Monthly view count for this repo (0 if unavailable)

---@alias RepositoryRenderer fun(repo: Repository, opts: RendererOpts): RepositoryField[]
