vim9script

# Regression test found while verifying the 2026-11f round: the "adopt a manual
# resize" logic treated the width a pane gets from `:only` (the whole screen)
# as the user's chosen width, so after `:only` and one WinResized the pane was
# stuck at the 80-column maximum.
# Run: vim -N -u NONE -i NONE -S tests/integration/test_audit_2026_11g_adopt.vim -c 'cquit!'

$XDG_CACHE_HOME = tempname()
execute 'set rtp^=' .. fnameescape(fnamemodify(expand('<script>:p'), ':h:h:h') .. '/src')
runtime! plugin/vproj.vim
set nomore columns=160 lines=40 ttimeout ttimeoutlen=0

var failures: number = 0
var saved_cwd: string = getcwd()
var root: string = resolve(fnamemodify(tempname(), ':p')) .. '_vproj_adopt'
mkdir(root, 'p')

def Assert(cond: bool, msg: string): void
  if !cond
    echohl ErrorMsg | echom 'FAIL: ' .. msg | echohl None
    failures += 1
  else
    echom 'PASS: ' .. msg
  endif
enddef

def PaneWinWidth(): number
  var wnr: number = bufwinnr(vproj#GetPaneBufnr())
  return wnr > 0 ? winwidth(wnr) : -1
enddef

for f in ['a.txt', 'b.txt', 'c.txt']
  writefile([f], root .. '/' .. f)
endfor
execute 'cd ' .. fnameescape(root)

# Permanent pane beside an edit window, at its configured width.
vproj#PaneTogglePermanent()
var configured: number = vproj#GetPaneWidth()
Assert(PaneWinWidth() == configured, 'start: pane window is its configured width (' .. PaneWinWidth() .. ' vs ' .. configured .. ')')

# :only from the pane gives it the whole screen. That is not a width anyone chose.
win_gotoid(win_findbuf(vproj#GetPaneBufnr())[0])
only
Assert(winnr('$') == 1, ':only left the pane as the only window')
vproj#HandleResize()
Assert(vproj#GetPaneWidth() == configured, ':only then WinResized keeps the configured width (' .. vproj#GetPaneWidth() .. ' vs ' .. configured .. ')')

# Opening a file makes the edit window again; the pane must be back at its width.
vproj#SelectByNavChar('a')
Assert(PaneWinWidth() == configured, 'after opening a file the pane window is its configured width (' .. PaneWinWidth() .. ' vs ' .. configured .. ')')

# A real manual resize (pane beside another window) is still adopted.
var pane_wid: number = win_findbuf(vproj#GetPaneBufnr())[0]
win_execute(pane_wid, 'vertical resize 55')
vproj#HandleResize()
Assert(vproj#GetPaneWidth() == 55, 'a manual resize beside another window is still adopted (' .. vproj#GetPaneWidth() .. ')')

# Cleanup
if vproj#IsPaneVisible()
  vproj#PaneClose()
endif
silent! only!
silent! :%bwipeout!
execute 'cd ' .. fnameescape(saved_cwd)
delete(root, 'rf')

echom ''
if failures == 0
  echom 'ALL TESTS PASSED.'
else
  echohl ErrorMsg | echom failures .. ' TEST(S) FAILED.' | echohl None
  cquit!
endif
qa!
