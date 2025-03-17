local M = {}

local local_cache = {}

local remote_cache = {}

local function get_repo_url(path, cb)
  vim.system(
    { "git", "config", "--get", "remote.origin.url" },
    { cwd = path },
    function(result)
      if result.code ~= 0 then
        cb(nil)
        return
      end

      cb(result.stdout:gsub("%s+$", ""))
    end
  )
end

local function check_github_status(path, branch, cb)
  vim.system(
    { "gh", "run", "list", "--branch", branch, "--limit", "1", "--json", "status,conclusion" },
    { cwd = path },
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

local function watch_status(path, branch, abort_signal, sleep_duration)
  local function next()
    remote_cache[path].accessed = false

    local timer = vim.uv.new_timer()
    timer:start(sleep_duration, 0, function()
      if abort_signal.abort then
        return
      end

      if remote_cache[path].accessed then
        watch_status(path, branch, abort_signal, sleep_duration)
      else
        remote_cache[path] = nil
      end
    end)
  end

  if branch then
    get_repo_url(
      path,
      function(repo_url)
        if abort_signal.abort then
          return
        end

        if repo_url and repo_url:match("github.com") then
          check_github_status(path, branch, function(status_result)
            if abort_signal.abort then
              return
            end

            if status_result then
              remote_cache[path].status = status_result.status
              remote_cache[path].conclusion = status_result.conclusion
            end
            next()
          end)
        else
          remote_cache[path].status = nil
          remote_cache[path].conclusion = nil
          next()
        end
      end
    )
  else
    next()
  end
end

local function watch_branch(path, sleep_duration)
  vim.system(
    { "git", "rev-parse", "--abbrev-ref", "HEAD" },
    { cwd = path },
    function(obj)
      if obj.code == 0 then
        local_cache[path].branch = obj.stdout:gsub("%s+$", "")
      else
        local_cache[path].branch = nil
      end

      local_cache[path].accessed = false

      local timer = vim.uv.new_timer()
      timer:start(sleep_duration, 0, function()
        if local_cache[path].accessed then
          watch_branch(path, sleep_duration)
        else
          local_cache[path] = nil
        end
      end)
    end
  )
end

local function get(path, watch_branch_sleep_duration, watch_status_sleep_duration)
  if local_cache[path] then
    local_cache[path].accessed = true
  else
    local_cache[path] = {
      branch = nil,
      accessed = true,
    }
    watch_branch(path, watch_branch_sleep_duration)
  end

  if remote_cache[path] then
    remote_cache[path].accessed = true
  else
    remote_cache[path] = {
      branch = nil,
      status = nil,
      conclusion = nil,
      accessed = true,
    }
  end

  if local_cache[path].branch ~= remote_cache[path].branch then
    remote_cache[path].branch = local_cache[path].branch
    remote_cache[path].status = nil
    remote_cache[path].conclusion = nil

    if remote_cache[path].abort_signal then
      remote_cache[path].abort_signal.abort = true
    end

    local abort_signal = { abort = false }
    watch_status(path, local_cache[path].branch, abort_signal, watch_status_sleep_duration)
    remote_cache[path].abort_signal = abort_signal
  end

  return remote_cache[path].status, remote_cache[path].conclusion
end

function M.create_getter(opts)
  local merged_opts = vim.tbl_extend(
    "force",
    { watch_branch_sleep_duration = 1000, watch_status_sleep_duration = 10000 },
    opts or {}
  )

  return function(path)
    return get(path, merged_opts.watch_branch_sleep_duration, merged_opts.watch_status_sleep_duration)
  end
end

return M
