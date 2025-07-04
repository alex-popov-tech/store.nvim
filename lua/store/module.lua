local config = require("store.config")
local Modal = require("store.modal")
local http = require("store.http")
local help_modal = require("store.ui.help_modal")

local M = {}

local current_modal = nil
local current_config = nil

local ZINDEX = {
  BASE_MODAL = 45,
}

M.setup = function(args)
  current_config = config.build(args)
end

-- Helper function to get logger instance
local function get_log()
  return config.log
end

local function open_url_in_browser(url)
  local cmd
  local os_name = vim.loop.os_uname().sysname

  if os_name == "Darwin" then
    cmd = "open"
  elseif os_name == "Linux" then
    cmd = "xdg-open"
  elseif os_name == "Windows_NT" then
    cmd = "start"
  else
    return false
  end

  local full_command = string.format("%s '%s'", cmd, url)
  local result = vim.fn.system(full_command)
  local exit_code = vim.v.shell_error

  return exit_code == 0
end

-- Helper function to filter repositories by query (case-insensitive URL search)
local function filter_repositories(repositories, query)
  if not query or query == "" then
    return repositories
  end

  local filtered = {}
  local lower_query = string.lower(query)

  for _, repo in ipairs(repositories) do
    if repo.html_url and string.find(string.lower(repo.html_url), lower_query, 1, true) then
      table.insert(filtered, repo)
    end
  end

  return filtered
end

-- Helper function to generate modal content with filtering support
local function generate_modal_content(data, filter_query, modal_instance)
  local header_lines = {}
  local body_lines = {}

  if not data or not data.repositories then
    get_log().warn("No repository data found in response - data format may have changed")
    return {
      header = {
        "📦 Store.nvim - Plugin Browser",
        "Filter: | Found: 0/0 plugins",
        "Last updated: unknown",
        "Press '?' for help",
      },
      body = {
        "",
        "  ❌ No plugin data available",
        "",
        "  The data format may have changed.",
        "",
      },
    }
  end

  -- Filter repositories based on query
  local filtered_repos = filter_repositories(data.repositories, filter_query)
  local total_count = #data.repositories
  local filtered_count = #filtered_repos

  -- Generate header
  table.insert(header_lines, "📦 Store.nvim - Plugin Browser")
  local filter_display = filter_query and filter_query ~= "" and filter_query or ""
  table.insert(
    header_lines,
    "Filter: " .. filter_display .. " | Found: " .. filtered_count .. "/" .. total_count .. " plugins"
  )
  table.insert(header_lines, "Last updated: " .. (data.crawled_at or "unknown"))
  table.insert(header_lines, "Press '?' for help")

  for _, repo in ipairs(filtered_repos) do
    table.insert(body_lines, "  " .. repo.html_url)
  end
  table.insert(body_lines, "")

  return {
    header = header_lines,
    body = body_lines,
  }
end

-- Helper function to generate error content for modals
local function generate_error_content(title, error_message, modal_instance)
  return {
    header = {
      title or "📦 Store.nvim - Plugin Browser",
      "Filter: | Found: 0/0 plugins",
      "Last updated: error",
      "Press '?' for help",
    },
    body = {
      "",
      "  ❌ Error loading plugins:",
      "",
      "  " .. (error_message or "Unknown error"),
      "",
      "  Press 'r' to retry or 'q' to close",
      "",
    },
  }
end

local function update_modal_with_filter(modal_instance, data)
  if not data then
    return
  end

  local filter_query = modal_instance:get_filter_query()
  local content = generate_modal_content(data, filter_query, modal_instance)
  modal_instance:update_content(content)
end

local function get_repo_url_from_current_line(modal_instance)
  if not modal_instance.win_id or not vim.api.nvim_win_is_valid(modal_instance.win_id) then
    return nil
  end

  local cursor = vim.api.nvim_win_get_cursor(modal_instance.win_id)
  local line_num = cursor[1]
  local buf_id = modal_instance.buf_id

  if not vim.api.nvim_buf_is_valid(buf_id) then
    return nil
  end

  -- No need to check header offset since header is in separate window now
  local lines = vim.api.nvim_buf_get_lines(buf_id, line_num - 1, line_num, false)
  if #lines == 0 then
    return nil
  end

  local line = lines[1]
  return line:match("(https://github%.com/[^%s]+)")
end

M.close = function()
  if current_modal then
    get_log().debug("Closing store modal")
    current_modal:close()
    current_modal = nil
    return true
  end
  return false
end

M.toggle = function()
  if current_modal then
    return M.close()
  else
    return M.open()
  end
end

-- Helper function to generate fallback preview content from repository data
local function generate_fallback_preview_content(repo)
  if not repo then
    return { "Select a plugin to preview" }
  end

  local lines = {}
  table.insert(lines, "# 📦 " .. (repo.full_name or "Unknown"))
  table.insert(lines, "")
  table.insert(lines, "> " .. (repo.description or "No description available"))
  table.insert(lines, "")
  table.insert(lines, "---")
  table.insert(lines, "")
  table.insert(lines, "## 📊 Repository Stats")
  table.insert(lines, "")
  table.insert(lines, "| Metric | Count |")
  table.insert(lines, "|--------|-------|")
  table.insert(lines, "| ⭐ Stars | **" .. (repo.stargazers_count or 0) .. "** |")
  table.insert(lines, "| 👀 Watchers | **" .. (repo.watchers_count or 0) .. "** |")
  table.insert(lines, "| 🍴 Forks | **" .. (repo.fork_count or 0) .. "** |")
  table.insert(lines, "")
  table.insert(lines, "## 🕒 Last Updated")
  table.insert(lines, "")
  table.insert(lines, "```")
  table.insert(lines, (repo.updated_at or "Unknown"))
  table.insert(lines, "```")
  table.insert(lines, "")
  table.insert(lines, "## 🔗 Repository")
  table.insert(lines, "")
  table.insert(lines, "[🌐 View on GitHub](" .. (repo.html_url or "") .. ")")

  if repo.topics and #repo.topics > 0 then
    table.insert(lines, "")
    table.insert(lines, "## 🏷️ Topics")
    table.insert(lines, "")
    local topic_line = ""
    for i, topic in ipairs(repo.topics) do
      if i > 1 then
        topic_line = topic_line .. " "
      end
      topic_line = topic_line .. "`" .. topic .. "`"
    end
    table.insert(lines, topic_line)
  end

  return lines
end

-- Helper function to generate preview content (README or fallback)
local function generate_preview_content(repo, modal_instance)
  if not repo then
    modal_instance:update_preview_debounced({ "Select a plugin to preview" })
    return
  end

  -- Extract owner/repo from the URL
  local owner_repo = repo.html_url:match("github%.com/([^/]+/[^/]+)")
  if not owner_repo then
    get_log().warn("Could not extract owner/repo from URL: " .. (repo.html_url or "unknown"))
    local fallback_content = generate_fallback_preview_content(repo)
    modal_instance:update_preview_debounced(fallback_content)
    return
  end

  local loading_timer = nil

  -- Set a timer to show loading message after 50ms if not completed
  loading_timer = vim.fn.timer_start(50, function()
    loading_timer = nil
    modal_instance:update_preview_debounced({ "🔄 Loading README for " .. (repo.full_name or owner_repo) .. "..." })
  end)

  -- Try to get README content asynchronously
  http.get_readme(owner_repo, function(readme_response)
    -- Cancel loading timer if it hasn't fired yet
    if loading_timer then
      vim.fn.timer_stop(loading_timer)
      loading_timer = nil
    end

    if readme_response.success and readme_response.body then
      get_log().debug(
        "Fetched README for "
          .. owner_repo
          .. " ("
          .. #readme_response.body
          .. " lines)"
          .. (readme_response.from_cache and " [cached]" or " [network]")
      )
      modal_instance:update_preview(readme_response.body)
    else
      get_log().warn("Failed to fetch README for " .. owner_repo .. ": " .. (readme_response.error or "unknown error"))
      local fallback_content = generate_fallback_preview_content(repo)
      modal_instance:update_preview(fallback_content)
    end
  end)
end

-- Helper function to get repository data from current line
local function get_repo_data_from_current_line(modal_instance)
  if not modal_instance._original_data or not modal_instance._original_data.repositories then
    return nil
  end

  local url = get_repo_url_from_current_line(modal_instance)
  if not url then
    return nil
  end

  -- Find the repository data matching the URL
  for _, repo in ipairs(modal_instance._original_data.repositories) do
    if repo.html_url == url then
      return repo
    end
  end

  return nil
end

-- Main function to open modal (with preview as default and only mode)
M.open = function()
  if current_modal then
    return false
  end

  get_log().debug("Opening store modal")

  if not current_config then
    get_log().error("Store.nvim not initialized. Call setup() first.")
    return false
  end

  local modal = Modal:new({
    zindex = ZINDEX.BASE_MODAL,
    on_cursor_move = function(modal_instance, github_url)
      -- Handle cursor movement over GitHub URLs
      local repo = get_repo_data_from_current_line(modal_instance)
      if repo then
        generate_preview_content(repo, modal_instance)
      end
    end,
    on_init = function(modal_instance)
      http.fetch_plugins(function(data, error)
        if error then
          get_log().error("Failed to fetch plugin data: " .. error)
          local error_content = generate_error_content("📦 Store.nvim - Plugin Browser", error, modal_instance)
          modal_instance:update_content(error_content)
          modal_instance:update_preview_debounced({ "Error loading preview" })
        else
          get_log().debug("Successfully fetched plugin data")
          modal_instance._original_data = data

          local filtered_repos = filter_repositories(data.repositories, "")
          local content = generate_modal_content(data, "", modal_instance)

          modal_instance:update_content(content)
          modal_instance:update_preview_debounced({ "Put cursor on repository to see its preview" })
        end
      end)
    end,
    on_close = function(_, modal_instance)
      current_modal = nil
      get_log().debug("Modal closed")
    end,
    keybindings = {
      ["f"] = function(_, modal_instance)
        help_modal.close()
        get_log().debug("Opening filter input modal")
        local current_filter = modal_instance:get_filter_query()

        vim.ui.input({
          prompt = "Filter repositories: ",
          default = current_filter,
        }, function(input)
          if input ~= nil then
            get_log().debug("Applying filter: '" .. input .. "'")
            modal_instance:update_filter_query(input)

            if modal_instance._original_data then
              update_modal_with_filter(modal_instance, modal_instance._original_data)

              -- Update preview for first filtered result
              local filtered_repos = filter_repositories(modal_instance._original_data.repositories, input)
              if #filtered_repos > 0 then
                generate_preview_content(filtered_repos[1], modal_instance)
              else
                modal_instance:update_preview_debounced({ "No plugins match filter" })
              end
            end
          end
        end)
      end,
      ["<cr>"] = function(_, modal_instance)
        help_modal.close()
        get_log().debug("User pressed <cr> to open repository")
        local url = get_repo_url_from_current_line(modal_instance)
        if url then
          open_url_in_browser(url)
        else
          get_log().warn("No GitHub URL found on current line")
        end
      end,
      ["r"] = function(_, modal_instance)
        help_modal.close()
        get_log().debug("Modal refresh requested by user")
        local loading_content = {
          header = {
            "📦 Store.nvim - Plugin Browser",
            "Filter: | Found: 0/0 plugins",
            "Last updated: loading...",
            "Press '?' for help",
          },
          body = {
            "",
            "  🔄 Loading plugins from store...",
            "",
          },
        }
        modal_instance:update_content(loading_content)
        modal_instance:update_preview_debounced({ "Refreshing..." })

        http.fetch_plugins(function(data, error)
          if error then
            get_log().error("Refresh failed: " .. error)
            local error_content = generate_error_content("📦 Store.nvim - Plugin Browser", error, modal_instance)
            modal_instance:update_content(error_content)
            modal_instance:update_preview_debounced({ "Error loading preview" })
          else
            modal_instance._original_data = data
            update_modal_with_filter(modal_instance, data)

            -- Update preview for first item
            local filtered_repos = filter_repositories(data.repositories, modal_instance:get_filter_query())
            if #filtered_repos > 0 then
              generate_preview_content(filtered_repos[1], modal_instance)
            end
          end
        end)
      end,
      [current_config.keybindings.help or "?"] = function(_, modal_instance)
        get_log().debug("Help requested by user")
        help_modal.open()
      end,
    },
  }, current_config)

  -- Create initial loading content and preview
  local loading_content = {
    header = {
      "📦 Store.nvim - Plugin Browser",
      "Filter: | Found: 0/0 plugins",
      "Last updated: loading...",
      "Press '?' for help",
    },
    body = {
      "",
      "  🔄 Loading plugins from store...",
      "",
    },
  }

  local loading_preview = { "Put cursor on repository to see its preview" }

  -- Open with preview mode
  local success = modal:open_with_preview(loading_content, loading_preview)
  if success then
    current_modal = modal
    get_log().debug("Store modal opened successfully")
    return true
  else
    get_log().error("Failed to open modal")
  end

  return false
end

-- Expose Modal for external access
M.Modal = Modal

-- Get current config (for external use)
M.get_config = function()
  return current_config
end

return M
