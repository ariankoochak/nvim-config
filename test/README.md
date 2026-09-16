# Tests

Two suites. Neither one reads or writes your real configuration.

| Suite | What it proves | Needs |
| --- | --- | --- |
| [`keymaps/`](keymaps) | `nvim/lua/config/vscode.lua` behaves like VSCode | `nvim` on PATH |
| [`install/`](install) | the installer does the right thing on a real machine | Docker |
| [`verify-config.lua`](verify-config.lua) | the installed config actually loads: extras, colourscheme, mappings, sqlfluff dialect | an installed config |

---

## Keymap tests

```bash
./test/keymaps/run.sh          # mappings only, no plugins  (a few seconds)
./test/keymaps/run.sh --full   # the same spec against the real LazyVim config
```

### How it works, and why

The obvious approach — `nvim_feedkeys(keys, "x!", …)` in a headless Neovim —
**deadlocks** the moment a mapping leaves the editor in Insert mode: the `x`
flag asks Neovim to run the keys to completion, and Insert mode never
"completes". So the suite drives a real editor from the outside instead:

1. `run.sh` starts `nvim --headless --listen <socket>`.
2. `spec.lua` runs in a *second* Neovim (`nvim -l`) and connects to that socket
   with `sockconnect(… { rpc = true })`.
3. Keys go in with `nvim_input` followed by a short sleep — `nvim_input` only
   queues them, there is no synchronous "and now run them" call.
4. Assertions come back through `nvim_exec_lua`.

`keymaps/init.lua` loads nothing but `config/vscode.lua`, with `clipboard=""` so
a real X11/Wayland clipboard provider cannot rewrite `"+` behind the tests'
back. A failure there is a failure in the mappings, not in something around
them.

`--full` runs the identical spec against `nvim/init.lua` in a throwaway
`XDG_CONFIG_HOME`/`XDG_DATA_HOME`/… under `/tmp`. Two things make that work:

- the config is **copied** into the temporary `XDG_CONFIG_HOME`, not symlinked:
  your own `~/.config/nvim` is never touched, and lazy.nvim -- which rewrites
  `lazy-lock.json` inside `stdpath("config")` whenever it installs something --
  cannot write into the repo during a test run;
- headless Neovim never fires `UIEnter`, which is what lazy.nvim uses to trigger
  `User VeryLazy` — and LazyVim loads `lua/config/keymaps.lua` (and therefore
  our mappings) on that event. `keymaps/full-init.lua` fires it by hand.

The first `--full` run clones every plugin, which takes a while. Point
`NVIM_TEST_SHARE_DATA` at an already-populated `XDG_DATA_HOME` to reuse one.

### Coverage

Selection building and shrinking, empty selections returning to Insert,
selecting from the end of a line, typing and `<BS>` over a selection (including
that neither touches the registers), copy keeping the selection, `<Left>`/
`<Right>` collapsing, paste over a selection, linewise copy/paste-above with the
cursor staying on its line, charwise paste at end of line, line moves in Normal,
Insert and Select mode, the smart-home toggle, `<C-s>` staying in Insert and
actually writing the file, word jumps wrapping across lines, the `<M-b>`/`<M-f>`
aliases, Persian (multi-byte) word selection and replacement, and starting a
selection from Normal mode.

---

## Installer tests

```bash
./test/install/run.sh          # every scenario
./test/install/run.sh 02 04    # only these
```

Each scenario gets a fresh container built from
[`install/Dockerfile`](install/Dockerfile): Ubuntu 24.04 with `curl`,
`ca-certificates` and `sudo`, a non-root user with a real `.bashrc`, and Node
from the official tarball — because the installer must *find* a Node, never
install one.

| Scenario | Asserts |
| --- | --- |
| `01-clean-ubuntu` | Neovim lands in `~/.local`, the config is linked, the rc line is added, LazyVim loads headlessly, the colourscheme resolves to `xcodedark`, the mappings are live, and `:checkhealth` reports no error for lazy.nvim, Mason, treesitter or LSP. |
| `02-old-neovim` | With Ubuntu's own (too old) `neovim` installed, the installer exits non-zero; the message names the path, the version, the requirement, an apt-specific hint and the sentence "Nothing has been changed on your system"; and **nothing** was created — no `~/.config/nvim`, no `~/.local/...`, and a byte-identical `~/.bashrc`. |
| `03-rerun` | A second run leaves `~/.bashrc` byte-identical with exactly one env line, the same symlinks, no new `*.bak.*`, and an unmodified `lazy-lock.json`. |
| `04-newer-neovim` | With a newer Neovim already in `/usr/local`, nothing lands in `~/.local/share/nvim-dist`, no managed symlink is created, the summary says the existing one was reused, and the plugins were installed with it. |

Scenario 2 is the one that matters most: it is the executable version of the
promise that a failed install leaves the machine untouched.

---

## Config smoke test

```bash
nvim --headless -c "luafile test/verify-config.lua"
```

Run against a config that is already installed (or through an isolated
`XDG_CONFIG_HOME`, as CI and scenario 1 do). It checks that lazy.nvim is set up,
that every extra was imported, that the colourscheme resolves to the right one
for the detected terminal, that the VSCode mappings are live in every mode they
claim, that `bashls` and the shell tooling are configured, that sqlfluff uses
the `postgres` dialect, and that the update checker stays off.

It exists as a script rather than a chain of `-c 'lua assert(...)'` for one
reason: **a failing `assert` inside `-c` prints an error and lets Neovim carry
on to `qa`, so the process still exits 0.** A CI step built that way is green no
matter what breaks. This script does its own bookkeeping and calls `cquit`.

---

## Linting

```bash
shellcheck -x -S style install.sh scripts/*.sh shell/env.sh \
  test/keymaps/run.sh test/install/run.sh test/install/lib.sh \
  test/install/scenarios/*.sh
stylua --config-path nvim/stylua.toml --check nvim test/keymaps test/verify-config.lua
```

Both run in CI on every push, together with the keymap suite and a real
installer run on `ubuntu-latest` and `macos-latest`.
