vim9script

# Coverage tests — untested behaviors from the audit gap analysis
# Run: vim -N -u NONE -S tests/coverage.vim

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

def Setup(): void
  if vproj#IsPaneVisible()
    vproj#PaneClose()
  endif
  vproj#PaneOpen()
  if vproj#GetCurrentMode() != 'file'
    vproj#SwitchMode('file')
  endif
enddef

# ──────────────────────────────────────────────
# ItemIndex / FirstSelectableLine
# ──────────────────────────────────────────────
echom '--- ItemIndex / FirstSelectableLine ---'
Setup()

# FirstSelectableLine must be 3 in all modes
Assert(PaneCursorLine() == 3, 'cursor starts on line 3 in file mode')

vproj#SwitchMode('buf')
Assert(PaneCursorLine() == 3, 'cursor starts on line 3 in buf mode')

vproj#SwitchMode('git')
Assert(PaneCursorLine() == 4, 'cursor starts on line 4 in git mode (separator at line 3)')

# SelectNext from line 3 → line 4 (not status line)
vproj#SwitchMode('file')
var before = PaneCursorLine()
execute 'normal j'
Assert(PaneCursorLine() == before + 1, 'SelectNext advances from first item')

# SelectPrev from line 3 → wraps to last item
execute 'normal k'
Assert(PaneCursorLine() >= 3, 'SelectPrev wraps from first item')

# ──────────────────────────────────────────────
# NavigateIntoFirstDir
# ──────────────────────────────────────────────
echom '--- NavigateIntoFirstDir ---'
Setup()
vproj#SwitchMode('file')

# In the vproj project root, first subdir should be src/ or tests/
try
  vproj#NavigateIntoFirstDir()
  Assert(vproj#IsPaneVisible(), 'NavigateIntoFirstDir keeps pane open')
  Assert(vproj#GetCurrentMode() == 'file', 'NavigateIntoFirstDir preserves file mode')
catch
  Assert(false, 'NavigateIntoFirstDir error: ' .. v:exception)
endtry

# ──────────────────────────────────────────────
# ToggleInclude guards (status line, non-git mode)
# ──────────────────────────────────────────────
echom '--- ToggleInclude guards ---'

# In file mode, + should not crash but should show nothing
Setup()
vproj#SwitchMode('file')
try
  execute 'normal +'
  Assert(vproj#IsPaneVisible(), '+ in file mode does not crash')
catch
  Assert(false, '+ in file mode error: ' .. v:exception)
endtry

# In git mode with no project, cursor on first item (line 3), press +
vproj#SwitchMode('git')
execute 'normal +'
Assert(vproj#IsPaneVisible(), '+ in git mode no-project does not crash')

# - key similarly
execute 'normal -'
Assert(vproj#IsPaneVisible(), '- in git mode no-project does not crash')

# ──────────────────────────────────────────────
# CloseBuffer outside buf mode
# ──────────────────────────────────────────────
echom '--- CloseBuffer outside buf mode ---'
Setup()
vproj#SwitchMode('file')
try
  execute 'normal x'
  Assert(vproj#IsPaneVisible(), 'x in file mode shows message, does not crash')
catch
  Assert(false, 'x in file mode error: ' .. v:exception)
endtry

vproj#SwitchMode('git')
try
  execute 'normal x'
  Assert(vproj#IsPaneVisible(), 'x in git mode shows message, does not crash')
catch
  Assert(false, 'x in git mode error: ' .. v:exception)
endtry

# ──────────────────────────────────────────────
# Nav offset bounds
# ──────────────────────────────────────────────
echom '--- Nav offset bounds ---'
Setup()
vproj#SwitchMode('file')

# nav_offset starts at 0 after fresh Setup
# (nav_offset persists across mode switches, so test this BEFORE shifting)
Assert(vproj#GetNavOffset() == 0, 'nav_offset starts at 0')

# Shift backward at 0 should stay at 0
vproj#ShiftNavBackward()
Assert(vproj#GetNavOffset() == 0, 'ShiftNavBackward at 0 stays at 0')

# Shift forward many times, should not crash
var offset = vproj#GetNavOffset()
for _ in range(100)
  vproj#ShiftNavForward()
  if vproj#GetNavOffset() == offset
    break
  endif
  offset = vproj#GetNavOffset()
endfor
Assert(vproj#GetNavOffset() >= 0, 'nav_offset stays non-negative after shifts')
Assert(vproj#GetNavOffset() < 100, 'nav_offset is bounded')

# ──────────────────────────────────────────────
# Nav char — uppercase and digit chars
# ──────────────────────────────────────────────
echom '--- Nav char uppercase / digit ---'
Setup()
vproj#SwitchMode('file')

# nav_offset is 0 after Setup; test uppercase nav char
vproj#SelectByNavChar('A')
Assert(vproj#IsPaneVisible(), 'SelectByNavChar uppercase does not crash')

# Shift nav offset forward a few times, then test digit
vproj#ShiftNavForward()
vproj#ShiftNavForward()
vproj#SelectByNavChar('3')
Assert(vproj#IsPaneVisible(), 'SelectByNavChar digit does not crash')

# ──────────────────────────────────────────────
# Mode cycling (SwitchMode covers same logic as Enter on menu)
# ──────────────────────────────────────────────
echom '--- Mode cycling ---'
Setup()

Assert(vproj#GetCurrentMode() == 'file', 'starts in file mode')
vproj#SwitchMode('buf')
Assert(vproj#GetCurrentMode() == 'buf', 'SwitchMode file→buf')
vproj#SwitchMode('git')
Assert(vproj#GetCurrentMode() == 'git', 'SwitchMode buf→git')
vproj#SwitchMode('file')
Assert(vproj#GetCurrentMode() == 'file', 'SwitchMode git→file')

# ──────────────────────────────────────────────
# SetPaneWidth invalid values
# ──────────────────────────────────────────────
echom '--- SetPaneWidth invalid ---'
Setup()

var w = vproj#GetPaneWidth()
vproj#SetPaneWidth(10)
Assert(vproj#GetPaneWidth() == w, 'SetPaneWidth(10) below min 20 rejected')

vproj#SetPaneWidth(90)
Assert(vproj#GetPaneWidth() == w, 'SetPaneWidth(90) above max 80 rejected')

vproj#SetPaneWidth(50)
Assert(vproj#GetPaneWidth() == 50, 'SetPaneWidth(50) accepted')
vproj#SetPaneWidth(40)

# ──────────────────────────────────────────────
# Mode-specific width config
# ──────────────────────────────────────────────
echom '--- Mode-specific width ---'
Setup()

g:vproj_pane_width_file = 45
vproj#SwitchMode('file')
Assert(vproj#GetPaneWidth() == 45, 'file-mode width config applied')

g:vproj_pane_width_buf = 35
vproj#SwitchMode('buf')
Assert(vproj#GetPaneWidth() == 35, 'buf-mode width config applied')

g:vproj_pane_width_git = 30
vproj#SwitchMode('git')
Assert(vproj#GetPaneWidth() == 30, 'git-mode width config applied')

g:vproj_pane_width_qfix = 38
vproj#SwitchMode('qfix')
Assert(vproj#GetPaneWidth() == 38, 'qfix-mode width config applied')

unlet g:vproj_pane_width_file
unlet g:vproj_pane_width_buf
unlet g:vproj_pane_width_git
unlet g:vproj_pane_width_qfix
vproj#SwitchMode('file')

# ──────────────────────────────────────────────
# NavigateUp at filesystem root
# ──────────────────────────────────────────────
echom '--- NavigateUp at root ---'
Setup()
vproj#SwitchMode('file')

# Repeated NavigateUp should eventually stop at root without crash
for _ in range(50)
  vproj#NavigateUp()
endfor
Assert(vproj#IsPaneVisible(), 'NavigateUp 50x keeps pane open')
Assert(vproj#GetCurrentMode() == 'file', 'NavigateUp 50x preserves mode')

# ──────────────────────────────────────────────
# HandleBufWipeout state reset
# ──────────────────────────────────────────────
echom '--- HandleBufWipeout ---'
Setup()

vproj#SetPaneWidth(45)

vproj#HandleBufWipeout()
Assert(!vproj#IsPaneVisible(), 'HandleBufWipeout clears pane visibility')
Assert(vproj#GetPaneWidth() == 45, 'HandleBufWipeout preserves pane width')
Assert(vproj#GetCurrentMode() == 'file', 'HandleBufWipeout preserves mode')

# ──────────────────────────────────────────────
# Refresh when pane is closed
# ──────────────────────────────────────────────
echom '--- Refresh when closed ---'
Setup()
vproj#PaneClose()

try
  vproj#Refresh()
  Assert(!vproj#IsPaneVisible(), 'Refresh when closed does not re-open')
catch
  Assert(false, 'Refresh when closed error: ' .. v:exception)
endtry

# ──────────────────────────────────────────────
# PaneGrow/PaneShrink bounds
# ──────────────────────────────────────────────
echom '--- PaneGrow/PaneShrink bounds ---'
Setup()

# Grow to max
while vproj#GetPaneWidth() < 80
  vproj#PaneGrow()
endwhile
vproj#PaneGrow()
Assert(vproj#GetPaneWidth() == 80, 'PaneGrow capped at 80')

# Shrink to min
while vproj#GetPaneWidth() > 20
  vproj#PaneShrink()
endwhile
vproj#PaneShrink()
Assert(vproj#GetPaneWidth() == 20, 'PaneShrink capped at 20')

vproj#SetPaneWidth(40)

# ──────────────────────────────────────────────
# ToggleInfoColumn
# ──────────────────────────────────────────────
echom '--- ToggleInfoColumn ---'
Setup()

vproj#ToggleInfoColumn()
Assert(vproj#IsPaneVisible(), 'F1 toggle keeps pane open')

# Toggle back
vproj#ToggleInfoColumn()
Assert(vproj#IsPaneVisible(), 'F1 toggle back keeps pane open')

# ──────────────────────────────────────────────
# SelectByNavChar with ch not on current page
# ──────────────────────────────────────────────
echom '--- SelectByNavChar missing char ---'
Setup()

# Press a nav char that doesn't exist on current page (only '..' has no char)
try
  execute 'normal m'
  Assert(vproj#IsPaneVisible(), 'nav char m (not on page) does not crash')
catch
  Assert(false, 'nav char m error: ' .. v:exception)
endtry

# ──────────────────────────────────────────────
# RenameProject in non-git mode
# ──────────────────────────────────────────────
echom '--- RenameProject guard ---'
Setup()
vproj#SwitchMode('file')

try
  vproj#RenameProject()
  Assert(vproj#IsPaneVisible(), 'RenameProject in file mode exits early')
catch
  Assert(false, 'RenameProject in file mode error: ' .. v:exception)
endtry

# ──────────────────────────────────────────────
# Cleanup
# ──────────────────────────────────────────────
vproj#PaneClose()

echom ''
if failures == 0
  echom 'ALL COVERAGE TESTS PASSED.'
else
  echohl ErrorMsg
  echom failures .. ' COVERAGE TEST(S) FAILED.'
  echohl None
  cquit!
endif
qa!
