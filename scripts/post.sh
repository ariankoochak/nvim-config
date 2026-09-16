#!/usr/bin/env bash
# Headless plugin, LSP-tool and parser installation.
#
# Everything here calls "$NVIM" (the absolute path chosen by preflight_neovim),
# never a bare `nvim`: PATH inside this process may still point at an old or
# non-existent binary.

run_post() {
  log "Installing plugins and tools (headless)"

  # `restore`, never `sync`: sync would *update* plugins and rewrite
  # lazy-lock.json, which defeats the point of committing the lockfile.
  # Plugins that are missing entirely are installed by lazy.nvim itself during
  # startup (install.missing defaults to true) before this command runs.
  step "lazy: installing missing plugins and restoring lazy-lock.json"
  if ! "$NVIM" --headless "+Lazy! restore" +qa 2>&1 | sed 's/^/     /'; then
    die "Plugin installation failed. Run '$NVIM' and check :Lazy for details."
  fi

  local tmp lua_script
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/nvim-post.XXXXXX")"
  lua_script="$tmp/post.lua"
  _write_post_lua "$lua_script"

  # The naive `nvim --headless -c '...' +qa` aborts Mason mid-download: +qa
  # quits as soon as the command returns, while Mason and nvim-treesitter both
  # install asynchronously. The script below blocks on each install instead, and
  # quits by itself when it is done.
  step "mason + treesitter (this blocks until every install finishes)"
  if ! NVIM_CONFIG_NODE_OK="$NODE_OK" "$NVIM" --headless -c "luafile $lua_script" 2>&1 | sed 's/^/     /'; then
    rm -rf "$tmp"
    die "Tool installation failed. Run '$NVIM' and check :Mason / :checkhealth."
  fi
  rm -rf "$tmp"

  summary "Plugins: restored from nvim/lazy-lock.json; Mason tools and Treesitter parsers installed"
}

_write_post_lua() {
  cat >"$1" <<'LUA'
-- Headless post-install: block until Mason packages and Treesitter parsers are
-- really on disk. Written to a temp file by scripts/post.sh.

local function out(msg)
  io.stdout:write(msg .. "\n")
  io.stdout:flush()
end

local node_ok = (vim.env.NVIM_CONFIG_NODE_OK == "1")
local failures = {}

-- LazyVim lazy-loads everything; headless Neovim fires neither VeryLazy nor
-- UIEnter, so the plugins have to be pulled in explicitly.
local ok_lazy, Lazy = pcall(require, "lazy")
if not ok_lazy then
  out("ERROR: lazy.nvim is not available")
  vim.cmd("cquit 1")
end
pcall(Lazy.load, { plugins = { "mason.nvim", "nvim-treesitter" } })

--------------------------------------------------------------------------
-- Mason
--------------------------------------------------------------------------
local function install_mason_tools()
  local ok_reg, mr = pcall(require, "mason-registry")
  if not ok_reg then
    out("mason-registry unavailable; skipping tool installation")
    return
  end

  local refreshed = false
  mr.refresh(function()
    refreshed = true
  end)
  if not vim.wait(120000, function()
    return refreshed
  end, 200) then
    out("WARNING: the Mason registry refresh timed out")
  end

  local wanted = (LazyVim.opts("mason.nvim") or {}).ensure_installed or {}
  for _, name in ipairs(wanted) do
    local ok_pkg, pkg = pcall(mr.get_package, name)
    if not ok_pkg then
      out(("WARNING: unknown Mason package %q"):format(name))
    elseif pkg:is_installed() then
      out(("ok      %s (already installed)"):format(name))
    else
      -- Mason resolves npm packages through `npm`; without Node they cannot be
      -- installed, and failing the whole run over it would be unhelpful.
      local source = (pkg.spec.source or {}).id or ""
      if not node_ok and source:match("^pkg:npm/") then
        out(("skipped %s (needs Node >= the configured minimum)"):format(name))
      elseif pkg:is_installing() then
        -- LazyVim's own mason config fires `p:install()` for every missing
        -- package the moment mason.nvim loads, so by now most of them are
        -- already running. Calling install() again asserts; wait instead.
        if not vim.wait(600000, function()
          return not pkg:is_installing()
        end, 200) then
          out(("WARNING: %s timed out"):format(name))
          failures[#failures + 1] = name
        elseif pkg:is_installed() then
          out(("ok      %s"):format(name))
        else
          out(("WARNING: %s failed to install"):format(name))
          failures[#failures + 1] = name
        end
      else
        local done, success = false, false
        pkg:install(nil, function(ok)
          success, done = ok, true
        end)
        if not vim.wait(600000, function()
          return done
        end, 200) then
          out(("WARNING: %s timed out"):format(name))
          failures[#failures + 1] = name
        elseif success then
          out(("ok      %s"):format(name))
        else
          out(("WARNING: %s failed to install"):format(name))
          failures[#failures + 1] = name
        end
      end
    end
  end
end

--------------------------------------------------------------------------
-- Treesitter
--------------------------------------------------------------------------
local function install_parsers()
  local ok_ts, TS = pcall(require, "nvim-treesitter")
  if not ok_ts or not TS.install then
    out("nvim-treesitter unavailable; skipping parsers")
    return
  end

  -- nvim-treesitter's `main` branch needs the tree-sitter CLI for grammars it
  -- has to generate. LazyVim installs it through Mason; ensure_treesitter_cli
  -- never calls back when the package is already there, so check first.
  if vim.fn.executable("tree-sitter") == 0 then
    local ok_util, TSUtil = pcall(require, "lazyvim.util.treesitter")
    if ok_util then
      local done = false
      TSUtil.ensure_treesitter_cli(function()
        done = true
      end)
      vim.wait(300000, function()
        return done or vim.fn.executable("tree-sitter") == 1
      end, 200)
    end
  end
  if vim.fn.executable("tree-sitter") == 0 then
    out("WARNING: no tree-sitter CLI; parsers needing generation will be skipped")
  end

  local wanted = (LazyVim.opts("nvim-treesitter") or {}).ensure_installed or {}
  if #wanted == 0 then
    return
  end
  out(("installing %d treesitter parsers"):format(#wanted))

  local task = TS.install(wanted, { summary = true })
  local ok_wait, err = task:pwait(900000)
  if not ok_wait then
    out("WARNING: treesitter install did not finish cleanly: " .. tostring(err))
    failures[#failures + 1] = "treesitter parsers"
  else
    out("ok      treesitter parsers")
  end
end

--------------------------------------------------------------------------
-- markdown-preview.nvim
--------------------------------------------------------------------------
-- Its lazy.nvim build hook downloads a prebuilt binary through
-- mkdp#util#open_terminal(), which needs a window and gets killed the moment a
-- headless Neovim quits. The plugin ships a synchronous variant for exactly
-- this case.
local function build_markdown_preview()
  local plugin = require("lazy.core.config").plugins["markdown-preview.nvim"]
  if not plugin then
    return
  end
  local bin = vim.fn.glob(plugin.dir .. "/app/bin/markdown-preview-*", false, true)
  if #bin > 0 then
    out("ok      markdown-preview binary (already present)")
    return
  end
  pcall(require("lazy").load, { plugins = { "markdown-preview.nvim" } })
  local ok_install = pcall(vim.fn["mkdp#util#install_sync"], true)
  bin = vim.fn.glob(plugin.dir .. "/app/bin/markdown-preview-*", false, true)
  if ok_install and #bin > 0 then
    out("ok      markdown-preview binary")
  else
    out("WARNING: markdown-preview binary missing; run :Lazy build markdown-preview.nvim")
  end
end

local ok_run, err = pcall(function()
  install_mason_tools()
  install_parsers()
  build_markdown_preview()
end)

if not ok_run then
  out("ERROR: " .. tostring(err))
  vim.cmd("cquit 1")
end

if #failures > 0 then
  out("Some tools did not install: " .. table.concat(failures, ", "))
  out("This is not fatal; run :Mason and :checkhealth inside Neovim to retry.")
end

vim.cmd("qa!")
LUA
}
