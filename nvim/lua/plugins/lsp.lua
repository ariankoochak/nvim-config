-- Shell tooling on top of the LazyVim defaults.
--
-- Everything for TypeScript/JavaScript/React/Next.js comes from the
-- `lang.typescript` extra (vtsls: JSX/TSX prop completion, auto-imports,
-- package import suggestions), JSON schemas from `lang.json` (SchemaStore) and
-- Tailwind class completion from `lang.tailwind` -- none of which needs
-- repeating here.

return {
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        -- bash-language-server; it shells out to shellcheck for diagnostics
        -- and to shfmt for formatting, both installed below.
        bashls = {},
      },
    },
  },

  {
    "mason-org/mason.nvim",
    -- `ensure_installed` is declared with opts_extend upstream, so this adds to
    -- the LazyVim list instead of replacing it.
    opts = {
      ensure_installed = {
        "shellcheck",
        "shfmt",
      },
    },
  },
}
