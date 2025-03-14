local M = {}

local branch_cache = {}

local status_cache = {}

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

local function watch_status(path, branch, abort_signal)
  local function next()
    status_cache[path].accessed = false

    local timer = vim.uv.new_timer()
    timer:start(10000, 0, function()
      if abort_signal.abort then
        return
      end

      if status_cache[path].accessed then
        watch_status(path, branch, abort_signal)
      else
        status_cache[path] = nil
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
              status_cache[path].status = status_result.status
              status_cache[path].conclusion = status_result.conclusion
            end
            next()
          end)
        else
          status_cache[path].status = nil
          status_cache[path].conclusion = nil
          next()
        end
      end
    )
  else
    next()
  end
end

local function watch_branch(path)
  vim.system(
    { "git", "rev-parse", "--abbrev-ref", "HEAD" },
    { cwd = path },
    function(obj)
      if obj.code == 0 then
        branch_cache[path].branch = obj.stdout:gsub("%s+$", "")
      else
        branch_cache[path].branch = nil
      end

      branch_cache[path].accessed = false

      local timer = vim.uv.new_timer()
      timer:start(1000, 0, function()
        if branch_cache[path].accessed then
          watch_branch(path)
        else
          branch_cache[path] = nil
        end
      end)
    end
  )
end

function M.get(path)
  if branch_cache[path] then
    branch_cache[path].accessed = true
  else
    branch_cache[path] = {
      branch = nil,
      accessed = true,
    }
    watch_branch(path)
  end

  if status_cache[path] then
    status_cache[path].accessed = true
  else
    status_cache[path] = {
      branch = nil,
      status = nil,
      conclusion = nil,
      accessed = true,
    }
  end

  if branch_cache[path].branch ~= status_cache[path].branch then
    status_cache[path].branch = branch_cache[path].branch
    status_cache[path].status = nil
    status_cache[path].conclusion = nil

    if status_cache[path].abort_signal then
      status_cache[path].abort_signal.abort = true
    end

    local abort_signal = { abort = false }
    watch_status(path, branch_cache[path].branch, abort_signal)
    status_cache[path].abort_signal = abort_signal
  end

  return status_cache[path].status, status_cache[path].conclusion
end

return M
