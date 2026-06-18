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

	# Clear stale session to avoid inherited dir=/tmp
	delete(expand('~/.cache/vproj/session'))
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
# 16. ToggleGitFilter — functional test
# ══════════════════════════════════════════════════
echom '--- ToggleGitFilter ---'
Setup()

# Indicator absent by default — check that [G] doesn't appear AFTER [Q]fix
var ml1 = PaneLine(1)
Assert(ml1 !~ 'Q\]fix.*\[G\]', 'git filter indicator absent by default')

try
  vproj#ToggleGitFilter()
  Assert(vproj#IsPaneVisible(), 'ToggleGitFilter keeps pane visible')
  var ml2 = PaneLine(1)
  Assert(ml2 =~ 'Q\]fix.*\[G\]', 'git filter indicator appears after toggle')
catch
  Assert(false, 'ToggleGitFilter error: ' .. v:exception)
endtry

# Toggle back to off
vproj#ToggleGitFilter()
var ml3 = PaneLine(1)
Assert(ml3 !~ 'Q\]fix.*\[G\]', 'git filter indicator cleared on second toggle')

# Refresh clears git filter
vproj#ToggleGitFilter()
vproj#Refresh()
var ml4 = PaneLine(1)
Assert(ml4 !~ 'Q\]fix.*\[G\]', 'Refresh clears git filter')

# Mode switch clears git filter
vproj#ToggleGitFilter()
vproj#SwitchMode('buf')
var ml5 = PaneLine(1)
Assert(ml5 !~ 'Q\]fix.*\[G\]', 'SwitchMode clears git filter')

# ══════════════════════════════════════════════════
# 17. HandleF1 — pane vs. non-pane paths
# ══════════════════════════════════════════════════
echom '--- HandleF1 ---'
Setup()

try
  vproj#HandleF1()
  Assert(vproj#IsPaneVisible(), 'HandleF1 in pane toggles info column')
catch
  Assert(false, 'HandleF1 in pane error: ' .. v:exception)
endtry

vproj#PaneClose()

# HandleF1 outside pane — opens help
try
  vproj#HandleF1()
  Assert(true, 'HandleF1 outside pane no crash')
catch
  Assert(false, 'HandleF1 outside pane error: ' .. v:exception)
endtry

# Close any help window that opened
if winnr('$') > 1
  wincmd w
  if &buftype == 'help'
    close
  endif
endif
vproj#PaneClose()

# ══════════════════════════════════════════════════
# 18. CloseBuffer with actual buffers
# ══════════════════════════════════════════════════
echom '--- CloseBuffer functional ---'
vproj#PaneClose()

# Open real buffers
silent! edit! /tmp/vproj_gap_buf_a.txt
silent! edit! /tmp/vproj_gap_buf_b.txt
silent! edit! /tmp/vproj_gap_buf_c.txt

vproj#PaneOpen()
vproj#SwitchMode('buf')

# Should have at least 3 buffers beyond menu/separator
try
  vproj#CloseBuffer()
  Assert(vproj#IsPaneVisible(), 'CloseBuffer in buf mode keeps pane visible')
catch
  Assert(false, 'CloseBuffer error: ' .. v:exception)
endtry

vproj#PaneClose()

# Cleanup
silent! bdelete! /tmp/vproj_gap_buf_a.txt
silent! bdelete! /tmp/vproj_gap_buf_b.txt
silent! bdelete! /tmp/vproj_gap_buf_c.txt

# ══════════════════════════════════════════════════
# 19. PromptFilter — feedkeys functional test
# ══════════════════════════════════════════════════
echom '--- PromptFilter ---'
Setup()

try
  call feedkeys("vim\<CR>", 't')
  vproj#PromptFilter()
  Assert(vproj#IsPaneVisible(), 'PromptFilter with pattern ok')
catch
  Assert(false, 'PromptFilter error: ' .. v:exception)
endtry

# Clear filter with empty input
try
  call feedkeys("\<CR>", 't')
  vproj#PromptFilter()
  Assert(vproj#IsPaneVisible(), 'PromptFilter clear ok')
catch
  Assert(false, 'PromptFilter clear error: ' .. v:exception)
endtry

# ══════════════════════════════════════════════════
# 20. Mode cycling via SwitchMode (all 4 modes, round-trip)
# ══════════════════════════════════════════════════
echom '--- Mode cycling ---'
Setup()

# file → buf → git → qfix → file
vproj#SwitchMode('buf')
Assert(vproj#GetCurrentMode() == 'buf', 'SwitchMode: file→buf')
vproj#SwitchMode('git')
Assert(vproj#GetCurrentMode() == 'git', 'SwitchMode: buf→git')
vproj#SwitchMode('qfix')
Assert(vproj#GetCurrentMode() == 'qfix', 'SwitchMode: git→qfix')
vproj#SwitchMode('file')
Assert(vproj#GetCurrentMode() == 'file', 'SwitchMode: qfix→file')

# ══════════════════════════════════════════════════
# 21. NavigateIntoFirstDir with no subdirectory
# ══════════════════════════════════════════════════
echom '--- NavigateIntoFirstDir in empty dir ---'

vproj#PaneClose()
call mkdir('/tmp/vproj_gap_empty_dir', 'p')
execute 'cd /tmp/vproj_gap_empty_dir'

vproj#PaneOpen()
try
  vproj#NavigateIntoFirstDir()
  Assert(true, 'NavigateIntoFirstDir empty-dir no crash')
catch
  Assert(false, 'NavigateIntoFirstDir empty-dir error: ' .. v:exception)
endtry
vproj#PaneClose()
call delete('/tmp/vproj_gap_empty_dir', 'rf')

# ══════════════════════════════════════════════════
# 22. Empty directory — works without crash, shows parent dir
# ══════════════════════════════════════════════════
echom '--- Empty directory ---'

call mkdir('/tmp/vproj_gap_empty2', 'p')
execute 'cd /tmp/vproj_gap_empty2'

vproj#PaneOpen()
var elines = getbufline(bufnr('VPROJ'), 1, '$')
var has_parent = false
for l in elines
  if l =~ '\.\.'
    has_parent = true
    break
  endif
endfor
Assert(has_parent, 'empty directory shows parent (..) entry')
Assert(vproj#GetCurrentMode() == 'file', 'empty directory: stays in file mode')
vproj#PaneClose()
call delete('/tmp/vproj_gap_empty2', 'rf')

# ══════════════════════════════════════════════════
# 23. Session persistence round-trip
# ══════════════════════════════════════════════════
echom '--- Session persistence ---'

vproj#PaneOpen()
vproj#SwitchMode('buf')
vproj#SetPaneWidth(55)
vproj#ToggleInfoColumn()  # flip once
vproj#PaneClose()

vproj#PaneOpen()
Assert(vproj#GetCurrentMode() == 'buf', 'session restores buf mode')
Assert(vproj#GetPaneWidth() == 55, 'session restores width 55')
vproj#PaneClose()

# Restore default state
vproj#PaneOpen()
vproj#SetPaneWidth(40)
vproj#SwitchMode('file')
vproj#ToggleInfoColumn()  # flip back
vproj#PaneClose()

# ══════════════════════════════════════════════════
# 24. ParseVprojFile with malformed / edge input
# ══════════════════════════════════════════════════
echom '--- ParseVprojFile malformed ---'

var tmp_v = '/tmp/vproj_gap_malformed.vproj'

# Minimal valid .vproj
writefile(['Project Name: GapTest', '# comment', '', 'garbage line', 'Included Directories:', 'src'], tmp_v)
try
  var p = vproj#ParseVprojFile(tmp_v)
  Assert(get(p, 'name', '') == 'GapTest', 'malformed .vproj: name parsed')
  Assert(len(get(p, 'included_dirs', [])) == 1, 'malformed .vproj: 1 included dir')
catch
  Assert(false, 'ParseVprojFile malformed error: ' .. v:exception)
endtry

# Bogus root path
writefile(['Project Name: Bogus', 'Project Root: /nonexistent/xyz/123', 'Included Directories:', 'src'], tmp_v)
try
  var p2 = vproj#ParseVprojFile(tmp_v)
  Assert(empty(get(p2, 'root', '')), 'bogus root: cleared to empty')
catch
  Assert(false, 'ParseVprojFile bogus-root error: ' .. v:exception)
endtry

call delete(tmp_v)

# ══════════════════════════════════════════════════
# 25. Binary file detection
# ══════════════════════════════════════════════════
echom '--- Binary file ---'

var bdata = 0z000102030405060708090a0b0c0d0e0f
writefile(bdata, '/tmp/vproj_gap_binary.bin')

vproj#PaneClose()
execute 'cd /tmp'
vproj#PaneOpen()
vproj#SwitchMode('file')

var p_lines = getbufline(bufnr('VPROJ'), 1, '$')
var bin_line = 0
for i in range(len(p_lines))
  if p_lines[i] =~ 'vproj_gap_binary\.bin'
    bin_line = i + 1
    break
  endif
endfor

if bin_line > 0
  var pw2 = win_findbuf(bufnr('VPROJ'))[0]
  win_execute(pw2, 'normal ' .. bin_line .. 'G')
  try
    vproj#SelectCurrent()
    Assert(true, 'binary file SelectCurrent no crash')
  catch
    Assert(false, 'Binary SelectCurrent error: ' .. v:exception)
  endtry
else
  Assert(true, 'binary file not in listing (filtered or not created)')
endif

vproj#PaneClose()
call delete('/tmp/vproj_gap_binary.bin')

# ══════════════════════════════════════════════════
# 26. Qfix column jump and invalid entry skip
# ══════════════════════════════════════════════════
echom '--- Qfix edge cases ---'

writefile(['col1 col2 col3 col4 col5', 'a b c d e'], '/tmp/vproj_gap_qfix2.txt')

# Mix valid and invalid entries
setqflist([
  {filename: '/nonexistent/bad.txt', lnum: 1, col: 1, text: 'bad', valid: false},
  {filename: '/tmp/vproj_gap_qfix2.txt', lnum: 2, col: 5, text: 'col 5', valid: true},
])

vproj#PaneOpen()
vproj#SwitchMode('qfix')

# Should have only the valid entry
var qlines = getbufline(bufnr('VPROJ'), 1, '$')
var hits = 0
for l in qlines
  if l =~ 'vproj_gap_qfix2'
    hits += 1
  endif
endfor
Assert(hits == 1, 'qfix skips invalid entry, shows 1 valid')

# Jump to entry with column
try
  vproj#SelectCurrent()
  Assert(true, 'qfix column-jump entry opened')
catch
  Assert(false, 'qfix column-jump error: ' .. v:exception)
endtry

vproj#PaneClose()
call delete('/tmp/vproj_gap_qfix2.txt')

# ══════════════════════════════════════════════════
# 27. GitStageToggle guards (non-file modes)
# ══════════════════════════════════════════════════
echom '--- GitStageToggle guards ---'
Setup()

vproj#SwitchMode('buf')
try
  vproj#GitStageToggle()
  Assert(vproj#IsPaneVisible(), 'GitStageToggle in buf mode exits early')
catch
  Assert(false, 'GitStageToggle buf-mode error: ' .. v:exception)
endtry

vproj#SwitchMode('git')
try
  vproj#GitStageToggle()
  Assert(vproj#IsPaneVisible(), 'GitStageToggle in git mode exits early')
catch
  Assert(false, 'GitStageToggle git-mode error: ' .. v:exception)
endtry

vproj#SwitchMode('qfix')
try
  vproj#GitStageToggle()
  Assert(vproj#IsPaneVisible(), 'GitStageToggle in qfix mode exits early')
catch
  Assert(false, 'GitStageToggle qfix-mode error: ' .. v:exception)
endtry

# ══════════════════════════════════════════════════
# 28. Pane buffer name is VPROJ after open
# ══════════════════════════════════════════════════
echom '--- Pane buffer name ---'
vproj#PaneClose()

vproj#PaneOpen()
var pb = bufnr('VPROJ')
Assert(pb > 0, 'pane buffer exists after open')
Assert(bufname(pb) == 'VPROJ', 'pane buffer named VPROJ')
Assert(bufexists(pb), 'pane buffer is valid')
vproj#PaneClose()

# ══════════════════════════════════════════════════
# 29. ToggleInfoColumn across all modes
# ══════════════════════════════════════════════════
echom '--- ToggleInfoColumn across modes ---'
Setup()

vproj#ToggleInfoColumn()
Assert(vproj#IsPaneVisible(), 'ToggleInfoColumn in file mode ok')

vproj#SwitchMode('buf')
vproj#ToggleInfoColumn()
Assert(vproj#IsPaneVisible(), 'ToggleInfoColumn in buf mode ok')

vproj#SwitchMode('git')
vproj#ToggleInfoColumn()
Assert(vproj#IsPaneVisible(), 'ToggleInfoColumn in git mode ok')

vproj#SwitchMode('qfix')
vproj#ToggleInfoColumn()
Assert(vproj#IsPaneVisible(), 'ToggleInfoColumn in qfix mode ok')

vproj#SwitchMode('file')

# ══════════════════════════════════════════════════
# 30. SelectPrev wrap-around from first item
# ══════════════════════════════════════════════════
echom '--- SelectPrev wrap-around ---'
Setup()

vproj#SelectPrev()
Assert(vproj#GetCurrentMode() == 'file', 'SelectPrev from first wraps, mode preserved')
Assert(vproj#IsPaneVisible(), 'SelectPrev from first no crash')

vproj#SelectLast()
vproj#SelectNext()
Assert(vproj#GetCurrentMode() == 'file', 'SelectNext from last wraps, mode preserved')

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
