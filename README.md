gh-run-status.nvim
===

A Neovim plugin that monitors the status of GitHub Actions runs for the current branch.

## Features

- Automatically monitors GitHub Actions run status for the current branch
- Caches status information to minimize API calls
- Intelligently updates when branch changes
- Provides status and conclusion information for UI integrations

## Requirements

- [GitHub CLI (`gh`)](https://cli.github.com/) installed and authenticated
- Git repository connected to GitHub

## Installation

Using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  'gitusp/gh-run-status.nvim',
}
```

## Usage

```lua
-- Create a getter function with custom options (optional)
local get_status = require('gh-run-status').create_getter({
  watch_branch_sleep_duration = 1000,  -- Check branch changes every 1 second
  watch_status_sleep_duration = 10000, -- Check status changes every 10 seconds
})

-- Get current GitHub Actions status
local status, conclusion = get_status('/path/to/your/repo')
```

### Example lualine integration

```lua
{
'nvim-lualine/lualine.nvim',
  dependencies = {
    'nvim-tree/nvim-web-devicons',
    'gitusp/gh-run-status.nvim',
  },
  config = function()
    local get_gh_run_status = require('gh-run-status').create_getter()
    local function gh_run_status()
      local status, conclusion = get_gh_run_status(vim.fn.getcwd())
      if not status then
        return ""
      end

      if status == "completed" then
        if conclusion == "success" or conclusion == "neutral" or conclusion == "skipped" then
          return "✓"
        else
          return "✗"
        end
      elseif status == "expected" or status == "in_progress" or status == "pending" or status == "queued" or status == "requested" or status == "waiting" then
        return "⏱"
      else
        return "✗"
      end
    end

    require('lualine').setup({
      sections = {
        lualine_b = { 'branch', gh_run_status, 'diff', 'diagnostics' },
      }
    })
  end,
}
```

For more information about Github's `status` and `conclusion`, you may consult [the official documentation](https://docs.github.com/en/pull-requests/collaborating-with-pull-requests/collaborating-on-repositories-with-code-quality-features/about-status-checks#check-statuses-and-conclusions).  
You can also find lualine's [default configuration here](https://github.com/nvim-lualine/lualine.nvim/tree/edf4b24861fa5d586058ff2c9e8982bb971f7098?tab=readme-ov-file#default-configuration).

## Health Check

Run `:checkhealth gh-run-status` to verify that all dependencies are properly installed.

## Acknowledgements

This plugin was entirely written with assistance from Claude 3.7 Sonnet. As I'm new to Vim plugin development, any corrections, suggestions, or improvements are greatly welcome!

## Compatibility

This plugin has only been tested on macOS. Contributions and help testing on other platforms are welcome!
