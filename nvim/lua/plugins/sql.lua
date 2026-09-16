-- SQL / PostgreSQL.
--
-- The heavy lifting is already done by LazyVim's `lang.sql` extra, which pulls
-- in vim-dadbod, vim-dadbod-ui and vim-dadbod-completion, registers the
-- `dadbod` provider as a blink.cmp source for sql/mysql/plsql, adds the `sql`
-- treesitter parser, wires the edgy layout and installs sqlfluff through Mason.
-- None of that is repeated here -- only the two things the extra gets wrong for
-- a PostgreSQL user:
--
--   * sqlfluff defaults to the `ansi` dialect, which flags perfectly valid
--     Postgres as a parse error;
--   * connections have to come from somewhere, and that somewhere must not be
--     this repository. `$DATABASE_URL` and dadbod-ui's own saved connections
--     (<leader>D -> "Add connection") are the two supported routes. No
--     credentials are stored here.

return {
  {
    "tpope/vim-dadbod",
    optional = true,
    init = function()
      local url = vim.env.DATABASE_URL
      if not url or url == "" then
        return
      end
      -- Prepend, so a project-local `.lazy.lua` that sets vim.g.dbs itself
      -- still wins on name collisions.
      local dbs = vim.g.dbs or {}
      table.insert(dbs, 1, { name = "DATABASE_URL", url = url })
      vim.g.dbs = dbs
    end,
  },

  {
    "stevearc/conform.nvim",
    optional = true,
    opts = function(_, opts)
      opts.formatters = opts.formatters or {}
      opts.formatters.sqlfluff = { args = { "format", "--dialect=postgres", "-" } }
    end,
  },

  {
    "mfussenegger/nvim-lint",
    optional = true,
    -- `opts.linters` is a LazyVim extension that deep-merges into
    -- `require("lint").linters`. The full arg list is spelled out rather than
    -- using `prepend_args`, because sqlfluff only accepts --dialect *after*
    -- the subcommand.
    opts = {
      linters = {
        sqlfluff = { args = { "lint", "--format=json", "--dialect=postgres", "-" } },
      },
    },
  },
}
