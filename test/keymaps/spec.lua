-- Keymap test suite for nvim/lua/config/vscode.lua.
--
-- Driven over RPC rather than with nvim_feedkeys: feedkeys with the "x!" flags
-- deadlocks a headless Neovim as soon as the mapping leaves it in Insert mode.
-- Instead run.sh starts a server with --listen, and this script (run through
-- `nvim -l`) connects to it, types with nvim_input and reads the result back
-- with nvim_exec_lua.
--
--   nvim -l test/keymaps/spec.lua <socket> [tmpdir]

local socket = arg[1] or error("usage: nvim -l spec.lua <socket> [tmpdir]")
local tmpdir = arg[2] or "/tmp"

local chan = vim.fn.sockconnect("pipe", socket, { rpc = true })

--------------------------------------------------------------------------
-- Tiny harness
--------------------------------------------------------------------------

local passed, failed = 0, 0
local failures = {}
local current = "<none>"

local function lua_exec(code, args)
  return vim.rpcrequest(chan, "nvim_exec_lua", code, args or {})
end

--- Type keys and give the editor a moment to process them. nvim_input only
--- queues the keys; there is no synchronous "and now run them" call.
local function feed(keys)
  vim.rpcrequest(chan, "nvim_input", keys)
  vim.uv.sleep(60)
end

local function describe(value)
  return (vim.inspect(value):gsub("%s+", " "))
end

local function check(ok, message)
  if ok then
    passed = passed + 1
  else
    failed = failed + 1
    failures[#failures + 1] = ("%s: %s"):format(current, message)
  end
end

local function eq(actual, expected, what)
  check(
    vim.deep_equal(actual, expected),
    ("%s\n      expected %s\n      got      %s"):format(what, describe(expected), describe(actual))
  )
end

local function test(name, fn)
  current = name
  local ok, err = pcall(fn)
  if not ok then
    failed = failed + 1
    failures[#failures + 1] = ("%s: raised %s"):format(name, tostring(err))
  end
end

--------------------------------------------------------------------------
-- Editor helpers
--------------------------------------------------------------------------

local RESET = [[
  local lines, row, col, insert = ...
  vim.cmd("silent! noautocmd %bwipeout!")
  -- listed and *not* scratch: a scratch buffer has buftype=nofile and cannot
  -- be written, which the <C-s> test needs.
  local buf = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_win_set_buf(0, buf)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  for _, r in ipairs({ '"', "-", "+" }) do
    pcall(vim.fn.setreg, r, "", "v")
  end
  local M = require("config.vscode")
  M.state = { row = nil }
  M._regs = nil
  if insert then
    M.enter_insert(row, col)
  else
    vim.cmd("stopinsert")
    vim.api.nvim_win_set_cursor(0, { row, math.min(col, math.max(0, #(lines[row] or "") - 1)) })
  end
]]

--- Wipe every buffer, load `lines`, and park the cursor at a boundary.
local function reset(lines, row, col, insert)
  lua_exec(RESET, { lines, row, col, insert ~= false })
  vim.uv.sleep(30)
end

local STATE = [[
  local mode = vim.fn.mode(1)
  local selection = nil
  local first = mode:sub(1, 1)
  if first == "s" or first == "S" or first == "v" or first == "V" then
    local kind = (first == "S" or first == "V") and "V" or "v"
    selection = table.concat(vim.fn.getregion(vim.fn.getpos("v"), vim.fn.getpos("."), { type = kind }), "\n")
  end
  return {
    mode = mode,
    lines = vim.api.nvim_buf_get_lines(0, 0, -1, false),
    cursor = vim.api.nvim_win_get_cursor(0),
    selection = selection,
    unnamed = vim.fn.getreg('"'),
    unnamed_type = vim.fn.getregtype('"'),
    minus = vim.fn.getreg("-"),
  }
]]

local function state()
  return lua_exec(STATE)
end

local function set_register(name, text, regtype)
  lua_exec(
    [[
    local name, text, regtype = ...
    pcall(vim.fn.setreg, name, text, regtype)
  ]],
    { name, text, regtype }
  )
end

--------------------------------------------------------------------------
-- Tests
--------------------------------------------------------------------------

test("select to line end, then shrink by word", function()
  reset({ "hello world foo" }, 1, 6)
  feed("<C-S-Right>")
  local s = state()
  eq(s.mode:sub(1, 1), "s", "shift+end enters Select mode")
  eq(s.selection, "world foo", "selects to the end of the line")

  feed("<M-S-Left>")
  s = state()
  eq(s.mode:sub(1, 1), "s", "still in Select mode")
  eq(s.selection, "world ", "one word back shrinks the selection")
end)

test("an empty selection returns to Insert at the anchor", function()
  reset({ "abc" }, 1, 3)
  feed("<C-S-Right>")
  local s = state()
  eq(s.mode, "i", "back to Insert mode")
  eq(s.cursor, { 1, 3 }, "cursor stays at the end of the line")
end)

test("select from the end of the line", function()
  reset({ "hello" }, 1, 5)
  feed("<C-S-Left>")
  local s = state()
  eq(s.mode:sub(1, 1), "s", "Select mode")
  eq(s.selection, "hello", "selects the whole line")
end)

test("typing replaces the selection and stays in Insert", function()
  reset({ "hello" }, 1, 5)
  feed("<C-S-Left>")
  feed("X")
  local s = state()
  eq(s.mode, "i", "typing leaves us in Insert mode")
  eq(s.lines, { "X" }, "the selection was replaced")
  eq(s.cursor, { 1, 1 }, "cursor sits after the typed character")
end)

test("typing over a selection does not touch the registers", function()
  reset({ "hello" }, 1, 5)
  set_register('"', "KEEP", "v")
  set_register("-", "SMALL", "v")
  feed("<C-S-Left>")
  feed("X")
  local s = state()
  eq(s.unnamed, "KEEP", "the unnamed register survives (VSCode never clobbers it)")
  eq(s.minus, "SMALL", "the small-delete register survives")
end)

test("<BS> over a selection does not touch the registers", function()
  reset({ "hello world" }, 1, 11)
  set_register('"', "KEEP", "v")
  set_register("-", "SMALL", "v")
  feed("<C-S-Left>")
  feed("<BS>")
  local s = state()
  eq(s.lines, { "" }, "the selection is gone")
  eq(s.mode, "i", "and we are in Insert mode")
  eq(s.unnamed, "KEEP", "unnamed register untouched")
  eq(s.minus, "SMALL", "small-delete register untouched")
end)

test("copy keeps the selection", function()
  reset({ "hello" }, 1, 5)
  feed("<C-S-Left>")
  feed("<C-c>")
  local s = state()
  eq(s.mode:sub(1, 1), "s", "still selected after copying")
  eq(s.selection, "hello", "and it is the same selection")
  eq(s.unnamed, "hello", "the text was copied")
  eq(s.unnamed_type, "v", "charwise")
end)

test("<Right> collapses the selection to its end", function()
  reset({ "hello" }, 1, 5)
  feed("<C-S-Left>")
  feed("<Right>")
  local s = state()
  eq(s.mode, "i", "back to Insert mode")
  eq(s.cursor, { 1, 5 }, "at the end of the selection")
end)

test("<Left> collapses the selection to its start", function()
  reset({ "hello" }, 1, 5)
  feed("<C-S-Left>")
  feed("<Left>")
  local s = state()
  eq(s.mode, "i", "back to Insert mode")
  eq(s.cursor, { 1, 0 }, "at the start of the selection")
end)

test("paste over a selection", function()
  reset({ "hello world" }, 1, 0)
  set_register('"', "XY", "v")
  feed("<M-S-Right>")
  eq(state().selection, "hello", "the word is selected")
  feed("<C-v>")
  local s = state()
  eq(s.lines, { "XY world" }, "the selection was replaced by the clipboard")
  eq(s.mode, "i", "and we end in Insert mode")
  eq(s.cursor, { 1, 2 }, "cursor after the pasted text")
end)

test("linewise copy pastes above and keeps the cursor on its line", function()
  reset({ "aaa", "bbb" }, 2, 1)
  feed("<C-c>")
  local s = state()
  eq(s.unnamed, "bbb\n", "the whole line was copied")
  eq(s.unnamed_type, "V", "linewise")

  feed("<C-v>")
  s = state()
  eq(s.lines, { "aaa", "bbb", "bbb" }, "the copy went in above the current line")
  eq(s.cursor, { 3, 1 }, "the cursor stayed on its own line, which moved down")
  eq(s.mode, "i", "still in Insert mode")
end)

test("charwise paste at the end of a line", function()
  reset({ "ab" }, 1, 2)
  set_register('"', "XY", "v")
  feed("<C-v>")
  local s = state()
  eq(s.lines, { "abXY" }, "pasted at the cursor")
  eq(s.cursor, { 1, 4 }, "cursor after the pasted text, past the last character")
end)

test("move a line up and down, keeping the column", function()
  reset({ "one", "two", "three" }, 2, 2)
  feed("<M-Up>")
  local s = state()
  eq(s.lines, { "two", "one", "three" }, "the line moved up")
  eq(s.cursor, { 1, 2 }, "the cursor followed it and kept its column")

  feed("<M-Down>")
  s = state()
  eq(s.lines, { "one", "two", "three" }, "and back down")
  eq(s.cursor, { 2, 2 }, "cursor still on the same text")
end)

test("smart home toggles between first non-blank and column 0", function()
  reset({ "    indented" }, 1, 8)
  feed("<C-Left>")
  eq(state().cursor, { 1, 4 }, "first non-blank")
  feed("<C-Left>")
  eq(state().cursor, { 1, 0 }, "then column 0")
  feed("<C-Left>")
  eq(state().cursor, { 1, 4 }, "and back to the first non-blank")
end)

test("<C-Right> goes to the end of the line", function()
  reset({ "abc" }, 1, 0)
  feed("<C-Right>")
  eq(state().cursor, { 1, 3 }, "past the last character")
end)

test("<C-S-Left> then <BS> clears to the first non-blank", function()
  reset({ "  hello world" }, 1, 13)
  feed("<C-S-Left>")
  eq(state().selection, "hello world", "selects back to the first non-blank")
  feed("<BS>")
  local s = state()
  eq(s.lines, { "  " }, "the indent survives")
  eq(s.cursor, { 1, 2 }, "cursor at the first non-blank")
end)

test("<C-BS> clears the current line without changing registers", function()
  reset({ "hello world", "keep" }, 1, 5)
  set_register('"', "KEEP", "v")
  set_register("-", "SMALL", "v")
  feed("<C-BS>")
  local s = state()
  eq(s.lines, { "", "keep" }, "only the current line was cleared")
  eq(s.cursor, { 1, 0 }, "cursor returns to the start of the cleared line")
  eq(s.mode, "i", "we remain in Insert mode")
  eq(s.unnamed, "KEEP", "unnamed register untouched")
  eq(s.minus, "SMALL", "small-delete register untouched")
end)

test("<C-h> is the terminal encoding of Ctrl+Backspace", function()
  reset({ "hello" }, 1, 3)
  feed("<C-h>")
  local s = state()
  eq(s.lines, { "" }, "Ctrl+H clears the current line too")
  eq(s.cursor, { 1, 0 }, "cursor returns to its start")
end)

test("<C-Del> is the extended-key encoding of Ctrl+Backspace", function()
  reset({ "hello" }, 1, 3)
  feed("<C-Del>")
  local s = state()
  eq(s.lines, { "" }, "Ctrl+Delete clears the current line too")
  eq(s.cursor, { 1, 0 }, "cursor returns to its start")
end)

test("Alt+Backspace deletes one UTF-8 word without changing registers", function()
  reset({ "سلام دنیا" }, 1, #"سلام دنیا")
  set_register('"', "KEEP", "v")
  set_register("-", "SMALL", "v")
  feed("<M-BS>")
  local s = state()
  eq(s.lines, { "سلام " }, "the preceding Persian word was deleted whole")
  eq(s.cursor, { 1, #"سلام " }, "cursor lands at the deleted word's start")
  eq(s.mode, "i", "we remain in Insert mode")
  eq(s.unnamed, "KEEP", "unnamed register untouched")
  eq(s.minus, "SMALL", "small-delete register untouched")
end)

test("<M-Del> is the alternate terminal encoding of Alt+Backspace", function()
  reset({ "one two" }, 1, 7)
  feed("<M-Del>")
  local s = state()
  eq(s.lines, { "one " }, "the previous word was deleted")
  eq(s.cursor, { 1, 4 }, "cursor lands at the deleted word's start")
end)

test("word jumps wrap across lines", function()
  reset({ "foo bar", "baz qux" }, 1, 7)
  feed("<M-Right>")
  eq(state().cursor, { 2, 3 }, "steps onto the next line and over its first word")
  feed("<M-Left>")
  eq(state().cursor, { 2, 0 }, "back to the start of that word")
  feed("<M-Left>")
  eq(state().cursor, { 1, 4 }, "and onto the last word of the previous line")
end)

test("<M-b> and <M-f> behave like the Option+Arrow aliases", function()
  reset({ "foo bar baz" }, 1, 0)
  feed("<M-f>")
  eq(state().cursor, { 1, 3 }, "<M-f> jumps a word right")
  feed("<M-b>")
  eq(state().cursor, { 1, 0 }, "<M-b> jumps a word left")
end)

test("Persian text selects and is replaced by word", function()
  -- Every letter here is two bytes, so a word motion that counted bytes rather
  -- than characters would land in the middle of one.
  reset({ "سلام دنیا" }, 1, 0)
  feed("<M-S-Right>")
  local s = state()
  eq(s.mode:sub(1, 1), "s", "Select mode")
  eq(s.selection, "سلام", "the first word is selected, not a half character")

  set_register('"', "X", "v")
  feed("<C-v>")
  s = state()
  eq(s.lines, { "X دنیا" }, "the word was replaced cleanly")
  eq(s.cursor, { 1, 1 }, "cursor after the replacement")
end)

test("<C-s> saves and stays in Insert mode", function()
  local path = tmpdir .. "/ctrl-s-test.txt"
  reset({ "content" }, 1, 7)
  lua_exec([[ vim.cmd("silent! file " .. vim.fn.fnameescape(...)) ]], { path })
  feed("<C-s>")
  local s = state()
  eq(s.mode, "i", "still in Insert mode after saving")
  eq(lua_exec([[ return vim.fn.filereadable(...) ]], { path }), 1, "the file was written")
  lua_exec([[ pcall(vim.fn.delete, ...) ]], { path })
end)

test("<C-s> saves an unnamed buffer to the chosen path", function()
  local path = tmpdir .. "/ctrl-s-unnamed.txt"
  reset({ "content" }, 1, 7)
  lua_exec(
    [[
    local path = ...
    pcall(vim.fn.delete, path)
    _G.nvim_config_test_ui_input = vim.ui.input
    vim.ui.input = function(opts, on_confirm)
      _G.nvim_config_test_save_prompt = opts
      on_confirm(path)
    end
  ]],
    { path }
  )
  feed("<C-s>")
  local saved = lua_exec(
    [[
    local path = ...
    local result = {
      mode = vim.fn.mode(1),
      name = vim.api.nvim_buf_get_name(0),
      readable = vim.fn.filereadable(path),
      prompt = _G.nvim_config_test_save_prompt,
    }
    vim.ui.input = _G.nvim_config_test_ui_input
    _G.nvim_config_test_ui_input = nil
    _G.nvim_config_test_save_prompt = nil
    pcall(vim.fn.delete, path)
    return result
  ]],
    { path }
  )
  eq(saved.mode, "i", "still in Insert mode after saving an unnamed buffer")
  eq(saved.name, path, "the buffer is associated with the chosen file")
  eq(saved.readable, 1, "the chosen file was written")
  eq(saved.prompt.prompt, "Save as: ", "the save prompt was shown")
  eq(saved.prompt.completion, "file", "the prompt offers file completion")
end)

test("<C-s> leaves an unnamed buffer unchanged when save is cancelled", function()
  reset({ "content" }, 1, 7)
  lua_exec([[
    _G.nvim_config_test_ui_input = vim.ui.input
    vim.ui.input = function(_, on_confirm) on_confirm(nil) end
  ]])
  feed("<C-s>")
  local cancelled = lua_exec([[
    local result = { mode = vim.fn.mode(1), name = vim.api.nvim_buf_get_name(0) }
    vim.ui.input = _G.nvim_config_test_ui_input
    _G.nvim_config_test_ui_input = nil
    return result
  ]])
  eq(cancelled.mode, "i", "stays in Insert mode after cancelling")
  eq(cancelled.name, "", "the buffer remains unnamed")
end)

test("a selection can start from Normal mode", function()
  reset({ "hello world" }, 1, 0, false)
  feed("<C-S-Right>")
  local s = state()
  eq(s.mode:sub(1, 1), "s", "Select mode")
  eq(s.selection, "hello world", "selects to the end of the line")
end)

test("selected lines move with <M-Up> and keep the selection", function()
  reset({ "one", "two", "three" }, 2, 0)
  feed("<M-S-Right>")
  eq(state().selection, "two", "the word is selected")
  feed("<M-Up>")
  local s = state()
  eq(s.lines, { "two", "one", "three" }, "the line moved up")
  eq(s.mode:sub(1, 1), "s", "still in Select mode")
  eq(s.selection, "two", "with the same text selected")
  eq(s.cursor[1], 1, "on the new row")
end)

test("plain motions in Select mode collapse and move", function()
  reset({ "hello world" }, 1, 0)
  feed("<C-S-Right>")
  eq(state().selection, "hello world", "the line is selected")
  feed("<C-Left>")
  local s = state()
  eq(s.mode, "i", "collapsed back into Insert mode")
  eq(s.cursor, { 1, 0 }, "and moved to the first non-blank")
end)

--------------------------------------------------------------------------
-- Report
--------------------------------------------------------------------------

-- Ask the server to quit. It closes the channel while handling this, so the
-- request never gets a reply -- notify, and ignore whatever happens.
pcall(vim.rpcnotify, chan, "nvim_command", "qa!")

io.stdout:write(("\n%d passed, %d failed\n"):format(passed, failed))
for _, failure in ipairs(failures) do
  io.stdout:write("  FAIL  " .. failure .. "\n")
end
os.exit(failed == 0 and 0 or 1)
