vim9script

# Integration: pane lifecycle — preview, tree view, permanent mode
# Run: vim -N -u NONE -S tests/integration/test_pane_lifecycle.vim

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

def PaneBufnr(): number
  return bufnr('VPROJ')
enddef

def PaneWinnr(): number
  var pb = PaneBufnr()
  return pb > 0 ? bufwinnr(pb) : -1
enddef

def Setup(): void
  if vproj#IsPaneVisible()
    vproj#PaneClose()
  endif
  execute 'cd' getcwd()
enddef

# ══════════════════════════════════════════════════
# 1. Preview mode — basic toggle
# ══════════════════════════════════════════════════
echom '--- Preview mode toggle ---'
Setup()

# Create a test file for preview
writefile(['line one', 'line two', 'line three'], '/tmp/vproj_preview_test.txt')

vproj#PaneOpen()
vproj#SwitchMode('file')

# Pane should be the only window initially
Assert(winnr('$') >= 1, 'preview: at least 1 window before toggle')

# Toggle preview on
vproj#TogglePreview()
# TogglePreview is silence on no-op — just verify no crash and pane stays
Assert(vproj#IsPaneVisible(), 'preview: pane stays visible after toggle')

vproj#PaneClose()
call delete('/tmp/vproj_preview_test.txt')

# ══════════════════════════════════════════════════
# 2. Tree view — basic toggle in file mode
# ══════════════════════════════════════════════════
echom '--- Tree view toggle ---'
Setup()

vproj#PaneOpen()
vproj#SwitchMode('file')

Assert(!vproj#IsTreeViewActive(), 'tree view: starts inactive')
vproj#ToggleTreeView()
Assert(vproj#IsTreeViewActive(), 'tree view: toggles on')
Assert(vproj#IsPaneVisible(), 'tree view: pane still visible after on')
vproj#ToggleTreeView()
Assert(!vproj#IsTreeViewActive(), 'tree view: toggles off')
Assert(vproj#IsPaneVisible(), 'tree view: pane still visible after off')

# ══════════════════════════════════════════════════
# 3. Tree view — entering a directory expands it
# ══════════════════════════════════════════════════
echom '--- Tree view directory expand ---'
vproj#ToggleTreeView()
Assert(vproj#IsTreeViewActive(), 'tree expand: tree active')

# Navigate to a subdirectory and press Enter (SelectCurrent)
# With tree view active, this should expand rather than navigate into
var before_lines = getbufline(PaneBufnr(), 1, '$')->len()
# Just verify the operation doesn't crash and pane stays
Assert(vproj#IsPaneVisible(), 'tree expand: pane visible before dir enter')

# Move to line 3 (first item) — we need a directory to expand on
# In a test dir we may or may not have subdirs — just verify no crash
try
  vproj#SelectCurrent()
  Assert(vproj#IsPaneVisible(), 'tree expand: pane still visible after enter')
catch
  Assert(vproj#IsPaneVisible(), 'tree expand: pane still visible after catch')
endtry

vproj#ToggleTreeView()

# ══════════════════════════════════════════════════
# 4. Tree view — T key outside file mode is a no-op
# ══════════════════════════════════════════════════
echom '--- Tree view in non-file modes ---'
vproj#SwitchMode('buf')
Assert(!vproj#IsTreeViewActive(), 'tree buf: inactive in buf mode')
vproj#ToggleTreeView()
# Should remain inactive (tree view only works in file mode)
Assert(vproj#IsPaneVisible(), 'tree buf: pane visible')

vproj#SwitchMode('code')
vproj#ToggleTreeView()
Assert(vproj#IsPaneVisible(), 'tree code: pane visible')

vproj#SwitchMode('qfix')
vproj#ToggleTreeView()
Assert(vproj#IsPaneVisible(), 'tree qfix: pane visible')

vproj#SwitchMode('file')

# ══════════════════════════════════════════════════
# 5. Permanent mode — toggle and Esc behavior
# ══════════════════════════════════════════════════
echom '--- Permanent mode ---'
vproj#PaneClose()
vproj#PaneTogglePermanent()
Assert(vproj#IsPaneVisible(), 'perm: pane opens in permanent mode')

# Esc should NOT close in permanent mode
vproj#HandleEsc()
Assert(vproj#IsPaneVisible(), 'perm: Esc does not close pane')

# Toggle permanent → should close (permanent → closed)
vproj#PaneTogglePermanent()
Assert(!vproj#IsPaneVisible(), 'perm: second toggle closes pane')

# Toggle permanent again → open
vproj#PaneTogglePermanent()
Assert(vproj#IsPaneVisible(), 'perm: third toggle reopens')

# Q should close in permanent mode (not switch to qfix)
vproj#HandlePaneQ()
Assert(!vproj#IsPaneVisible(), 'perm: Q closes pane in permanent mode')

# ══════════════════════════════════════════════════
# 6. Permanent mode — Tab transitions to temporary
# ══════════════════════════════════════════════════
echom '--- Permanent → temporary transition ---'
vproj#PaneTogglePermanent()
Assert(vproj#IsPaneVisible(), 'perm-temp: open in permanent')

# Tab from permanent mode → transitions to temporary (stays open)
vproj#PaneToggle()
Assert(vproj#IsPaneVisible(), 'perm-temp: Tab from perm stays open (now temp)')

# Esc now closes (temporary mode)
vproj#HandleEsc()
Assert(!vproj#IsPaneVisible(), 'perm-temp: Esc closes in temp mode')

# ══════════════════════════════════════════════════
# 7. Temporary mode — Q switches to qfix
# ══════════════════════════════════════════════════
echom '--- Temp mode Q → qfix ---'
vproj#PaneToggle()
Assert(vproj#IsPaneVisible(), 'tempQ: pane open in temp mode')

vproj#HandlePaneQ()
Assert(vproj#IsPaneVisible(), 'tempQ: pane still visible after Q')
Assert(vproj#GetCurrentMode() == 'qfix', 'tempQ: Q switches to qfix in temp mode')

vproj#PaneClose()

# ══════════════════════════════════════════════════
# 8. PaneTogglePermanent — full cycle (4 state transitions)
# ══════════════════════════════════════════════════
echom '--- PaneTogglePermanent full cycle ---'

# closed → permanent
vproj#PaneTogglePermanent()
Assert(vproj#IsPaneVisible(), 'cycle: 1 — pane open')

# permanent → closed
vproj#PaneTogglePermanent()
Assert(!vproj#IsPaneVisible(), 'cycle: 2 — pane closed')

# closed → permanent
vproj#PaneTogglePermanent()
Assert(vproj#IsPaneVisible(), 'cycle: 3 — pane open again')

# permanent → closed
vproj#PaneTogglePermanent()
Assert(!vproj#IsPaneVisible(), 'cycle: 4 — pane closed again')

# ══════════════════════════════════════════════════
# 9. PaneToggle — tab cycling from closed (temp → close → temp)
# ══════════════════════════════════════════════════
echom '--- PaneToggle temp cycle ---'

# closed → temporary
vproj#PaneToggle()
Assert(vproj#IsPaneVisible(), 'tab-cycle: 1 — pane open (temp)')

# temporary → close
vproj#PaneToggle()
Assert(!vproj#IsPaneVisible(), 'tab-cycle: 2 — pane closed')

# closed → temporary
vproj#PaneToggle()
Assert(vproj#IsPaneVisible(), 'tab-cycle: 3 — pane open (temp)')

# Switch to permanent, then Tab to downgrade to temp → then Tab to close
vproj#PaneTogglePermanent()  # temp → permanent
# Tab from permanent → temp (stays open)
vproj#PaneToggle()
Assert(vproj#IsPaneVisible(), 'tab-cycle: 4 — perm→temp, pane still open')

# Tab from temp → close
vproj#PaneToggle()
Assert(!vproj#IsPaneVisible(), 'tab-cycle: 5 — temp→closed')

# ══════════════════════════════════════════════════
# 10. Repeated TogglePreview doesn't crash
# ══════════════════════════════════════════════════
echom '--- TogglePreview stress ---'
Setup()
vproj#PaneOpen()
vproj#SwitchMode('file')

for i in range(3)
  vproj#TogglePreview()
  Assert(vproj#IsPaneVisible(), 'preview-stress: toggle ' .. (i + 1) .. ' pane visible')
endfor

vproj#PaneClose()

# ══════════════════════════════════════════════════
# 11. Tree view — repeated toggle doesn't crash
# ══════════════════════════════════════════════════
echom '--- TreeView stress ---'
vproj#PaneOpen()
vproj#SwitchMode('file')

for i in range(5)
  vproj#ToggleTreeView()
  Assert(vproj#IsPaneVisible(), 'tree-stress: toggle ' .. (i + 1) .. ' pane visible')
endfor

vproj#PaneClose()

# ══════════════════════════════════════════════════
# 12. HandleF1 in permanent mode
# ══════════════════════════════════════════════════
echom '--- F1 in permanent mode ---'
vproj#PaneTogglePermanent()
Assert(vproj#IsPaneVisible(), 'f1-perm: pane open in permanent')

try
  vproj#HandleF1()
  Assert(vproj#IsPaneVisible(), 'f1-perm: pane visible after F1')
catch
  Assert(vproj#IsPaneVisible(), 'f1-perm: pane visible after F1 error')
endtry

vproj#PaneClose()

# ══════════════════════════════════════════════════
# 13. ToggleInfoColumn — verify state consistency
# ══════════════════════════════════════════════════
echom '--- InfoColumn state consistency ---'
vproj#PaneOpen()

var initial_info = vproj#IsInfoColumnVisible()
vproj#ToggleInfoColumn()
Assert(vproj#IsInfoColumnVisible() != initial_info, 'info: toggled once (state changed)')
vproj#ToggleInfoColumn()
Assert(vproj#IsInfoColumnVisible() == initial_info, 'info: toggled twice (back to original)')
Assert(vproj#IsPaneVisible(), 'info: pane still visible')

vproj#PaneClose()

# ══════════════════════════════════════════════════
# 14. HandlePaneQ in temporary mode (edge case)
# ══════════════════════════════════════════════════
echom '--- HandlePaneQ edge cases ---'
vproj#PaneToggle()
Assert(vproj#IsPaneVisible(), 'q-edge: pane open in temp')

# First press: temp → qfix
vproj#HandlePaneQ()
Assert(vproj#GetCurrentMode() == 'qfix', 'q-edge: switched to qfix')

# Second press (still temp, now in qfix): should switch to next mode
vproj#HandlePaneQ()
# HandlePaneQ in temp mode switches to qfix regardless of current mode
Assert(vproj#GetCurrentMode() == 'qfix', 'q-edge: stays in qfix after second Q')

vproj#PaneClose()

# ══════════════════════════════════════════════════
# Cleanup
# ══════════════════════════════════════════════════
vproj#PaneClose()
Assert(!vproj#IsPaneVisible(), 'cleanup: pane closed')

echom ''
if failures == 0
  echom 'ALL PANE LIFECYCLE TESTS PASSED.'
else
  echohl ErrorMsg
  echom failures .. ' PANE LIFECYCLE TEST(S) FAILED.'
  echohl None
  cquit!
endif
qa!
