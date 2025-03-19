local M = {}

local local_cache = {}

local remote_cache = {}

local function check_github_status(repo_root, branch, cb)
  vim.system(
    { "gh", "run", "list", "--branch", branch, "--limit", "1", "--json", "status,conclusion" },
    { cwd = repo_root },
    function(result)
      if result.code ~= 0 then
        cb(nil)
        return
      end

      local ok, parsed = pcall(vim.json.decode, result.stdout)
      if not ok or not parsed or #parsed == 0 then
        cb(nil)
        return
      end

      cb(parsed[1])
    end
  )
end

local function watch_remote(key, data, sleep_duration)
  -- TODO: Implement more drivers
  check_github_status(data.repo_root, data.branch, function(status_result)
    if status_result then
      remote_cache[key].data = status_result
    end

    remote_cache[key].accessed = false

    local timer = vim.uv.new_timer()
    timer:start(sleep_duration, 0, function()
      if remote_cache[key].accessed then
        watch_remote(key, data, sleep_duration)
      else
        remote_cache[key] = nil
      end
    end)
  end)
end

local function watch_local(path, sleep_duration)
  local rev_parse_result
  local get_config_result

  local function next()
    if rev_parse_result.code == 0 and get_config_result.code == 0 then
      local repo_url = get_config_result.stdout:gsub("%s+$", "")
      local driver = repo_url:match("github.com") and "github" or nil

      if driver then
        local lines = vim.split(rev_parse_result.stdout, '\n')
        local repo_root = lines[1]:gsub("%s+$", "")
        local branch = lines[2]:gsub("%s+$", "")

        local_cache[path].data = { repo_root = repo_root, driver = driver, branch = branch }
      else
        local_cache[path].data = nil
      end
    else
      local_cache[path].data = nil
    end

    local_cache[path].accessed = false

    local timer = vim.uv.new_timer()
    timer:start(sleep_duration, 0, function()
      if local_cache[path].accessed then
        watch_local(path, sleep_duration)
      else
        local_cache[path] = nil
      end
    end)
  end

  vim.system(
    { "git", "rev-parse", "--show-toplevel", "--abbrev-ref", "HEAD" },
    { cwd = path },
    function(result)
      rev_parse_result = result

      if get_config_result then
        next()
      end
    end
  )

  vim.system(
    { "git", "config", "--get", "remote.origin.url" },
    { cwd = path },
    function(result)
      get_config_result = result

      if rev_parse_result then
        next()
      end
    end
  )
end

local function get(path, watch_local_sleep_duration, watch_remote_sleep_duration)
  if local_cache[path] then
    local_cache[path].accessed = true
  else
    local_cache[path] = {
      data = nil,
      accessed = true,
    }
    watch_local(path, watch_local_sleep_duration)
  end

  if local_cache[path].data then
    local key = table.concat(
      { local_cache[path].data.driver, local_cache[path].data.repo_root, local_cache[path].data.branch },
      "\n"
    )

    if remote_cache[key] then
      remote_cache[key].accessed = true
    else
      remote_cache[key] = {
        data = nil,
        accessed = true,
      }
      watch_remote(key, local_cache[path].data, watch_remote_sleep_duration)
    end

    if remote_cache[key].data then
      return remote_cache[key].data.status, remote_cache[key].data.conclusion
    end
  end

  return nil, nil
end

function M.create_getter(opts)
  local merged_opts = vim.tbl_extend(
    "force",
    { watch_local_sleep_duration = 1000, watch_remote_sleep_duration = 10000 },
    opts or {}
  )

  return function(path)
    return get(path, merged_opts.watch_local_sleep_duration, merged_opts.watch_remote_sleep_duration)
  end
end

return M
