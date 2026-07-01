vim9script

# Integration test: Paging — activate paging with many items
# Run: vim -N -u NONE -S tests/integration/test_paging.vim

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

echom '=== Paging Integration Tests ==='

# ── Setup: create temp directory with many files ──
var saved_cwd: string = getcwd()
var tmpdir: string = '/tmp/vproj_paging_test'
silent! call delete(tmpdir, 'rf')
mkdir(tmpdir)
var f: number = 0
while f < 60
  writefile(['test'], printf('%s/file_%02d.txt', tmpdir, f))
  f += 1
endwhile

# ── Navigate to temp dir and open pane ──
execute 'cd' tmpdir
vproj#PaneOpen()
vproj#SwitchMode('file')

Assert(vproj#IsPaneVisible(), 'pane visible with 60-item directory')
Assert(PaneCursorLine() == 3, 'cursor starts on line 3')

# ── Navigate through items without crashing ──
vproj#SelectNext()
Assert(PaneCursorLine() == 4, 'SelectNext to line 4')
vproj#SelectNext()
Assert(PaneCursorLine() == 5, 'SelectNext to line 5')
vproj#SelectPrev()
Assert(PaneCursorLine() == 4, 'SelectPrev back to line 4')

# ── Jump to first and last ──
vproj#SelectFirst()
Assert(PaneCursorLine() == 3, 'SelectFirst to line 3')

# ── NextPage/PrevPage don't crash ──
vproj#NextPage()
Assert(vproj#IsPaneVisible(), 'NextPage does not crash')

vproj#PrevPage()
Assert(vproj#IsPaneVisible(), 'PrevPage does not crash')

# ── Mode switch with paged items ──
vproj#SwitchMode('buf')
Assert(PaneCursorLine() == 3, 'buf mode after paged file mode: cursor on line 3')

vproj#SwitchMode('code')
Assert(PaneCursorLine() == 4, 'git mode after paged file mode: cursor on line 4')

# ── Nav offset doesn't leak between modes ──
vproj#ShiftNavForward()
vproj#SwitchMode('file')
vproj#SelectFirst()
Assert(PaneCursorLine() == 3, 'nav shifted then mode switched: SelectFirst still line 3')

# ── Cleanup ──
vproj#PaneClose()
execute 'cd' saved_cwd
silent! call delete(tmpdir, 'rf')

Assert(!vproj#IsPaneVisible(), 'pane closed cleanly')

echom ''
if failures == 0
  echom 'ALL PAGING TESTS PASSED.'
else
  echohl ErrorMsg
  echom failures .. ' PAGING TEST(S) FAILED.'
  echohl None
  cquit!
endif
qa!
