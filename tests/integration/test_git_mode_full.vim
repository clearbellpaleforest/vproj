vim9script

# Integration test: Code mode — project creation, include/exclude, .vproj write
# Run: vim -N -u NONE -S tests/integration/test_git_mode_full.vim

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

echom '=== Code Mode Integration Tests ==='

# ── Setup: open pane in code mode ──
if vproj#IsPaneVisible()
  vproj#PaneClose()
endif
vproj#PaneOpen()
vproj#SwitchMode('code')

# ── Test 1: Code mode starts with correct layout ──
# Line 1 = mode menu, line 2 = project status, line 3 = separator, line 4 = first item
Assert(PaneCursorLine() == 4, 'git mode: cursor starts on first item (line 4)')
Assert(vproj#GetCurrentMode() == 'code', 'code mode: GetCurrentMode returns code')

# ── Test 2: Navigate up/down respects code mode header ──
vproj#SelectNext()
Assert(PaneCursorLine() == 5, 'git mode: SelectNext moves to line 5')
vproj#SelectPrev()
Assert(PaneCursorLine() == 4, 'git mode: SelectPrev returns to line 4')

# ── Test 3: Switch modes, cursor lands on correct line ──
vproj#SwitchMode('file')
Assert(PaneCursorLine() == 3, 'switch to file mode: cursor on line 3')
Assert(vproj#GetCurrentMode() == 'file', 'GetCurrentMode returns file')

vproj#SwitchMode('buf')
Assert(PaneCursorLine() == 3, 'switch to buf mode: cursor on line 3')
Assert(vproj#GetCurrentMode() == 'buf', 'GetCurrentMode returns buf')

vproj#SwitchMode('code')
Assert(PaneCursorLine() == 4, 'switch back to git mode: cursor on line 4')

# ── Test 4: SelectFirst/SelectLast jump to correct bounds ──
vproj#SwitchMode('file')
vproj#SelectFirst()
Assert(PaneCursorLine() == 3, 'SelectFirst goes to line 3 in file mode')
vproj#SwitchMode('code')
vproj#SelectFirst()
Assert(PaneCursorLine() == 4, 'SelectFirst goes to line 4 in git mode')

# ── Test 5: Close/reopen preserves mode & cursor ──
vproj#PaneClose()
Assert(!vproj#IsPaneVisible(), 'pane closed')
vproj#PaneOpen()
# Session persistence restores last mode (git) after close/reopen
Assert(PaneCursorLine() == 4, 'reopen: cursor on first item in git mode (session restore)')

# ── Test 6: NavigateUp from code mode works ──
vproj#SwitchMode('code')
vproj#NavigateUp()
Assert(vproj#IsPaneVisible(), 'NavigateUp in git mode keeps pane visible')

# ── Cleanup ──
vproj#PaneClose()
Assert(!vproj#IsPaneVisible(), 'pane closes cleanly')

echom ''
if failures == 0
  echom 'ALL CODE MODE INTEGRATION TESTS PASSED.'
else
  echohl ErrorMsg
  echom failures .. ' CODE MODE TEST(S) FAILED.'
  echohl None
  cquit!
endif
qa!
