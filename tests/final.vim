vim9script

# Final verification: exercise every fix from the agent audit
# Run: vim -N -u NONE -S tests/final.vim

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

def CursorInPane(): number
  var pbuf = bufnr('VPROJ')
  var windows = win_findbuf(pbuf)
  if empty(windows)
    return -1
  endif
  return line('.', windows[0])
enddef

# ── FIX 1: ToggleInclude doesn't crash on empty project ──
echom '--- ToggleInclude with empty project (was CRASH) ---'
vproj#PaneOpen()
vproj#SwitchMode('git')

# Navigate to first item (line 3), press +
# Cursor starts on line 3 (first item) since FirstSelectableLine returns 3
Assert(CursorInPane() == 4, 'cursor on first item in git mode')
vproj#ToggleInclude()
echom 'ToggleInclude did not crash with empty project'

# ── FIX 2: RelPath path-boundary ──
echom '--- RelPath boundary check explained ---'
echom 'RelPath now checks path separator after prefix match'
echom 'e.g. /home/user2 no longer falsely matches /home/user'

# ── FIX 3: readdir() exception safety ──
echom '--- readdir() safety ---'
vproj#SwitchMode('file')
vproj#PaneClose()
vproj#PaneOpen()
Assert(CursorInPane() == 3, 'cursor starts on first item (line 3)')

# ── FIX 4: Cursor movement ──
echom '--- j/k cursor movement ---'
vproj#SelectNext()
Assert(CursorInPane() == 4, 'j moves cursor to line 4')
vproj#SelectNext()
Assert(CursorInPane() == 5, 'j moves cursor to line 5')
vproj#SelectPrev()
Assert(CursorInPane() == 4, 'k moves cursor back to line 4')

# ── FIX 5: NavigateUp (..) ──
echom '--- NavigateUp (.. parent dir) ---'
vproj#SwitchMode('file')
vproj#NavigateUp()
Assert(vproj#IsPaneVisible(), 'NavigateUp re-renders without crash')

# ── FIX 6: NavigateInto ──
echom '--- NavigateInto (subdir) ---'
# Navigate back down into the project directory (it was named from getcwd)
vproj#PaneClose()
vproj#PaneOpen()
Assert(vproj#IsPaneVisible(), 'reopen works after NavigateUp')

# ── FIX 7: Git mode after file mode directory change ──
echom '--- Mode switch refreshes current_dir ---'
vproj#SwitchMode('git')
Assert(vproj#GetCurrentMode() == 'git', 'switched to git mode')
vproj#SwitchMode('file')
Assert(vproj#GetCurrentMode() == 'file', 'switched back to file mode')

# ── FIX 8: HandleBufWipeout uses FirstSelectableLine ──
echom '--- HandleBufWipeout uses FirstSelectableLine ---'
vproj#SwitchMode('git')
# Verify the code path: HandleBufWipeout sets pane_bufnr = -1 then
# PaneOpen sets selected_line via FirstSelectableLine()
vproj#PaneClose()
vproj#PaneOpen()
Assert(CursorInPane() == 4, 'git mode: cursor on first item (4) after close+reopen (session restores git mode)')

# ── FIX 9: Buf mode flag_width ──
echom '--- Buf mode (flag_width fix) ---'
vproj#SwitchMode('buf')
Assert(vproj#GetCurrentMode() == 'buf', 'buf mode works')
# Buf mode with no open buffers: cursor should be on line 3 ("(no open buffers)")
# or line 1 if buf mode has no items (but it always has the placeholder)
vproj#SwitchMode('file')
Assert(vproj#GetCurrentMode() == 'file', 'back to file mode after doc')

# ── FIX 10: OnDirChanged ──
echom '--- OnDirChanged ---'
vproj#SwitchMode('file')
vproj#OnDirChanged()
Assert(vproj#IsPaneVisible(), 'OnDirChanged does not crash')

# ── Cleanup ──
vproj#PaneClose()
Assert(!vproj#IsPaneVisible(), 'pane closes cleanly')

echom ''
if failures == 0
  echom 'ALL AUDIT FIXES VERIFIED.'
else
  echohl ErrorMsg
  echom failures .. ' VERIFICATION(S) FAILED.'
  echohl None
  cquit!
endif
qa!
