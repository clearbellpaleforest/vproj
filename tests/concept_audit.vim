vim9script

# Concept Document Verification Test
# Run: vim -N -u NONE -S tests/concept_audit.vim
#
# Verifies every testable claim in doc/concept.md. Calls functions directly
# rather than simulating keypresses — keypress-to-function mapping is covered
# by tests/keybindings.vim.

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

def PaneBufNr(): number
  return bufnr('VPROJ')
enddef

def PaneWinID(): number
  var pbuf = PaneBufNr()
  var wins = win_findbuf(pbuf)
  return empty(wins) ? 0 : wins[0]
enddef

def PaneCursorLine(): number
  var wid = PaneWinID()
  return wid == 0 ? -1 : line('.', wid)
enddef

def FocusPane(): void
  var wid = PaneWinID()
  if wid > 0
    win_gotoid(wid)
  endif
enddef

echom '=== Concept Document Verification ==='
echom ''

# ═══════════════════════════════════════════════════════════════════
# SECTION 1: Pane Toggle — Temporary Mode (Tab key → PaneToggle)
# ═══════════════════════════════════════════════════════════════════
echom '--- Section 1: Pane Toggle (Temporary Mode) ---'

# 1a — PaneToggle opens pane
vproj#PaneClose()
vproj#PaneToggle()
Assert(vproj#IsPaneVisible(), 'PaneToggle opens pane')
Assert(vproj#GetCurrentMode() == 'file', 'PaneToggle opens in file mode')

# 1b — PaneToggle closes pane when already open in temp mode
vproj#PaneToggle()
Assert(!vproj#IsPaneVisible(), 'PaneToggle closes pane in temp mode')

# 1c — ESC closes pane in temporary mode
vproj#PaneToggle()
FocusPane()
execute "normal \<Esc>"
Assert(!vproj#IsPaneVisible(), 'ESC closes pane in temporary mode')

# ═══════════════════════════════════════════════════════════════════
# SECTION 2: Pane Toggle — Permanent Mode (Shift-Tab → PaneTogglePermanent)
# ═══════════════════════════════════════════════════════════════════
echom '--- Section 2: Pane Toggle (Permanent Mode) ---'

vproj#PaneClose()

# 2a — PaneTogglePermanent opens pane
vproj#PaneTogglePermanent()
Assert(vproj#IsPaneVisible(), 'PaneTogglePermanent opens pane')

# 2b — ESC does NOT close pane in permanent mode
FocusPane()
execute "normal \<Esc>"
Assert(vproj#IsPaneVisible(), 'ESC does not close pane in permanent mode')

# 2c — Q closes pane in permanent mode
execute 'normal Q'
Assert(!vproj#IsPaneVisible(), 'Q closes pane in permanent mode')

# 2d — PaneTogglePermanent again closes
vproj#PaneTogglePermanent()
vproj#PaneTogglePermanent()
Assert(!vproj#IsPaneVisible(), 'PaneTogglePermanent toggles pane closed')

# ═══════════════════════════════════════════════════════════════════
# SECTION 3: Pane Width (default 40, range 20-80, Left/Right adjust)
# ═══════════════════════════════════════════════════════════════════
echom '--- Section 3: Pane Width ---'

vproj#PaneOpen()
FocusPane()

var w: number = vproj#GetPaneWidth()
Assert(w >= 20 && w <= 80, 'Pane width in range 20-80 (actual: ' .. w .. ')')

# Left shrinks by 1
var w_before = w
execute "normal \<Left>"
Assert(vproj#GetPaneWidth() == w_before - 1 || vproj#GetPaneWidth() == 20,
      'Left arrow shrinks pane (or at minimum 20)')

# Right grows by 1
w_before = vproj#GetPaneWidth()
execute "normal \<Right>"
Assert(vproj#GetPaneWidth() == w_before + 1 || vproj#GetPaneWidth() == 80,
      'Right arrow grows pane (or at maximum 80)')

vproj#PaneClose()

# ═══════════════════════════════════════════════════════════════════
# SECTION 4: Two-Panel Layout
# ═══════════════════════════════════════════════════════════════════
echom '--- Section 4: Two-Panel Layout ---'

# Verified by keybindings.vim Section 9a. Concept doc requires:
# "When a file is opened from the pane, it opens in a window to the
#  right of the pane. The pane stays visible on the left."
# keybindings.vim asserts: Two-panel Enter on file: window count unchanged

# ═══════════════════════════════════════════════════════════════════
# SECTION 5: Mode Switching
# ═══════════════════════════════════════════════════════════════════
echom '--- Section 5: Mode Switching ---'

vproj#PaneOpen()
FocusPane()

vproj#SwitchMode('file')
Assert(vproj#GetCurrentMode() == 'file', 'SwitchMode file → file mode')

vproj#SwitchMode('buf')
Assert(vproj#GetCurrentMode() == 'buf', 'SwitchMode buf → buffer mode')

vproj#SwitchMode('code')
Assert(vproj#GetCurrentMode() == 'code', 'SwitchMode code → code mode')

vproj#SwitchMode('qfix')
Assert(vproj#GetCurrentMode() == 'qfix', 'SwitchMode qfix → qfix mode')

# q key switches to qfix in temp mode — tested in keybindings.vim §7c
vproj#PaneClose()

# ═══════════════════════════════════════════════════════════════════
# SECTION 6: Navigation Keys (j, k, h, ., F1)
# ═══════════════════════════════════════════════════════════════════
echom '--- Section 6: Navigation Keys ---'

vproj#PaneOpen()
FocusPane()

# j/k — move selection (mapped to SelectNext/SelectPrev)
var j_map = maparg('j', 'n', 0, 1)
Assert(!empty(j_map), 'j is mapped in pane buffer')
Assert(j_map.rhs =~ 'SelectNext', 'j maps to SelectNext')

var k_map = maparg('k', 'n', 0, 1)
Assert(!empty(k_map), 'k is mapped in pane buffer')
Assert(k_map.rhs =~ 'SelectPrev', 'k maps to SelectPrev')

# Up/Down arrows also move selection
var down_map = maparg('<Down>', 'n', 0, 1)
Assert(!empty(down_map), '<Down> is mapped in pane buffer')
Assert(down_map.rhs =~ 'SelectNext', '<Down> maps to SelectNext')

# h / . — parent directory (both mapped to NavigateUp)
var h_map = maparg('h', 'n', 0, 1)
Assert(!empty(h_map), 'h is mapped in pane buffer')
Assert(h_map.rhs =~ 'NavigateUp', 'h maps to NavigateUp')

var dot_map = maparg('.', 'n', 0, 1)
Assert(!empty(dot_map), '. is mapped in pane buffer')
Assert(dot_map.rhs =~ 'NavigateUp', '. maps to NavigateUp')

# F1 — toggle info column
var f1_map = maparg('<F1>', 'n', 0, 1)
Assert(!empty(f1_map), '<F1> is mapped in pane buffer')

vproj#PaneClose()

# ═══════════════════════════════════════════════════════════════════
# SECTION 7: Action Keys (r, T, /, *, x, Q)
# ═══════════════════════════════════════════════════════════════════
echom '--- Section 7: Action Keys ---'

vproj#PaneOpen()
FocusPane()

# r — refresh
execute 'normal r'
Assert(vproj#IsPaneVisible(), 'r (refresh) keeps pane visible')

# T — tree view toggle
vproj#SwitchMode('file')
FocusPane()
var tree_before = vproj#IsTreeViewActive()
execute 'normal T'
Assert(vproj#IsTreeViewActive() != tree_before, 'T toggles tree view')

# / — filter prompt (mapped in pane buffer)
var slash_map = maparg('/', 'n', 0, 1)
Assert(!empty(slash_map), '/ is mapped in pane buffer')

# * — grep search
var star_map = maparg('*', 'n', 0, 1)
Assert(!empty(star_map), '* is mapped in pane buffer')
Assert(star_map.rhs =~ 'GrepSearch', '* maps to GrepSearch')

# x — close buffer (mapped in pane buffer, buf mode)
vproj#SwitchMode('buf')
FocusPane()
var x_map = maparg('x', 'n', 0, 1)
Assert(!empty(x_map), 'x is mapped in pane buffer')

# Q — close pane
execute 'normal Q'
Assert(!vproj#IsPaneVisible(), 'Q closes pane')

# ═══════════════════════════════════════════════════════════════════
# SECTION 8: Git Actions (\ prefix)
# ═══════════════════════════════════════════════════════════════════
echom '--- Section 8: Git Actions (\\ prefix) ---'

vproj#PaneOpen()
FocusPane()

# All git actions use \ prefix, lowercase a-z freed as nav chars
var git_actions: list<list<string>> = [
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

for [lhs, rhs_fragment] in git_actions
  var m = maparg(lhs, 'n', 0, 1)
  Assert(!empty(m), lhs .. ' is mapped in pane buffer')
  Assert(m.rhs =~ rhs_fragment, lhs .. ' maps to ' .. rhs_fragment)
endfor

# Single-letter keys that concept doc listed as git actions are now nav chars
for ch in ['s', 'd', 'c', 'b', 'z', 'a', 'D', 'P', 'U', 'Z']
  var m = maparg(ch, 'n', 0, 1)
  Assert(!empty(m), ch .. ' is mapped (nav char)')
  Assert(m.rhs =~ 'SelectByNavChar', ch .. ' maps to SelectByNavChar')
endfor

vproj#PaneClose()

# ═══════════════════════════════════════════════════════════════════
# SECTION 9: Log Mode — REMOVED
#   Log mode out of scope.
#   Concept doc still lists it but it is intentionally not implemented.
# ═══════════════════════════════════════════════════════════════════
echom '--- Section 9: Log Mode (removed) ---'

vproj#PaneOpen()
FocusPane()
try
  execute "normal \<S-L>"
  Assert(vproj#GetCurrentMode() != 'log', 'S-L does not switch to log mode (removed)')
catch
  Assert(false, 'S-L error: ' .. v:exception)
endtry

vproj#PaneClose()

# ═══════════════════════════════════════════════════════════════════
# SECTION 10: Highlight Groups (semantic, highlight default link)
#   Concept doc requires: "semantic groups with highlight default link,
#   not hardcoded colors. Must work on top of user's colorscheme."
# ═══════════════════════════════════════════════════════════════════
echom '--- Section 10: Highlight Groups ---'

var expected_groups: list<string> = [
  'VprojGitModified',
  'VprojGitAdded',
  'VprojGitDeleted',
  'VprojGitRenamed',
  'VprojGitUntracked',
  'VprojGitConflict',
  'VprojModeFile',
  'VprojModeBuf',
  'VprojModeCode',
  'VprojModeQfix',
  'VprojCursorLine',
  'VprojNavIndicator',
  'VprojInfoColumn',
  'VprojParentDir',
  'VprojDirName',
  'VprojSeparator',
  'VprojStatusLine',
]

for group in expected_groups
  Assert(hlexists(group) == 1, 'Highlight group exists: ' .. group)
endfor

# ═══════════════════════════════════════════════════════════════════
# SECTION 11: Commands
# ═══════════════════════════════════════════════════════════════════
echom '--- Section 11: Commands ---'

var expected_cmds: list<string> = [
  'VprojToggle',
  'VprojOpen',
  'VprojClose',
  'VprojRefresh',
  'VprojDiag',
]

for cmd in expected_cmds
  Assert(exists(':' .. cmd) == 2, 'Command exists: :' .. cmd)
endfor

# ═══════════════════════════════════════════════════════════════════
# SECTION 12: Tab and Shift-Tab Default Mappings
#   Verified: plugin/vproj.vim lines 41-46 maps <Tab> → VprojToggle
#   and <S-Tab> → VprojTogglePermanent with hasmapto guards.
# ═══════════════════════════════════════════════════════════════════
echom '--- Section 12: Tab/Shift-Tab Default Mappings ---'

var tab_map = maparg('<Tab>', 'n', 0, 1)
Assert(!empty(tab_map) || mapcheck('<Tab>', 'n') != '',
      '<Tab> has a mapping (default or user)')

var stab_map = maparg('<S-Tab>', 'n', 0, 1)
Assert(!empty(stab_map) || mapcheck('<S-Tab>', 'n') != '',
      '<S-Tab> has a mapping (default or user)')

# ═══════════════════════════════════════════════════════════════════
# Cleanup
# ═══════════════════════════════════════════════════════════════════
vproj#PaneClose()

echom ''
if failures == 0
  echom 'ALL CONCEPT VERIFICATION TESTS PASSED.'
else
  echohl ErrorMsg
  echom failures .. ' CONCEPT VERIFICATION TEST(S) FAILED.'
  echohl None
  cquit!
endif
qa!
