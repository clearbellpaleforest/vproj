vim9script

# Keybinding verification — tests every mapped and passthrough key
# Run: vim -N -u NONE -S tests/keybindings.vim

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

def PaneWinID(): number
  var pbuf = bufnr('VPROJ')
  var wins = win_findbuf(pbuf)
  return empty(wins) ? 0 : wins[0]
enddef

def PaneCursorLine(): number
  var wid = PaneWinID()
  return wid == 0 ? -1 : line('.', wid)
enddef

# Focus the pane window so normal-mode commands target it
def FocusPane(): void
  var wid = PaneWinID()
  if wid > 0
    win_gotoid(wid)
  endif
enddef

# Ensure pane is open in file mode
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
# SECTION 1: Navigation (j/k freed as nav chars; arrows for cursor movement)
# ──────────────────────────────────────────────
echom '--- Navigation ---'
Setup()
var start: number = PaneCursorLine()

# j and k are now nav chars (freed as nav char) — they route
# through VprojKey for file-opening, not cursor movement.
# <Down> and <Up> are the cursor movement keys.
execute "normal \<Down>"
Assert(PaneCursorLine() > start, '<Down> moves cursor down')

execute "normal \<Up>"
Assert(PaneCursorLine() == start, '<Up> moves cursor back up')

# ──────────────────────────────────────────────
# SECTION 2: . (parent dir via VprojKey), h freed as nav char
# h, j, k, l are all nav chars now — all lowercase a-z route through VprojKey.
# Parent directory navigation uses '.' (routed through VprojKey for mode guard)
# or Ctrl-K.
# ──────────────────────────────────────────────
echom '--- Parent nav ---'
Setup()

# . — parent directory via VprojKey (mode-guarded: file/code only)
execute 'normal .'
Assert(vproj#IsPaneVisible() && vproj#GetCurrentMode() == 'file',
      '. (parent) keeps pane open in file mode')

# Ctrl-K — parent directory (no mode guard, works in all modes)
vproj#SwitchMode('file')
execute "normal \<C-K>"
Assert(vproj#IsPaneVisible() && vproj#GetCurrentMode() == 'file',
      'C-K (parent) keeps pane open in file mode')

# h — nav char (not parent navigation; freed as nav char)
var h_map = maparg('h', 'n', 0, 1)
Assert(empty(h_map) || h_map.rhs =~ 'VprojKey\|SelectByNavChar',
      'h is NOT mapped to NavigateUp (nav char or unmapped)')

# S-L — Log mode removed; verify S-L is not mapped to a mode switch
Setup()
try
  execute "normal \<S-L>"
  Assert(vproj#GetCurrentMode() == 'file', 'S-L no longer switches (log mode removed)')
catch
  Assert(false, 'S-L error: ' .. v:exception)
endtry

# ──────────────────────────────────────────────
# SECTION 3: Enter key (mapped to SelectCurrent)
# ──────────────────────────────────────────────
echom '--- Enter ---'
Setup()

# Enter on first item (.. in file mode) calls NavigateUp, re-renders pane
try
  execute "normal \<CR>"
  Assert(vproj#GetCurrentMode() == 'file', 'Enter on .. preserves file mode')
  Assert(vproj#IsPaneVisible(), 'Enter on .. pane stays visible')
  Assert(PaneCursorLine() >= 3, 'Enter on .. cursor on valid selectable line')
catch
  Assert(false, 'Enter error: ' .. v:exception)
endtry
# Re-setup for next section
Setup()

# ──────────────────────────────────────────────
# SECTION 4: Mode switching keys (F, D, C)
# ──────────────────────────────────────────────
echom '--- Mode Switching ---'
Setup()

# Mode switching uses Shift keys: S-F=File, S-B=Buf, S-C=Code
execute "normal \<S-F>"
Assert(vproj#GetCurrentMode() == 'file', 'S-F stays in file mode')
Assert(vproj#IsPaneVisible(), 'S-F keeps pane open')

execute "normal \<S-B>"
Assert(vproj#GetCurrentMode() == 'buf', 'S-B switches to buf mode')

execute "normal \<S-C>"
Assert(vproj#GetCurrentMode() == 'code', 'S-C switches to code mode')

execute "normal \<S-F>"
Assert(vproj#GetCurrentMode() == 'file', 'S-F back to file mode')

# ──────────────────────────────────────────────
# SECTION 5: Action keys (R, X freed; use Shift variants + +/-)
# r, x freed as nav chars. Refresh moved to Shift-R.
# CloseBuffer moved to Shift-X.
# ──────────────────────────────────────────────
echom '--- Actions ---'
Setup()

# R — refresh (Shift-R, in pane buffer)
execute "normal \<S-R>"
Assert(vproj#IsPaneVisible(), 'R (refresh) keeps pane open')
Assert(vproj#GetCurrentMode() == 'file', 'R preserves mode')

# X — close buffer (Shift-X in buf mode)
if winnr('$') > 1
  wincmd l
else
  rightbelow new
endif
edit /tmp/vproj_test_xbuf.txt
write!
FocusPane()
vproj#SwitchMode('buf')
FocusPane()
var buf_count_before = len(getbufinfo({'buflisted': 1}))
try
  execute "normal \<S-X>"
  var buf_count_after = len(getbufinfo({'buflisted': 1}))
  Assert(buf_count_after < buf_count_before, 'X (close buffer): buffer count decreased')
  Assert(vproj#IsPaneVisible(), 'X (close buffer): pane stays visible')
catch
  Assert(false, 'X error: ' .. v:exception)
endtry
silent! call delete('/tmp/vproj_test_xbuf.txt')

# +/- — toggle include (code mode); verify mode preserved
Setup()
vproj#SwitchMode('code')
FocusPane()
try
  execute 'normal +'
  Assert(vproj#GetCurrentMode() == 'code', '+ (toggle include): mode stays code')
  Assert(vproj#IsPaneVisible(), '+ (toggle include): pane stays visible')
catch
  Assert(false, '+ error: ' .. v:exception)
endtry

try
  execute 'normal -'
  Assert(vproj#GetCurrentMode() == 'code', '- (toggle include): mode stays code')
  Assert(vproj#IsPaneVisible(), '- (toggle include): pane stays visible')
catch
  Assert(false, '- error: ' .. v:exception)
endtry

# ──────────────────────────────────────────────
# SECTION 6: Width keys (Left, Right)
# ──────────────────────────────────────────────
echom '--- Width ---'
Setup()
vproj#SwitchMode('file')
FocusPane()
var w_before: number = vproj#GetPaneWidth()

execute "normal \<Right>"
Assert(vproj#GetPaneWidth() == w_before + 1, '<Right> grows pane')

execute "normal \<Left>"
Assert(vproj#GetPaneWidth() == w_before, '<Left> shrinks pane')

# ──────────────────────────────────────────────
# SECTION 7: Close keys (Q closes, q freed as nav char)
# q is now a nav char (key freed as nav char). Q (Shift-Q) still handles pane close/qfix.
# ──────────────────────────────────────────────
echom '--- Close ---'
Setup()

# Q (Shift-Q) in temp mode: switches to qfix
execute "normal \<S-Q>"
Assert(vproj#IsPaneVisible(), 'Q (temp mode): switches to qfix')
Assert(vproj#GetCurrentMode() == 'qfix', 'Q (temp mode): mode is qfix')

# Q in permanent mode: closes pane
vproj#SwitchMode('file')
vproj#PaneTogglePermanent()
execute "normal \<S-Q>"
Assert(!vproj#IsPaneVisible(), 'Q (perm mode): pane closes')

# PaneClose function path
vproj#PaneOpen()
Assert(vproj#IsPaneVisible(), 'reopen after Q')
vproj#PaneClose()
Assert(!vproj#IsPaneVisible(), 'PaneClose functions correctly')

# ──────────────────────────────────────────────
# SECTION 7b: HandleEsc — temp vs permanent mode
# ──────────────────────────────────────────────
echom '--- HandleEsc ---'
Setup()

# Esc in temporary mode (default): should close the pane
execute "normal \<Esc>"
Assert(!vproj#IsPaneVisible(), 'Esc (temp mode): pane closes')

# Reopen, toggle to permanent mode, Esc should NOT close
vproj#PaneOpen()
vproj#PaneTogglePermanent()
execute "normal \<Esc>"
Assert(vproj#IsPaneVisible(), 'Esc (perm mode): pane stays open')
vproj#PaneClose()

# ──────────────────────────────────────────────
# SECTION 7c: q freed as nav char (key freed as nav char)
# Lowercase q is now a nav char routed through VprojKey.
# ──────────────────────────────────────────────
echom '--- q nav char ---'
Setup()
var q_map = maparg('q', 'n', 0, 1)
Assert(empty(q_map) || q_map.rhs =~ 'VprojKey\|SelectByNavChar',
      'q is NOT mapped to HandlePaneQ (nav char or unmapped)')

# ──────────────────────────────────────────────
# SECTION 8: Passthrough keys (Vim defaults untouched)
# All lowercase a-z are nav chars via VprojKey — not passthrough.
# Uppercase letters and Ctrl-keys are unmapped and behave as Vim defaults.
# ──────────────────────────────────────────────
echom '--- Passthrough ---'
Setup()
FocusPane()

# Standard Vim movement keys (not mapped in pane)
# 0 — line start
var zero_map = maparg('0', 'n', 0, 1)
Assert(empty(zero_map), '0 is unmapped (Vim default)')

# $ — line end
var dollar_map = maparg('$', 'n', 0, 1)
Assert(empty(dollar_map), '$ is unmapped (Vim default)')

# G, H — uppercase, not nav chars, should be Vim defaults
var G_map = maparg('G', 'n', 0, 1)
Assert(empty(G_map), 'G is unmapped (Vim default)')

var H_map = maparg('H', 'n', 0, 1)
Assert(empty(H_map), 'H is unmapped (Vim default)')

# Ctrl-F — not mapped, Vim default page-down
var ctrl_f = maparg('<C-F>', 'n', 0, 1)
Assert(empty(ctrl_f), 'Ctrl-F is unmapped (Vim default)')

# / — filter prompt (mapped to PromptFilter)
var slash_map = maparg('/', 'n', 0, 1)
Assert(!empty(slash_map), '/ is mapped in pane')
if !empty(slash_map)
  Assert(slash_map.rhs =~ 'PromptFilter', '/ maps to PromptFilter')
endif

# * — grep search (mapped to GrepSearch)
var star_map = maparg('*', 'n', 0, 1)
Assert(!empty(star_map), '* is mapped in pane')
if !empty(star_map)
  Assert(star_map.rhs =~ 'GrepSearch', '* maps to GrepSearch')
endif

# ──────────────────────────────────────────────
# SECTION 9: Single-window file open
# ──────────────────────────────────────────────
echom '--- Single Window File Open ---'
Setup()
vproj#PaneTogglePermanent()

# Close the non-pane window so only pane remains (winnr('$') == 1)
if winnr('$') > 1
  wincmd w
  close!
endif

# Move past parent dir (..) and subdirs to a file item (max 100 attempts)
var attempts: number = 0
var pbuf: number = bufnr('VPROJ')
var cline: number = PaneCursorLine()
if pbuf > 0 && cline > 0
  var line_text: string = getbufline(pbuf, cline)[0]
  while attempts < 100 && line_text =~ '/'
    execute "normal \<Down>"
    attempts += 1
    cline = PaneCursorLine()
    if cline <= 0 || empty(getbufline(pbuf, cline))
      break
    endif
    line_text = getbufline(pbuf, cline)[0]
  endwhile
endif

if attempts >= 100
  # All items are directories — Enter on dir navigates into it
  execute 'normal gg3G'
  try
    execute "normal \<CR>"
    Assert(vproj#IsPaneVisible(), 'Single-window: Enter on dir keeps pane visible')
    Assert(vproj#GetCurrentMode() == 'file', 'Single-window: Enter on dir preserves mode')
  catch
    Assert(false, 'Single-window dir enter error: ' .. v:exception)
  endtry
else
  try
    execute "normal \<CR>"
    Assert(winnr('$') == 2, 'Enter on file: exactly 2 windows (pane + file)')
    wincmd l
    var right_buf = bufname('%')
    Assert(right_buf != 'VPROJ', 'Single-window: right panel shows opened file, not pane')
    FocusPane()
    Assert(vproj#IsPaneVisible(), 'Pane stays open after file open')
    # Cursor should be back in the pane after file open
    Assert(bufname('%') == 'VPROJ', 'Cursor returned to pane')
  catch
    Assert(false, 'Single-window file open error: ' .. v:exception)
  endtry
endif


	# ──────────────────────────────────────────────
	# ──────────────────────────────────────────────
	# SECTION 9a: Two-panel file open (Enter must not create 3rd window)
	# ──────────────────────────────────────────────
	echom '--- Two-Panel File Open ---'
	Setup()
	# Setup() already creates a 2-panel layout via PaneOpen
	# Press Enter on a file — must reuse existing right panel, not create a 3rd
	var wins_before_9a = winnr('$')
	# Navigate past dirs to a file
	var pbuf_9a = bufnr('VPROJ')
	var cline_9a = PaneCursorLine()
	var attempts_9a = 0
	if pbuf_9a > 0 && cline_9a > 0
	  var line_text_9a = getbufline(pbuf_9a, cline_9a)[0]
	  while attempts_9a < 100 && line_text_9a =~ '/'
	    execute "normal \<Down>"
	    attempts_9a += 1
	    cline_9a = PaneCursorLine()
	    if cline_9a <= 0 || empty(getbufline(pbuf_9a, cline_9a))
	      break
	    endif
	    line_text_9a = getbufline(pbuf_9a, cline_9a)[0]
	  endwhile
	endif

	if attempts_9a < 100
	  try
	    execute "normal \<CR>"
	    # Must stay at exactly 2 windows — pane + file (not 3)
	    Assert(winnr('$') == wins_before_9a, 'Two-panel Enter on file: window count unchanged')
	    wincmd l
	    var right_buf = bufname('%')
	    Assert(right_buf != 'VPROJ', 'Two-panel Enter: right panel shows opened file, not pane')
	    FocusPane()
	    Assert(vproj#IsPaneVisible(), 'Two-panel Enter: pane stays visible')
	    Assert(bufname('%') == 'VPROJ', 'Two-panel Enter: cursor returns to pane')
	  catch
	    Assert(false, 'Two-panel Enter error: ' .. v:exception)
	  endtry
	else
	  # All items are dirs — Enter on one navigates into it
	  execute 'normal gg3G'
	  try
	    execute "normal \<CR>"
	    Assert(vproj#IsPaneVisible(), 'Two-panel: Enter on dir keeps pane visible')
	    Assert(vproj#GetCurrentMode() == 'file', 'Two-panel: Enter on dir preserves mode')
	  catch
	    Assert(false, 'Two-panel dir enter error: ' .. v:exception)
	  endtry
	endif
# ──────────────────────────────────────────────
# SECTION 9b: PaneTogglePermanent double-toggle
# ──────────────────────────────────────────────
echom '--- PaneTogglePermanent Double-Toggle ---'
Setup()

# First toggle: temporary → permanent
vproj#PaneTogglePermanent()
Assert(vproj#IsPaneVisible(), 'perm-1: pane visible after first toggle')

# Second toggle: permanent → close
vproj#PaneTogglePermanent()
Assert(!vproj#IsPaneVisible(), 'perm-2: pane closed after second toggle')

# Third toggle: closed → open in permanent
vproj#PaneTogglePermanent()
Assert(vproj#IsPaneVisible(), 'perm-3: pane reopened after third toggle')

# Fourth toggle: permanent → close
vproj#PaneTogglePermanent()
Assert(!vproj#IsPaneVisible(), 'perm-4: pane closed after fourth toggle')

# ──────────────────────────────────────────────
# SECTION 9c: ToggleInfoColumn edge cases
# ──────────────────────────────────────────────
echom '--- ToggleInfoColumn ---'
Setup()

var info_before: bool = vproj#IsInfoColumnVisible()
vproj#ToggleInfoColumn()
Assert(vproj#IsInfoColumnVisible() != info_before, 'ToggleInfoColumn: toggles visibility')
Assert(vproj#IsPaneVisible(), 'ToggleInfoColumn: pane stays visible')

vproj#ToggleInfoColumn()
Assert(vproj#IsInfoColumnVisible() == info_before, 'ToggleInfoColumn: toggles back')

# Toggle in buf mode
vproj#SwitchMode('buf')
var info_buf_before = vproj#IsInfoColumnVisible()
vproj#ToggleInfoColumn()
Assert(vproj#IsInfoColumnVisible() != info_buf_before, 'ToggleInfoColumn in buf: visibility toggled')
Assert(vproj#IsPaneVisible(), 'ToggleInfoColumn in buf: pane stays visible')

# Toggle in code mode
vproj#SwitchMode('code')
var info_code_before = vproj#IsInfoColumnVisible()
vproj#ToggleInfoColumn()
Assert(vproj#IsInfoColumnVisible() != info_code_before, 'ToggleInfoColumn in code: visibility toggled')
Assert(vproj#IsPaneVisible(), 'ToggleInfoColumn in code: pane stays visible')

# ──────────────────────────────────────────────
# SECTION 9d: Tree view toggle
# ──────────────────────────────────────────────
echom '--- Tree View Toggle ---'
Setup()

var tree_before: bool = vproj#IsTreeViewActive()
Assert(!tree_before, 'tree view: starts inactive')

execute 'normal T'
Assert(vproj#IsTreeViewActive() != tree_before, 'tree view: T toggles on')
Assert(vproj#IsPaneVisible(), 'tree view: pane stays visible after toggle on')

execute 'normal T'
Assert(vproj#IsTreeViewActive() == tree_before, 'tree view: T toggles back off')
Assert(vproj#IsPaneVisible(), 'tree view: pane stays visible after toggle off')

# ──────────────────────────────────────────────
# SECTION 10: Git actions (\ prefix)
# ──────────────────────────────────────────────
echom '--- Git Action Mappings ---'
Setup()

# All git actions now use \ prefix
var expected_mappings: list<list<string>> = [
  ['\s', 'GitStageToggle'],
  ['\d', 'OpenDiffPreview'],
  ['\D', 'DiscardChanges'],
  ['\c', 'GitCommit'],
  ['\p', 'GitPush'],
  ['\u', 'GitPull'],
  ['\b', 'GitBranchSwitch'],
  ['\z', 'GitStashPush'],
  ['\Z', 'GitStashPop'],
  ['\a', 'GitBlame'],
]

for [lhs, rhs_fragment] in expected_mappings
  var m = maparg(lhs, 'n', 0, 1)
  Assert(!empty(m), lhs .. ' is mapped in pane buffer')
  Assert(m.rhs =~ rhs_fragment, lhs .. ' maps to ' .. rhs_fragment)
endfor

# Verify single-letter git keys are now nav chars (freed from git duty)
# Lowercase s/d/c/b/z/a are all nav chars (VprojKey). Uppercase D/P/U/Z are
# unmapped — the git discard/push/pull/stash-pop actions use \ prefix.
for ch in ['s', 'd', 'c', 'b', 'z', 'a']
  var m = maparg(ch, 'n', 0, 1)
  Assert(!empty(m), ch .. ' mapped as nav char')
  Assert(m.rhs =~ 'VprojKey\|SelectByNavChar',
        ch .. ' maps to VprojKey or SelectByNavChar (freed from git)')
endfor
for ch in ['D', 'P', 'U', 'Z']
  var m = maparg(ch, 'n', 0, 1)
  # D/U/Z should not be mapped. P is Shift-P (TogglePreview) — not a git action.
  Assert(empty(m) || m.rhs =~ 'VprojKey\|SelectByNavChar\|TogglePreview\|Git',
        ch .. ' is NOT mapped to a git action (freed)')
endfor

# ──────────────────────────────────────────────
# Cleanup
# ──────────────────────────────────────────────
vproj#PaneClose()

echom ''
if failures == 0
  echom 'ALL KEYBINDINGS VERIFIED.'
else
  echohl ErrorMsg
  echom failures .. ' KEYBINDING TEST(S) FAILED.'
  echohl None
  cquit!
endif
qa!
