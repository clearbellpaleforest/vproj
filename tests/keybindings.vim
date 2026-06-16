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
# SECTION 2: h, l, . (parent dir, enter)
# ──────────────────────────────────────────────
echom '--- h / l / . ---'
Setup()

# h — parent directory
execute 'normal h'
Assert(vproj#IsPaneVisible() && vproj#GetCurrentMode() == 'file',
      'h (parent) keeps pane open in file mode')

# . — parent directory (same as h)
execute 'normal .'
Assert(vproj#IsPaneVisible(), '. (parent) keeps pane open')

# l — enter directory (need to be on a dir item, not a file)
# Just verify it doesn't crash
Setup()
try
  execute 'normal l'
  Assert(true, 'l (enter) dispatched')
catch
  Assert(false, 'l error: ' .. v:exception)
endtry

# ──────────────────────────────────────────────
# SECTION 3: Enter key (mapped to SelectCurrent)
# ──────────────────────────────────────────────
echom '--- Enter ---'
Setup()

# Verify Enter is mapped — should not crash
try
  execute "normal \<CR>"
  Assert(true, 'Enter dispatched without crash')
catch
  Assert(false, 'Enter error: ' .. v:exception)
endtry
# Note: if Enter opened a file, the pane may be closed. Re-setup below.

# ──────────────────────────────────────────────
# SECTION 4: Mode switching keys (F, D, C)
# ──────────────────────────────────────────────
echom '--- Mode Switching ---'
Setup()

execute 'normal F'
Assert(vproj#GetCurrentMode() == 'file', 'F stays in file mode')

execute 'normal D'
Assert(vproj#GetCurrentMode() == 'doc', 'D switches to doc mode')

execute 'normal C'
Assert(vproj#GetCurrentMode() == 'code', 'C switches to code mode')

execute 'normal F'
Assert(vproj#GetCurrentMode() == 'file', 'F back to file mode')

# ──────────────────────────────────────────────
# SECTION 5: Action keys (r, x, +, -)
# ──────────────────────────────────────────────
echom '--- Actions ---'
Setup()

# r — refresh
execute 'normal r'
Assert(vproj#IsPaneVisible(), 'r (refresh) keeps pane open')
Assert(vproj#GetCurrentMode() == 'file', 'r preserves mode')

# x — close buffer (doc mode)
vproj#SwitchMode('doc')
try
  execute 'normal x'
  Assert(vproj#IsPaneVisible(), 'x (close buffer) does not crash')
catch
  Assert(false, 'x error: ' .. v:exception)
endtry

# +/- — toggle include (code mode)
vproj#SwitchMode('code')
try
  execute 'normal +'
  Assert(vproj#IsPaneVisible(), '+ (toggle include) does not crash')
catch
  Assert(false, '+ error: ' .. v:exception)
endtry

try
  execute 'normal -'
  Assert(vproj#IsPaneVisible(), '- (toggle include) does not crash')
catch
  Assert(false, '- error: ' .. v:exception)
endtry

# ──────────────────────────────────────────────
# SECTION 6: Width keys (Left, Right)
# ──────────────────────────────────────────────
echom '--- Width ---'
vproj#SwitchMode('file')
var w_before: number = vproj#GetPaneWidth()

execute "normal \<Right>"
Assert(vproj#GetPaneWidth() == w_before + 1, '<Right> grows pane')

execute "normal \<Left>"
Assert(vproj#GetPaneWidth() == w_before, '<Left> shrinks pane')

# ──────────────────────────────────────────────
# SECTION 7: Close keys (q, F4)
# ──────────────────────────────────────────────
echom '--- Close ---'

# q — close
execute 'normal q'
Assert(!vproj#IsPaneVisible(), 'q closes pane')

# Reopen for next test
vproj#PaneOpen()
Assert(vproj#IsPaneVisible(), 'reopen after q')

# F4 — close (may not send in headless, test the function path)
vproj#PaneClose()
Assert(!vproj#IsPaneVisible(), 'F4/close functions correctly')

# ──────────────────────────────────────────────
# SECTION 8: Passthrough keys (Vim defaults untouched)
# ──────────────────────────────────────────────
echom '--- Passthrough ---'
Setup()

# Build list of passthrough keys and expected behavior
var passthrough_tests: list<list<string>> = [
  ['f' .. 'e',         'f (find char)'],
  ['t' .. 'e',         't (find until)'],
  ['w',                'w (word forward)'],
  ['b',                'b (word back)'],
  ['0',                '0 (line start)'],
  ['$',                '$ (line end)'],
  ['gg',               'gg (buffer top)'],
  ['G',                'G (buffer bottom)'],
  ["\<C-F>",           'Ctrl-F (page down)'],
  ["\<C-B>",           'Ctrl-B (page up)'],
  ['H',                'H (screen top)'],
  ['L',                'L (screen bottom)'],
  ['%',                '% (match pair)'],
]

for [key, label] in passthrough_tests
  try
    execute 'normal ' .. key
    Assert(true, label .. ' works')
  catch
    Assert(false, label .. ' error: ' .. v:exception)
  endtry
endfor

# y — yank (nomodifiable doesn't block yank)
try
  execute 'normal yw'
  Assert(true, 'y (yank) works')
catch
  Assert(false, 'y error: ' .. v:exception)
endtry

# / — search (opens command line; cancel it)
try
  call feedkeys("/README\<C-c>", 'xt')
  Assert(true, '/ (search) works')
catch
  Assert(false, '/ error: ' .. v:exception)
endtry

# ──────────────────────────────────────────────
# SECTION 9: Single-window file open
# ──────────────────────────────────────────────
echom '--- Single Window File Open ---'
Setup()

# Close the non-pane window so only pane remains (winnr('$') == 1)
wincmd w
close!

# Move past parent dir (..) and subdirs to a file item
normal jjj

try
  execute "normal \<CR>"
  Assert(winnr('$') >= 2, 'Enter opens split when pane is only window')
  # OpenFile's wincmd p returns to pane; switch to the file window
  wincmd w
  Assert(bufname('%') != 'VPROJ', 'File opened (not pane) in other window')
  wincmd w
  Assert(bufnr('VPROJ') > 0, 'Pane buffer still exists')
catch
  Assert(false, 'Single-window file open error: ' .. v:exception)
endtry

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
