-- Loaded by LazyVim after lazyvim.config.autocmds.
--
-- The register-protection autocmds that Select mode needs live in
-- config/vscode.lua, next to the mappings they belong to.

local augroup = function(name)
  return vim.api.nvim_create_augroup("nvim_config_" .. name, { clear = true })
end

-- Explain the habamax fallback instead of leaving the user wondering why the
-- colourscheme looks nothing like the screenshots.
vim.api.nvim_create_autocmd("User", {
  group = augroup("truecolor_notice"),
  pattern = "VeryLazy",
  once = true,
  callback = function()
    if require("config.terminal").truecolor() then
      return
    end
    vim.schedule(function()
      vim.notify(
        "No 24-bit colour detected, so xcodedark is disabled and habamax is used instead.\n"
          .. "Override with NVIM_TRUECOLOR=1 if your terminal does support truecolor.",
        vim.log.levels.WARN,
        { title = "nvim-config" }
      )
    end)
  end,
})

-- dadbod's query output is a wide table; wrapping it makes it unreadable.
vim.api.nvim_create_autocmd("FileType", {
  group = augroup("dadbod"),
  pattern = { "dbout", "dbui" },
  callback = function()
    vim.opt_local.wrap = false
    vim.opt_local.spell = false
  end,
})
