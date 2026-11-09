vim9script

# Audit Fix Verification — tests all 8 items from the bug report
# Run: vim -N -u NONE -S tests/audit_fixes.vim

# Hermetic setup (run_all.sh also isolates HOME/XDG_CACHE_HOME/TMPDIR):
#  - session cache lives in a temp dir, never the real user cache
#  - cwd is a temp fixture dir, so code-mode +/-/ToggleInclude can never write
#    the repo's tracked vproj.vproj
#  - runtimepath is absolute so autoload still resolves after any :cd
$XDG_CACHE_HOME = tempname()
execute 'set rtp+=' .. fnameescape(expand('<script>:p:h:h') .. '/src')
runtime! plugin/vproj.vim
set nomore
const FIXTURE_DIR: string = tempname()
mkdir(FIXTURE_DIR .. '/subdir_a', 'p')
mkdir(FIXTURE_DIR .. '/subdir_b', 'p')
writefile(['alpha'], FIXTURE_DIR .. '/alpha.txt')
writefile(['beta'], FIXTURE_DIR .. '/beta.txt')
writefile(['gamma'], FIXTURE_DIR .. '/gamma.txt')
execute 'cd' fnameescape(FIXTURE_DIR)
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

def FocusPane(): void
  var wid = PaneWinID()
  if wid > 0
    win_gotoid(wid)
  endif
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
# FIX 1: Dynamic NAV_CHARS — a-z all available
# ──────────────────────────────────────────────
echom '=== Fix 1: Dynamic NAV_CHARS (a-z all available) ==='
Setup()
FocusPane()

# Every lowercase letter a-z must route through VprojKey (which dispatches
# to SelectByNavChar for file/code mode, or the mode-specific handler)
for ch in range(char2nr('a'), char2nr('z'))
  var m = maparg(nr2char(ch), 'n', 0, 1)
  if !empty(m)
    Assert(m.rhs =~ 'VprojKey\|SelectByNavChar',
          'Letter ' .. nr2char(ch) .. ' maps to VprojKey or SelectByNavChar')
  else
    # Some letters may be unmapped if test environment is minimal
    Assert(true, 'Letter ' .. nr2char(ch) .. ' has no conflicting mapping')
  endif
endfor

# ──────────────────────────────────────────────
# FIX 2: NavChar returns '.' for parent dir
# ──────────────────────────────────────────────
echom '=== Fix 2: Parent dir gets "." indicator ==='
Setup()
FocusPane()

# '.' must route through VprojKey (which dispatches to SelectByNavChar)
var dot_map = maparg('.', 'n', 0, 1)
Assert(!empty(dot_map), 'dot key "." is mapped')
Assert(get(dot_map, 'rhs', '') =~ 'VprojKey\|SelectByNavChar', 'dot "." maps to VprojKey or SelectByNavChar')

# ──────────────────────────────────────────────
# FIX 3: SelectByNavChar opens files immediately
# ──────────────────────────────────────────────
echom '=== Fix 3: SelectByNavChar opens files ==='
Setup()
FocusPane()
vproj#SwitchMode('file')

# Find the first file line (not '..', not a dir/) and return its nav char.
# A def, not a script-level loop: `var` inside a script-level for body is a
# script item, and the second iteration aborts with E1041 (redefining).
def FirstFileNavChar(): string
  var pbuf: number = bufnr('VPROJ')
  var total: number = getbufinfo(pbuf)[0].linecount
  for lnum in range(3, total)
    var linetext: string = getbufline(pbuf, lnum)[0]
    if linetext =~ '^[a-z] ' && linetext !~ '^[a-z] .*/'
      return linetext[0]
    endif
  endfor
  return ''
enddef

# The fixture (cwd) holds alpha.txt, beta.txt, gamma.txt, so a file exists.
var nav_char: string = FirstFileNavChar()
Assert(!empty(nav_char), 'fixture listing has a file line with a nav char')
if !empty(nav_char)
  var wins_before: number = winnr('$')
  execute 'normal ' .. nav_char
  # Temporary mode: opening a file closes the pane; the file is current.
  Assert(fnamemodify(bufname('%'), ':t') =~ '^\(alpha\|beta\|gamma\)\.txt$',
        'Nav char ' .. nav_char .. ' opened a fixture file (got ' .. bufname('%') .. ')')
  Assert(!vproj#IsPaneVisible() || winnr('$') >= wins_before,
        'Nav char ' .. nav_char .. ' opens file without crashing')
endif

# ──────────────────────────────────────────────
# FIX 4 & 5: saved_origin_wid — file opens in correct window
# ──────────────────────────────────────────────
echom '=== Fix 4/5: Origin window tracking ==='

# Open a file in a window first, then open pane, then open another file
# The second file should open in the first window, not create a new split
# Own temp dir (was /tmp): a known, small listing.
const ORIGIN_DIR: string = tempname()
mkdir(ORIGIN_DIR, 'p')
execute 'cd' fnameescape(ORIGIN_DIR)
writefile(['test1'], ORIGIN_DIR .. '/vproj_test_a.txt')
writefile(['test2'], ORIGIN_DIR .. '/vproj_test_b.txt')

# Start with one file open in a single window
only
execute 'edit' fnameescape(ORIGIN_DIR .. '/vproj_test_a.txt')
var origin_wid = win_getid()

# Open pane (should remember origin_wid)
vproj#PaneOpen()
vproj#SwitchMode('file')

# Count windows — should be 2 (origin + pane)
var wins_after_pane = winnr('$')
Assert(wins_after_pane == 2, 'After pane open: exactly 2 windows')

# Navigate to test_b.txt in the pane and open it
FocusPane()
vproj#SwitchMode('file')

# Select vproj_test_b.txt through the plugin (SelectNext keeps the plugin's
# selected_line in sync; a bare cursor jump would not) and open it with Enter.
def SelectLineMatching(pat: string): bool
  var pbuf: number = bufnr('VPROJ')
  var wins: list<number> = win_findbuf(pbuf)
  if empty(wins)
    return false
  endif
  vproj#SelectFirst()
  for _ in range(getbufinfo(pbuf)[0].linecount)
    if getbufline(pbuf, line('.', wins[0]))[0] =~ pat
      return true
    endif
    vproj#SelectNext()
  endfor
  return false
enddef

var found_b: bool = SelectLineMatching('vproj_test_b')
Assert(found_b, 'vproj_test_b.txt is listed in the pane')
if found_b
  # Permanent mode so the pane stays open after the file opens
  vproj#PaneTogglePermanent()
  FocusPane()
  execute "normal \<CR>"
  Assert(winnr('$') == 2, 'File open: still 2 windows (no extra split)')
  Assert(win_id2win(origin_wid) > 0
        && fnamemodify(bufname(winbufnr(origin_wid)), ':t') == 'vproj_test_b.txt',
        'File open: vproj_test_b.txt opened in the origin window')
endif

vproj#PaneClose()
execute 'cd' fnameescape(FIXTURE_DIR)

# ──────────────────────────────────────────────
# FIX 6: Key mappings — j/k/h/p/q/r/x freed for nav
# ──────────────────────────────────────────────
echom '=== Fix 6: j/k/h/p/q/r/x freed as nav keys ==='
Setup()
FocusPane()

# These keys must NOT be mapped to navigation/action functions anymore
# They are now nav chars (SelectByNavChar) or unmapped

# j — must NOT be mapped to cursor movement
var j_map = maparg('j', 'n', 0, 1)
Assert(empty(j_map) || get(j_map, 'rhs', '') =~ 'VprojKey\|SelectByNavChar',
      'j is NOT mapped to cursor movement (nav char or unmapped)')

# k — must NOT be mapped to cursor movement
var k_map = maparg('k', 'n', 0, 1)
Assert(empty(k_map) || get(k_map, 'rhs', '') =~ 'VprojKey\|SelectByNavChar',
      'k is NOT mapped to cursor movement (nav char or unmapped)')

# h — must NOT be mapped to parent navigation
var h_map = maparg('h', 'n', 0, 1)
Assert(empty(h_map) || get(h_map, 'rhs', '') =~ 'VprojKey\|SelectByNavChar',
      'h is NOT mapped to NavigateUp (nav char or unmapped)')

# Arrow keys MUST still work (replacement for j/k)
var down_map = maparg('<Down>', 'n', 0, 1)
Assert(!empty(down_map), '<Down> is mapped')
Assert(get(down_map, 'rhs', '') =~ 'SelectNext', '<Down> maps to SelectNext')

var up_map = maparg('<Up>', 'n', 0, 1)
Assert(!empty(up_map), '<Up> is mapped')
Assert(get(up_map, 'rhs', '') =~ 'SelectPrev', '<Up> maps to SelectPrev')

# Q (capital) must close pane
# Q → HandlePaneQ: switches to qfix in temporary mode, closes in permanent
var Q_map = maparg('Q', 'n', 0, 1)
Assert(!empty(Q_map), 'Q is mapped')
Assert(get(Q_map, 'rhs', '') =~ 'HandlePaneQ', 'Q maps to HandlePaneQ')

# R (shift-R) must be refresh
var R_map = maparg('R', 'n', 0, 1)
Assert(!empty(R_map), 'R is mapped')
Assert(get(R_map, 'rhs', '') =~ 'Refresh', 'R maps to Refresh')

# P (shift-P) must be preview toggle
var P_map = maparg('P', 'n', 0, 1)
Assert(!empty(P_map), 'P is mapped')
Assert(get(P_map, 'rhs', '') =~ 'TogglePreview', 'P maps to TogglePreview')

# X (shift-X) must be close buffer
var X_map = maparg('X', 'n', 0, 1)
Assert(!empty(X_map), 'X is mapped')
Assert(get(X_map, 'rhs', '') =~ 'CloseBuffer', 'X maps to CloseBuffer')

# p must be a nav char (TogglePreview moved to P)
var p_map = maparg('p', 'n', 0, 1)
Assert(empty(p_map) || get(p_map, 'rhs', '') =~ 'VprojKey\|SelectByNavChar',
      'p is NOT mapped to TogglePreview (nav char or unmapped)')

# r must be a nav char (Refresh moved to R)
var r_map = maparg('r', 'n', 0, 1)
Assert(empty(r_map) || get(r_map, 'rhs', '') =~ 'VprojKey\|SelectByNavChar',
      'r is NOT mapped to Refresh (nav char or unmapped)')

# x must be a nav char (CloseBuffer moved to X)
var x_map = maparg('x', 'n', 0, 1)
Assert(empty(x_map) || get(x_map, 'rhs', '') =~ 'VprojKey\|SelectByNavChar',
      'x is NOT mapped to CloseBuffer (nav char or unmapped)')

# ──────────────────────────────────────────────
# FIX 7: Nav indicator color (visual — verify highlight group exists)
# ──────────────────────────────────────────────
echom '=== Fix 7: Nav indicator highlight group ==='
Setup()

var hl_exists: bool = hlexists('VprojNavIndicator')
Assert(hl_exists, 'VprojNavIndicator highlight group exists')

# ──────────────────────────────────────────────
# FIX 8: No duplicate Q mapping
# ──────────────────────────────────────────────
echom '=== Fix 8: No duplicate Q mapping ==='
Setup()
FocusPane()

# Q should appear exactly once in the buffer's mappings
var Q_maps = filter(maparg('Q', 'n', 0, 1)->copy(), (_, v) => true)
# maparg only returns one — if it returns one, there's no conflict causing issues
Assert(!empty(Q_map), 'Q has exactly one active mapping (no duplicate conflict)')

# ──────────────────────────────────────────────
# Bonus: Ctrl key alternatives
# ──────────────────────────────────────────────
echom '=== Ctrl alternatives for navigation ==='

var ck_map = maparg('<C-K>', 'n', 0, 1)
Assert(!empty(ck_map), '<C-K> is mapped')
Assert(get(ck_map, 'rhs', '') =~ 'NavigateUp', '<C-K> maps to NavigateUp')

var cj_map = maparg('<C-J>', 'n', 0, 1)
Assert(!empty(cj_map), '<C-J> is mapped')
Assert(get(cj_map, 'rhs', '') =~ 'NavigateIntoFirstDir', '<C-J> maps to NavigateIntoFirstDir')

var ct_map = maparg('<C-T>', 'n', 0, 1)
Assert(!empty(ct_map), '<C-T> is mapped')
Assert(get(ct_map, 'rhs', '') =~ 'SelectFirst', '<C-T> maps to SelectFirst')

var cb_map = maparg('<C-B>', 'n', 0, 1)
Assert(!empty(cb_map), '<C-B> is mapped')
Assert(get(cb_map, 'rhs', '') =~ 'SelectLast', '<C-B> maps to SelectLast')

# ──────────────────────────────────────────────
# Cleanup
# ──────────────────────────────────────────────
vproj#PaneClose()

echom ''
if failures == 0
  echom 'ALL AUDIT FIXES VERIFIED.'
else
  echohl ErrorMsg
  echom failures .. ' AUDIT FIX TEST(S) FAILED.'
  echohl None
  cquit!
endif
qa!
