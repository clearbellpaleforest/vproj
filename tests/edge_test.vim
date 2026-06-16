vim9script

# Edge case stress tests
# Run: vim -N -u NONE -S tests/edge_test.vim

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

# ── Width bounds ──
vproj#PaneOpen()
Assert(vproj#GetPaneWidth() == 40, 'default width is 40')

vproj#SetPaneWidth(10)
Assert(vproj#GetPaneWidth() == 40, 'SetPaneWidth(10) rejected (below min 20)')

vproj#SetPaneWidth(90)
Assert(vproj#GetPaneWidth() == 40, 'SetPaneWidth(90) rejected (above max 80)')

vproj#SetPaneWidth(30)
Assert(vproj#GetPaneWidth() == 30, 'SetPaneWidth(30) accepted')

while vproj#GetPaneWidth() < 80 | vproj#PaneGrow() | endwhile
Assert(vproj#GetPaneWidth() == 80, 'PaneGrow to max 80')

vproj#PaneGrow()
Assert(vproj#GetPaneWidth() == 80, 'PaneGrow past max clamped at 80')

while vproj#GetPaneWidth() > 20 | vproj#PaneShrink() | endwhile
Assert(vproj#GetPaneWidth() == 20, 'PaneShrink to min 20')

vproj#PaneShrink()
Assert(vproj#GetPaneWidth() == 20, 'PaneShrink past min clamped at 20')

vproj#SetPaneWidth(40)

# ── NavigateUp at root ──
vproj#NavigateUp()
Assert(vproj#IsPaneVisible(), 'NavigateUp 1x keeps pane open')
vproj#NavigateUp()
vproj#NavigateUp()
vproj#NavigateUp()
Assert(vproj#IsPaneVisible(), 'NavigateUp 4x (at root) keeps pane open')

# ── Invalid mode ──
vproj#SwitchMode('invalid')
Assert(vproj#GetCurrentMode() == 'file', 'SwitchMode(invalid) ignored, stays file')

# ── ToggleInclude in file mode ──
vproj#ToggleInclude()
Assert(vproj#IsPaneVisible(), 'ToggleInclude file mode does not crash')

# ── CloseBuffer in doc mode with no buffers ──
vproj#SwitchMode('doc')
vproj#CloseBuffer()
Assert(vproj#IsPaneVisible(), 'CloseBuffer doc mode no buffers does not crash')

# ── CloseBuffer in file mode (wrong mode) ──
vproj#SwitchMode('file')
vproj#CloseBuffer()
Assert(vproj#IsPaneVisible(), 'CloseBuffer file mode does not crash')

# ── Code mode: ToggleInclude on parent entry ──
vproj#SwitchMode('code')
# Navigate past line 1 (menu) and 2 (status), land on first item
vproj#SelectNext()
vproj#SelectNext()
Assert(vproj#IsPaneVisible(), 'code mode: moved cursor down')
vproj#ToggleInclude()
Assert(vproj#IsPaneVisible(), 'code mode: ToggleInclude on first item (no project) does not crash')

# ── Refresh when pane is closed ──
vproj#PaneClose()
vproj#Refresh()
Assert(!vproj#IsPaneVisible(), 'Refresh when closed does not re-open pane')

# ── Re-open after close ──
vproj#PaneOpen()
Assert(vproj#IsPaneVisible(), 'Re-open after close works')

# ── HandleBufWipeout call ──
vproj#HandleBufWipeout()
Assert(!vproj#IsPaneVisible(), 'HandleBufWipeout resets visible state')

# ── PaneToggle idempotence ──
vproj#PaneToggle()
Assert(vproj#IsPaneVisible(), 'PaneToggle opens closed pane')
vproj#PaneToggle()
Assert(!vproj#IsPaneVisible(), 'PaneToggle closes open pane')
vproj#PaneToggle()
Assert(vproj#IsPaneVisible(), 'PaneToggle re-opens')

# ── SetPaneWidth when pane is visible ──
vproj#SetPaneWidth(50)
Assert(vproj#GetPaneWidth() == 50, 'SetPaneWidth(50) when visible works')
vproj#SetPaneWidth(40)

# ── SelectCurrent on empty items ──
# Move cursor to an empty area and call SelectCurrent
vproj#SwitchMode('doc')
# Should handle gracefully if no buffers
vproj#SelectCurrent()
Assert(vproj#GetCurrentMode() == 'doc', 'SelectCurrent in doc mode no crash')

# ── Mode switch from empty state ──
vproj#SwitchMode('file')
Assert(vproj#IsPaneVisible(), 'Switch back to file mode works')
vproj#SwitchMode('code')
Assert(vproj#GetCurrentMode() == 'code', 'Switch to code mode works')
vproj#SwitchMode('file')
Assert(vproj#GetCurrentMode() == 'file', 'Switch back to file mode works')

# ── SelectNext/Prev wrapping ──
# In doc mode with no buffers, there's only 3 lines: menu, separator, "(empty)"
# SelectNext should wrap
vproj#SelectNext()
Assert(vproj#GetCurrentMode() == 'file', 'SelectNext in file mode no crash')

# Cleanup
vproj#PaneClose()

echom ''
if failures == 0
  echom 'ALL EDGE CASE TESTS PASSED.'
else
  echohl ErrorMsg
  echom failures .. ' EDGE CASE TEST(S) FAILED.'
  echohl None
  cquit!
endif
qa!
