-- lazy.nvim bootstrap + the LazyVim spec.
--
-- Extras are imported here rather than through `:LazyExtras`, so this repo is
-- the single source of truth: a fresh clone reproduces the exact same setup
-- without anyone touching lazyvim.json.

local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not (vim.uv or vim.loop).fs_stat(lazypath) then
  local lazyrepo = "https://github.com/folke/lazy.nvim.git"
  local out = vim.fn.system({ "git", "clone", "--filter=blob:none", "--branch=stable", lazyrepo, lazypath })
  if vim.v.shell_error ~= 0 then
    vim.api.nvim_echo({
      { "Failed to clone lazy.nvim:\n", "ErrorMsg" },
      { out, "WarningMsg" },
      { "\nPress any key to exit..." },
    }, true, {})
    vim.fn.getchar()
    os.exit(1)
  end
end
vim.opt.rtp:prepend(lazypath)

require("lazy").setup({
  spec = {
    { "LazyVim/LazyVim", import = "lazyvim.plugins" },

    -- Languages. The order mirrors lazyvim/plugins/xtras.lua's priorities:
    -- typescript wants to load early, prettier late.
    { import = "lazyvim.plugins.extras.lang.typescript" },
    { import = "lazyvim.plugins.extras.lang.json" },
    { import = "lazyvim.plugins.extras.lang.yaml" },
    { import = "lazyvim.plugins.extras.lang.docker" },
    { import = "lazyvim.plugins.extras.lang.markdown" },
    { import = "lazyvim.plugins.extras.lang.tailwind" },
    { import = "lazyvim.plugins.extras.lang.sql" },
    -- { import = "lazyvim.plugins.extras.lang.prisma" },

    { import = "lazyvim.plugins.extras.linting.eslint" },
    { import = "lazyvim.plugins.extras.formatting.prettier" },

    { import = "plugins" },
  },
  defaults = {
    lazy = false,
    version = false, -- always use the latest git commit, pinned by lazy-lock.json
  },
  install = { colorscheme = { "xcodedark", "habamax" } },
  -- Updates are deliberate: `:Lazy update` -> test -> commit lazy-lock.json.
  checker = { enabled = false },
  change_detection = { notify = false },
  performance = {
    rtp = {
      disabled_plugins = {
        "gzip",
        "tarPlugin",
        "tohtml",
        "tutor",
        "zipPlugin",
      },
    },
  },
})
