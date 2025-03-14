local M = {}

local health = vim.health

local start = health.start
local ok = health.ok
local warn = health.warn
local error = health.error
local info = health.info

local function check_executable(name)
  if vim.fn.executable(name) == 1 then
    ok(string.format("Found executable: %s", name))
    return true
  else
    error(string.format("Missing required executable: %s", name))
    return false
  end
end

local function check_github_login()
  local status = vim.system({"gh", "auth", "status"}):wait()

  if status.code == 0 then
    ok("GitHub CLI authenticated")
    return true
  else
    warn("GitHub CLI not authenticated. Run 'gh auth login' to authenticate")
    return false
  end
end

local function check_deps()
  local has_git = check_executable("git")
  local has_gh = check_executable("gh")

  if has_git and has_gh then
    check_github_login()
  end
end

function M.check()
  start("gh-run-status.nvim")

  info("Checking plugin health...")
  check_deps()

  -- Also provide info about configuration
  info("Plugin configuration:")
  info("- Default watch_branch_sleep_duration: 1000ms")
  info("- Default watch_status_sleep_duration: 10000ms")
  info("Adjust these values with M.create_getter({...})")
end

return M
