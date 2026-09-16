-- Init for the "against the real config" run of the same spec.
--
-- The real nvim/init.lua is loaded through XDG_CONFIG_HOME (see run.sh), so all
-- this does is fire the events a headless Neovim never fires by itself.
-- LazyVim loads lua/config/keymaps.lua -- and therefore our mappings -- on
-- User VeryLazy, which lazy.nvim triggers from UIEnter. Headless has no UI.

vim.api.nvim_exec_autocmds("User", { pattern = "VeryLazy", modeline = false })

vim.opt.clipboard = ""
vim.opt.swapfile = false
vim.opt.timeoutlen = 200
vim.opt.ttimeoutlen = 20
