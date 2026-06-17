vim9script

# Gap coverage tests — behaviors not exercised by existing test suites
# Run: vim -N -u NONE -S tests/gaps.vim

set rtp+=src
runtime! plugin/vproj.vim
set nomore

var failures: number = 0
def Assert(cond: bool, msg: string): void
  if !cond
    echohl ErrorMsg | echom 'FAIL: ' .. msg | echohl None
    failures += 1
  else
    echom 'PASS: ' .. msg
  endif
enddef

def PaneCursorLine(): number
  var pbuf = bufnr('VPROJ')
  var wins = win_findbuf(pbuf)
  return empty(wins) ? -1 : line('.', wins[0])
enddef

def PaneBufnr(): number
  return bufnr('VPROJ')
enddef

def PaneLineCount(): number
  var pbuf = bufnr('VPROJ')
  if pbuf <= 0 || !bufexists(pbuf)
    return 0
  endif
  return getbufinfo(pbuf)[0].linecount
enddef

def PaneLine(lnum: number): string
  var pbuf = bufnr('VPROJ')
  var lines = getbufline(pbuf, lnum)
  return empty(lines) ? '' : lines[0]
enddef

def Setup(): void
  if vproj#IsPaneVisible()
    vproj#PaneClose()
  endif
  execute 'cd' getcwd()
  vproj#PaneOpen()
  if vproj#GetCurrentMode() != 'file'
    vproj#SwitchMode('file')
  endif
enddef

# ══════════════════════════════════════════════════
# 1. BuildDisplayLines structure (indirect via Render)
# ══════════════════════════════════════════════════
echom '--- BuildDisplayLines structure ---'
Setup()

# Line 1 must be mode menu (contains [F]ile, [B]uf, [G]it, [Q]fix)
var line1 = PaneLine(1)
Assert(line1 =~ '\[F\]ile', 'line 1: mode menu has [F]ile')
Assert(line1 =~ '\[B\]uf', 'line 1: mode menu has [B]uf')
Assert(line1 =~ '\[G\]it', 'line 1: mode menu has [G]it')
Assert(line1 =~ '\[Q\]fix', 'line 1: mode menu has [Q]fix')

# Line 2 must be separator in file mode
var line2 = PaneLine(2)
Assert(line2 =~ '^-\+$', 'line 2: separator in file mode')

# Cursor starts on line 3 (first selectable item)
Assert(PaneCursorLine() == 3, 'file mode: cursor on line 3 (first item)')

# Git mode structure
vproj#SwitchMode('git')
var cline1 = PaneLine(1)
Assert(cline1 =~ '\[F\]ile', 'git mode line 1: mode menu')
var cline2 = PaneLine(2)
Assert(cline2 =~ '^\*', 'git mode line 2: status line (starts with *)')
var cline3 = PaneLine(3)
Assert(cline3 =~ '^-\+$', 'git mode line 3: separator')
Assert(PaneCursorLine() == 4, 'git mode: cursor on line 4 (first item)')

# Buf mode structure
vproj#SwitchMode('buf')
var dline1 = PaneLine(1)
Assert(dline1 =~ '\[F\]ile', 'buf mode line 1: mode menu')
var dline2 = PaneLine(2)
Assert(dline2 =~ '^-\+$', 'buf mode line 2: separator')
Assert(PaneCursorLine() == 3, 'buf mode: cursor on line 3 (first buf line)')

# Qfix mode structure
vproj#SwitchMode('qfix')
var qline1 = PaneLine(1)
Assert(qline1 =~ '\[F\]ile', 'qfix mode line 1: mode menu')
Assert(qline1 =~ '\[Q\]fix', 'qfix mode line 1: qfix label present')
var qline2 = PaneLine(2)
Assert(qline2 =~ '^-\+$', 'qfix mode line 2: separator')
# Empty qflist should show placeholder
Assert(PaneCursorLine() == 3, 'qfix mode: cursor on line 3 (first item / placeholder)')
var qline3 = PaneLine(3)
Assert(qline3 =~ 'no quickfix', 'qfix empty: placeholder message shown')

# Populate qflist and verify entries
var qfix_tmp = '/tmp/vproj_qfix_gaps'
if isdirectory(qfix_tmp) | delete(qfix_tmp, 'rf') | endif
mkdir(qfix_tmp)
writefile(['aaa', 'bbb'], qfix_tmp .. '/x.txt')
setqflist([{filename: qfix_tmp .. '/x.txt', lnum: 2, col: 1, text: 'test entry', valid: true}])
vproj#SwitchMode('file')
vproj#SwitchMode('qfix')
Assert(PaneCursorLine() == 3, 'qfix populated: cursor on first entry')
var qp3 = PaneLine(3)
Assert(qp3 =~ 'x.txt', 'qfix populated: filename shown')
vproj#SelectNext()
Assert(PaneCursorLine() == 3, 'qfix single entry: SelectNext wraps to first')
delete(qfix_tmp, 'rf')

# ══════════════════════════════════════════════════
# 2. OnDirChanged integration
# ══════════════════════════════════════════════════
echom '--- OnDirChanged integration ---'
Setup()

# Verify OnDirChanged is a no-op when CWD hasn't changed
vproj#OnDirChanged()
Assert(vproj#IsPaneVisible(), 'OnDirChanged with no CWD change keeps pane open')
Assert(vproj#GetCurrentMode() == 'file', 'OnDirChanged preserves mode')

# OnDirChanged in git mode is a no-op
vproj#SwitchMode('git')
vproj#OnDirChanged()
Assert(vproj#GetCurrentMode() == 'git', 'OnDirChanged in git mode is no-op')

# OnDirChanged when pane is closed
vproj#PaneClose()
vproj#OnDirChanged()
Assert(!vproj#IsPaneVisible(), 'OnDirChanged when closed does not crash')

# Reopen and verify CWD tracking
execute 'cd /tmp'
vproj#PaneOpen()
var pane_visible_after_cd = vproj#IsPaneVisible()
Assert(pane_visible_after_cd, 'PaneOpen after cd /tmp works')

# ══════════════════════════════════════════════════
# 3. Paging + Nav combination
# ══════════════════════════════════════════════════
echom '--- Paging + Nav combination ---'
Setup()

# Navigate to a directory with many entries to trigger paging
vproj#SwitchMode('file')
execute 'cd' getcwd()

# Shift nav forward then press a nav char
vproj#ShiftNavForward()
Assert(vproj#GetNavOffset() > 0, 'ShiftNavForward advances offset')
vproj#SelectByNavChar('a')
Assert(vproj#IsPaneVisible(), 'SelectByNavChar(a) after ShiftNavForward no crash')

# Shift nav backward
vproj#ShiftNavBackward()
Assert(vproj#GetNavOffset() == 0, 'ShiftNavBackward returns to 0')

# SelectByNavChar with a char on second page (mapped to position that exists)
vproj#SelectByNavChar('B')
Assert(vproj#IsPaneVisible(), 'SelectByNavChar(B) no crash')

# SelectByNavChar with a char definitely not on page
vproj#SelectByNavChar('Q')
Assert(vproj#IsPaneVisible(), 'SelectByNavChar(Q) not on page, no crash')

# ══════════════════════════════════════════════════
# 4. NextPage / PrevPage cursor clamping
# ══════════════════════════════════════════════════
echom '--- NextPage / PrevPage ---'
Setup()
vproj#SwitchMode('file')

# PrevPage at page 0 should stay at 0, no crash
vproj#PrevPage()
Assert(vproj#IsPaneVisible(), 'PrevPage at page 0 no crash')

# NextPage should move to page 1 if there are enough items
vproj#NextPage()
Assert(vproj#IsPaneVisible(), 'NextPage no crash')

# Back to page 0
vproj#PrevPage()
Assert(vproj#IsPaneVisible(), 'PrevPage back to page 0 no crash')

# ══════════════════════════════════════════════════
# 5. NavigateIntoFirstDir + NavigateUp composition
# ══════════════════════════════════════════════════
echom '--- NavigateIntoFirstDir + NavigateUp ---'
Setup()
vproj#SwitchMode('file')

# NavigateIntoFirstDir enters first subdirectory
try
  vproj#NavigateIntoFirstDir()
  Assert(vproj#IsPaneVisible(), 'NavigateIntoFirstDir keeps pane open')
catch
  Assert(false, 'NavigateIntoFirstDir error: ' .. v:exception)
endtry

# NavigateUp back
vproj#NavigateUp()
Assert(vproj#IsPaneVisible(), 'NavigateUp after NavigateIntoFirstDir keeps pane open')

# ══════════════════════════════════════════════════
# 6. Multiple Open/Close cycles
# ══════════════════════════════════════════════════
echom '--- Multiple Open/Close cycles ---'

for i in range(5)
  vproj#PaneOpen()
  Assert(vproj#IsPaneVisible(), 'open cycle ' .. (i + 1) .. ': pane visible')
  Assert(vproj#GetCurrentMode() == 'file', 'open cycle ' .. (i + 1) .. ': default mode file')
  vproj#PaneClose()
  Assert(!vproj#IsPaneVisible(), 'close cycle ' .. (i + 1) .. ': pane not visible')
endfor

# ══════════════════════════════════════════════════
# 7. HandleBufWipeout then PaneOpen (no PaneClose)
# ══════════════════════════════════════════════════
echom '--- HandleBufWipeout → PaneOpen ---'
vproj#PaneOpen()
vproj#HandleBufWipeout()
Assert(!vproj#IsPaneVisible(), 'HandleBufWipeout clears visibility')

# Open after HandleBufWipeout should work cleanly
vproj#PaneOpen()
Assert(vproj#IsPaneVisible(), 'PaneOpen after HandleBufWipeout works')
Assert(PaneCursorLine() == 3, 'cursor on line 3 after HandleBufWipeout + PaneOpen')

# ══════════════════════════════════════════════════
# 8. Git mode with .vproj project file
# ══════════════════════════════════════════════════
echom '--- Git mode with .vproj file ---'
vproj#PaneClose()

# Write a test .vproj file in a temp directory
var tmpdir = '/tmp/vproj_test_gaps'
if isdirectory(tmpdir)
  delete(tmpdir, 'rf')
endif
mkdir(tmpdir)
mkdir(tmpdir .. '/lib')
mkdir(tmpdir .. '/bin')
writefile(['hello world'], tmpdir .. '/README.md')
writefile([''], tmpdir .. '/main.vim')

var vproj_content = [
  'Project Name: test-project',
  'Project Root: ' .. tmpdir,
  'Included Directories:',
  'lib',
  'Included Files:',
  'README.md',
  'main.vim',
  'Excluded Directories:',
  'bin',
  'Excluded Files:',
  ''
]
writefile(vproj_content, tmpdir .. '/.vproj')

execute 'cd' tmpdir
vproj#PaneOpen()
vproj#SwitchMode('git')

# Verify git mode shows the project
Assert(vproj#GetCurrentMode() == 'git', 'switched to git mode with .vproj')

# Status line (line 2) should show the project name
var status_line = PaneLine(2)
Assert(status_line =~ 'test-project', 'status line shows project name')

# RenameProject requires interactive input() — can't test in headless mode.
# Guard coverage (non-git mode early return) is tested in coverage.vim.

# Clean up test project
vproj#PaneClose()
delete(tmpdir, 'rf')

# ══════════════════════════════════════════════════
# 9. SelectByNavChar with paged items
# ══════════════════════════════════════════════════
echom '--- SelectByNavChar paged ---'
Setup()
vproj#SwitchMode('file')

# Navigate to /usr/bin to get lots of items → guaranteed paging
execute 'cd /usr/bin'
vproj#SwitchMode('file')

# Verify paging kicks in (should have > 20 items)
vproj#NextPage()
vproj#SelectByNavChar('a')
Assert(vproj#IsPaneVisible(), 'SelectByNavChar(a) on page 2 no crash')

vproj#NextPage()
vproj#SelectByNavChar('B')
Assert(vproj#IsPaneVisible(), 'SelectByNavChar(B) on page 3 no crash')

# Return to page 0
vproj#PrevPage()
vproj#PrevPage()

# ══════════════════════════════════════════════════
# 10. Mode switch preserves pane state
# ══════════════════════════════════════════════════
echom '--- Mode switch state preservation ---'
vproj#PaneClose()
execute 'cd' getcwd()
vproj#PaneOpen()

# Set a custom width, switch modes, verify width persists
vproj#SetPaneWidth(55)
Assert(vproj#GetPaneWidth() == 55, 'width set to 55')

vproj#SwitchMode('buf')
Assert(vproj#GetPaneWidth() == 55, 'width 55 preserved in buf mode')

vproj#SwitchMode('git')
Assert(vproj#GetPaneWidth() == 55, 'width 55 preserved in git mode')

vproj#SwitchMode('qfix')
Assert(vproj#GetPaneWidth() == 55, 'width 55 preserved in qfix mode')

vproj#SwitchMode('file')
Assert(vproj#GetPaneWidth() == 55, 'width 55 preserved back in file mode')

vproj#SetPaneWidth(40)

# ══════════════════════════════════════════════════
# 11. SelectFirst / SelectLast
# ══════════════════════════════════════════════════
echom '--- SelectFirst / SelectLast ---'
Setup()
vproj#SwitchMode('file')

vproj#SelectLast()
var last_pos = PaneCursorLine()
Assert(last_pos > 3, 'SelectLast moves to last selectable line')

vproj#SelectFirst()
Assert(PaneCursorLine() == 3, 'SelectFirst returns to line 3')

# Git mode
vproj#SwitchMode('git')
vproj#SelectLast()
Assert(vproj#IsPaneVisible(), 'SelectLast in git mode no crash')

vproj#SelectFirst()
Assert(PaneCursorLine() == 4, 'SelectFirst in git mode returns to line 4')

# Qfix mode
vproj#SwitchMode('qfix')
vproj#SelectLast()
Assert(vproj#IsPaneVisible(), 'SelectLast in qfix mode no crash')
vproj#SelectFirst()
Assert(vproj#IsPaneVisible(), 'SelectFirst in qfix mode no crash')

# ══════════════════════════════════════════════════
# 12. ToggleInfoColumn across modes
# ══════════════════════════════════════════════════
echom '--- ToggleInfoColumn across modes ---'
Setup()

vproj#ToggleInfoColumn()
vproj#SwitchMode('buf')
vproj#ToggleInfoColumn()
Assert(vproj#IsPaneVisible(), 'ToggleInfoColumn in buf mode no crash')

vproj#SwitchMode('git')
vproj#ToggleInfoColumn()
Assert(vproj#IsPaneVisible(), 'ToggleInfoColumn in git mode no crash')

vproj#SwitchMode('qfix')
vproj#ToggleInfoColumn()
Assert(vproj#IsPaneVisible(), 'ToggleInfoColumn in qfix mode no crash')

vproj#SwitchMode('file')

# ══════════════════════════════════════════════════
# 13. Wrap-around SelectNext / SelectPrev
# ══════════════════════════════════════════════════
echom '--- SelectNext / SelectPrev wrap ---'
Setup()
vproj#SwitchMode('file')

# SelectPrev from first item should wrap to last
vproj#SelectPrev()
Assert(vproj#IsPaneVisible(), 'SelectPrev from first item no crash')
Assert(vproj#GetCurrentMode() == 'file', 'SelectPrev from first stays in file mode')

# SelectNext from last item should wrap to first
vproj#SelectLast()
vproj#SelectNext()
Assert(vproj#IsPaneVisible(), 'SelectNext from last item no crash')
Assert(vproj#GetCurrentMode() == 'file', 'SelectNext from last stays in file mode')

# ══════════════════════════════════════════════════
# 14. PaneToggle idempotence
# ══════════════════════════════════════════════════
echom '--- PaneToggle idempotence ---'
vproj#PaneClose()
Assert(!vproj#IsPaneVisible(), 'pane closed')

vproj#PaneToggle()
Assert(vproj#IsPaneVisible(), 'PaneToggle opens')
var first_line = PaneCursorLine()
Assert(first_line == 3, 'cursor on line 3 after toggle open')

vproj#PaneToggle()
Assert(!vproj#IsPaneVisible(), 'PaneToggle closes')

vproj#PaneToggle()
Assert(vproj#IsPaneVisible(), 'PaneToggle opens again')

# ══════════════════════════════════════════════════
# 15. Exported query functions
# ══════════════════════════════════════════════════
echom '--- Exported queries ---'
Setup()

Assert(vproj#GetPaneWidth() == 40, 'GetPaneWidth returns 40')
Assert(vproj#GetCurrentMode() == 'file', 'GetCurrentMode returns file')
Assert(vproj#GetNavOffset() == 0, 'GetNavOffset returns 0')
Assert(vproj#IsPaneVisible(), 'IsPaneVisible returns true')

vproj#SwitchMode('buf')
Assert(vproj#GetCurrentMode() == 'buf', 'GetCurrentMode returns buf')
vproj#SwitchMode('git')
Assert(vproj#GetCurrentMode() == 'git', 'GetCurrentMode returns git')
vproj#SwitchMode('qfix')
Assert(vproj#GetCurrentMode() == 'qfix', 'GetCurrentMode returns qfix')

# ══════════════════════════════════════════════════
# Cleanup
# ══════════════════════════════════════════════════
Setup()
vproj#PaneClose()
Assert(!vproj#IsPaneVisible(), 'cleanup: pane closed')

echom ''
if failures == 0
  echom 'ALL GAP TESTS PASSED.'
else
  echohl ErrorMsg
  echom failures .. ' GAP TEST(S) FAILED.'
  echohl None
  cquit!
endif
qa!
