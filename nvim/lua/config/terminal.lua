-- Terminal capability detection.
--
-- Neovim cannot ask a terminal what it supports, so this guesses from the
-- environment and lets the user override the guess. Everything here is pure:
-- no side effects, so it can be required from options.lua, from plugin specs
-- and from tests.

local M = {}

--- Darwin kernel major version (25 == macOS 26). 0 when not on macOS.
---@return integer
function M.darwin_major()
  local uname = (vim.uv or vim.loop).os_uname()
  if uname.sysname ~= "Darwin" then
    return 0
  end
  return tonumber(uname.release:match("^(%d+)")) or 0
end

--- Does the terminal render 24-bit colour?
---
--- Overridable with NVIM_TRUECOLOR=1 / NVIM_TRUECOLOR=0.
---@return boolean
function M.truecolor()
  local override = vim.env.NVIM_TRUECOLOR
  if override == "1" then
    return true
  elseif override == "0" then
    return false
  end

  local colorterm = (vim.env.COLORTERM or ""):lower()
  if colorterm == "truecolor" or colorterm == "24bit" then
    return true
  end

  -- The Linux virtual console has 16 colours and nothing more.
  if vim.env.TERM == "linux" then
    return false
  end

  -- Terminal.app only grew 24-bit colour in macOS 26 (Darwin 25). Before that
  -- it silently quantises every hex colour to its 256-colour palette, which
  -- makes a GUI-only colourscheme look broken rather than merely different.
  if vim.env.TERM_PROGRAM == "Apple_Terminal" then
    return M.darwin_major() >= 25
  end

  return true
end

--- Is a Nerd Font available for icons?
---
--- Set NVIM_NO_NERD_FONT (to anything) to say no.
---@return boolean
function M.nerd_font()
  local override = vim.env.NVIM_NO_NERD_FONT
  return override == nil or override == ""
end

return M
