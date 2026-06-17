vim9script

# Smoke test for VPROJ plugin
# Run: vim -N -u NONE -S tests/smoke.vim

var failures: number = 0

def Assert(cond: bool, msg: string): void
  if !cond
    echohl ErrorMsg
    echom 'FAIL: ' .. msg
    echohl None
    failures += 1
  else
    echom 'PASS: ' .. msg
  endif
enddef

# Load the plugin
set rtp+=src
runtime! plugin/vproj.vim

# Test 1: Plugin loaded
Assert(exists('g:loaded_vproj'), 'Plugin loads without errors')

# Test 2: Pane starts closed
Assert(!vproj#IsPaneVisible(), 'Pane starts closed')

# Test 3: Open pane
vproj#PaneOpen()
Assert(vproj#IsPaneVisible(), 'Pane opens')

# Test 4: Default mode is file
Assert(vproj#GetCurrentMode() == 'file', 'Default mode is file')

# Test 5: Switch to buf mode
vproj#SwitchMode('buf')
Assert(vproj#GetCurrentMode() == 'buf', 'Switch to buf mode')

# Test 6: Switch to file mode
vproj#SwitchMode('file')
Assert(vproj#GetCurrentMode() == 'file', 'Switch back to file mode')

# Test 7: Pane width is default 40
Assert(vproj#GetPaneWidth() == 40, 'Default pane width is 40')

# Test 8: Grow and shrink
vproj#PaneGrow()
Assert(vproj#GetPaneWidth() == 41, 'PaneGrow increases width')
vproj#PaneShrink()
Assert(vproj#GetPaneWidth() == 40, 'PaneShrink decreases width')

# Test 9: Switch to git mode
vproj#SwitchMode('git')
Assert(vproj#GetCurrentMode() == 'git', 'Switch to git mode')

# Test 10: Switch back to file mode
vproj#SwitchMode('file')
Assert(vproj#GetCurrentMode() == 'file', 'Switch back from git mode')

# Test 11: Close pane
vproj#PaneClose()
Assert(!vproj#IsPaneVisible(), 'Pane closes')

# Test 12: Toggle open
vproj#PaneToggle()
Assert(vproj#IsPaneVisible(), 'PaneToggle opens')
vproj#PaneToggle()
Assert(!vproj#IsPaneVisible(), 'PaneToggle closes')

# Report
echom ''
if failures == 0
  echom 'All smoke tests passed.'
else
  echohl ErrorMsg
  echom failures .. ' test(s) FAILED.'
  echohl None
  cquit!
endif

qa!
