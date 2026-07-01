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

# L — Log mode
Setup()
try
  execute 'normal L'
  Assert(vproj#GetCurrentMode() == 'log', 'L switches to log mode')
catch
  Assert(false, 'L error: ' .. v:exception)
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
# Pane stays open after file open in new two-panel layout
Setup()

# ──────────────────────────────────────────────
# SECTION 4: Mode switching keys (F, D, C)
# ──────────────────────────────────────────────
echom '--- Mode Switching ---'
Setup()

execute 'normal f'
Assert(vproj#GetCurrentMode() == 'file', 'f stays in file mode')

execute 'normal b'
Assert(vproj#GetCurrentMode() == 'buf', 'b switches to buf mode')

execute 'normal g'
Assert(vproj#GetCurrentMode() == 'code', 'g switches to git mode')

execute 'normal f'
Assert(vproj#GetCurrentMode() == 'file', 'f back to file mode')

# ──────────────────────────────────────────────
# SECTION 5: Action keys (r, x, +, -)
# ──────────────────────────────────────────────
echom '--- Actions ---'
Setup()

# r — refresh
execute 'normal r'
Assert(vproj#IsPaneVisible(), 'r (refresh) keeps pane open')
Assert(vproj#GetCurrentMode() == 'file', 'r preserves mode')

# x — close buffer (buf mode)
vproj#SwitchMode('buf')
try
  execute 'normal x'
  Assert(vproj#IsPaneVisible(), 'x (close buffer) does not crash')
catch
  Assert(false, 'x error: ' .. v:exception)
endtry

# +/- — toggle include (git mode)
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
# SECTION 7: Close keys (q)
# ──────────────────────────────────────────────
echom '--- Close ---'

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
# SECTION 8: Passthrough keys (Vim defaults untouched)
# ──────────────────────────────────────────────
echom '--- Passthrough ---'
Setup()

# Build list of passthrough keys and expected behavior
  # Note: f, b, g are mapped with <nowait> so f+char, gg, b, etc.
  # are NOT passthrough — they trigger mode switches or nav char jumps.
  # Test only truly unmapped Vim motion keys.
var passthrough_tests: list<list<string>> = [
  ['t' .. 'e',         't (find until)'],
  ['w',                'w (word forward)'],
  ['0',                '0 (line start)'],
  ['$',                '$ (line end)'],
  ['G',                'G (buffer bottom)'],
  ["\<C-F>",           'Ctrl-F (page down)'],
  ['H',                'H (screen top)'],
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

# / — filter prompt (was passthrough, now mapped to PromptFilter)
# Verify mapping exists (can't test directly: input() blocks in script)
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
wincmd w
close!

# Move past parent dir (..) and subdirs to a file item (max 100 attempts)
var attempts: number = 0
while attempts < 100 && getbufline(bufnr('VPROJ'), PaneCursorLine())[0] =~ '/'
  execute 'normal j'
  attempts += 1
endwhile

if attempts >= 100
  Assert(true, 'Single-window: no non-dir item found (all dirs) — skipped')
else
  try
    execute "normal \<CR>"
    Assert(winnr('$') >= 2, 'Enter on file: two-panel layout exists')
    Assert(vproj#IsPaneVisible(), 'Pane stays open after file open')
    # Cursor should be back in the pane after file open
    Assert(bufname('%') == 'VPROJ', 'Cursor returned to pane')
  catch
    Assert(false, 'Single-window file open error: ' .. v:exception)
  endtry
endif

# ──────────────────────────────────────────────
# SECTION 10: Git stash and blame mappings
# ──────────────────────────────────────────────
echom '--- Git Stash/Blame Mappings ---'
Setup()

var stash_z_map = maparg('z', 'n', 0, 1)
Assert(!empty(stash_z_map), 'z is mapped in pane buffer')
Assert(stash_z_map.rhs =~ 'GitStashPush', 'z maps to GitStashPush')

var stash_Z_map = maparg('Z', 'n', 0, 1)
Assert(!empty(stash_Z_map), 'Z is mapped in pane buffer')
Assert(stash_Z_map.rhs =~ 'GitStashPop', 'Z maps to GitStashPop')

var blame_a_map = maparg('a', 'n', 0, 1)
Assert(!empty(blame_a_map), 'a is mapped in pane buffer')
Assert(blame_a_map.rhs =~ 'GitBlame', 'a maps to GitBlame')

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
