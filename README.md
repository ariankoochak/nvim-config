# nvim-config

A LazyVim configuration for TypeScript/JavaScript, React and Next.js, Node,
Docker/YAML, Bash and PostgreSQL — plus a one-line installer that sets up a
matching environment on **Ubuntu** and **macOS**.

The headline feature is `lua/config/vscode.lua`: a set of VSCode-style editing
keys (`Ctrl+S`, `Ctrl+C`/`Ctrl+V`, line and word deletion, Shift-selection, word
jumps, line moves) that behave the way muscle memory expects, on both platforms,
from a single config.
On macOS the terminal layer translates `Cmd` to `Ctrl` so the Neovim side never
needs a platform switch.

> **Screenshot placeholder** — drop a `docs/screenshot.png` into the repo and
> uncomment the line below.
>
> <!-- ![nvim-config running in iTerm2](docs/screenshot.png) -->

---

## Contents

1. [Quick install](#quick-install)
2. [Requirements](#requirements)
3. [Neovim version policy](#neovim-version-policy)
4. [What the installer changes](#what-the-installer-changes)
5. [Keyboard shortcuts](#keyboard-shortcuts)
6. [Terminal setup](#terminal-setup)
7. [Truecolor and icons](#truecolor-and-icons)
8. [Known limitations](#known-limitations)
9. [Updating](#updating)
10. [Running the tests](#running-the-tests)
11. [Uninstalling](#uninstalling)
12. [Troubleshooting](#troubleshooting)

---

## Quick install

```bash
curl -fsSL https://raw.githubusercontent.com/ariankoochak/nvim-config/main/install.sh | bash
```

With flags:

```bash
# also set up zsh + oh-my-zsh + powerlevel10k
curl -fsSL .../install.sh | bash -s -- --with-shell

# skip the Nerd Font download
curl -fsSL .../install.sh | bash -s -- --no-fonts

# skip the macOS terminal integration
curl -fsSL .../install.sh | bash -s -- --no-terminal

# free up Ctrl+Left / Ctrl+Right on macOS (opt-in, needs a logout)
curl -fsSL .../install.sh | bash -s -- --macos-disable-space-shortcuts
```

The bootstrap clones the repo to `~/.nvim-config` (override with
`NVIM_CONFIG_DIR`) and hands over to `scripts/setup.sh`. After the first install
you can re-run it directly:

```bash
bash ~/.nvim-config/scripts/setup.sh --with-shell
```

### Flags

| Flag | Effect |
| --- | --- |
| `--with-shell` | Installs zsh (Ubuntu), oh-my-zsh and powerlevel10k, and on macOS with iTerm2 the Shell Integration that Automatic Profile Switching needs. Never runs `chsh` for you. |
| `--no-fonts` | Skips the JetBrainsMono Nerd Font download. |
| `--no-terminal` | Skips the macOS terminal integration (iTerm2 Dynamic Profile, Terminal.app profile). No effect on Linux. |
| `--macos-disable-space-shortcuts` | Disables the macOS Mission Control shortcuts bound to `Ctrl+Left`/`Ctrl+Right`. Opt-in only; requires logging out. |
| `--help` | Prints the flag list. |

Re-running is safe: every step checks before it acts, so a second run makes no
changes and adds no duplicate lines to your rc files.

---

## Requirements

The installer draws a hard line between what it installs and what it only
checks.

| | Ubuntu (apt) | macOS (Homebrew) |
| --- | --- | --- |
| **Installed for you** | `git` `curl` `unzip` `tar` `build-essential` `ripgrep` `fd-find` `postgresql-client` `xclip` `wl-clipboard` `fontconfig`; a `~/.local/bin/fd` shim for Debian's `fdfind`; the Nerd Font into `~/.local/share/fonts` | `ripgrep` `fd` `libpq`; the `font-jetbrains-mono-nerd-font` cask |
| **Installed only when missing** | Neovim (see the policy below), into `~/.local` without sudo | same |
| **Required, never installed** | Node.js ≥ 20 and npm | Homebrew; Node.js ≥ 20 and npm |
| **Checked and reported** | the `tree-sitter` CLI | the `tree-sitter` CLI |

**Node** is deliberately never installed — you manage it with your version
manager. If `node`/`npm` are missing or too old the installer warns loudly and
continues, but these will not be set up:

- the TypeScript/JavaScript language server (`vtsls`), `eslint`, `prettier`,
  `tailwindcss-language-server`, `bash-language-server`
- the `tree-sitter` CLI, which LazyVim installs through Mason as the npm package
  `tree-sitter-cli`. nvim-treesitter's `main` branch needs it for any grammar it
  has to generate from source.

Install Node and re-run `scripts/setup.sh` to pick them all up.

On macOS, `libpq` is keg-only, so `shell/env.sh` adds its `bin` directory to
`PATH` — that is where `psql` comes from.

---

## Neovim version policy

There is never a second Neovim on your PATH. The installer figures out which one
to use *before* changing anything.

| Situation | What happens |
| --- | --- |
| **No `nvim` found** | Downloads the official release tarball for the pinned version into `~/.local/share/nvim-dist/<asset>` and symlinks `~/.local/bin/nvim`. No sudo. |
| **`nvim` ≥ 0.11.2** | Used exactly as it is. Nothing is installed. If it is newer than the most recently tested release you get a *warning*, not an error. |
| **`nvim` < 0.11.2** | The installer **refuses** and exits. The error names the path, the detected version, the required version and an upgrade hint based on where the binary came from (snap / Homebrew / apt). Nothing on your system has been touched. |
| **Exception: an outdated `nvim` that this installer manages** | If `~/.local/bin/nvim` is our symlink into `~/.local/share/nvim-dist/`, it is upgraded in place instead of failing. |

Versions live in one place, [`versions.env`](versions.env):

| Variable | Meaning |
| --- | --- |
| `NVIM_MIN_VERSION` | LazyVim's minimum (`0.11.2`). Below this the installer refuses. |
| `NVIM_INSTALL_VERSION` | The release installed when no `nvim` exists (`v0.12.5`). |
| `NVIM_MAX_TESTED` | Highest tested feature release (`0.12`). Newer only warns. |
| `NODE_MIN_MAJOR` | Minimum Node major (`20`). Checked, never installed. |
| `NERD_FONT`, `NERD_FONT_VERSION` | Font family and nerd-fonts release. |

Every later step calls the absolute path the preflight picked, not a bare
`nvim`, because `PATH` inside a running script is not the `PATH` of your shell.
When the two differ, the closing summary tells you to open a new terminal.

---

## What the installer changes

| Path | What lands there |
| --- | --- |
| `~/.nvim-config` | The clone (override with `NVIM_CONFIG_DIR`). |
| `~/.config/nvim` | Symlink to `~/.nvim-config/nvim`. |
| `~/.local/share/nvim-dist/` | Only when Neovim had to be installed. |
| `~/.local/bin/nvim` | Only when Neovim had to be installed. |
| `~/.local/bin/fd` | Ubuntu only: symlink to `fdfind`. |
| `~/.local/share/fonts/JetBrainsMonoNerdFont/` | Ubuntu only, unless `--no-fonts`. |
| `~/.bashrc`, `~/.zshrc` | One guarded line sourcing `shell/env.sh`, added only if the file already exists. |
| `~/.oh-my-zsh`, `…/themes/powerlevel10k` | `--with-shell` only. |
| `~/.iterm2_shell_integration.zsh` | macOS + iTerm2 + `--with-shell`. |
| `~/Library/Application Support/iTerm2/DynamicProfiles/nvim-config.json` | macOS + iTerm2: a symlink to `terminal/macos/nvim-config.json`. |

### Backups

Anything in the way is moved aside, never deleted, as `<path>.bak.<timestamp>`.
On a **first** install the three Neovim state directories are backed up too, so
a previous configuration's plugin data cannot bleed into LazyVim's:

- `~/.local/share/nvim`
- `~/.local/state/nvim`
- `~/.cache/nvim`

Every backup made during a run is listed in the closing summary.

---

## Keyboard shortcuts

On macOS these keys are produced by the terminal layer: iTerm2 translates `Cmd`
into the control codes Neovim expects, while Terminal.app cannot remap `Cmd` at
all and therefore uses `Ctrl` directly, like Linux.

### VSCode-style editing

Every mapping below comes from [`nvim/lua/config/vscode.lua`](nvim/lua/config/vscode.lua).
`n` = normal, `i` = insert, `s` = select, `x` = visual.

| Action | Linux | macOS (iTerm2) | macOS (Terminal.app) | Modes |
| --- | --- | --- | --- | --- |
| Save, staying in the current mode | `Ctrl+S` | `Cmd+S` | `Ctrl+S` | n, i, x, s |
| Smart home — first non-blank, then column 0 | `Ctrl+←` | `Cmd+←` | `Ctrl+←` | n, i |
| End of line | `Ctrl+→` | `Cmd+→` | `Ctrl+→` | n, i |
| Word left / right (crosses lines) | `Alt+←` / `Alt+→` | `Option+←` / `Option+→` | `Option+←` / `Option+→` | n, i |
| Same, as the Terminal.app escape sequences | `Alt+B` / `Alt+F` | `Option+B` / `Option+F` | `Option+B` / `Option+F` | n, i |
| Select to smart line start / line end | `Ctrl+Shift+←` / `Ctrl+Shift+→` | `Cmd+Shift+←` / `Cmd+Shift+→` | `Ctrl+Shift+←` / `Ctrl+Shift+→` | n, i, s |
| Extend selection by a word | `Alt+Shift+←` / `Alt+Shift+→` | `Option+Shift+←` / `Option+Shift+→` | — (see limitations) | n, i, s |
| Collapse selection to its start / end | `←` / `→` | `←` / `→` | `←` / `→` | s |
| Collapse the selection, then move | `Ctrl+←/→`, `Alt+←/→` | `Cmd+←/→`, `Option+←/→` | `Ctrl+←/→`, `Option+←/→` | s |
| Copy the whole current line (linewise) | `Ctrl+C` | `Cmd+C` | `Ctrl+C` | i |
| Copy the selection, keeping it selected | `Ctrl+C` | `Cmd+C` | `Ctrl+C` | s, x |
| Paste | `Ctrl+V` | `Cmd+V` | `Ctrl+V` | i |
| Replace the selection with the clipboard, end in insert | `Ctrl+V` | `Cmd+V` | `Ctrl+V` | s |
| Delete the selection **without touching any register** | `Backspace` / `Delete` | `Backspace` / `Delete` | `Backspace` / `Delete` | s |
| Clear the entire current line **without touching any register** | `Ctrl+Backspace` | `Ctrl+Backspace` | `Ctrl+Backspace` | i |
| Delete the preceding word **without touching any register** | `Alt+Backspace` | `Option+Backspace` | `Option+Backspace` | i |
| Move the current line up / down, keeping the column | `Alt+↑` / `Alt+↓` | `Option+↑` / `Option+↓` | `Option+↑` / `Option+↓` | n, i |
| Move the selected line, keeping the selection | `Alt+↑` / `Alt+↓` | `Option+↑` / `Option+↓` | `Option+↑` / `Option+↓` | s |

Details worth knowing:

- **Selections use Select mode, not Visual mode.** Typing replaces the
  selection, exactly like VSCode.
- **Copying a line copies it linewise.** Pasting it back inserts it *above* the
  current line and your cursor stays on the line it was on — again like VSCode.
- **Saving an unnamed buffer prompts for a path.** `Ctrl+S` starts from the
  current working directory; cancelling leaves the buffer unchanged.
- **Overwriting a selection never touches your clipboard.** Vim normally yanks
  the replaced text into the unnamed register, which `clipboard=unnamedplus`
  forwards to the system clipboard. The registers are snapshotted on the way
  into Select mode and restored on the way out.
- **Word motions are UTF-8 aware.** Any byte ≥ 0x80 counts as a word character,
  so Persian, Cyrillic and CJK text jump and select by word rather than by byte.
- **Delete shortcuts preserve the clipboard.** `Ctrl+Backspace` clears the text
  in the current line (leaving an empty line), and `Alt+Backspace` removes the
  preceding word. Neither alters the unnamed, small-delete or system clipboard
  registers; `Alt+Backspace` uses the same UTF-8-aware word rules as word motion.
  The config accepts terminal encodings of `Ctrl+Backspace` as `Ctrl+H` or
  `Ctrl+Delete`, and `Alt+Backspace` as `Alt+Backspace` or `Alt+Delete`.

### Overridden defaults

These are deliberate. Nothing else is taken away.

| Key | What it used to do | What it does now |
| --- | --- | --- |
| `Ctrl+←` / `Ctrl+→` (normal) | LazyVim: shrink/grow window width | Smart home / end of line |
| `Ctrl+S` (insert) | Neovim: LSP signature help | Save (use `Ctrl+K` for signature help — LazyVim binds it) |
| `Ctrl+C` (insert) | Leave insert mode | Copy the current line (use `Esc` or `Ctrl+[` to leave insert) |
| `Ctrl+V` (insert) | Insert the next key literally | Paste (use `Ctrl+Q` for a literal key) |

`Ctrl+V` in **normal** mode is deliberately left alone, so Visual Block still
works.

### Useful LazyVim defaults

Leader is `Space`, local leader is `\`.

| Action | Keys | Modes |
| --- | --- | --- |
| Find files (project root) | `<leader><space>` or `<leader>ff` | n |
| Find files (cwd) | `<leader>fF` | n |
| Grep (project root) | `<leader>/` or `<leader>sg` | n |
| Grep (cwd) | `<leader>sG` | n |
| Word/selection under cursor | `<leader>sw` | n, x |
| File explorer (root / cwd) | `<leader>e` / `<leader>E` | n |
| Buffers | `<leader>,` or `<leader>fb` | n |
| Previous / next buffer | `Shift+H` / `Shift+L` | n |
| Delete buffer | `<leader>bd` | n |
| Go to definition / references | `gd` / `gr` | n |
| Go to implementation / type definition / declaration | `gI` / `gy` / `gD` | n |
| Hover docs | `K` | n |
| Signature help | `gK` (normal), `Ctrl+K` (insert) | n, i |
| Rename symbol / rename file | `<leader>cr` / `<leader>cR` | n |
| Code action | `<leader>ca` | n, x |
| Organize imports | `<leader>co` | n |
| Format | `<leader>cf` | n, x |
| Diagnostics list (Trouble) | `<leader>xx` | n |
| Lazygit | `<leader>gg` | n |
| Terminal | `Ctrl+/` (toggle), `<leader>ft` | n, t |
| Plugin manager / Mason | `<leader>l` / `<leader>cm` | n |
| Quit all | `<leader>qq` | n |

The top buffer tab bar stays visible when only one regular file is open, so the
current file is always represented there.

When you first open a regular file, or start Neovim with a directory path, a
10-line terminal split opens at the bottom and focus stays in the editor. The
dashboard remains terminal-free, and closing this split does not make it reopen
automatically.

Press `<leader>` and wait to see everything, courtesy of which-key.

### SQL

Provided by LazyVim's `lang.sql` extra (vim-dadbod + dadbod-ui + dadbod
completion), with the sqlfluff dialect changed to **postgres** in
[`nvim/lua/plugins/sql.lua`](nvim/lua/plugins/sql.lua).

| Action | Keys |
| --- | --- |
| Toggle the database UI | `<leader>D` |
| Run the query under the cursor / the selection | `<leader>S` (in a `.sql` buffer) |
| Add a connection interactively | `<leader>D`, then `Add connection` |
| Completion for tables and columns | automatic in `sql`, `mysql`, `plsql` buffers |

Connections come from one of two places, and **never** from this repository:

1. `$DATABASE_URL` — if it is set, it shows up in the UI as `DATABASE_URL`.
2. dadbod-ui's own storage, under `~/.local/share/nvim/dadbod_ui`.

For per-project connections, create a `.lazy.lua` in the project root and add it
to `.gitignore`:

```lua
vim.g.dbs = {
  { name = "dev", url = "postgresql://user:pass@localhost:5432/app" },
}
return {}
```

Queries do **not** run on save (`g:db_ui_execute_on_save = false`), so a large
query cannot lock up Neovim by accident.

---

## Terminal setup

### GNOME Terminal (Ubuntu)

1. *Preferences → your profile → Text → Custom font* → **JetBrainsMono Nerd Font
   Mono** (some pickers show it as *JetBrainsMono NFM*).
2. Nothing else is needed. GNOME Terminal sends `Alt` as Meta and passes
   `Ctrl+Arrow` and `Ctrl+Shift+Arrow` through unmodified.

> **Ubuntu gotcha:** if you have more than one keyboard layout, GNOME binds
> `Alt+Shift` to "switch layout", which eats `Alt+Shift+←/→`. Change it under
> *Settings → Keyboard → Input Sources → alternative switching shortcut*, or
> remove the second layout.

### iTerm2 (macOS)

The installer symlinks a **Dynamic Profile** into
`~/Library/Application Support/iTerm2/DynamicProfiles/`. Your own profiles are
never modified, and the new profile inherits everything (colours, window size,
transparency) from your default profile — it only overrides the font and the
keys below.

| In the profile | Sends |
| --- | --- |
| `Cmd+S` | hex `0x13` (`Ctrl+S`) |
| `Cmd+C` | hex `0x03` (`Ctrl+C`) |
| `Cmd+V` | hex `0x16` (`Ctrl+V`) |
| `Ctrl+Backspace` | hex `0x08` (`Ctrl+H`, clear current line) |
| `Cmd+←` / `Cmd+→` | `ESC [1;5D` / `ESC [1;5C` (`<C-Left>` / `<C-Right>`) |
| `Cmd+Shift+←` / `Cmd+Shift+→` | `ESC [1;6D` / `ESC [1;6C` (`<C-S-Left>` / `<C-S-Right>`) |
| Left `Option` | `Esc+`, so `Option+Arrow`, `Option+Shift+Arrow` and `Option+↑/↓` arrive as Meta |

The profile activates through **Automatic Profile Switching**, bound to the
foreground job `nvim` (`"Bound Hosts": ["&nvim"]`), and reverts the moment you
leave Neovim. That is not a nicety: if `Cmd+C` sent `Ctrl+C` globally, it would
send `SIGINT` at your shell prompt.

APS requires **iTerm2 Shell Integration**, which `--with-shell` installs. It is
loaded with `ITERM2_SQUELCH_MARK=1` so it does not fight powerlevel10k over the
prompt string. Restart iTerm2 once after installing so it picks up the profile.

> **Limitation:** inside `ssh` the foreground job is `ssh`, not `nvim`, so the
> profile does not switch. Use `Ctrl` on the remote side.

To change the font size, edit the `"Normal Font"` value in
[`terminal/macos/nvim-config.json`](terminal/macos/nvim-config.json) — it is
`"<PostScript name> <size>"`, e.g. `JetBrainsMonoNFM-Regular 14`.

### Terminal.app (macOS)

Terminal.app can neither remap `Cmd` keys nor switch profiles per program, so
**`Ctrl` is used there**, exactly as on Linux.
[`terminal/macos/nvim-config.terminal`](terminal/macos/nvim-config.terminal) is
imported for you and turns on *Use Option as Meta key*.

Two things are manual, on purpose:

1. **The font.** Terminal.app stores fonts as an `NSKeyedArchiver` blob, which
   cannot be generated reliably off a Mac, and a guessed blob would be worse
   than none. Set it by hand: *Terminal → Settings → Profiles → nvim-config →
   Text → Font…* → **JetBrainsMono Nerd Font Mono**.
2. **Making it the default**, if you want it: select the profile and click
   *Default*.

`Alt+Shift+Arrow` is not available under Terminal.app — see
[Known limitations](#known-limitations).

### Mission Control (macOS)

macOS binds `Ctrl+←` and `Ctrl+→` to "Move left/right a space", and the system
wins before any terminal sees the key. Either clear them in *System Settings →
Keyboard → Keyboard Shortcuts → Mission Control*, or let the installer do it:

```bash
bash ~/.nvim-config/scripts/setup.sh --macos-disable-space-shortcuts
```

That disables symbolic hotkeys 79, 80, 81 and 82 (after exporting a backup of
`com.apple.symbolichotkeys` to your home directory) and asks you to log out. It
is opt-in and never runs by default. Under iTerm2 you can skip it entirely and
use `Cmd+←/→` instead.

### tmux

tmux swallows modified keys unless you tell it not to:

```tmux
set -g default-terminal "tmux-256color"
set -ga terminal-overrides ",*256col*:Tc"
set -s extended-keys on
set -as terminal-features 'xterm*:extkeys'
```

---

## Truecolor and icons

The colourscheme is [`fraeso/xcodedark.nvim`](https://github.com/fraeso/xcodedark.nvim),
which defines **GUI colours only**. Without 24-bit colour it does not degrade,
it breaks — so [`nvim/lua/config/terminal.lua`](nvim/lua/config/terminal.lua)
detects support and falls back to the built-in `habamax` when there is none.

Detection, in order:

1. `NVIM_TRUECOLOR=1` or `NVIM_TRUECOLOR=0` — your answer wins.
2. `COLORTERM=truecolor` or `COLORTERM=24bit` → yes.
3. `TERM=linux` (the Linux virtual console) → no.
4. `TERM_PROGRAM=Apple_Terminal` → yes only on macOS 26 or newer (Darwin ≥ 25);
   older Terminal.app quantises every hex colour to its 256-colour palette.
5. Otherwise → yes.

| Variable | Effect |
| --- | --- |
| `NVIM_TRUECOLOR=1` | Force truecolor on (and with it `termguicolors` and xcodedark). |
| `NVIM_TRUECOLOR=0` | Force it off; `habamax` is used and `termguicolors` stays off. |
| `NVIM_NO_NERD_FONT=1` | Tell plugins there is no Nerd Font (`vim.g.have_nerd_font = false`). |

When the fallback kicks in, Neovim says so once at startup rather than leaving
you to wonder why nothing looks like the screenshot.

---

## Known limitations

- **Shift-selection is single-line.** `Ctrl+Shift+Arrow` and `Alt+Shift+Arrow`
  stop at the start and end of the current line. Use `v`/`V` for multi-line
  selections.
- **`Cmd` keys only work in iTerm2**, and not over `ssh` (the foreground job is
  `ssh`, so Automatic Profile Switching does not fire). Terminal.app users use
  `Ctrl` everywhere.
- **`Alt+Shift+Arrow` does not reach Neovim from Terminal.app.** Terminal.app's
  Meta handling does not produce a distinct sequence for Option+Shift+Arrow.
  Select by word in iTerm2, or use `Ctrl+Shift+Arrow` and then shrink with
  `Alt+Shift+Arrow`… which is the same problem. In Terminal.app, fall back to
  Visual mode.
- **`Ctrl+C` no longer leaves insert mode.** Use `Esc` or `Ctrl+[`.
- **Normal-mode `Ctrl+→` stops on the last character**, not after it: Vim's
  normal-mode cursor sits *on* a character and cannot sit past the end of a
  line. In insert mode it goes to the true end.

---

## Updating

### Plugins

Updates are deliberate — `checker` is disabled, so Neovim never nags you.

```
:Lazy update      # inside Neovim
```

then use the editor for a while, and when you are happy:

```bash
cd ~/.nvim-config
git add nvim/lazy-lock.json
git commit -m "chore: update plugins"
```

The installer only ever runs `:Lazy! restore`, never `:Lazy sync`, so a fresh
machine reproduces exactly the commits in `nvim/lazy-lock.json`.

> The committed `lazy-lock.json` was generated with Neovim `v0.12.5`. LazyVim
> pins `nvim-treesitter` to a different commit on Neovim 0.11.x, so if you run
> 0.11 you may see a difference after the first `:Lazy restore`. Verify and
> regenerate it on your own machine before committing.

`nvim/lazyvim.json` is committed too. Its `extras` list is empty on purpose —
extras are imported in [`nvim/lua/config/lazy.lua`](nvim/lua/config/lazy.lua),
not through `:LazyExtras`, so the repo alone decides what is enabled.
`install_version` is what pins LazyVim's own defaults (the snacks picker and
explorer rather than fzf and neo-tree). LazyVim keeps a hash of its `NEWS.md` in
the same file, so the file changes whenever upstream ships a changelog entry —
commit that or discard it, it makes no difference to how anything behaves.

### The installer

```bash
cd ~/.nvim-config && git pull
bash scripts/setup.sh          # or re-run the curl one-liner
```

---

## Running the tests

See [`test/README.md`](test/README.md) for the details.

```bash
# VSCode-key behaviour, mappings only (fast, no plugins)
./test/keymaps/run.sh

# the same suite against the real LazyVim config, in an isolated XDG home
./test/keymaps/run.sh --full

# installer scenarios, each in its own Docker container
./test/install/run.sh
./test/install/run.sh 02        # just the "Neovim too old" scenario

# a headless smoke test of the installed config (colourscheme, extras, mappings)
nvim --headless -c "luafile test/verify-config.lua"

# linting
shellcheck -x -S style install.sh scripts/*.sh shell/env.sh
stylua --config-path nvim/stylua.toml --check nvim test/keymaps test/verify-config.lua
```

The keymap tests never read or write your real `~/.config`, `~/.local` or rc
files; the installer tests run only inside containers.

---

## Uninstalling

```bash
# 1. the config symlink (restore a backup if you had one)
rm ~/.config/nvim
# ls -d ~/.config/nvim.bak.*   and mv it back if you want the old one

# 2. plugin data, state and cache
rm -rf ~/.local/share/nvim ~/.local/state/nvim ~/.cache/nvim

# 3. the Neovim this installer put there (only if it did)
rm -rf ~/.local/share/nvim-dist ~/.local/bin/nvim

# 4. the shell line
#    remove the line containing "nvim-config" from ~/.bashrc and ~/.zshrc

# 5. macOS only
rm -f ~/Library/"Application Support"/iTerm2/DynamicProfiles/nvim-config.json
#    and delete the "nvim-config" profile in Terminal.app's settings
#    if you used --macos-disable-space-shortcuts, re-enable the Mission Control
#    shortcuts in System Settings, or restore the exported
#    ~/com.apple.symbolichotkeys.plist.bak.* with: defaults import com.apple.symbolichotkeys <file>

# 6. the repo itself
rm -rf ~/.nvim-config
```

`--with-shell` leaves oh-my-zsh and powerlevel10k behind on purpose; remove them
with `~/.oh-my-zsh/tools/uninstall.sh` if you want them gone.

---

## Troubleshooting

### The clipboard does not reach the system (Linux or ssh)

```
:checkhealth vim.provider
```

On a desktop you want `xclip` (X11) or `wl-clipboard` (Wayland); the installer
adds both. Over `ssh`, LazyVim deliberately leaves `clipboard` empty and relies
on OSC 52 — your terminal has to support it (iTerm2 does; GNOME Terminal does
not). Yanks still land in Neovim's own registers either way.

### Icons are boxes or question marks

The font in your *terminal* is what matters, not anything in Neovim. Pick
**JetBrainsMono Nerd Font Mono** in the terminal's settings, then check:

```bash
fc-list | grep -i 'JetBrainsMono'       # Linux
ls ~/Library/Fonts | grep -i JetBrains  # macOS
```

If you cannot install a Nerd Font, start Neovim with `NVIM_NO_NERD_FONT=1`.

### A key does nothing in Neovim

First find out whether it reaches the terminal at all. In a shell:

```bash
cat -v
# press the key; Ctrl+Left should print ^[[1;5D, Alt+Left ^[[1;3D or ^[b
```

Then whether it reaches Neovim: open `nvim`, press `i`, then `Ctrl+V` in **plain
Vim** (`vim -u NONE`) — in this config insert-mode `Ctrl+V` is paste, so use
`Ctrl+Q` here — followed by the key. Nothing appearing means the terminal, the
window manager or macOS swallowed it.

Common culprits:

| Symptom | Cause |
| --- | --- |
| `Ctrl+←/→` does nothing on macOS | Mission Control — see [Mission Control](#mission-control-macos) |
| `Alt+Shift+←/→` switches keyboard layout on Ubuntu | GNOME's layout-switch shortcut |
| `Cmd` keys do nothing in iTerm2 | Shell Integration missing, so Automatic Profile Switching never activates the profile; or iTerm2 was not restarted |
| Modified keys are lost inside tmux | `extended-keys` not enabled — see [tmux](#tmux) |

### `:checkhealth` complains about the tree-sitter CLI

Install Node ≥ 20 and re-run `bash ~/.nvim-config/scripts/setup.sh`; LazyVim
installs `tree-sitter-cli` through Mason, which needs npm.

### Markdown preview does not open

Its build hook downloads a binary through a terminal job that a headless Neovim
cannot run. The installer handles this, but if it was skipped:

```
:Lazy build markdown-preview.nvim
```

### Neovim starts but looks wrong / plugins are missing

```
:Lazy            # check for failed installs
:Lazy restore    # go back to the committed lockfile
:checkhealth
```

---

## Licence

[MIT](LICENSE)
