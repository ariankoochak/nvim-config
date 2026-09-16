-- Minimal init for the keymap test server.
--
-- Loads nothing but nvim/lua/config/vscode.lua: no LazyVim, no plugins, so a
-- failure here is a failure in the mappings and not in something around them.
--
-- Started as:
--   nvim --headless --clean -u test/keymaps/init.lua --listen <socket>

local this = debug.getinfo(1, "S").source:sub(2)
local root = vim.fn.fnamemodify(this, ":p:h:h:h")

vim.opt.runtimepath:prepend(root .. "/nvim")

-- The tests assert on register contents, so the system clipboard must stay out
-- of it: an X/Wayland provider would happily rewrite "+ behind our back.
vim.opt.clipboard = ""
vim.opt.swapfile = false
vim.opt.shadafile = "NONE"
vim.opt.termguicolors = false

-- Long enough that a multi-byte key sequence is never split, short enough that
-- the suite does not crawl.
vim.opt.timeoutlen = 200
vim.opt.ttimeoutlen = 20

require("config.vscode").setup()
