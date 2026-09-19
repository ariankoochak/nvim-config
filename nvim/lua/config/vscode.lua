--- VSCode-style editing keys.
---
--- Goal: an editor that reacts to the keys a VSCode user already has in their
--- fingers, on Linux and macOS, with one config. On macOS the terminal layer
--- (scripts/terminal.sh) translates Cmd into Ctrl, so everything below is
--- expressed in Ctrl/Meta and nothing here is platform specific.
---
--- The model
--- ---------
--- VSCode's cursor is a *boundary*: a position between two characters,
--- expressed here as a byte column in `0 .. #line`. Vim's visual selection is
--- inclusive of the character under the cursor, so boundaries are converted to
--- Vim positions only at the very edges, in `selection_keys()`.
---
--- Selections are shown in Select mode, not Visual mode, so that typing
--- replaces the selection the way it does in VSCode.
---
--- Known limitation: Ctrl/Alt + Shift selections are single-line. They stop at
--- the start and the end of the current line.

local M = {}

local api = vim.api
local fn = vim.fn

--- Anchor/cursor of the selection this module built, as boundaries.
--- Validated against Vim's own idea of the selection on every use; see
--- `current_state()`.
---@type { row: integer?, anchor: integer?, cursor: integer? }
M.state = { row = nil, anchor = nil, cursor = nil }

--- Snapshot of the registers Select mode is allowed to clobber.
---@type table?
M._regs = nil

--------------------------------------------------------------------------
-- Buffer / position helpers
--------------------------------------------------------------------------

---@param row integer 1-based
---@return string
local function get_line(row)
  return api.nvim_buf_get_lines(0, row - 1, row, false)[1] or ""
end

local function last_row()
  return api.nvim_buf_line_count(0)
end

--- Current row and boundary column.
---@return integer row, integer col
local function get_pos()
  local pos = api.nvim_win_get_cursor(0)
  return pos[1], pos[2]
end

--- Save the current buffer, asking where to save an unnamed file.
function M.save()
  local buf = api.nvim_get_current_buf()
  if api.nvim_buf_get_name(buf) ~= "" or vim.bo[buf].buftype ~= "" then
    vim.cmd("silent! update")
    return
  end

  vim.ui.input({
    prompt = "Save as: ",
    default = fn.getcwd(0) .. "/",
    completion = "file",
  }, function(path)
    if not path or path:match("^%s*$") then
      return
    end

    path = fn.fnamemodify(fn.expand(path), ":p")
    if fn.isdirectory(path) == 1 then
      return
    end

    vim.schedule(function()
      if api.nvim_buf_is_valid(buf) then
        api.nvim_buf_call(buf, function()
          vim.cmd("silent! saveas " .. fn.fnameescape(path))
        end)
      end
    end)
  end)
end

--- Byte length of the UTF-8 character starting at `col`.
---@param line string
---@param col integer
---@return integer
local function char_len(line, col)
  local b = line:byte(col + 1)
  if not b then
    return 0
  end
  if b >= 0xF0 then
    return 4
  elseif b >= 0xE0 then
    return 3
  elseif b >= 0xC0 then
    return 2
  end
  return 1
end

--- Start byte of the UTF-8 character that ends at boundary `col`.
---@param line string
---@param col integer
---@return integer
local function prev_char_start(line, col)
  if col <= 0 then
    return 0
  end
  local i = col - 1
  while i > 0 do
    local b = line:byte(i + 1)
    if b < 0x80 or b >= 0xC0 then
      break
    end
    i = i - 1
  end
  return i
end

--------------------------------------------------------------------------
-- Word motion
--------------------------------------------------------------------------

local WS, WORD, PUNCT = 0, 1, 2

--- Character class at boundary `col`.
--- Any byte >= 0x80 counts as a word character, so Persian, Cyrillic, CJK and
--- accented Latin text behave like words rather than like punctuation.
---@return integer?
local function class_at(line, col)
  local b = line:byte(col + 1)
  if not b then
    return nil
  end
  if b >= 0x80 then
    return WORD
  end
  local ch = string.char(b)
  if ch:match("%s") then
    return WS
  end
  if ch:match("[%w_]") then
    return WORD
  end
  return PUNCT
end

--- Skip whitespace, then consume one run of a single class.
local function word_right(line, col)
  local n = #line
  while col < n and class_at(line, col) == WS do
    col = col + char_len(line, col)
  end
  if col >= n then
    return n
  end
  local class = class_at(line, col)
  while col < n and class_at(line, col) == class do
    col = col + char_len(line, col)
  end
  return col
end

--- Mirror image of `word_right`.
local function word_left(line, col)
  while col > 0 do
    local prev = prev_char_start(line, col)
    if class_at(line, prev) ~= WS then
      break
    end
    col = prev
  end
  if col <= 0 then
    return 0
  end
  local class = class_at(line, prev_char_start(line, col))
  while col > 0 do
    local prev = prev_char_start(line, col)
    if class_at(line, prev) ~= class then
      break
    end
    col = prev
  end
  return col
end

--- VSCode's Home: first non-blank, or column 0 when already there.
local function smart_home(line, col)
  local first = #(line:match("^%s*") or "")
  if col == first then
    return 0
  end
  return first
end

--- Word motion that may step onto the neighbouring line, like VSCode does.
---@return integer row, integer col
local function move_word_right(row, col, cross)
  local line = get_line(row)
  if col >= #line then
    if cross and row < last_row() then
      return row + 1, word_right(get_line(row + 1), 0)
    end
    return row, #line
  end
  return row, word_right(line, col)
end

---@return integer row, integer col
local function move_word_left(row, col, cross)
  if col <= 0 then
    if cross and row > 1 then
      local line = get_line(row - 1)
      return row - 1, word_left(line, #line)
    end
    return row, 0
  end
  return row, word_left(get_line(row), col)
end

--- Applies one of the four motions to a boundary.
---@param kind "home"|"end"|"wordleft"|"wordright"
---@return integer row, integer col
local function apply_motion(kind, row, col, cross)
  local line = get_line(row)
  if kind == "home" then
    return row, smart_home(line, col)
  elseif kind == "end" then
    return row, #line
  elseif kind == "wordleft" then
    return move_word_left(row, col, cross)
  end
  return move_word_right(row, col, cross)
end

--------------------------------------------------------------------------
-- Cursor placement
--------------------------------------------------------------------------

--- Place the cursor on a boundary. In Normal mode a boundary at the end of the
--- line is not representable, so it is clamped to the last character.
local function set_cursor(row, col, insert)
  row = math.max(1, math.min(row, last_row()))
  local line = get_line(row)
  local max_col = #line
  if not insert and max_col > 0 then
    max_col = prev_char_start(line, #line)
  end
  col = math.max(0, math.min(col, max_col))
  pcall(api.nvim_win_set_cursor, 0, { row, col })
end

--- Enter Insert mode with the cursor *at* the given boundary.
---
--- `startinsert` puts the cursor before the character it is on, which cannot
--- express "after the last character" -- that needs `startinsert!`.
---@param row integer
---@param col integer
function M.enter_insert(row, col)
  row = math.max(1, math.min(row, last_row()))
  local line = get_line(row)
  col = math.max(0, math.min(col, #line))
  if col >= #line and #line > 0 then
    pcall(api.nvim_win_set_cursor, 0, { row, prev_char_start(line, #line) })
    vim.cmd("startinsert!")
  else
    pcall(api.nvim_win_set_cursor, 0, { row, col })
    vim.cmd("startinsert")
  end
end

--------------------------------------------------------------------------
-- Selection state
--------------------------------------------------------------------------

local function in_select_mode()
  local mode = fn.mode(1)
  return mode:sub(1, 1) == "s" or mode:sub(1, 1) == "S" or mode:sub(1, 1) == "\19"
end

--- Would the stored state reproduce exactly the selection Vim reports?
local function stored_matches(row, vcol, ccol)
  local state = M.state
  if state.row ~= row or not state.anchor or not state.cursor or state.anchor == state.cursor then
    return false
  end
  local line = get_line(row)
  local from, to
  if state.cursor > state.anchor then
    from, to = state.anchor, prev_char_start(line, state.cursor)
  else
    from, to = prev_char_start(line, state.anchor), state.cursor
  end
  return from == vcol and to == ccol
end

--- Anchor and cursor as boundaries, whatever mode we are in.
---
--- The stored state is preferred because it keeps the exact boundary the user
--- selected to; Vim's inclusive positions cannot express "the boundary after
--- the last character" on their own. When the stored state does not describe
--- the selection Vim actually has (someone moved it with other keys), it is
--- discarded and the state is derived from Vim instead.
---@return integer row, integer anchor, integer cursor
local function current_state()
  if in_select_mode() then
    local vpos, cpos = fn.getpos("v"), fn.getpos(".")
    local row = cpos[2]
    -- A multi-line selection is not something this module builds; collapse it.
    if vpos[2] ~= row then
      return row, cpos[3] - 1, cpos[3] - 1
    end
    local vcol, ccol = vpos[3] - 1, cpos[3] - 1
    if stored_matches(row, vcol, ccol) then
      return row, M.state.anchor, M.state.cursor
    end
    local line = get_line(row)
    if ccol >= vcol then
      return row, vcol, math.min(ccol + char_len(line, ccol), #line)
    end
    return row, math.min(vcol + char_len(line, vcol), #line), ccol
  end
  local row, col = get_pos()
  return row, col, col
end

local function forget_state()
  M.state = { row = nil, anchor = nil, cursor = nil }
end

--------------------------------------------------------------------------
-- Key sequences returned by the expr mappings
--------------------------------------------------------------------------

--- Keys that leave the current mode and enter Insert at a boundary.
local function enter_insert_keys(row, col)
  return ("<C-\\><C-n><Cmd>lua require('config.vscode').enter_insert(%d,%d)<CR>"):format(row, col)
end

--- Keys that build a Select-mode selection between two boundaries.
---
--- `v` starts on the anchor side so that the cursor ends up on the moving side,
--- which is what makes the next Shift+key extend rather than flip the
--- selection. `line` is the text the boundaries refer to, which is not
--- necessarily the text currently at `row` (see the line-move mappings).
local function selection_keys(row, line, anchor, cursor)
  local from, to
  if cursor > anchor then
    from, to = anchor + 1, prev_char_start(line, cursor) + 1
  else
    from, to = prev_char_start(line, anchor) + 1, cursor + 1
  end
  return ("<C-\\><C-n><Cmd>call cursor(%d,%d)<CR>v<Cmd>call cursor(%d,%d)<CR><C-g>"):format(row, from, row, to)
end

--------------------------------------------------------------------------
-- Clipboard
--------------------------------------------------------------------------

--- Write to both the unnamed and the system register.
---
--- `+` is wrapped: it simply does not exist without a clipboard provider (a
--- bare ssh session, a minimal container), and losing the copy entirely would
--- be worse than losing the *system* copy.
---@param lines string[]
---@param regtype string "v" or "V"
function M.set_clipboard(lines, regtype)
  fn.setreg('"', lines, regtype)
  pcall(fn.setreg, "+", lines, regtype)
  M.snapshot_registers()
end

--- Read the system register, falling back to the unnamed one.
---@return string[] lines, boolean linewise
local function get_clipboard()
  local text, regtype
  local ok, plus = pcall(fn.getreg, "+")
  if ok and plus and plus ~= "" then
    text, regtype = plus, fn.getregtype("+")
  else
    text, regtype = fn.getreg('"'), fn.getregtype('"')
  end
  text = text or ""
  local linewise = regtype:sub(1, 1) == "V"
  if linewise and text:sub(-1) == "\n" then
    text = text:sub(1, -2)
  end
  return vim.split(text, "\n", { plain = true }), linewise
end

--------------------------------------------------------------------------
-- Register protection
--------------------------------------------------------------------------
-- Typing over a Select-mode selection makes Vim yank the replaced text into the
-- unnamed register, and LazyVim's `clipboard=unnamedplus` forwards that to the
-- system clipboard. VSCode never touches the clipboard when you overwrite a
-- selection, so the registers are snapshotted on the way into Select mode and
-- put back on the way out.

function M.snapshot_registers()
  M._regs = {
    unnamed = { fn.getreg('"'), fn.getregtype('"') },
    delete = { fn.getreg("-"), fn.getregtype("-") },
  }
end

local function restore_registers()
  local regs = M._regs
  if not regs then
    return
  end
  if fn.getreg('"') ~= regs.unnamed[1] then
    fn.setreg('"', regs.unnamed[1], regs.unnamed[2])
  end
  if fn.getreg("-") ~= regs.delete[1] then
    fn.setreg("-", regs.delete[1], regs.delete[2])
  end
end

--------------------------------------------------------------------------
-- Actions
--------------------------------------------------------------------------

--- Insert mode Ctrl+C: copy the whole current line, linewise, like VSCode.
function M.copy_line()
  local row = get_pos()
  M.set_clipboard({ get_line(row) }, "V")
end

--- Select/Visual mode Ctrl+C: copy the selection and keep it selected.
function M.copy_selection()
  local mode = fn.mode(1):sub(1, 1)
  local regtype = "v"
  if mode == "S" or mode == "V" then
    regtype = "V"
  elseif mode == "\19" or mode == "\22" then
    regtype = "\22"
  end
  local lines = fn.getregion(fn.getpos("v"), fn.getpos("."), { type = regtype })
  M.set_clipboard(lines, regtype)
end

--- Insert mode Ctrl+V.
---
--- Linewise content is inserted *above* the current line and the cursor stays
--- on the line it was on, exactly like VSCode pasting a copied line. Charwise
--- content goes in at the cursor, which ends up after the pasted text.
---
--- `nvim_buf_set_text` rather than `nvim_put`: the latter misplaces text by one
--- column at the end of a line while in Insert mode.
function M.paste_insert()
  local lines, linewise = get_clipboard()
  local row, col = get_pos()
  if linewise then
    api.nvim_buf_set_lines(0, row - 1, row - 1, false, lines)
    set_cursor(row + #lines, col, true)
  else
    api.nvim_buf_set_text(0, row - 1, col, row - 1, col, lines)
    if #lines == 1 then
      set_cursor(row, col + #lines[1], true)
    else
      set_cursor(row + #lines - 1, #lines[#lines], true)
    end
  end
end

--- Replace `[start_col, end_col)` on `row` with the clipboard, then insert.
--- Called from the key sequence returned by the Select-mode Ctrl+V mapping,
--- once Select mode has already been left.
function M.paste_over(row, start_col, end_col)
  local lines, linewise = get_clipboard()
  local replacement = vim.deepcopy(lines)
  if linewise then
    -- A copied *line* keeps its line break when it replaces a selection.
    replacement[#replacement + 1] = ""
  end
  api.nvim_buf_set_text(0, row - 1, start_col, row - 1, end_col, replacement)
  if #replacement == 1 then
    M.enter_insert(row, start_col + #replacement[1])
  else
    M.enter_insert(row + #replacement - 1, #replacement[#replacement])
  end
end

--- Insert mode Ctrl+Backspace: clear the current line, like the requested
--- VSCode-style line delete. Uses the buffer API instead of a Vim delete
--- command, so this operation never overwrites the unnamed/delete registers.
function M.clear_line()
  local row = get_pos()
  api.nvim_buf_set_lines(0, row - 1, row, false, { "" })
  M.enter_insert(row, 0)
end

--- Insert mode Alt+Backspace: delete the preceding word, including whitespace
--- immediately before the cursor. This shares the UTF-8-aware word rules used
--- by Alt+Left, so Persian and other non-ASCII words are always kept intact.
--- The buffer API also keeps the clipboard and delete registers unchanged.
function M.delete_word_left()
  local row, col = get_pos()
  local start_row, start_col = move_word_left(row, col, true)
  if start_row == row and start_col == col then
    return
  end
  api.nvim_buf_set_text(0, start_row - 1, start_col, row - 1, col, { "" })
  M.enter_insert(start_row, start_col)
end

--- Move the current line up or down, keeping the cursor's column.
---@param dir -1|1
---@param insert boolean
function M.move_line(dir, insert)
  local row, col = get_pos()
  if (dir < 0 and row <= 1) or (dir > 0 and row >= last_row()) then
    return
  end
  local target = dir < 0 and (row - 2) or (row + 1)
  vim.cmd(("silent! %dmove %d"):format(row, target))
  set_cursor(row + dir, col, insert)
end

--------------------------------------------------------------------------
-- Mapping callbacks
--------------------------------------------------------------------------

--- Shift + motion: start or extend a Select-mode selection. Single line only.
---@param kind "home"|"end"|"wordleft"|"wordright"
local function shift_motion(kind)
  return function()
    local row, anchor, cursor = current_state()
    local line = get_line(row)
    local _, new_cursor = apply_motion(kind, row, cursor, false)
    if new_cursor == anchor then
      forget_state()
      return enter_insert_keys(row, new_cursor)
    end
    M.state = { row = row, anchor = anchor, cursor = new_cursor }
    return selection_keys(row, line, anchor, new_cursor)
  end
end

--- Plain motion in Normal/Insert mode.
local function plain_motion(kind, insert)
  return function()
    local row, col = get_pos()
    local new_row, new_col = apply_motion(kind, row, col, true)
    forget_state()
    set_cursor(new_row, new_col, insert)
  end
end

--- Plain motion in Select mode: collapse the selection onto its cursor end,
--- then move from there and return to Insert mode.
local function select_motion(kind)
  return function()
    local row, _, cursor = current_state()
    local new_row, new_col = apply_motion(kind, row, cursor, true)
    forget_state()
    return enter_insert_keys(new_row, new_col)
  end
end

--- Select mode Left/Right: collapse to the selection's start or end.
---@param side "start"|"end"
local function collapse(side)
  return function()
    local row, anchor, cursor = current_state()
    local col = side == "start" and math.min(anchor, cursor) or math.max(anchor, cursor)
    forget_state()
    return enter_insert_keys(row, col)
  end
end

--- Select mode Ctrl+V.
local function paste_over_selection()
  local row, anchor, cursor = current_state()
  local start_col, end_col = math.min(anchor, cursor), math.max(anchor, cursor)
  forget_state()
  return ("<C-\\><C-n><Cmd>lua require('config.vscode').paste_over(%d,%d,%d)<CR>"):format(row, start_col, end_col)
end

--- Select mode Alt+Up/Down: move the selected line and keep the selection.
---@param dir -1|1
local function move_selected_line(dir)
  return function()
    local row, anchor, cursor = current_state()
    local line = get_line(row)
    if (dir < 0 and row <= 1) or (dir > 0 and row >= last_row()) then
      return selection_keys(row, line, anchor, cursor)
    end
    local target = dir < 0 and (row - 2) or (row + 1)
    M.state = { row = row + dir, anchor = anchor, cursor = cursor }
    return ("<C-\\><C-n><Cmd>silent! %dmove %d<CR>"):format(row, target)
      .. selection_keys(row + dir, line, anchor, cursor)
  end
end

--------------------------------------------------------------------------
-- setup
--------------------------------------------------------------------------

function M.setup()
  local function map(mode, lhs, rhs, desc, opts)
    opts = vim.tbl_extend("force", { desc = desc, silent = true }, opts or {})
    vim.keymap.set(mode, lhs, rhs, opts)
  end
  local function expr(mode, lhs, rhs, desc)
    map(mode, lhs, rhs, desc, { expr = true })
  end

  -- Save. Named buffers update normally; unnamed ones prompt for a path.
  -- Overrides Neovim's Insert-mode <C-s> (signature help); LazyVim also binds
  -- that to <C-k>.
  map({ "n", "i", "x", "s" }, "<C-s>", M.save, "Save File")

  -- Motion. In Normal mode this overrides LazyVim's window-resize bindings.
  for _, spec in ipairs({
    { lhs = "<C-Left>", kind = "home", desc = "Smart Home (first non-blank / column 0)" },
    { lhs = "<C-Right>", kind = "end", desc = "End of Line" },
    { lhs = "<M-Left>", kind = "wordleft", desc = "Word Left" },
    { lhs = "<M-Right>", kind = "wordright", desc = "Word Right" },
    -- Terminal.app sends ESC b / ESC f for Option+Left / Option+Right.
    { lhs = "<M-b>", kind = "wordleft", desc = "Word Left" },
    { lhs = "<M-f>", kind = "wordright", desc = "Word Right" },
  }) do
    map("n", spec.lhs, plain_motion(spec.kind, false), spec.desc)
    map("i", spec.lhs, plain_motion(spec.kind, true), spec.desc)
    expr("s", spec.lhs, select_motion(spec.kind), spec.desc .. " (collapse selection)")
  end

  -- Shift + motion: select. Single line by design.
  for _, spec in ipairs({
    { lhs = "<C-S-Left>", kind = "home", desc = "Select to Line Start" },
    { lhs = "<C-S-Right>", kind = "end", desc = "Select to Line End" },
    { lhs = "<M-S-Left>", kind = "wordleft", desc = "Select Word Left" },
    { lhs = "<M-S-Right>", kind = "wordright", desc = "Select Word Right" },
  }) do
    expr({ "n", "i", "s" }, spec.lhs, shift_motion(spec.kind), spec.desc)
  end

  -- Collapse a selection with a plain arrow, like VSCode.
  expr("s", "<Left>", collapse("start"), "Collapse Selection to Start")
  expr("s", "<Right>", collapse("end"), "Collapse Selection to End")

  -- Copy. Normal-mode <C-v> is deliberately left alone so that Visual Block
  -- still works.
  map("i", "<C-c>", M.copy_line, "Copy Line")
  map({ "s", "x" }, "<C-c>", M.copy_selection, "Copy Selection")

  -- Paste.
  map("i", "<C-v>", M.paste_insert, "Paste")
  expr("s", "<C-v>", paste_over_selection, "Paste over Selection")

  -- Delete a selection without touching any register. <C-g> flips Select mode
  -- to Visual, then "_c changes into the black hole register.
  map("s", "<BS>", '<C-g>"_c', "Delete Selection")
  map("s", "<Del>", '<C-g>"_c', "Delete Selection")

  -- Delete backwards. Most terminals encode Ctrl+Backspace as Ctrl+H, while
  -- terminals with extended key reporting can send the distinct <C-BS> code.
  -- Keep Ctrl+H scoped to Insert mode: in Normal mode LazyVim uses it to focus
  -- the window to the left.
  map("i", "<C-BS>", M.clear_line, "Clear Current Line")
  map("i", "<C-h>", M.clear_line, "Clear Current Line")
  map("i", "<C-Del>", M.clear_line, "Clear Current Line")
  -- Meta + a terminal's Backspace byte can arrive as either <M-BS> or
  -- <M-Del>, depending on whether that terminal uses 0x08 or 0x7f.
  map("i", "<M-BS>", M.delete_word_left, "Delete Previous Word")
  map("i", "<M-Del>", M.delete_word_left, "Delete Previous Word")

  -- Move lines.
  map("n", "<M-Up>", function()
    M.move_line(-1, false)
  end, "Move Line Up")
  map("n", "<M-Down>", function()
    M.move_line(1, false)
  end, "Move Line Down")
  map("i", "<M-Up>", function()
    M.move_line(-1, true)
  end, "Move Line Up")
  map("i", "<M-Down>", function()
    M.move_line(1, true)
  end, "Move Line Down")
  expr("s", "<M-Up>", move_selected_line(-1), "Move Selected Line Up")
  expr("s", "<M-Down>", move_selected_line(1), "Move Selected Line Down")

  local group = api.nvim_create_augroup("nvim_config_vscode_registers", { clear = true })
  api.nvim_create_autocmd("ModeChanged", {
    group = group,
    pattern = "*:s",
    callback = M.snapshot_registers,
  })
  -- Only s:i. Leaving Select mode any other way (our own paste, which drops to
  -- Normal first) must not roll back a register that was written on purpose.
  api.nvim_create_autocmd("ModeChanged", {
    group = group,
    pattern = "s:i",
    callback = restore_registers,
  })
end

return M
