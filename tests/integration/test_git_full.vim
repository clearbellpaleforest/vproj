vim9script

# Integration tests for git features: Diff, Commit, Push, Pull, Branch (Log mode removed)
# Run: vim -N -u NONE -S tests/integration/test_git_full.vim

set rtp+=src
runtime! plugin/vproj.vim
set nomore

var failures: number = 0

def PaneCursorLine(): number
  var pbuf = bufnr('VPROJ')
  var wins = win_findbuf(pbuf)
  return empty(wins) ? -1 : line('.', wins[0])
enddef

def Assert(cond: bool, msg: string): void
  if !cond
    echohl ErrorMsg | echom 'FAIL: ' .. msg | echohl None
    failures += 1
  else
    echom 'PASS: ' .. msg
  endif
enddef

# ──────────────────────────────────────────────
# Ensure clean slate
# ──────────────────────────────────────────────
vproj#PaneClose()
call delete(expand('~/.cache/vproj/session'))

# ──────────────────────────────────────────────
# SECTION 1: Log mode removed
# ──────────────────────────────────────────────
echom '--- Log Mode Removed ---'
vproj#PaneOpen()

# 'log' is not in MODE_KEYS — SwitchMode is a no-op, stays in current mode
vproj#SwitchMode('log')
Assert(vproj#IsPaneVisible(), 'log removed: pane still visible')
Assert(vproj#GetCurrentMode() == 'file', 'log removed: mode stays file')

# Mode menu shows 4 modes, not 5 — no [L]og
var lines = getbufline(bufnr('VPROJ'), 1, '$')
Assert(len(lines) >= 3, 'log removed: at least 3 lines (menu + sep + item)')
Assert(lines[0] !~ '\[L\]og', 'log removed: menu has no [L]og')
Assert(lines[0] =~ '\[F\]ile.*\[B\]uf.*\[C\]ode.*\[q\]fix', 'log removed: menu shows 4 modes')

# Cursor is on first selectable item (file mode)
var cursor_line = PaneCursorLine()
Assert(cursor_line == 3, 'log removed: cursor on first item')

# L removed as log mode key — uppercase L is now unmapped (log mode removed)
var L_map = maparg('L', 'n', 0, 1)
Assert(empty(L_map), 'L unmapped (log mode removed)')
# Lowercase l is a nav char (was previously shadowed by log mode L)
var l_map = maparg('l', 'n', 0, 1)
Assert(!empty(l_map), 'l is a nav char')
Assert(l_map.rhs =~ 'SelectByNavChar\|VprojKey', 'l maps to nav dispatch (freed from log mode)')

# Verify mode switching works correctly with 4 modes only
vproj#SwitchMode('buf')
Assert(vproj#GetCurrentMode() == 'buf', 'mode: buf')
vproj#SwitchMode('code')
Assert(vproj#GetCurrentMode() == 'code', 'mode: code')
vproj#SwitchMode('qfix')
Assert(vproj#GetCurrentMode() == 'qfix', 'mode: qfix')
vproj#SwitchMode('file')
Assert(vproj#GetCurrentMode() == 'file', 'mode: file')

# ──────────────────────────────────────────────
# SECTION 5: Diff Preview
# ──────────────────────────────────────────────
echom '--- Diff Preview ---'

vproj#SwitchMode('file')

# \d opens a diff preview window — verify window count changes
var wins_before: number = winnr('$')
try
  execute 'normal \d'
  var wins_after: number = winnr('$')
  Assert(vproj#IsPaneVisible(), '\d diff preview: pane stays visible')
  Assert(wins_after >= wins_before, '\d diff preview: window count did not decrease')
catch
  Assert(false, '\d diff preview error: ' .. v:exception)
endtry

# Close any diff window that may have opened
var pane_wnr = bufwinnr(bufnr('VPROJ'))
var pane_wid = pane_wnr > 0 ? win_getid(pane_wnr) : 0
var all_wins = range(1, winnr('$'))
for wnr in all_wins
  if wnr != pane_wnr && getbufvar(winbufnr(wnr), '&filetype') == 'diff'
    var wid = win_getid(wnr)
    win_gotoid(wid)
    close!
    break
  endif
endfor
if pane_wid > 0
  win_gotoid(pane_wid)
endif

# ──────────────────────────────────────────────
# SECTION 6: Diff Preview on Non-Git File
# ──────────────────────────────────────────────
echom '--- Diff Preview Edge Cases ---'

# OpenDiffPreview on first item (.. is a dir, so it exits early)
var wins_edge_before: number = winnr('$')
try
  call vproj#OpenDiffPreview()
  var wins_edge_after: number = winnr('$')
  Assert(wins_edge_after == wins_edge_before, 'OpenDiffPreview on dir: no windows created')
  Assert(vproj#IsPaneVisible(), 'OpenDiffPreview on dir: pane still visible')
catch
  Assert(false, 'OpenDiffPreview crash: ' .. v:exception)
endtry

# ──────────────────────────────────────────────
# SECTION 6b: IsRegularFile with symlink (gap 5)
# ──────────────────────────────────────────────
echom '--- IsRegularFile Symlink ---'

# IsRegularFile is used by ReadDir (line 2079) to filter directory entries.
# A symlink to a regular file should pass IsRegularFile and appear in the listing.
var sl_dir = '/tmp/vproj_symlink_test'
if isdirectory(sl_dir) | delete(sl_dir, 'rf') | endif
mkdir(sl_dir)
writefile(['symlink test content', 'line 2'], sl_dir .. '/real_file.txt')
silent! system('ln -s ' .. shellescape(sl_dir .. '/real_file.txt') .. ' ' .. shellescape(sl_dir .. '/link_to_file.txt'))

execute 'cd' sl_dir
vproj#PaneClose()
vproj#PaneOpen()
vproj#SwitchMode('file')

# Scan the listing for the symlink — IsRegularFile must return true for it to appear
var sl_lines = getbufline(bufnr('VPROJ'), 1, '$')
var sl_symlink_found = false
var sl_real_found = false
for l in sl_lines
  if l =~ 'link_to_file'
    sl_symlink_found = true
  endif
  if l =~ 'real_file'
    sl_real_found = true
  endif
endfor
Assert(sl_real_found, 'symlink: real_file.txt appears in listing')
Assert(sl_symlink_found, 'symlink: link_to_file.txt appears in listing (IsRegularFile returned true)')

vproj#PaneClose()
execute 'cd' getcwd()
delete(sl_dir, 'rf')

# Reopen pane for subsequent sections
vproj#PaneOpen()
vproj#SwitchMode('file')

# ──────────────────────────────────────────────
# SECTION 7: Discard Changes Edge Cases
# ──────────────────────────────────────────────
echom '--- Discard Edge Cases ---'

# Discard in buf mode should exit early (guard: mode != 'file' && mode != 'code')
vproj#SwitchMode('buf')
var wins_discard1: number = winnr('$')
try
  call vproj#DiscardChanges()
  Assert(winnr('$') == wins_discard1, 'DiscardChanges in buf mode: no windows created')
  Assert(vproj#GetCurrentMode() == 'buf', 'DiscardChanges in buf mode: mode unchanged')
catch
  Assert(false, 'DiscardChanges in buf mode crash: ' .. v:exception)
endtry

# Discard in code mode should exit early (guard: empty item or not in git)
vproj#SwitchMode('code')
var wins_discard2: number = winnr('$')
try
  call vproj#DiscardChanges()
  Assert(winnr('$') == wins_discard2, 'DiscardChanges in code mode: no windows created')
  Assert(vproj#GetCurrentMode() == 'code', 'DiscardChanges in code mode: mode unchanged')
catch
  Assert(false, 'DiscardChanges in code mode crash: ' .. v:exception)
endtry

# ──────────────────────────────────────────────
# SECTION 8: D Key is Nav Char (DiscardChanges uses \D)
# ──────────────────────────────────────────────
echom '--- D Key Mapping ---'
vproj#SwitchMode('file')
var D_map = maparg('D', 'n', 0, 1)
Assert(empty(D_map), 'Uppercase D unmapped (freed from git)')
var d_map = maparg('d', 'n', 0, 1)
Assert(!empty(d_map), 'Lowercase d is mapped in pane buffer')
Assert(d_map.rhs =~ 'VprojKey\|SelectByNavChar', 'd is nav char (freed from git)')

# \D maps to DiscardChanges
var bslash_D_map = maparg('\D', 'n', 0, 1)
Assert(!empty(bslash_D_map), '\D has a mapping')
Assert(bslash_D_map.rhs =~ 'DiscardChanges', '\D maps to DiscardChanges')

# ──────────────────────────────────────────────
# SECTION 9: Git Functions Exist
# ──────────────────────────────────────────────
echom '--- Function Existence ---'

# Commit/BranchSwitch use input() — can't call in scripts.
# Push/Pull would actually push/pull — verify exist without calling.
Assert(exists('*vproj#GitCommit') == 1, 'GitCommit function exists')
Assert(exists('*vproj#GitPush') == 1, 'GitPush function exists')
Assert(exists('*vproj#GitPull') == 1, 'GitPull function exists')
Assert(exists('*vproj#GitBranchSwitch') == 1, 'GitBranchSwitch function exists')
Assert(exists('*vproj#OpenDiffPreview') == 1, 'OpenDiffPreview function exists')
Assert(exists('*vproj#DiscardChanges') == 1, 'DiscardChanges function exists')

# ──────────────────────────────────────────────
# SECTION 10: GitPush / GitPull Mappings
# ──────────────────────────────────────────────
echom '--- Push/Pull Mappings ---'

# Verify the key mappings for \p and \u are wired to GitPush/GitPull
var p_map = maparg('\p', 'n', 0, 1)
Assert(!empty(p_map), '\p is mapped')
Assert(p_map.rhs =~ 'GitPush', '\p maps to GitPush')

var u_map = maparg('\u', 'n', 0, 1)
Assert(!empty(u_map), '\u is mapped')
Assert(u_map.rhs =~ 'GitPull', '\u maps to GitPull')

# ──────────────────────────────────────────────
# SECTION 12: C, P, U, B Key Mappings
# ──────────────────────────────────────────────
echom '--- Whole-Repo Key Mappings ---'

vproj#SwitchMode('file')

var c_map = maparg('C', 'n', 0, 1)
Assert(!empty(c_map), 'C is mapped in pane buffer')
Assert(c_map.lhs == 'C', 'C map exists')

var P_map = maparg('P', 'n', 0, 1)
Assert(!empty(P_map), 'P is mapped in pane buffer')
Assert(P_map.lhs == 'P', 'P map exists')

var U_map = maparg('U', 'n', 0, 1)
Assert(empty(U_map), 'U is unmapped (freed from git)')
var u_nav_map = maparg('u', 'n', 0, 1)
Assert(!empty(u_nav_map), 'u is a nav char')
Assert(u_nav_map.rhs =~ 'VprojKey\|SelectByNavChar', 'u is nav char (freed from git)')

var b_map = maparg('B', 'n', 0, 1)
Assert(!empty(b_map), 'B is mapped in pane buffer')
Assert(b_map.lhs == 'B', 'B map exists')

# ──────────────────────────────────────────────
# SECTION 13: NAV_CHARS Exclusion
# ──────────────────────────────────────────────
echom '--- NAV_CHARS Exclusion ---'

# Verify git action keys use \ prefix
# d, D, c, P, U, b, a, z, Z are now nav chars — git actions use \ prefix
vproj#SwitchMode('file')

# d is a nav char (freed by \ prefix), not a direct action key
var d_nav_map = maparg('d', 'n', 0, 1)
Assert(!empty(d_nav_map), 'd has a mapping')
Assert(d_nav_map.rhs =~ 'VprojKey\|SelectByNavChar', 'd is nav char (git actions use \\ prefix)')

# \d maps to OpenDiffPreview
var bslash_d_map = maparg('\d', 'n', 0, 1)
Assert(!empty(bslash_d_map), '\\d has a mapping')
Assert(bslash_d_map.rhs =~ 'OpenDiffPreview', '\\d maps to OpenDiffPreview')

# L freed (log mode removed) — uppercase L is unmapped, lowercase l is a nav char
var L_action_map = maparg('L', 'n', 0, 1)
Assert(empty(L_action_map), 'L unmapped (log mode removed)')
var l_action_map = maparg('l', 'n', 0, 1)
Assert(!empty(l_action_map), 'l is nav char (freed from log mode)')
Assert(l_action_map.rhs =~ 'VprojKey\|SelectByNavChar', 'l maps to nav dispatch (log mode removed)')

# ──────────────────────────────────────────────
# SECTION 14: Session Persistence — log→file migration
# ──────────────────────────────────────────────
echom '--- Session Persistence ---'

vproj#SwitchMode('log')
vproj#PaneClose()

# Reopen — session with 'log' should migrate to 'file'
vproj#PaneOpen()
Assert(vproj#IsPaneVisible(), 'session: pane visible after reopen')
Assert(vproj#GetCurrentMode() == 'file', 'session: log migrated to file')

# ──────────────────────────────────────────────
# SECTION 15: SwitchMode('log') is a no-op
# ──────────────────────────────────────────────
echom '--- SwitchMode(log) no-op ---'

vproj#SwitchMode('log')
Assert(vproj#GetCurrentMode() == 'file', 'log→file: mode stays file')
var w_before = vproj#GetPaneWidth()

# SwitchMode('log') should not change width
vproj#SwitchMode('log')
Assert(vproj#GetPaneWidth() == w_before, 'log→file: width unchanged')

# ToggleInfoColumn verification after log→file migration
var info_state_before = vproj#IsInfoColumnVisible()
vproj#ToggleInfoColumn()
Assert(vproj#IsInfoColumnVisible() != info_state_before, 'log→file: info column toggle changed visibility')
Assert(vproj#IsPaneVisible(), 'log→file: pane visible after first toggle')

vproj#ToggleInfoColumn()
Assert(vproj#IsInfoColumnVisible() == info_state_before, 'log→file: info column toggle back to original')
Assert(vproj#IsPaneVisible(), 'log→file: pane visible after second toggle')

# SECTION 19: GitStashPush / GitStashPop Function Existence
# ──────────────────────────────────────────────
echom '--- Stash Function Existence ---'

Assert(exists('*vproj#GitStashPush'), 'GitStashPush function exists')
Assert(exists('*vproj#GitStashPop'), 'GitStashPop function exists')

# SECTION 20: GitBlame Function and Guards
# ──────────────────────────────────────────────
echom '--- Blame Function Existence ---'

Assert(exists('*vproj#GitBlame'), 'GitBlame function exists')

# Blame is file+code-mode-only — should exit silently in other modes
vproj#SwitchMode('buf')
var wins_blame1: number = winnr('$')
try
  call vproj#GitBlame()
  Assert(winnr('$') == wins_blame1, 'GitBlame in buf mode: no windows created')
  Assert(vproj#GetCurrentMode() == 'buf', 'GitBlame in buf mode: mode unchanged')
catch
  Assert(false, 'GitBlame in buf mode threw: ' .. v:exception)
endtry

vproj#SwitchMode('code')
var wins_blame2: number = winnr('$')
try
  call vproj#GitBlame()
  Assert(winnr('$') == wins_blame2, 'GitBlame in code mode: no windows created')
  Assert(vproj#GetCurrentMode() == 'code', 'GitBlame in code mode: mode unchanged')
catch
  Assert(false, 'GitBlame in code mode threw: ' .. v:exception)
endtry

# Switch back to file mode for further tests
vproj#SwitchMode('file')

# ──────────────────────────────────────────────
# Cleanup
# ──────────────────────────────────────────────

unlet! g:vproj_pane_width_log
vproj#PaneClose()
call delete(expand('~/.cache/vproj/session'))

echom ''
if failures == 0
  echom 'ALL GIT FULL INTEGRATION TESTS PASSED.'
else
  echohl ErrorMsg
  echom failures .. ' GIT FULL INTEGRATION TEST(S) FAILED.'
  echohl None
  cquit!
endif
qa!
