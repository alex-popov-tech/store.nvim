local help = require("store.ui.help")
local event_handlers = require("store.ui.store_modal.event_handlers")
local database = require("store.database")
local telemetry = require("store.telemetry")
local sort = require("store.sort")
local filter = require("store.ui.filter")
local sort_select = require("store.ui.sort_select")
local plugin_utils = require("store.utils")
local utils = require("store.ui.store_modal.utils")
local logger = require("store.logger").createLogger({ context = "actions" })

local M = {}

---@param instance StoreModal instance of main modal
---@return string|nil error in case of failure
function M.close(instance)
  logger.debug("Action: close")
  local err = instance:close()
  if err then
    return err
  end
end

---@param instance StoreModal instance of main modal
---@return string|nil error in case of failure
function M.filter(instance)
  logger.info("Opening filter")
  local previous_focus = instance.state.current_focus

  local filter_component, error_msg = filter.new(vim.tbl_extend("force", instance.config.layout.filter, {
    current_query = instance.state.filter_query or "",
    on_value = function(query)
      -- there are 5 cases possible:
      -- 0. filter not changed - do nothing
      -- 1. filter is empty - DB data + sorting
      -- 2. filter is non-empty - apply filtering on DB data + sorting

      -- case 0
      if instance.state.filter_query == query then
        return
      end

      logger.debug("Applying filter: " .. query)

      -- case 1
      if query == "" then
        logger.debug("Filter cleared, showing all " .. #instance.state.repos .. " repositories")
        instance.state.currently_displayed_repos = vim.tbl_extend("force", {}, instance.state.repos)
        -- sort only if custom sort
        if instance.state.sort_config.type ~= "recently_updated" then
          logger.debug("Sorting " .. #instance.state.currently_displayed_repos .. " filtered repositories")
          local err = utils.sort(
            instance.state.currently_displayed_repos,
            { installed_items = instance.state.installed_items, download_stats_monthly = instance.state.download_stats_monthly, download_stats_weekly = instance.state.download_stats_weekly, view_stats_monthly = instance.state.view_stats_monthly, view_stats_weekly = instance.state.view_stats_weekly },
            instance.state.sort_config.type
          )
          if err ~= nil then
            logger.warn("Cannot sort repositories: " .. err)
            return
          end
        end
      end

      if query ~= "" then
        logger.debug("Filter is non-empty, applying filtering on " .. #instance.state.repos .. " repositories")
        local filtered, error = utils.filter(instance.state.repos, query)
        if error ~= nil then
          logger.error("Failed to filter repositories: " .. error)
          return
        end
        instance.state.currently_displayed_repos = filtered
      end
      instance.state.filter_query = query

      local error = instance.heading:render({
        filter_query = instance.state.filter_query,
        filtered_count = #instance.state.currently_displayed_repos,
      })
      if error ~= nil then
        logger.warn("Failed to re-render heading after filter: " .. error)
      end

      error = instance.list:render({
        items = instance.state.currently_displayed_repos,
        sort_type = instance.state.sort_config.type,
        download_stats_monthly = instance.state.download_stats_monthly,
        view_stats_monthly = instance.state.view_stats_monthly,
      })
      if error ~= nil then
        logger.warn("Failed to re-render list after filter: " .. error)
      end

      if instance.layout_provider then
        instance.layout_provider:update_winbar(instance.list, instance.preview)
      end
    end,
    on_exit = function()
      -- Restore focus to previous component
      if instance.list:get_window_id() == previous_focus then
        instance.list:focus()
      elseif instance.preview:get_window_id() == previous_focus then
        instance.preview:focus()
      end
    end,
  }))

  if error_msg then
    logger.warn("Failed to create filter component: " .. error_msg)
    return
  end
  logger.debug("Filter component created successfully")

  local open_error = filter_component:open()
  if open_error then
    logger.warn("Failed to open filter component: " .. open_error)
  end
end

function M.help(instance)
  logger.debug("Action: help")
  logger.info("Opening help")

  -- Store current focus for restoration
  local previous_focus = instance.state.current_focus
  -- Use centralized layout calculations
  local help_layout = instance.config.layout.help

  help.open({
    layout = help_layout,
    keybindings = instance.config.keybindings,
    on_exit = function()
      -- Restore focus after closing help
      if previous_focus == "list" then
        instance.list:focus()
      elseif previous_focus == "preview" then
        instance.preview:focus()
      end
    end,
  })
end

function M.open(instance)
  logger.debug("Action: open repository")
  if not instance.state.current_repository or not instance.state.current_repository.url then
    logger.warn("No repository selected")
    return
  end

  local error = plugin_utils.open_url(instance.state.current_repository.url)
  if error then
    logger.warn("Failed to open URL: " .. instance.state.current_repository.url)
  else
    logger.info("Opened repository: " .. instance.state.current_repository.full_name)
  end
end

function M.sort(instance)
  logger.debug("Action: sort")
  local previous_focus = instance.state.current_focus

  local sort_layout = instance.config.layout.sort

  local sort_component, error_msg = sort_select.new({
    width = sort_layout.width,
    height = sort_layout.height,
    row = sort_layout.row,
    col = sort_layout.col,
    current_sort = instance.state.sort_config.type,
    on_value = function(selected_sort)
      -- there are 5 cases possible:
      -- 0. sort not changed - do nothing
      -- 1. no filter + recently_updated sort = use db data
      -- 2. filter + recently_updated sort = filter db data
      -- 3. no filter + other sort = sort curr filtered list
      -- 4. filter + other sort = sort curr filtered list

      -- case 0
      if instance.state.sort_config.type == selected_sort then
        return
      end

      logger.debug("Applying sort: " .. selected_sort)

      -- case 1
      if selected_sort == "recently_updated" and instance.state.filter_query == "" then
        instance.state.currently_displayed_repos = vim.tbl_extend("force", {}, instance.state.repos)
      end

      -- case 2
      if selected_sort == "recently_updated" and instance.state.filter_query ~= "" then
        local filtered, err = utils.filter(instance.state.repos, instance.state.filter_query)
        if err ~= nil then
          logger.error("Failed to filter repositories: " .. err)
          return
        end
        instance.state.currently_displayed_repos = filtered
      end

      -- case 3, 4
      if selected_sort ~= "recently_updated" then
        logger.debug("Sorting " .. #instance.state.currently_displayed_repos .. " filtered(?) repositories")
        local sorting = sort.sorts[selected_sort]
        if not sorting then
          logger.warn("Unknown sort type: " .. selected_sort)
          return
        end
        table.sort(instance.state.currently_displayed_repos, function(a, b)
          return sorting.fn(a, b, { installed_items = instance.state.installed_items, download_stats_monthly = instance.state.download_stats_monthly, download_stats_weekly = instance.state.download_stats_weekly, view_stats_monthly = instance.state.view_stats_monthly, view_stats_weekly = instance.state.view_stats_weekly })
        end)
      end

      instance.state.sort_config.type = selected_sort

      -- re-render components
      local heading_error = instance.heading:render({ sort_type = selected_sort })
      if heading_error ~= nil then
        logger.warn("Failed to render heading after sort: " .. heading_error)
      end

      local list_error = instance.list:render({
        items = instance.state.currently_displayed_repos,
        sort_type = selected_sort,
        download_stats_monthly = instance.state.download_stats_monthly,
        view_stats_monthly = instance.state.view_stats_monthly,
      })
      if list_error ~= nil then
        logger.warn("Failed to render list after sort: " .. list_error)
      end
      logger.debug("Sort operation completed")
    end,
    on_exit = function()
      -- Restore focus
      if instance.list:get_window_id() == previous_focus then
        instance.list:focus()
      elseif instance.preview:get_window_id() == previous_focus then
        instance.preview:focus()
      end
    end,
  })

  if error_msg then
    logger.warn("Failed to create sort component: " .. error_msg)
    return
  end

  local open_error = sort_component:open()
  if open_error then
    logger.warn("Failed to open sort component: " .. open_error)
  end
end

function M.switch_list(instance)
  logger.debug("Action: switch to list tab")
  if instance.preview:get_window_id() == instance.state.current_focus then
    instance.preview:save_cursor_on_blur()
  end
  instance.list:set_active_tab("list")
  instance.list:focus()
  instance.state.current_focus = instance.list:get_window_id()
end

function M.switch_install(instance)
  logger.debug("Action: switch to install tab")
  if instance.preview:get_window_id() == instance.state.current_focus then
    instance.preview:save_cursor_on_blur()
  end
  local repo = instance.state.current_repository
  if repo then
    local telemetry = package.loaded["store.telemetry"]
    if telemetry then telemetry.track("view", repo.full_name) end
  end
  local snippet = instance.state.install_catalogue and repo and instance.state.install_catalogue[repo.full_name]
  instance.list:render_install(repo, snippet, instance.state.plugin_manager_mode)
  instance.list:set_active_tab("install")
  instance.list:focus()
  instance.state.current_focus = instance.list:get_window_id()
end

function M.switch_readme(instance)
  logger.debug("Action: switch to readme tab")
  instance.preview:set_active_tab("readme")
  instance.preview:focus()
  instance.state.current_focus = instance.preview:get_window_id()
  local repo = instance.state.current_repository
  if repo then
    local telemetry = package.loaded["store.telemetry"]
    if telemetry then telemetry.track("view", repo.full_name) end
    database.get_readme(repo, function(content, error)
      if error then
        instance.preview:render({ state = "error", content = { error } })
      else
        instance.preview:render({ state = "ready", content = content, readme_id = repo.full_name })
      end
    end)
  end
end

function M.switch_docs(instance)
  logger.debug("Action: switch/cycle docs")
  local repo = instance.state.current_repository
  if not repo or not repo.doc or #repo.doc == 0 then
    return -- no docs available, silently ignore
  end

  local preview = instance.preview
  local current_tab = preview:get_active_tab()

  if current_tab == "docs" then
    -- Cycle to next doc (wrap around)
    local next_index = (preview.state.doc_index % #repo.doc) + 1
    preview.state.doc_index = next_index
  else
    -- Switch from readme to docs, show first doc
    preview.state.doc_index = 1
    preview:set_active_tab("docs")
  end

  -- Update tab labels immediately (shows counter before fetch completes)
  preview:update_doc_label()

  -- Fetch and render the selected doc
  local doc_path = repo.doc[preview.state.doc_index]
  preview:render_docs({ state = "loading" })

  instance.preview:focus()
  instance.state.current_focus = instance.preview:get_window_id()

  local telemetry = package.loaded["store.telemetry"]
  if telemetry then telemetry.track("view", repo.full_name) end

  database.get_doc(repo, doc_path, function(content, error)
    if error then
      -- offline with nothing cached is a state, not an error: the
      -- preview says so, quietly, instead of dumping curl's complaint
      local offline = error:find("not connected", 1, true)
        or error:find("network unreachable", 1, true)
      local content_lines = offline and { "", "  Not connected", "" } or { error }
      instance.preview:render_docs({ state = "error", content = content_lines })
    else
      instance.preview:render_docs({ state = "ready", content = content, docs_id = repo.full_name .. "::" .. doc_path })
    end
  end)
end

---Toggle the preview full screen: whatever the Docs or Readme tab is
---showing opens in a window covering the editor, and the same key (or q)
---brings the modal back. Only does something while content is on screen.
---@param instance StoreModal instance of main modal
function M.toggle_docs_fullscreen(instance)
  logger.debug("Action: toggle docs fullscreen")
  local preview = instance.preview
  if not (preview and preview.state) then
    return
  end
  -- whatever the preview is showing: the docs tab's buffer, or the
  -- readme's — f fullscreens the pane either way (the key works from
  -- the README tab too, not only once D was pressed)
  local tab = preview:get_active_tab()
  local src = tab == "docs" and preview.state.buf.docs_id or preview.state.buf.id
  if tab ~= "docs" and tab ~= "readme" then
    return
  end

  -- toggle back: the fullscreen window goes, the modal keeps the focus
  if instance.docs_fullscreen and vim.api.nvim_win_is_valid(instance.docs_fullscreen) then
    local win = instance.docs_fullscreen
    instance.docs_fullscreen = nil
    pcall(vim.api.nvim_win_close, win, true)
    if instance.state.current_focus and vim.api.nvim_win_is_valid(instance.state.current_focus) then
      pcall(vim.api.nvim_set_current_win, instance.state.current_focus)
    end
    return
  end

  -- the text as it sits in the shown buffer right now
  local lines = {}
  if src and vim.api.nvim_buf_is_valid(src) then
    lines = vim.api.nvim_buf_get_lines(src, 0, -1, false)
  end
  if #lines == 0 then
    return -- nothing rendered yet: loading or error, nothing to enlarge
  end

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  local ft = vim.bo[src].filetype
  if ft ~= "" then
    pcall(function()
      vim.bo[buf].filetype = ft
    end)
  end
  vim.bo[buf].modifiable = false
  vim.bo[buf].bufhidden = "wipe"

  -- the screen as this nvim sees it: the attached UI when there is one
  -- (a terminal), the options when there is not (headless, an embedded
  -- core, a UI attached later) — nvim_list_uis() can be empty, and a nil
  -- index there used to kill the whole toggle
  local uis = vim.api.nvim_list_uis()
  local width = (uis[1] and uis[1].width) or vim.o.columns
  local height = (uis[1] and uis[1].height) or vim.o.lines
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    row = 0,
    col = 0,
    width = math.max(1, width),
    height = math.max(1, height - vim.o.cmdheight - (vim.o.laststatus == 0 and 0 or 1)),
    style = "minimal",
    border = "none",
    zindex = 100,
  })
  vim.wo[win].wrap = true
  vim.wo[win].linebreak = true
  vim.wo[win].scrolloff = 2
  instance.docs_fullscreen = win

  -- back to the modal: the toggle key, or the closers
  local keys = vim.list_extend(
    { "f" },
    vim.list_extend(
      (instance.config.keybindings and instance.config.keybindings.toggle_docs_fullscreen) or {},
      instance.config.keybindings and instance.config.keybindings.close or {}
    )
  )
  local seen = {}
  for _, key in ipairs(keys) do
    if not seen[key] then
      seen[key] = true
      vim.keymap.set("n", key, function()
        if instance.docs_fullscreen and vim.api.nvim_win_is_valid(instance.docs_fullscreen) then
          local w = instance.docs_fullscreen
          instance.docs_fullscreen = nil
          pcall(vim.api.nvim_win_close, w, true)
        end
        if instance.state.current_focus and vim.api.nvim_win_is_valid(instance.state.current_focus) then
          pcall(vim.api.nvim_set_current_win, instance.state.current_focus)
        end
      end, {
        buffer = buf,
        silent = true,
        nowait = true,
        desc = "store.nvim: docs fullscreen off",
      })
    end
  end

  -- the modal closing under it must take the fullscreen with it
  vim.api.nvim_create_autocmd("WinClosed", {
    pattern = tostring(instance.preview:get_window_id()),
    once = true,
    callback = function()
      if instance.docs_fullscreen and vim.api.nvim_win_is_valid(instance.docs_fullscreen) then
        local w = instance.docs_fullscreen
        instance.docs_fullscreen = nil
        pcall(vim.api.nvim_win_close, w, true)
      end
    end,
  })
end

---The doc (or readme) the preview is showing, taken out of the store: the
---modal closes (the doc is the thing on screen now, not the store) and the
---text opens in a real buffer — a new tab, a vertical or a horizontal split
---— named after the repository and the doc, wrapped and highlighted like
---the preview. Nothing else about the store is kept: it is a snapshot of
---what the tab was showing.
---@param instance StoreModal instance of main modal
---@param how 'tab'|'vsplit'|'split'
function M.open_docs_external(instance, how)
  logger.debug("Action: open docs in a " .. how)
  local preview = instance.preview
  if not (preview and preview.state) then
    return
  end
  local tab = preview:get_active_tab()
  if tab ~= "docs" and tab ~= "readme" then
    return -- nothing on screen to take out
  end
  local src = tab == "docs" and preview.state.buf.docs_id or preview.state.buf.id
  if not (src and vim.api.nvim_buf_is_valid(src)) then
    return
  end
  local lines = vim.api.nvim_buf_get_lines(src, 0, -1, false)
  if #lines == 0 then
    return -- loading or error: nothing to take out yet
  end
  local ft = vim.bo[src].filetype

  -- the name: the repository and the doc (or the readme), so :buffers and
  -- the tab label say what the buffer is
  local repo = instance.state.current_repository
  local doc_path = "README.md"
  if tab == "docs" then
    doc_path = preview.state.doc_paths and preview.state.doc_paths[preview.state.doc_index] or nil
  end
  local name = "store://"
  if repo and repo.full_name then
    name = name .. repo.full_name
  end
  if doc_path and doc_path ~= "" then
    name = name .. "/" .. doc_path
  end

  -- the modal goes first: closing it restores the windows underneath, so
  -- the tab or the split opens on the restored layout, not under the modal
  local close_err = M.close(instance)
  if close_err then
    logger.warn("Failed to close the modal: " .. close_err)
  end

  local buf = vim.api.nvim_create_buf(false, true)
  -- buffer names are unique in a session: opening the same doc twice (a
  -- tab, then a split of the same page) would collide on the plain name,
  -- and nvim_buf_set_name would fail leaving the buffer nameless — try
  -- the name, then numbered copies of it
  if not pcall(vim.api.nvim_buf_set_name, buf, name) then
    local stem, n = name, 2
    while not pcall(vim.api.nvim_buf_set_name, buf, stem .. " (" .. n .. ")") do
      n = n + 1
      if n > 20 then
        break -- give up named, the doc still opens
      end
    end
  end
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  if ft ~= "" then
    pcall(function()
      vim.bo[buf].filetype = ft
    end)
  end
  vim.bo[buf].modifiable = false
  vim.bo[buf].buflisted = true
  vim.bo[buf].bufhidden = "hide"

  local cmd = how == "tab" and "tabnew" or (how == "vsplit" and "vnew" or "new")
  local ok, err = pcall(vim.cmd, cmd)
  if not ok then
    logger.warn("Cannot open the doc in a " .. how .. ": " .. tostring(err))
    vim.api.nvim_buf_delete(buf, { force = true })
    return
  end
  vim.api.nvim_win_set_buf(0, buf)
  vim.wo.wrap = true
  vim.wo.linebreak = true
  vim.wo.scrolloff = 2
end

function M.reset(instance)
  logger.info("Refreshing plugin database")

  instance.heading:render({ state = "loading" })
  instance.list:render({ state = "loading" })
  instance.preview:render({ state = "loading" })

  local err = database.clear()
  if err ~= nil then
    logger.warn("Failed to clear database: " .. err)
  end

  -- Concurrently fetch plugins data and installed plugins; the explicit
  -- refresh forces the network (the freshness window is for the quiet
  -- opens, not for the button the user just pressed)
  database.fetch_plugins(function(data, err)
    event_handlers.on_db(instance, data, err)
  end, { force = true })

  -- Concurrently fetch installed plugins
  plugin_utils.get_installed_plugins(
    { preferred_manager = instance.config and instance.config.plugin_manager },
    function(installed_data, mode, installed_err, overview)
      event_handlers.on_installed_plugins(instance, installed_data, mode, installed_err, overview)
    end
  )

  -- Clear and re-fetch stats (both periods)
  instance.state.download_stats_monthly = nil
  instance.state.download_stats_weekly = nil
  instance.state.view_stats_monthly = nil
  instance.state.view_stats_weekly = nil
  telemetry.fetch_stats("month", function(data, err)
    event_handlers.on_stats(instance, "month", data, err)
  end)
  telemetry.fetch_stats("week", function(data, err)
    event_handlers.on_stats(instance, "week", data, err)
  end)
end

function M.hover(instance)
  logger.debug("Action: hover")
  local repo = instance.state.current_repository
  if not repo then
    logger.warn("No repository selected for hover")
    return
  end

  local hover = require("store.ui.hover")
  local full_name = repo.full_name
  local component, err = hover.new({
    repository = repo,
    download_stats_weekly = instance.state.download_stats_weekly and instance.state.download_stats_weekly[full_name],
    download_stats_monthly = instance.state.download_stats_monthly and instance.state.download_stats_monthly[full_name],
    view_stats_weekly = instance.state.view_stats_weekly and instance.state.view_stats_weekly[full_name],
    view_stats_monthly = instance.state.view_stats_monthly and instance.state.view_stats_monthly[full_name],
  })
  if err then
    logger.warn("Failed to create hover component: " .. err)
    return
  end

  local show_err = component:show()
  if show_err then
    logger.warn("Failed to show hover component: " .. show_err)
  else
    logger.debug("Hover displayed for repository: " .. repo.full_name)
  end
end

return M
