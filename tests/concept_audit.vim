vim9script

# Concept Document Verification Test
# Run: vim -N -u NONE -S tests/concept_audit.vim
#
# Verifies every testable claim in doc/concept.md. Calls functions directly
# rather than simulating keypresses — keypress-to-function mapping is covered
# by tests/keybindings.vim.

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

# rhs of a normal-mode mapping in the current buffer, '' when unmapped.
# Never index maparg()'s dict directly: an unmapped key returns {} and
# `.rhs` aborts the whole script with E716.
def MapRhs(lhs: string): string
  return get(maparg(lhs, 'n', false, true), 'rhs', '')
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
# SECTION 6: Navigation Keys (<Down>/<Up>, ., F1; j/k/h are nav chars)
# ═══════════════════════════════════════════════════════════════════
echom '--- Section 6: Navigation Keys ---'

vproj#PaneOpen()
FocusPane()

# <Down>/<Up> move the selection. j/k/h are nav chars since 53f814c
# (all lowercase a-z route through VprojKey).
Assert(MapRhs('<Down>') =~ 'SelectNext', '<Down> maps to SelectNext')
Assert(MapRhs('<Up>') =~ 'SelectPrev', '<Up> maps to SelectPrev')
for ch in ['j', 'k', 'h']
  Assert(MapRhs(ch) =~ 'VprojKey', ch .. ' is a nav char (maps to VprojKey)')
endfor

# . — parent directory, routed through VprojKey for the file/code mode guard
Assert(MapRhs('.') =~ 'VprojKey("\.")', '. maps to VprojKey(".") (parent dir)')
# <C-K> — parent directory, direct
Assert(MapRhs('<C-K>') =~ 'NavigateUp', '<C-K> maps to NavigateUp')

# F1 — toggle info column (global <Plug>VprojF1 mapping, pane-aware handler)
Assert(maparg('<F1>', 'n') =~ 'VprojF1', '<F1> maps to <Plug>VprojF1')

vproj#PaneClose()

# ═══════════════════════════════════════════════════════════════════
# SECTION 7: Action Keys (R, T, /, *, X, Q)
# ═══════════════════════════════════════════════════════════════════
echom '--- Section 7: Action Keys ---'

vproj#PaneOpen()
FocusPane()

# R — refresh (lowercase r is a nav char)
Assert(MapRhs('R') =~ 'Refresh', 'R maps to Refresh')
execute 'normal R'
Assert(vproj#IsPaneVisible(), 'R (refresh) keeps pane visible')

# T — tree view toggle
vproj#SwitchMode('file')
FocusPane()
var tree_before = vproj#IsTreeViewActive()
execute 'normal T'
Assert(vproj#IsTreeViewActive() != tree_before, 'T toggles tree view')

# / — filter prompt (mapped in pane buffer)
Assert(MapRhs('/') =~ 'PromptFilter', '/ maps to PromptFilter')

# * — grep search
Assert(MapRhs('*') =~ 'GrepSearch', '* maps to GrepSearch')

# X — close buffer (buf mode; lowercase x is a nav char)
vproj#SwitchMode('buf')
FocusPane()
Assert(MapRhs('X') =~ 'CloseBuffer', 'X maps to CloseBuffer')
Assert(MapRhs('x') =~ 'VprojKey', 'x is a nav char (maps to VprojKey)')

# Q — HandlePaneQ: temporary mode switches to qfix, permanent mode closes
Assert(MapRhs('Q') =~ 'HandlePaneQ', 'Q maps to HandlePaneQ')
execute 'normal Q'
Assert(vproj#IsPaneVisible() && vproj#GetCurrentMode() == 'qfix',
      'Q in temporary mode switches to qfix (pane stays open)')
vproj#PaneTogglePermanent()
FocusPane()
execute 'normal Q'
Assert(!vproj#IsPaneVisible(), 'Q in permanent mode closes pane')

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
  Assert(MapRhs(lhs) =~ rhs_fragment, lhs .. ' maps to ' .. rhs_fragment)
endfor

# Lowercase keys the concept doc listed as git actions are now nav chars
for ch in ['s', 'd', 'c', 'b', 'z', 'a']
  Assert(MapRhs(ch) =~ 'VprojKey', ch .. ' is a nav char (maps to VprojKey)')
endfor
# Uppercase D/U/Z are unmapped (git actions moved to \ prefix)
for ch in ['D', 'U', 'Z']
  Assert(empty(maparg(ch, 'n')), ch .. ' is unmapped (git action moved to \\ prefix)')
endfor
# P is Shift-P: preview toggle, not git push
Assert(MapRhs('P') =~ 'TogglePreview', 'P maps to TogglePreview')

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
