-- Colourscheme: fraeso/xcodedark.nvim, with a habamax fallback.
--
-- Three things about this plugin shape the spec below (all verified against its
-- source, lua/xcodedark/init.lua):
--
--  1. `setup(opts)` just forwards to `load(opts)`: it applies the theme
--     immediately and stores nothing. `:colorscheme xcodedark` therefore
--     re-runs `load()` with *defaults*, silently discarding anything passed
--     through lazy.nvim's `opts`. So: no `opts`, an empty `config`, and the
--     options are handed to `load()` at the moment LazyVim asks for a theme.
--  2. It defines GUI colours only -- no cterm equivalents -- so on a terminal
--     without truecolour it does not degrade, it breaks.
--  3. It sets `vim.g.colours_name` (British spelling, a typo upstream) instead
--     of `vim.g.colors_name`, which is the variable everything else reads.

local opts = {
  transparent = false,
  terminal_colors = true,
  integrations = {
    telescope = true,
    nvim_tree = true,
    gitsigns = true,
    bufferline = true,
    incline = true,
    lazygit = true,
    which_key = true,
    notify = true,
    snacks = true,
    blink = true,
  },
}

return {
  {
    "fraeso/xcodedark.nvim",
    lazy = false,
    priority = 1000,
    config = function() end,
  },

  {
    "LazyVim/LazyVim",
    opts = {
      colorscheme = function()
        if not require("config.terminal").truecolor() then
          vim.cmd.colorscheme("habamax")
          return
        end
        require("xcodedark").load(opts)
        vim.g.colors_name = "xcodedark"
      end,
    },
  },
}
