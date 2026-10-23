-- Standalone synthetic regression for failed install-catalogue refreshes.
-- Run from the repository root with: lua tests/install_catalogue_etag.lua
package.path = "lua/?.lua;lua/?/init.lua;" .. package.path

local scheduled = {}
local etag_value = "old-etag"
local response_status = 500
local saved_catalogue

vim = {
  schedule = function(callback)
    table.insert(scheduled, callback)
  end,
  log = { levels = { INFO = 1 } },
  tbl_count = function(value)
    local count = 0
    for _ in pairs(value) do count = count + 1 end
    return count
  end,
  trim = function(value) return value:match("^%s*(.-)%s*$") end,
  json = {
    decode = function()
      return { items = { { full_name = "synthetic/fresh" } } }
    end,
  },
}

local function run_scheduled()
  while #scheduled > 0 do
    table.remove(scheduled, 1)()
  end
end

local etag_file = {
  exists = function() return true end,
  read = function() return etag_value end,
  write = function(_, content) etag_value = content end,
}
local cache_dir = {
  exists = function() return true end,
}
setmetatable(cache_dir, {
  __div = function(_, name)
    if name == "lazy.nvim.json.etag" then return etag_file end
    return { exists = function() return false end }
  end,
})

package.preload["store.database.cache"] = function()
  return {
    get_install_catalogue = function() return "file", { items = { { full_name = "synthetic/stale" } } } end,
    save_install_catalogue = function(_, content, on_saved)
      saved_catalogue = content
      vim.schedule(on_saved)
      return nil
    end,
  }
end
package.preload["store.database.github_client"] = function() return {} end
package.preload["store.database.gitlab_client"] = function() return {} end
package.preload["store.database.utils"] = function()
  return { get_cache_dir = function() return cache_dir end }
end
package.preload["store.utils"] = function()
  return { tryNotify = function() end }
end
package.preload["store.config"] = function()
  return {
    get = function()
      return { install_catalogue_urls = { ["lazy.nvim"] = "https://synthetic.invalid/catalogue.json" } }
    end,
  }
end
package.preload["store.logger"] = function()
  return {
    createLogger = function()
      return setmetatable({}, { __index = function() return function() end end })
    end,
  }
end
package.preload["store.plenary.curl"] = function()
  return {
    head = function(_, options)
      options.callback({ status = 200, headers = { "ETag: new-etag" } })
    end,
    get = function(_, options)
      local response = { status = response_status, body = "synthetic response" }
      options.callback(response)
    end,
  }
end

local database = require("store.database")
local failed_result, failed_error
database.fetch_install_catalogue("lazy.nvim", function(data, err)
  failed_result, failed_error = data, err
end)
run_scheduled()
assert(failed_result == nil and failed_error ~= nil, "failed refresh should report its HTTP error")
assert(etag_value == "old-etag", "failed refresh must not advance the cached ETag")

response_status = 200
local fresh_result, fresh_error
database.fetch_install_catalogue("lazy.nvim", function(data, err)
  fresh_result, fresh_error = data, err
end)
run_scheduled()
assert(fresh_error == nil and fresh_result == saved_catalogue, "successful refresh should return and cache the new catalogue")
assert(etag_value == "new-etag", "ETag should advance only after the catalogue cache write succeeds")

print("install catalogue ETag regression passed")
