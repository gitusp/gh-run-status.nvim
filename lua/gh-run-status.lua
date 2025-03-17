local M = {}

local local_cache = {}

local remote_cache = {}

local function get_repo_url(repo_root, cb)
  vim.system(
    { "git", "config", "--get", "remote.origin.url" },
    { cwd = repo_root },
    function(result)
      if result.code ~= 0 then
        cb(nil)
        return
      end

      cb(result.stdout:gsub("%s+$", ""))
    end
  )
end

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

local function watch_remote(key, repo_root, branch, sleep_duration)
  local function next()
    remote_cache[key].accessed = false

    local timer = vim.uv.new_timer()
    timer:start(sleep_duration, 0, function()
      if remote_cache[key].accessed then
        watch_remote(key, repo_root, branch, sleep_duration)
      else
        remote_cache[key] = nil
      end
    end)
  end

  get_repo_url(
    repo_root,
    function(repo_url)
      if repo_url and repo_url:match("github.com") then
        check_github_status(repo_root, branch, function(status_result)
          if status_result then
            remote_cache[key].data = status_result
          end
          next()
        end)
      else
        remote_cache[key].data = nil
        next()
      end
    end
  )
end

local function watch_local(path, sleep_duration)
  vim.system(
    { "git", "rev-parse", "--show-toplevel", "--abbrev-ref", "HEAD" },
    { cwd = path },
    function(obj)
      if obj.code == 0 then
        local lines = vim.split(obj.stdout, '\n')
        local repo_root = lines[1]:gsub("%s+$", "")
        local branch = lines[2]:gsub("%s+$", "")

        local_cache[path].data = { repo_root = repo_root, branch = branch }
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
    local key = local_cache[path].data.repo_root .. "//" .. local_cache[path].data.branch

    if remote_cache[key] then
      remote_cache[key].accessed = true
    else
      remote_cache[key] = {
        data = nil,
        accessed = true,
      }
      watch_remote(key, local_cache[path].data.repo_root, local_cache[path].data.branch, watch_remote_sleep_duration)
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
