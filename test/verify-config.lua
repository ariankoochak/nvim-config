-- Headless smoke test for the *real* configuration.
--
--   nvim --headless -c "luafile test/verify-config.lua"
--
-- Exits non-zero when anything fails. That matters: a failing `assert` inside a
-- plain `-c lua ...` prints an error and lets Neovim carry on to `qa`, so the
-- process still exits 0 and CI happily goes green. This script does the
-- checking itself and calls `cquit`.

local failures = {}

local function out(msg)
  io.stdout:write(msg .. "\n")
  io.stdout:flush()
end

local function check(name, fn)
  local ok, err = pcall(fn)
  if ok then
    out("ok      " .. name)
  else
    out("FAIL    " .. name)
    failures[#failures + 1] = ("%s: %s"):format(name, tostring(err))
  end
end

-- Headless Neovim attaches no UI, so lazy.nvim never fires User VeryLazy --
-- which is when LazyVim loads lua/config/keymaps.lua, and with it our mappings.
vim.api.nvim_exec_autocmds("User", { pattern = "VeryLazy", modeline = false })

check("lazy.nvim is set up", function()
  local plugins = require("lazy.core.config").plugins
  assert(plugins["LazyVim"], "LazyVim is not in the spec")
  assert(plugins["lazy.nvim"], "lazy.nvim is not in the spec")
end)

check("the completion engine and its sources are present", function()
  local plugins = require("lazy.core.config").plugins
  assert(plugins["blink.cmp"], "blink.cmp is missing")
  assert(plugins["friendly-snippets"], "friendly-snippets is missing")
end)

check("the extras were imported", function()
  local plugins = require("lazy.core.config").plugins
  assert(plugins["SchemaStore.nvim"], "the json extra did not load (SchemaStore missing)")
  assert(plugins["vim-dadbod-ui"], "the sql extra did not load (dadbod-ui missing)")
  assert(plugins["conform.nvim"], "the prettier extra did not load (conform missing)")
  assert(plugins["nvim-lint"], "the eslint extra did not load (nvim-lint missing)")
end)

check("the colourscheme resolves for this terminal", function()
  local want = require("config.terminal").truecolor() and "xcodedark" or "habamax"
  assert(vim.g.colors_name == want, ("expected %s, got %s"):format(want, tostring(vim.g.colors_name)))
  assert(vim.o.termguicolors == require("config.terminal").truecolor(), "termguicolors does not match detection")
end)

check("the VSCode mappings are live", function()
  for _, spec in ipairs({
    { "<C-S-Right>", "i" },
    { "<C-S-Left>", "n" },
    { "<M-S-Right>", "s" },
    { "<C-s>", "s" },
    { "<C-v>", "i" },
    { "<C-c>", "i" },
    { "<BS>", "s" },
    { "<M-Up>", "i" },
    { "<M-b>", "n" },
  }) do
    assert(vim.fn.maparg(spec[1], spec[2]) ~= "", ("%s is not mapped in %s mode"):format(spec[1], spec[2]))
  end
end)

check("bashls is configured", function()
  local opts = LazyVim.opts("nvim-lspconfig")
  assert(opts.servers and opts.servers.bashls, "bashls is not in the lspconfig servers")
end)

check("shell tooling is in the Mason list", function()
  local ensure = (LazyVim.opts("mason.nvim") or {}).ensure_installed or {}
  for _, tool in ipairs({ "shellcheck", "shfmt" }) do
    assert(vim.tbl_contains(ensure, tool), tool .. " is not in mason's ensure_installed")
  end
end)

check("sqlfluff uses the postgres dialect", function()
  require("lazy").load({ plugins = { "nvim-lint" } })
  local args = require("lint").linters.sqlfluff.args
  assert(vim.tbl_contains(args, "--dialect=postgres"), "linter args: " .. vim.inspect(args))

  require("lazy").load({ plugins = { "conform.nvim" } })
  local formatter = require("conform").get_formatter_config("sqlfluff")
  assert(formatter, "conform has no sqlfluff formatter")
  assert(vim.tbl_contains(formatter.args, "--dialect=postgres"), "formatter args: " .. vim.inspect(formatter.args))
end)

check("plugin updates are not checked automatically", function()
  local config = require("lazy.core.config")
  assert(config.options.checker.enabled == false, "lazy's update checker is enabled")
end)

if #failures > 0 then
  out("")
  for _, failure in ipairs(failures) do
    out("  " .. failure)
  end
  out(("\n%d check(s) failed"):format(#failures))
  vim.cmd("cquit 1")
end

out("\nall checks passed")
vim.cmd("qa!")
