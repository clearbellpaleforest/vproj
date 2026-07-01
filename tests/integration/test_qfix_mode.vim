vim9script

# Integration test: Qfix mode — quickfix list display, jump-to-entry, empty state
# Run: vim -N -u NONE -S tests/integration/test_qfix_mode.vim

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

def PaneLine(lnum: number): string
  var pbuf = bufnr('VPROJ')
  var lines = getbufline(pbuf, lnum)
  return empty(lines) ? '' : lines[0]
enddef

echom '=== Qfix Mode Integration Tests ==='

# ── Setup: open pane in qfix mode with empty qflist ──
vproj#PaneOpen()
vproj#SwitchMode('qfix')

Assert(vproj#GetCurrentMode() == 'qfix', 'qfix mode active with empty qflist')
Assert(vproj#IsPaneVisible(), 'pane visible in qfix mode')

# ── Layout: empty state ──
var line1 = PaneLine(1)
Assert(line1 =~ '\[F\]ile', 'qfix empty: line 1 is mode menu')
Assert(line1 =~ '\[Q\]fix', 'qfix empty: qfix label in mode menu')

var line2 = PaneLine(2)
Assert(line2 =~ '^-\+$', 'qfix empty: line 2 is separator')

var line3 = PaneLine(3)
Assert(line3 =~ 'no quickfix', 'qfix empty: line 3 shows empty message')

# ── Switch to qfix from other modes ──
vproj#SwitchMode('file')
vproj#SwitchMode('qfix')
Assert(vproj#GetCurrentMode() == 'qfix', 'file→qfix switch works')

vproj#SwitchMode('buf')
vproj#SwitchMode('qfix')
Assert(vproj#GetCurrentMode() == 'qfix', 'buf→qfix switch works')

vproj#SwitchMode('code')
vproj#SwitchMode('qfix')
Assert(vproj#GetCurrentMode() == 'qfix', 'git→qfix switch works')

# ── Populate qflist with test entries ──
# Use project-relative paths so qfix displays readable relative paths
writefile(['line one', 'line two', 'line three'], 'test_a.txt')
writefile(['alpha', 'beta', 'gamma'], 'test_b.txt')

# Build a qflist manually
var qflist = [
  {filename: getcwd() .. '/test_a.txt', lnum: 1, col: 1, text: 'first entry', valid: true},
  {filename: getcwd() .. '/test_a.txt', lnum: 3, col: 1, text: 'third line', valid: true},
  {filename: getcwd() .. '/test_b.txt', lnum: 2, col: 5, text: 'beta entry', valid: true},
]
setqflist(qflist)

# Reopen pane to refresh
vproj#PaneClose()
vproj#PaneOpen()
vproj#SwitchMode('qfix')

# ── Layout: populated state ──
var p1 = PaneLine(1)
Assert(p1 =~ '\[F\]ile', 'qfix populated: line 1 is mode menu')
var p2 = PaneLine(2)
Assert(p2 =~ '^-\+$', 'qfix populated: line 2 is separator')

# Should have 3 entries starting at line 3
Assert(PaneCursorLine() == 3, 'qfix populated: cursor on first entry (line 3)')
var p3 = PaneLine(3)
Assert(p3 =~ 'test_a.txt', 'qfix populated: line 3 has first filename')
Assert(p3 =~ 'first entry', 'qfix populated: line 3 has entry text')

# ── Navigation ──
vproj#SelectNext()
Assert(PaneCursorLine() == 4, 'qfix: SelectNext moves to line 4')
vproj#SelectNext()
Assert(PaneCursorLine() == 5, 'qfix: SelectNext moves to line 5')

vproj#SelectPrev()
Assert(PaneCursorLine() == 4, 'qfix: SelectPrev back to line 4')

vproj#SelectFirst()
Assert(PaneCursorLine() == 3, 'qfix: SelectFirst goes to line 3')

vproj#SelectLast()
Assert(PaneCursorLine() == 5, 'qfix: SelectLast goes to line 5')

# ── SelectByNavChar ──
vproj#SelectByNavChar('c')
Assert(PaneCursorLine() == 3, 'qfix: nav char c jumps to line 3')

# ── PaneGrow/Shrink in qfix ──
var w0 = vproj#GetPaneWidth()
vproj#PaneGrow()
Assert(vproj#GetPaneWidth() == w0 + 1, 'qfix: PaneGrow works')
vproj#PaneShrink()
Assert(vproj#GetPaneWidth() == w0, 'qfix: PaneShrink works')

# ── NavigateUp in qfix ──
vproj#NavigateUp()
Assert(vproj#IsPaneVisible(), 'qfix: NavigateUp does not crash')

# ── ToggleInfoColumn in qfix ──
vproj#ToggleInfoColumn()
Assert(vproj#IsPaneVisible(), 'qfix: ToggleInfoColumn does not crash')

# ── Refresh ──
vproj#Refresh()
Assert(vproj#GetCurrentMode() == 'qfix', 'qfix: Refresh preserves mode')

# ── Close pane ──
vproj#PaneClose()
Assert(!vproj#IsPaneVisible(), 'qfix: pane closes cleanly')

# ── Cleanup ──
delete('test_a.txt')
delete('test_b.txt')

echom ''
if failures == 0
  echom 'ALL QFIX MODE INTEGRATION TESTS PASSED.'
else
  echohl ErrorMsg
  echom failures .. ' QFIX MODE TEST(S) FAILED.'
  echohl None
  cquit!
endif
qa!
