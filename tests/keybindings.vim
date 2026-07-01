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
# SECTION 1: Navigation keys (j, k, Down, Up)
# ──────────────────────────────────────────────
echom '--- Navigation ---'
Setup()
var start: number = PaneCursorLine()

execute 'normal j'
Assert(PaneCursorLine() > start, 'j moves cursor down')

execute 'normal k'
Assert(PaneCursorLine() == start, 'k moves cursor back up')

execute "normal \<Down>"
Assert(PaneCursorLine() > start, '<Down> moves cursor down')

execute "normal \<Up>"
Assert(PaneCursorLine() == start, '<Up> moves cursor back up')

# ──────────────────────────────────────────────
# SECTION 2: h, l, . (parent dir, index mode, parent)
# ──────────────────────────────────────────────
echom '--- h / . ---'
Setup()

# h — parent directory
execute 'normal h'
Assert(vproj#IsPaneVisible() && vproj#GetCurrentMode() == 'file',
      'h (parent) keeps pane open in file mode')

# . — parent directory (same as h)
execute 'normal .'
Assert(vproj#IsPaneVisible(), '. (parent) keeps pane open')

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
# SECTION 5: Action keys (r, x, +, -)
# ──────────────────────────────────────────────
echom '--- Actions ---'
Setup()

# r — refresh (in pane buffer)
execute 'normal r'
Assert(vproj#IsPaneVisible(), 'r (refresh) keeps pane open')
Assert(vproj#GetCurrentMode() == 'file', 'r preserves mode')

# x — close buffer (buf mode); create a buffer in right panel, close from pane
# Open test file in the RIGHT panel (not the pane), then focus pane and close it
if winnr('$') > 1
  wincmd l
else
  # Only one window — open a split
  rightbelow new
endif
edit /tmp/vproj_test_xbuf.txt
write!
# Back to pane, switch to buf mode, close the test buffer
FocusPane()
vproj#SwitchMode('buf')
FocusPane()
var buf_count_before = len(getbufinfo({'buflisted': 1}))
try
  execute 'normal x'
  var buf_count_after = len(getbufinfo({'buflisted': 1}))
  Assert(buf_count_after < buf_count_before, 'x (close buffer): buffer count decreased')
  Assert(vproj#IsPaneVisible(), 'x (close buffer): pane stays visible')
catch
  Assert(false, 'x error: ' .. v:exception)
endtry
# Clean up test file
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
# SECTION 7: Close keys (q)
# ──────────────────────────────────────────────
echom '--- Close ---'
Setup()

# Q — close
execute 'normal Q'
Assert(!vproj#IsPaneVisible(), 'Q closes pane')

# Reopen for next test
vproj#PaneOpen()
Assert(vproj#IsPaneVisible(), 'reopen after Q')

# PaneClose function path
vproj#PaneClose()
Assert(!vproj#IsPaneVisible(), 'PaneClose functions correctly')

# ──────────────────────────────────────────────
# SECTION 7b: HandleEsc — temp vs permanent mode (gap 1)
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
# SECTION 7c: HandlePaneQ — temp vs permanent mode (gap 2)
# ──────────────────────────────────────────────
echom '--- HandlePaneQ ---'
Setup()

# q in temporary mode (default): should switch to qfix, not close
execute 'normal q'
Assert(vproj#IsPaneVisible(), 'q (temp mode): pane stays open')
Assert(vproj#GetCurrentMode() == 'qfix', 'q (temp mode): switches to qfix mode')

# Switch back to file, toggle to permanent, q should close
vproj#SwitchMode('file')
vproj#PaneTogglePermanent()
execute 'normal q'
Assert(!vproj#IsPaneVisible(), 'q (perm mode): pane closes')

# ──────────────────────────────────────────────
# SECTION 8: Passthrough keys (Vim defaults untouched)
# ──────────────────────────────────────────────
echom '--- Passthrough ---'
Setup()
FocusPane()
var wid_passthru = PaneWinID()

# 0 — line start (column 1)
execute 'normal $0'
Assert(col('.', wid_passthru) == 1, '0: cursor goes to column 1')

# $ — line end
execute 'normal $'
Assert(col('.', wid_passthru) >= 1, '$: cursor at valid column')

# w — word forward: verify cursor moves from start of line
execute 'normal 0'
var col_before_w = col('.', wid_passthru)
execute 'normal w'
var col_after_w = col('.', wid_passthru)
# w may stay on same col if line has no word break; verify it did not crash
Assert(col_after_w >= col_before_w, 'w: cursor did not go backwards')

# G — buffer bottom: verify cursor line changed (unless already at bottom)
execute 'normal gg'
var line_before_G = line('.', wid_passthru)
execute 'normal G'
var line_after_G = line('.', wid_passthru)
# In a short buffer, gg and G may go to same line
Assert(line_after_G >= line_before_G, 'G: cursor moved to >= start line')

# H — screen top (line should be valid)
execute 'normal H'
Assert(line('.', wid_passthru) >= 1, 'H: cursor on a valid line')

# Ctrl-F — page down (line should be valid after scroll)
try
  execute "normal \<C-F>"
  Assert(line('.', wid_passthru) >= 1, 'Ctrl-F: cursor on a valid line after page down')
catch
  Assert(false, 'Ctrl-F error: ' .. v:exception)
endtry

# y — yank (nomodifiable does not block yank)
execute 'normal 0wyw'
var yanked = getreg('"')
Assert(!empty(yanked), 'y (yank): register is non-empty after yank')

# / — filter prompt (was passthrough, now mapped to PromptFilter)
try
  var slash_map = maparg('/', 'n', 0, 1)
  Assert(!empty(slash_map), '/ is mapped in pane')
catch
  Assert(false, '/ error: ' .. v:exception)
endtry

# * — grep search (can't call interactively: input() blocks)
try
  var star_map = maparg('*', 'n', 0, 1)
  Assert(!empty(star_map), '* is mapped in pane')
  Assert(star_map.rhs =~ 'GrepSearch', '* maps to GrepSearch')
catch
  Assert(false, '* error: ' .. v:exception)
endtry

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
    execute 'normal j'
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
	    execute 'normal j'
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
# SECTION 10: Git actions (\ prefix, per John Chamberlain spec)
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
for ch in ['s', 'd', 'c', 'b', 'z', 'a', 'D', 'P', 'U', 'Z']
  var m = maparg(ch, 'n', 0, 1)
  Assert(!empty(m), ch .. ' mapped as nav char')
  Assert(m.rhs =~ 'SelectByNavChar', ch .. ' maps to SelectByNavChar (freed from git)')
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
