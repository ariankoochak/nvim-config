-- Loaded by LazyVim *after* lazyvim.config.options, so these win.
--
-- Everything else is intentionally left at the LazyVim default.

local term = require("config.terminal")

-- LazyVim sets termguicolors unconditionally. On a terminal without 24-bit
-- colour that turns every GUI-only colourscheme into mush, so let the detected
-- capability decide instead. plugins/colorscheme.lua reads the same value and
-- falls back to habamax when this is false.
vim.opt.termguicolors = term.truecolor()

-- Advisory flag, read by plugins that offer an ASCII fallback.
vim.g.have_nerd_font = term.nerd_font()
