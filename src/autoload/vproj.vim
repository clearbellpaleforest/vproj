vim9script

# autoload/vproj.vim — VPROJ project manager

# Script-local state
var pane_bufnr: number = -1
var pane_width: number = 40
var current_mode: string = 'file'
var pane_open_mode: string = 'temporary'
var selected_line: number = 1
var current_dir: string = ''
var items: list<dict<any>> = []
var show_info_column: bool = true
var current_page: number = 0
var items_per_page: number = 1
# Width the user asked for while the terminal was too narrow to give it; 0
# when pane_width is what was asked for. A resize back restores it.
var pane_width_wanted: number = 0
var paging_active: bool = false
var nav_offset: number = 0
# True while vproj has added 'S' to 'shortmess'; only that flag is removed
# on close, so the user's own shortmess changes survive.
var added_shortmess_s: bool = false
# Window view carried across RetargetBuffer's :edit (see there).
var retarget_view: dict<any> = {}
var filter_pattern: string = ''
var git_filter_active: bool = false
var saved_origin_wid: number = -1

# Git integration cache
var git_status_map: dict<string> = {}
# Raw two-column porcelain status per absolute path: X = index, Y = worktree
# (e.g. ' M' modified unstaged, 'M ' staged, 'MM' both, '??' untracked).
# Actions need both columns; git_status_map folds them into one display char.
var git_status_xy: dict<string> = {}
# Source path of a staged rename or copy, keyed like git_status_xy.
var git_status_orig: dict<string> = {}
var git_branch_cache: string = ''
var git_root_cache: string = ''
# Last SaveSession failure. The save runs from the pane's wipeout autocmd,
# which PaneClose triggers inside win_execute(); echom output from there is
# discarded, so PaneClose re-reports this after the window is gone.
var session_error: string = ''
# The directory git_root_cache / git_branch_cache were computed for, and
# whether each was computed at all (an empty answer is a valid, cacheable one:
# not a repo, or a detached HEAD with nothing to name).
var git_ctx_dir: string = ''
var git_root_known: bool = false
var git_branch_known: bool = false

# Project state (code mode)
var project: dict<any> = {}
var code_root: string = ''



# Tree view state (file mode — T toggles)
var tree_view_active: bool = false
var expanded_dirs: dict<number> = {}

# Preview state (file modes — p toggles)
var preview_active: bool = false
var preview_bufnr: number = -1

const MODE_KEYS: list<string> = ['file', 'buf', 'code', 'qfix']
const MODE_LABELS: dict<string> = {file: '[F]ile', buf: '[B]uf', code: '[C]ode', qfix: '[q]fix'}
const MODE_HIGHLIGHT_GROUPS: dict<string> = {
  file: 'VprojModeFile', buf: 'VprojModeBuf', code: 'VprojModeCode',
  qfix: 'VprojModeQfix',
}
const MATCH_AUTO_ID: number = -1
const MODE_MENU_LINE: number = 1
const FILE_STATUS_SEP_LINE: number = 2
const CODE_STATUS_LINE: number = 2
const CODE_SEP_LINE: number = 3
const FIRST_FILE_ITEM_LINE: number = 3
const FIRST_CODE_ITEM_LINE: number = 4
const QFIX_SEP_LINE: number = 2
const FIRST_QFIX_ITEM_LINE: number = 3
# Nav chars are built dynamically at script load. Parent dir gets '.', then
# lowercase a-z for files. No static gaps — every letter is available.
var NAV_CHARS: list<string> = []
for ch in range(char2nr('a'), char2nr('z'))
  NAV_CHARS->add(nr2char(ch))
endfor
const MIN_WIDTH: number = 20
const MAX_WIDTH: number = 80
# Columns an edit window must keep when vproj opens a split beside it, and
# the width of the preview window.
const MIN_EDIT_WIDTH: number = 20
const PREVIEW_WIDTH: number = 40
# Narrowest preview worth opening; a wider one is used when the room allows.
const MIN_PREVIEW_WIDTH: number = 24
const AUTOGROUP: string = 'VprojPane'
var match_ids: list<number> = []
var cursor_match_id: number = -1
var total_pages: number = 0
var CmdheightNest: number = 0
var CmdheightSaved: number = 0

def LowerCmdheight(): void
  if CmdheightNest == 0
    CmdheightSaved = &cmdheight
    if CmdheightSaved > 2
      set cmdheight=1
    endif
  endif
  CmdheightNest += 1
enddef

def RestoreCmdheight(): void
  if CmdheightNest <= 0
    return
  endif
  CmdheightNest -= 1
  if CmdheightNest == 0
    &cmdheight = CmdheightSaved
  endif
enddef

# True for an absolute path. isabsolutepath() is newer than Vim 8.2.3995, and
# a direct call fails to compile (E117) on a Vim without it, so it is called
# by name when it exists.
def IsAbsPath(path: string): bool
  if exists('*isabsolutepath')
    return !!call('isabsolutepath', [path])
  endif
  if has('win32')
    return path =~ '^\a:[\\/]' || path =~ '^[\\/]'
  endif
  return path =~ '^/'
enddef

def Error(msg: string): void
  echohl ErrorMsg
  echom msg
  echohl None
enddef

# A per-action message ('Moved x -> /dir', 'No git changes for x') that must
# fit the command line: a longer one wraps and raises a hit-enter prompt. A
# too-long text keeps its start and its end, joined by '...', and that
# shortened text is what :messages records too.
def Info(msg: string): void
  var max_w: number = max([&columns - 12, 20])
  var text: string = msg
  if strwidth(text) > max_w
    var head_w: number = (max_w - 3 + 1) / 2
    var tail_w: number = max_w - 3 - head_w
    var head: string = ''
    for ch in split(text, '\zs')
      if strwidth(head .. ch) > head_w
        break
      endif
      head ..= ch
    endfor
    var tail: string = ''
    for ch in reverse(split(text, '\zs'))
      if strwidth(ch .. tail) > tail_w
        break
      endif
      tail = ch .. tail
    endfor
    text = head .. '...' .. tail
  endif
  if text ==# msg || msg !~# '^\(Deleted\|Reverted\|Moved\|Renamed\)\>'
    echom text
    return
  endif
  # A destructive action names what it changed: :messages must keep the FULL
  # text, not the shortened one. `silent echom` records nothing (measured on
  # Vim 9.2), so the full text is echom'd with enough command-line rows to
  # hold it (no hit-enter prompt), then the shortened form is shown on its own.
  var rows: number = (strwidth(msg) + &columns - 1) / &columns
  var saved_rows: number = &cmdheight
  if rows > saved_rows && rows <= &lines / 2
    try
      &cmdheight = rows
      echom msg
    finally
      &cmdheight = saved_rows
    endtry
    redraw
    echo text
  else
    echom text
  endif
enddef

def SortByName(A: dict<any>, B: dict<any>): number
  var a: string = tolower(A.name)
  var b: string = tolower(B.name)
  if a < b
    return -1
  elseif a > b
    return 1
  endif
  return 0
enddef

# Widest the pane may be: leave at least MIN_EDIT_WIDTH columns for editing
# plus the one-column separator between the pane and the edit window.
def SafeMaxWidth(): number
  return max([MIN_WIDTH, &columns - MIN_EDIT_WIDTH - 1])
enddef

# Width from g:{name}, clamped to MIN_WIDTH..MAX_WIDTH. A value that is not a
# Number (e.g. the string '50') falls back to the default with a message,
# instead of throwing E1012 on a typed assignment.
def ConfiguredWidth(name: string, default: number): number
  var raw: any = get(g:, name, default)
  if type(raw) != v:t_number
    Error('vproj: g:' .. name .. ' must be a Number, got ' .. string(raw))
    raw = default
  endif
  return min([MAX_WIDTH, max([MIN_WIDTH, raw])])
enddef

def NavChar(item: dict<any>, visible_idx: number): string
  if get(item, 'is_parent', false)
    return '. '
  endif
  # nav_offset is a block number: block 0 letters items 0-25, block 1
  # letters items 26-51, and so on.
  var nav_idx = visible_idx - nav_offset * len(NAV_CHARS)
  if nav_idx >= 0 && nav_idx < len(NAV_CHARS)
    return NAV_CHARS[nav_idx] .. ' '
  endif
  return '  '
enddef

# ──────────────────────────────────────────────
# Pane lifecycle
# ──────────────────────────────────────────────

export def PaneToggle(): void
  if IsPaneVisible()
    if pane_open_mode == 'permanent'
      # Transition to temporary mode (stays open, will close on ESC or file open)
      pane_open_mode = 'temporary'
      Render()
      silent! doautocmd <nomodeline> User VprojPaneOpenedTemporary
    else
      PaneClose()
    endif
  else
    PaneOpen()
    pane_open_mode = 'temporary'
    silent! doautocmd <nomodeline> User VprojPaneOpenedTemporary
  endif
enddef

export def PaneTogglePermanent(): void
  if IsPaneVisible()
    if pane_open_mode == 'temporary'
      # Transition to permanent mode (stays open, requires explicit close)
      pane_open_mode = 'permanent'
      Render()
      silent! doautocmd <nomodeline> User VprojPaneOpenedPermanent
    else
      PaneClose()
    endif
  else
    PaneOpen()
    pane_open_mode = 'permanent'
    silent! doautocmd <nomodeline> User VprojPaneOpenedPermanent
  endif
enddef

export def PaneOpen(): void
  if IsPaneVisible()
    return
  endif

  # Remember which window the user was in — files will open there
  saved_origin_wid = win_getid()

  if !added_shortmess_s && &shortmess !~# 'S'
    set shortmess+=S
    added_shortmess_s = true
  endif

  pane_width = ConfiguredWidth('vproj_pane_width_default', 40)
  if pane_width > SafeMaxWidth()
    pane_width = SafeMaxWidth()
  endif

  # Reuse existing buffer if it still exists
  DefineHighlights()
  if pane_bufnr > 0 && bufexists(pane_bufnr)
    # Switch to a window without winfixheight/winfixwidth so splits succeed.
    # Plugins like NERDTree/Tagbar set these, which may block splits (E36).
    var found_clear: bool = false
    for wnr in range(1, winnr('$'))
      var wid: number = win_getid(wnr)
      if !getwinvar(wid, '&winfixheight', 0)
          && !getwinvar(wid, '&winfixwidth', 0)
        win_gotoid(wid)
        found_clear = true
        break
      endif
    endfor
    if !found_clear
      # Fall back: find window without winfixheight (needed for :new)
      for wnr in range(1, winnr('$'))
        var wid2: number = win_getid(wnr)
        if !getwinvar(wid2, '&winfixheight', 0)
          win_gotoid(wid2)
          found_clear = true
          break
        endif
      endfor
      if !found_clear
        setwinvar(win_getid(), '&winfixheight', 0)
        setwinvar(win_getid(), '&winfixwidth', 0)
      endif
    endif
    var saved_minwidth: number = &winminwidth
    var saved_minheight: number = &winminheight
    LowerCmdheight()
    set winminwidth=1 winminheight=1
    try
      try
        new
        execute 'buffer ' .. pane_bufnr
      catch
        Error('vproj: Cannot open pane (reuse) -- ' .. v:exception .. ' (' .. &columns .. ' cols, ' .. winnr('$') .. ' wins)')
        return
      endtry
      try
        wincmd H
      catch
        try
          wincmd L
        catch
        endtry
      endtry
    finally
      &winminwidth = saved_minwidth
      &winminheight = saved_minheight
      RestoreCmdheight()
    endtry
    setwinvar(win_getid(), '&winfixwidth', 1)
    setwinvar(win_getid(), '&cursorline', 0)
    setwinvar(win_getid(), '&number', 0)
    setwinvar(win_getid(), '&relativenumber', 0)
    setwinvar(win_getid(), '&signcolumn', 'no')
    setwinvar(win_getid(), '&foldenable', 0)
    setwinvar(win_getid(), '&wrap', 0)
    silent! execute 'vert resize ' .. pane_width
    selected_line = FirstSelectableLine()
    SetupPaneMappings()
    SetupAutocommands()
    try
      LoadSession()
    catch
      echom 'vproj: session load error: ' .. v:exception
    endtry
    pane_open_mode = 'temporary'
    try
      Render()
    catch
      echom 'vproj: render error: ' .. v:exception
    endtry

    silent! doautocmd <nomodeline> User VprojPaneReady
    return
  endif

  # Switch to a window without winfixheight/winfixwidth so splits succeed.
  var found_clear: bool = false
  for wnr in range(1, winnr('$'))
    var wid: number = win_getid(wnr)
    if !getwinvar(wid, '&winfixheight', 0)
        && !getwinvar(wid, '&winfixwidth', 0)
      win_gotoid(wid)
      found_clear = true
      break
    endif
  endfor
  if !found_clear
    for wnr in range(1, winnr('$'))
      var wid2: number = win_getid(wnr)
      if !getwinvar(wid2, '&winfixheight', 0)
        win_gotoid(wid2)
        found_clear = true
        break
      endif
    endfor
    if !found_clear
      setwinvar(win_getid(), '&winfixheight', 0)
      setwinvar(win_getid(), '&winfixwidth', 0)
    endif
  endif
  # Open as horizontal split first — always succeeds regardless of
  # winfixwidth, narrow terms, or complex window layouts. Then try to
  # rotate to vertical (left edge preferred, right edge fallback).
  # If rotation fails, the pane stays horizontal at the bottom.
  var saved_minwidth: number = &winminwidth
  var saved_minheight: number = &winminheight
  LowerCmdheight()
  set winminwidth=1 winminheight=1
  try
    try
      new
    catch
      Error('vproj: Cannot open pane (new) -- ' .. v:exception .. ' (' .. &columns .. ' cols, ' .. winnr('$') .. ' wins)')
      if added_shortmess_s
        set shortmess-=S
        added_shortmess_s = false
      endif
      return
    endtry
    try
      wincmd H
    catch
      try
        wincmd L
      catch
        # Both edges blocked by winfixwidth — keep horizontal layout
      endtry
    endtry
  finally
    &winminwidth = saved_minwidth
    &winminheight = saved_minheight
    RestoreCmdheight()
  endtry
  var new_buf: number = bufnr('%')
  var new_wid: number = win_getid()
  pane_bufnr = new_buf

  setbufvar(pane_bufnr, '&buftype', 'nofile')
  setbufvar(pane_bufnr, '&bufhidden', 'wipe')
  setbufvar(pane_bufnr, '&swapfile', 0)
  setbufvar(pane_bufnr, '&buflisted', 0)
  setbufvar(pane_bufnr, '&modifiable', 0)
  setwinvar(new_wid, '&cursorline', 0)
  setwinvar(new_wid, '&number', 0)
  setwinvar(new_wid, '&relativenumber', 0)
  setwinvar(new_wid, '&signcolumn', 'no')
  setwinvar(new_wid, '&winfixwidth', 1)
  setwinvar(new_wid, '&foldenable', 0)
  setwinvar(new_wid, '&wrap', 0)
  setbufvar(pane_bufnr, '&spell', 0)
  setbufvar(pane_bufnr, '&list', 0)

  silent! keepalt file VPROJ

  silent! execute 'vert resize ' .. pane_width

  SetupAutocommands()
  current_dir = getcwd()
  if empty(current_dir)
    current_dir = expand('~')
  endif
  selected_line = FirstSelectableLine()
  try
    LoadSession()
  catch
    echom 'vproj: session load error: ' .. v:exception
  endtry
  pane_open_mode = 'temporary'
  try
    Render()
  catch
    echom 'vproj: render error: ' .. v:exception
  endtry
  SetupPaneMappings()
  silent! doautocmd <nomodeline> User VprojPaneReady
enddef

export def PaneClose(): void
  # An error left by an earlier save (e.g. a :quit close) was already shown
  # then; only a save made by THIS close is re-reported below.
  session_error = ''
  ClosePreview()
  # Wiping the pane buffer runs HandleBufWipeout, which saves the session
  # while state is still valid and then resets it. A second close finds
  # pane_bufnr == -1 and saves nothing, so it cannot clobber the session.
  var did_enew: bool = false
  if pane_bufnr > 0 && bufexists(pane_bufnr)
    # The pane buffer may also be shown in other tab pages; close those
    # windows too, or they linger with dead mappings.
    for wid in win_findbuf(pane_bufnr)
      if win_id2tabwin(wid)[0] != tabpagenr()
        try
          win_execute(wid, 'close')
        catch
          # Last window of the last tab — leave it; the wipe below handles state.
        endtry
      endif
    endfor
    var pane_wid: number = win_getid(bufwinnr(pane_bufnr))
    if pane_wid > 0
      if winnr('$') < 2
        try
          new
        catch
          try
            enew
            # Replaced buffer in last window — skip :close (would E444).
            did_enew = true
          catch
            # Terminal too small for any spare window.
            # Preserve pane state rather than corrupting it.
            return
          endtry
        endtry
      endif
      if !did_enew && win_id2win(pane_wid) > 0
        win_execute(pane_wid, 'close')
      endif
    endif
  endif
  # The close above saved the session inside win_execute(), where a failure's
  # message is lost; say it now.
  if !empty(session_error)
    Error(session_error)
    session_error = ''
  endif
  execute 'augroup ' .. AUTOGROUP .. ' | autocmd! | augroup END'
  HandleBufWipeout()
  silent! doautocmd <nomodeline> User VprojPaneClosed
enddef

export def HandleBufWipeout(): void
  # Reached from PaneClose and from the BufWipeout autocmd (:q in the pane).
  # Save before resetting, and only while a pane actually existed.
  if pane_bufnr > 0
    SaveSession()
  endif
  execute 'augroup ' .. AUTOGROUP .. ' | autocmd! | augroup END'
  ClosePreview()
  ClearPaneHighlights()
  match_ids = []
  cursor_match_id = -1
  pane_bufnr = -1
  pane_open_mode = 'temporary'
  current_mode = 'file'
  selected_line = FirstSelectableLine()
  items = []
  current_dir = ''
  code_root = ''
  project = {}
  show_info_column = true
  nav_offset = 0
  items_per_page = 1
  paging_active = false
  current_page = 0
  total_pages = 0
  filter_pattern = ''
  git_filter_active = false
  tree_view_active = false
  expanded_dirs = {}
  preview_active = false
  preview_bufnr = -1
  InvalidateGitCache()
  if added_shortmess_s
    set shortmess-=S
    added_shortmess_s = false
  endif
  saved_origin_wid = -1
enddef

export def PaneDiagnose(): void
  echom '=== vproj diagnostics ==='
  echom 'Terminal: ' .. &columns .. ' cols x ' .. &lines .. ' lines'
  echom 'Windows: ' .. winnr('$')
  echom 'winminwidth: ' .. &winminwidth .. '  winminheight: ' .. &winminheight
  echom 'winheight: ' .. &winheight .. '  cmdheight: ' .. &cmdheight
  echom 'laststatus: ' .. &laststatus .. '  equalalways: ' .. (&equalalways ? '1' : '0')
  echom 'splitbelow: ' .. (&splitbelow ? '1' : '0') .. '  splitright: ' .. (&splitright ? '1' : '0')
  echom 'pane_bufnr: ' .. pane_bufnr .. ' (exists: ' .. (pane_bufnr > 0 && bufexists(pane_bufnr) ? '1' : '0') .. ')'
  echom 'current_mode: ' .. current_mode
  echom 'added_shortmess_s: ' .. (added_shortmess_s ? '1' : '0')
  echom '&shortmess: ' .. &shortmess
  echom ''

  echom 'Window layout:'
  for info in getwininfo()
    var wnr: number = info.winnr
    var wfw: bool = getwinvar(info.winid, '&winfixwidth', 0)
    var wfh: bool = getwinvar(info.winid, '&winfixheight', 0)
    var bt: string = getbufvar(info.bufnr, '&buftype', '')
    var bn: string = bufname(info.bufnr)
    echom '  win ' .. wnr .. ': wfw=' .. (wfw ? '1' : '0') .. ' wfh=' .. (wfh ? '1' : '0') .. ' bt=' .. bt .. ' buf=' .. bn
  endfor
  echom ''

  # Report preflight state — same logic PaneOpen uses to pick a split-safe window
  var found_clear: bool = false
  var found_no_wfh: bool = false
  for info in getwininfo()
    if !getwinvar(info.winid, '&winfixheight', 0) && !getwinvar(info.winid, '&winfixwidth', 0)
      found_clear = true
      break
    endif
    if !getwinvar(info.winid, '&winfixheight', 0)
      found_no_wfh = true
    endif
  endfor
  echom 'Pane open preflight:'
  echom '  win clear of winfixheight+winfixwidth: ' .. (found_clear ? '1' : '0')
  echom '  fallback (no winfixheight): ' .. (found_no_wfh ? '1' : '0')
  echom ''

  # Lower winminwidth, winminheight, AND cmdheight before testing splits — same as PaneOpen
  var saved_minwidth: number = &winminwidth
  var saved_minheight: number = &winminheight
  LowerCmdheight()
  set winminwidth=1 winminheight=1
  try
    echom 'Testing splits (winmin=1x1, cmdheight=' .. &cmdheight .. '):'

    echom '  :new (horizontal split)...'
    try
      new
      echom '    :new SUCCEEDED (bufnr=' .. bufnr('%') .. ')'

      # Test vertical rotation — same as what PaneOpen does with wincmd H/L
      echom '  wincmd H (rotate to vertical left)...'
      try
        wincmd H
        echom '    wincmd H SUCCEEDED'
        wincmd L
      catch
        echom '    wincmd H FAILED: ' .. v:exception
      endtry

      close
    catch
      echom '    :new FAILED: ' .. v:exception
    endtry

    echom '  :rightbelow vertical new...'
    try
      rightbelow vertical new
      echom '    vertical new SUCCEEDED'
      close
    catch
      echom '    vertical new FAILED: ' .. v:exception
    endtry
  finally
    &winminwidth = saved_minwidth
    &winminheight = saved_minheight
    RestoreCmdheight()
  endtry

  echom '=== end diagnostics ==='
enddef

# scope is the DirChanged pattern ('global', 'tabpage' or 'window'). The autocmds pass
# expand('<amatch>'): v:event is empty inside DirChanged handlers on the Vim
# versions tested (9.2), so the scope cannot be read from it.
export def OnDirChanged(scope: string = 'global'): void
  InvalidateGitCache()
  if !IsPaneVisible() || current_mode == 'code'
    return
  endif
  # Only react to global dir changes, not window-local changes from
  # other windows (which would overwrite current_dir with wrong value).
  if scope == 'window' && bufnr('%') != pane_bufnr
    return
  endif
  var cwd: string = getcwd()
  if cwd != current_dir
    current_dir = cwd
    selected_line = FirstSelectableLine()
    current_page = 0
    nav_offset = 0
    Render()
  endif
enddef

# ──────────────────────────────────────────────
# Navigation
# ──────────────────────────────────────────────

def MoveCursor(lnum: number): void
  var wnr: number = bufwinnr(pane_bufnr)
  if wnr <= 0
    return
  endif
  if lnum < 1 || lnum > line('$', win_getid(wnr))
    return
  endif
  win_execute(win_getid(wnr), 'silent! call cursor(' .. lnum .. ', 1)')
enddef

# The mode menu (line 1) is selectable: Up from the first item lands on it
# and Enter cycles the mode. Separator and page-nav rows are not.
def SkipNonSelectable(line: number): bool
  if current_mode != 'code' && current_mode != 'qfix' && line == FILE_STATUS_SEP_LINE
    return true
  endif
  if current_mode == 'code' && line == CODE_SEP_LINE
    return true
  endif
  if current_mode == 'qfix' && line == QFIX_SEP_LINE
    return true
  endif
  if paging_active
    var info: list<dict<any>> = getbufinfo(pane_bufnr)
    if !empty(info)
      if line == info[0].linecount
        return true
      endif
    endif
  endif
  return false
enddef

def FirstSelectableLine(): number
  if current_mode == 'code'
    return FIRST_CODE_ITEM_LINE
  elseif current_mode == 'qfix'
    return FIRST_QFIX_ITEM_LINE
  else
    return FIRST_FILE_ITEM_LINE
  endif
enddef

def ApplyFilter(all_items: list<dict<any>>): list<dict<any>>
  if empty(filter_pattern)
    return all_items
  endif
  var result: list<dict<any>> = []
  var lower_pat: string = tolower(filter_pattern)
  for item in all_items
    var name: string = tolower(get(item, 'name', ''))
    var text: string = tolower(get(item, 'text', ''))
    if stridx(name, lower_pat) >= 0 || stridx(text, lower_pat) >= 0
      result->add(item)
    endif
  endfor
  return result
enddef

def ItemIndex(): number
  return (selected_line - FirstSelectableLine()) + (current_page * items_per_page)
enddef

def GetSelectedItem(): dict<any>
  var display_items: list<dict<any>> = ApplyFilter(items)
  if git_filter_active && (current_mode == 'file' || current_mode == 'code')
    display_items = ApplyGitFilter(display_items)
  endif
  # The menu (and in code mode the status line) sit above the first item.
  # Without this guard, on page 2+ ItemIndex() lands on an item of the
  # previous page.
  if selected_line < FirstSelectableLine()
    return {}
  endif
  var idx: number = ItemIndex()
  if idx < 0 || idx >= len(display_items)
    return {}
  endif
  return display_items[idx]
enddef

export def SelectNext(): void
  if !IsPaneVisible()
    return
  endif

  var binfos: list<dict<any>> = getbufinfo(pane_bufnr)
  if empty(binfos)
    return
  endif
  var total: number = binfos[0].linecount
  var next_line: number = selected_line + 1

  while next_line <= total && SkipNonSelectable(next_line)
    next_line += 1
  endwhile
  if next_line > total
    next_line = FirstSelectableLine()
  endif

  selected_line = next_line
  MoveCursor(selected_line)
  UpdateCursorHighlight()
  UpdatePreview()
enddef

export def SelectPrev(): void
  if !IsPaneVisible()
    return
  endif

  var binfos: list<dict<any>> = getbufinfo(pane_bufnr)
  if empty(binfos)
    return
  endif
  var total: number = binfos[0].linecount
  var prev_line: number = selected_line - 1

  while prev_line >= 1 && SkipNonSelectable(prev_line)
    prev_line -= 1
  endwhile
  if prev_line < 1
    prev_line = total
    while prev_line >= 1 && SkipNonSelectable(prev_line)
      if prev_line == 1
        break
      endif
      prev_line -= 1
    endwhile
  endif

  selected_line = prev_line
  MoveCursor(selected_line)
  UpdateCursorHighlight()
  UpdatePreview()
enddef

export def SelectFirst(): void
  if !IsPaneVisible()
    return
  endif
  selected_line = FirstSelectableLine()
  while SkipNonSelectable(selected_line)
    selected_line += 1
  endwhile
  MoveCursor(selected_line)
  UpdateCursorHighlight()
  UpdatePreview()
enddef

export def SelectLast(): void
  if !IsPaneVisible()
    return
  endif
  var binfos: list<dict<any>> = getbufinfo(pane_bufnr)
  if empty(binfos)
    return
  endif
  var total: number = binfos[0].linecount
  if total < 1
    return
  endif
  selected_line = total
  while selected_line >= 1 && SkipNonSelectable(selected_line)
    if selected_line == 1
      break
    endif
    selected_line -= 1
  endwhile
  MoveCursor(selected_line)
  UpdateCursorHighlight()
  UpdatePreview()
enddef

export def NavigateIntoFirstDir(): void
  if !IsPaneVisible()
    return
  endif
  # Only a directory the pane is showing: with a filter active, the first
  # directory in `items` can be one the user cannot see.
  var shown: list<dict<any>> = ApplyFilter(items)
  if git_filter_active && (current_mode == 'file' || current_mode == 'code')
    shown = ApplyGitFilter(shown)
  endif
  for item in shown
    if get(item, 'is_dir', false) && !get(item, 'is_parent', false)
      NavigateInto(get(item, 'name', ''))
      return
    endif
  endfor
enddef

export def GetNavOffset(): number
  return nav_offset
enddef

# Dispatcher — all nav char keystrokes route through here so mode-specific
# behaviour lives in one place instead of being scattered across handler functions.
# Mappings are buffer-local and static (never remapped on mode switch), so mode
# changes are instantaneous regardless of how many mappings exist.
export def VprojKey(key: string): void
  # AI prompt — mode-independent, always available
  if key == 'A'
    vproj#ai#AiTerminalChat()
    return
  endif

  if current_mode == 'file'
    FileModeKey(key)
  elseif current_mode == 'buf'
    BufModeKey(key)
  elseif current_mode == 'code'
    CodeModeKey(key)
  elseif current_mode == 'qfix'
    QfixModeKey(key)
  else
    Error('vproj: unknown mode "' .. current_mode .. '" -- key ignored')
  endif
enddef

def FileModeKey(key: string): void
  SelectByNavChar(key)
enddef

def BufModeKey(key: string): void
  # Nav chars move cursor to corresponding entry without opening files
  SelectByNavChar(key)
enddef

def CodeModeKey(key: string): void
  SelectByNavChar(key)
enddef

def QfixModeKey(key: string): void
  # Nav chars move cursor to corresponding entry without opening files
  SelectByNavChar(key)
enddef

export def SelectByNavChar(ch: string): void
  if !IsPaneVisible()
    return
  endif
  # '.' is the nav key for parent — navigate up
  if ch == '.'
    if current_mode == 'file' || current_mode == 'code'
      NavigateUp()
    endif
    return
  endif
  var display_items = empty(filter_pattern) ? items : ApplyFilter(items)
  if git_filter_active && (current_mode == 'file' || current_mode == 'code')
    display_items = ApplyGitFilter(display_items)
  endif
  var paginated = PageSlice(display_items)
  var visible_idx = 0
  var line_offset = 0
  for item in paginated
    if !get(item, 'is_parent', false)
      var nc = NavChar(item, visible_idx)
      if nc[0] == ch
        selected_line = FirstSelectableLine() + line_offset
        MoveCursor(selected_line)
        UpdateCursorHighlight()
        UpdatePreview()
        # In buf and qfix modes, nav chars only move cursor — don't open files
        if current_mode == 'buf' || current_mode == 'qfix'
          return
        endif
        var pane_wid: number = win_getid()
        var is_dir: bool = get(item, 'is_dir', false)
        if is_dir
          if tree_view_active
            var item_path: string = get(item, 'path', '')
            if !empty(item_path)
              if has_key(expanded_dirs, item_path)
                remove(expanded_dirs, item_path)
              else
                expanded_dirs[item_path] = 1
              endif
            endif
            Render()
          else
            NavigateInto(get(item, 'name', ''))
          endif
          # Directory navigation via nav key: keep pane open in temp mode too
          return
        endif
        # File — open it. Keep the pane when nothing opened (cancelled
        # save prompt, binary or unreadable file).
        if !OpenFile(get(item, 'path', ''))
          return
        endif
        FinishOpen(pane_wid)
        return
      endif
      visible_idx += 1
    endif
    line_offset += 1
  endfor
enddef

# Number of letter blocks needed for the items on the current page.
def NavBlockCount(): number
  var display_items = empty(filter_pattern) ? items : ApplyFilter(items)
  if git_filter_active && (current_mode == 'file' || current_mode == 'code')
    display_items = ApplyGitFilter(display_items)
  endif
  return BlocksIn(PageSlice(display_items))
enddef

# Letter blocks needed for the given visible items (parent entry excluded).
def BlocksIn(visible: list<dict<any>>): number
  var n: number = 0
  for item in visible
    if !get(item, 'is_parent', false)
      n += 1
    endif
  endfor
  return n == 0 ? 1 : (n + len(NAV_CHARS) - 1) / len(NAV_CHARS)
enddef

# > moves the letters to the next block of 26 items, wrapping at the end.
export def ShiftNavForward(): void
  if !IsPaneVisible()
    return
  endif
  var blocks: number = NavBlockCount()
  if blocks <= 1
    return
  endif
  nav_offset = (nav_offset + 1) % blocks
  Render()
enddef

# < moves the letters to the previous block, wrapping at the start.
export def ShiftNavBackward(): void
  if !IsPaneVisible()
    return
  endif
  var blocks: number = NavBlockCount()
  if blocks <= 1
    return
  endif
  nav_offset = (nav_offset + blocks - 1) % blocks
  Render()
enddef

# After something opened in the editing window: a temporary pane closes (the
# documented "auto-closes when you open a file"); a permanent pane takes the
# focus back so the user can open more. Shared by the nav letters and Enter.
def FinishOpen(pane_wid: number): void
  if pane_open_mode == 'temporary'
    PaneClose()
  else
    win_gotoid(pane_wid)
  endif
enddef

export def SelectCurrent(): void
  if !IsPaneVisible()
    return
  endif
  var pane_wid: number = win_getid()

  # Mode menu line: cycle through modes
  if selected_line == MODE_MENU_LINE
    var idx = index(MODE_KEYS, current_mode)
    var next_idx = (idx + 1) % len(MODE_KEYS)
    SwitchMode(MODE_KEYS[next_idx])
    return
  endif

  # Code mode: status line triggers rename
  if current_mode == 'code' && selected_line == CODE_STATUS_LINE
    RenameProject()
    return
  endif

  # Item selection — dispatch by mode
  var item: dict<any> = GetSelectedItem()
  if empty(item)
    return
  endif

  if current_mode == 'file'
    if get(item, 'is_parent', false)
      NavigateUp()
    elseif get(item, 'is_dir', false)
      if tree_view_active
        var item_path: string = get(item, 'path', '')
        if !empty(item_path)
          if has_key(expanded_dirs, item_path)
            remove(expanded_dirs, item_path)
          else
            expanded_dirs[item_path] = 1
          endif
        endif
        Render()
      else
        NavigateInto(get(item, 'name', ''))
      endif
    else
      if OpenFile(get(item, 'path', ''))
        FinishOpen(pane_wid)
      endif
    endif
  elseif current_mode == 'buf'
    if has_key(item, 'bufnr') && OpenBuffer(item.bufnr)
      FinishOpen(pane_wid)
    endif
  elseif current_mode == 'code'
    if get(item, 'is_parent', false)
      NavigateUp()
    elseif get(item, 'is_dir', false)
      NavigateInto(get(item, 'name', ''))
    else
      if OpenFile(get(item, 'path', ''))
        FinishOpen(pane_wid)
      endif
    endif
  elseif current_mode == 'qfix'
    if has_key(item, 'filename') && has_key(item, 'lnum') && OpenQfixEntry(item)
      FinishOpen(pane_wid)
    endif
  endif
enddef

# ──────────────────────────────────────────────
# Mode switching
# ──────────────────────────────────────────────

# Load the project for code mode: the .vproj for current_dir, else the one in
# getcwd() (current_dir then follows it). Sets project and code_root; an
# absent .vproj leaves an empty project rooted at current_dir.
def LoadCodeProject(): void
  var vproj_path: string = FindVprojFile(current_dir)
  if empty(vproj_path)
    var cwd: string = getcwd()
    if cwd != current_dir
      vproj_path = FindVprojFile(cwd)
      if !empty(vproj_path)
        current_dir = cwd
      endif
    endif
  endif
  if !empty(vproj_path)
    project = ParseVprojFile(vproj_path)
    code_root = !empty(get(project, 'root', '')) ? get(project, 'root', '') : current_dir
  else
    project = {}
    code_root = current_dir
  endif
enddef

export def SwitchMode(key: string): void
  var mode: string = key == 'git' ? 'code' : key
  if index(MODE_KEYS, mode) < 0
    return
  endif
  if mode != 'file' && mode != 'buf'
    ClosePreview()
  endif
  current_mode = mode
  var cwd: string = getcwd()
  if mode != 'code'
    current_dir = empty(cwd) ? expand('~') : cwd
  endif
  if mode == 'code'
    LoadCodeProject()
  endif
  selected_line = FirstSelectableLine()
  # Apply mode-specific width config if set
  var width_var: string = 'vproj_pane_width_' .. mode
  # 0 (the documented default) means: keep the current width.
  if get(g:, width_var, 0) isnot 0
    pane_width = min([ConfiguredWidth(width_var, pane_width), SafeMaxWidth()])
    ApplyWidth()
  endif
  current_page = 0
  nav_offset = 0
  filter_pattern = ''
  git_filter_active = false
  tree_view_active = false
  expanded_dirs = {}
  if mode != 'code'
    project = {}
    code_root = ''
  endif
  InvalidateGitCache()
  Render()
enddef

# ──────────────────────────────────────────────
# Width
# ──────────────────────────────────────────────

# Every width change goes through here: the pane never gets more than the
# terminal can spare (SafeMaxWidth), and a width the terminal could not give
# is remembered in pane_width_wanted so a later resize can restore it.
def FitPaneWidth(want: number): void
  pane_width = min([want, SafeMaxWidth()])
  pane_width_wanted = pane_width < want ? want : 0
  NoteTermSize()
enddef

# The terminal size the pane width was last fitted to. WinResized fires for
# every window size change, the user's own :vertical resize or mouse drag
# included; HandleResize tells that apart from a terminal resize by whether
# this changed. [0, 0] = not noted yet.
var fitted_term: list<number> = [0, 0]
def NoteTermSize(): void
  fitted_term = [&columns, &lines]
enddef

export def PaneGrow(): void
  if pane_width >= MAX_WIDTH || pane_width >= SafeMaxWidth()
    return
  endif
  FitPaneWidth(pane_width + 1)
  ApplyWidth()
  Render()
enddef

export def PaneShrink(): void
  if pane_width <= MIN_WIDTH
    return
  endif
  FitPaneWidth(pane_width - 1)
  ApplyWidth()
  Render()
enddef

export def SetPaneWidth(w: number): void
  if w < MIN_WIDTH || w > MAX_WIDTH
    return
  endif
  FitPaneWidth(w)
  ApplyWidth()
  Render()
enddef

# The terminal did not change, so a pane width that differs from pane_width
# is the user's doing (:vertical resize, a mouse drag): keep it. A width
# outside MIN_WIDTH..SafeMaxWidth is clamped, and only then is it applied.
def AdoptPaneWindowWidth(): void
  var wnr: number = bufwinnr(pane_bufnr)
  if wnr <= 0
    return
  endif
  var actual: number = winwidth(wnr)
  # A pane that has the whole row to itself (`:only`, `Ctrl-W o`, or every other
  # window closed) got that width from the layout, not from the user: keep the
  # configured width, so it is back at pane_width when an edit window returns.
  if actual >= &columns
    return
  endif
  var kept: number = min([max([actual, MIN_WIDTH]), min([MAX_WIDTH, SafeMaxWidth()])])
  if kept == pane_width && actual == kept
    return
  endif
  pane_width = kept
  pane_width_wanted = 0
  if actual != kept
    ApplyWidth()
  endif
enddef

# VimResized / WinResized: fit the pane to the terminal as it is now, then
# redraw so paging and row widths follow the new size. A pane that is not
# showing has nothing to fit.
var in_resize: bool = false
export def HandleResize(): void
  if in_resize || !IsPaneVisible()
    return
  endif
  in_resize = true
  try
    if fitted_term == [&columns, &lines]
      AdoptPaneWindowWidth()
    else
      FitPaneWidth(pane_width_wanted > 0 ? pane_width_wanted : pane_width)
      ApplyWidth()
    endif
    Render()
  finally
    in_resize = false
  endtry
enddef

# ──────────────────────────────────────────────
# Queries
# ──────────────────────────────────────────────

export def IsPaneVisible(): bool
  if pane_bufnr <= 0 || !bufexists(pane_bufnr)
    return false
  endif
  return bufwinnr(pane_bufnr) > 0
enddef

export def GetPaneWidth(): number
  return pane_width
enddef

export def GetCurrentMode(): string
  return current_mode
enddef

export def GetPaneBufnr(): number
  return pane_bufnr
enddef

export def IsPagingActive(): bool
  return paging_active
enddef

export def GetCurrentPage(): number
  return current_page
enddef

export def GetTotalPages(): number
  return total_pages
enddef

export def IsTreeViewActive(): bool
  return tree_view_active
enddef

export def IsInfoColumnVisible(): bool
  return show_info_column
enddef

export def IsGitFilterActive(): bool
  return git_filter_active
enddef

# ──────────────────────────────────────────────
# Display
# ──────────────────────────────────────────────

def RefreshItems(): void
  if current_mode == 'code'
    items = CodeItems()
  elseif current_mode == 'file'
    items = tree_view_active ? TreeItems(current_dir) : ReadDir(current_dir)
  elseif current_mode == 'buf'
    items = BufferList()
  else
    items = QfixItems()
  endif
enddef

def BuildDisplayLines(visible: list<dict<any>>): list<string>
  var lines: list<string> = []

  lines->add(BuildModeMenu())

  if current_mode == 'code'
    var status: string
    if empty(project) || empty(get(project, 'name', ''))
      status = '* (no project found)'
    else
      status = '* ' .. get(project, 'name', '')
      if !empty(code_root) && code_root != get(project, 'root', '')
        status = status .. '  ' .. code_root
      endif
    endif
    if strwidth(status) < pane_width
      status = status .. repeat(' ', pane_width - strwidth(status))
    endif
    lines->add(status)
    lines->add(repeat('-', pane_width))
    lines->extend(BuildCodeLines(visible))
  else
    lines->add(repeat('-', pane_width))
    if current_mode == 'file'
      lines->extend(tree_view_active ? BuildTreeLines(visible) : BuildFileLines(visible))
    elseif current_mode == 'buf'
      lines->extend(BuildBufLines(visible))
    else
      lines->extend(BuildQfixLines(visible))
    endif
  endif

  if paging_active
    lines->add(BuildPageNavRow())
  endif

  return lines
enddef

def Render(): void
  if !IsPaneVisible()
    return
  endif

  RefreshItems()
  var display_items = empty(filter_pattern) ? items : ApplyFilter(items)
  if git_filter_active && (current_mode == 'file' || current_mode == 'code')
    display_items = ApplyGitFilter(display_items)
  endif
  ComputePaging(display_items)
  var visible = PageSlice(display_items)
  # A directory change, refresh, delete or filter can leave fewer blocks
  # than nav_offset; with one block < and > cannot fix it.
  if nav_offset >= BlocksIn(visible)
    nav_offset = 0
  endif
  var lines: list<string> = BuildDisplayLines(visible)

  setbufvar(pane_bufnr, '&modifiable', 1)
  try
    deletebufline(pane_bufnr, 1, '$')
    setbufline(pane_bufnr, 1, lines)
  finally
    setbufvar(pane_bufnr, '&modifiable', 0)
  endtry
  setbufvar(pane_bufnr, '&modified', 0)

  setbufvar(pane_bufnr, '&statusline', BuildStatusline())

  ClearPaneHighlights()
  ApplyStaticHighlights()

  if selected_line < 1 || selected_line > len(lines) || SkipNonSelectable(selected_line)
    selected_line = FirstSelectableLine()
    while selected_line <= len(lines) && SkipNonSelectable(selected_line)
      selected_line += 1
    endwhile
    if selected_line > len(lines)
      selected_line = len(lines)
      while selected_line > 0 && SkipNonSelectable(selected_line)
        selected_line -= 1
      endwhile
      if selected_line < 1
        selected_line = FirstSelectableLine()
      endif
    endif
  endif
  # After the clamp: the highlight follows the final selected_line.
  UpdateCursorHighlight()
  MoveCursor(selected_line)
  UpdatePreview()
enddef

# Row 1 of the pane: the four mode labels plus the active-state markers
# (' *' filter, ' [G]' git filter). The row is exactly pane_width cells and
# the markers are never the part that is cut: when the full labels and the
# markers do not fit, the labels shrink to '[F] [B] [C] [q]', then to bare
# letters, and only then is the label text cut.
def BuildModeMenu(): string
  var markers: string = ''
  if !empty(filter_pattern)
    markers ..= ' *'
  endif
  if git_filter_active
    markers ..= ' [G]'
  endif
  var avail: number = pane_width - strwidth(markers)
  var parts: list<string> = []
  for key in MODE_KEYS
    parts->add(MODE_LABELS[key])
  endfor
  var base: string = join(parts, '  ')
  if strwidth(base) > avail
    base = join(MODE_KEYS->mapnew((_, k) => '[' .. MODE_LABELS[k][1] .. ']'), ' ')
  endif
  if strwidth(base) > avail
    base = join(MODE_KEYS->mapnew((_, k) => MODE_LABELS[k][1]), ' ')
  endif
  base = TruncateToWidth(base, max([avail, 0]))
  var line: string = base .. markers
  var w: number = strwidth(line)
  if w < pane_width
    line = line .. repeat(' ', pane_width - w)
  endif
  return line
enddef

def CountItems(): dict<number>
  var total: number = 0
  var included: number = 0
  for item in items
    if !get(item, 'is_parent', false)
      total += 1
      if get(item, 'included', false)
        included += 1
      endif
    endif
  endfor
  return {total: total, included: included}
enddef

def BuildStatusline(): string
  # Mode letter
  var mode_letter: string
  if current_mode == 'file'
    mode_letter = 'f'
  elseif current_mode == 'buf'
    mode_letter = 'b'
  elseif current_mode == 'code'
    mode_letter = 'c'
  elseif current_mode == 'qfix'
    mode_letter = 'q'
  else
    mode_letter = '?'
  endif

  var counts = CountItems()
  var count_str: string = current_mode == 'code'
    ? counts.included .. '/' .. counts.total
    : string(counts.total)
  var right: string = mode_letter .. ' ' .. count_str

  # Build left-side sections (composable: each section appears when data is present)
  var parts: list<string> = []

  # 1. Project name (code mode only)
  if current_mode == 'code' && !empty(get(project, 'name', ''))
    add(parts, '[' .. project.name .. ']')
  endif

  # 2. Current path (omitted in buf mode)
  if current_mode != 'buf'
    var root: string = current_mode == 'code' ? code_root : current_dir
    if !empty(root)
      # The useful part of a long directory is its END: keep the tail.
      var full_root: string = fnamemodify(root, ':~')
      var shown_root: string = full_root
      var root_room: number = max([8, pane_width - strwidth(right) - 2])
      var cut: number = 0
      while strwidth(shown_root) > root_room && cut < strchars(full_root) - 1
        cut += 1
        shown_root = '...' .. strcharpart(full_root, cut)
      endwhile
      add(parts, shown_root)
    endif
  endif

  # 3. Git overlay (code mode only)
  if current_mode == 'code'
    var branch: string = GitBranch()
    if !empty(branch)
      var git_part: string = '@' .. branch
      var sm: dict<string> = GitStatusMap()
      var m_count: number = 0
      var q_count: number = 0
      var a_count: number = 0
      for status in sm->values()
        if status == 'M'
          m_count += 1
        elseif status == '?'
          q_count += 1
        elseif status == 'A'
          a_count += 1
        endif
      endfor
      if m_count > 0
        git_part ..= '  ' .. m_count .. 'M'
      endif
      if q_count > 0
        git_part ..= '  ' .. q_count .. '?'
      endif
      if a_count > 0
        git_part ..= '  ' .. a_count .. 'A'
      endif
      add(parts, git_part)
    elseif IsInGitRepo()
      add(parts, 'untracked')
    endif
  endif

  var left: string = join(parts, '  ')
  var result: string

  if empty(left)
    # Right-align mode+count only
    result = repeat(' ', max([0, pane_width - strwidth(right)])) .. right
  else
    var total_w: number = strwidth(left) + strwidth(right)
    if total_w + 2 <= pane_width
      result = left .. repeat(' ', pane_width - total_w) .. right
    else
      result = left .. ' ' .. right
    endif
  endif

  result = TruncateToWidth(result, pane_width)
  var w: number = strwidth(result)
  if w < pane_width
    result = result .. repeat(' ', pane_width - w)
  endif

  return substitute(result, '%', '%%', 'g')
enddef

def ComputePaging(all_items: list<dict<any>>): void
  var wnr: number = bufwinnr(pane_bufnr)
  var win_height: number = wnr > 0 ? winheight(wnr) : 0
  var header_lines: number = current_mode == 'code' ? 3 : 2
  items_per_page = win_height - header_lines
  if items_per_page < 1
    items_per_page = 1
  endif
  if len(all_items) > items_per_page
    items_per_page = win_height - header_lines - 1
    if items_per_page < 1
      items_per_page = 1
    endif
  endif
  paging_active = len(all_items) > items_per_page
  if !paging_active
    current_page = 0
    total_pages = 1
    return
  endif
  total_pages = (len(all_items) + items_per_page - 1) / items_per_page
  if current_page >= total_pages
    current_page = total_pages - 1
  endif
  if current_page < 0
    current_page = 0
  endif
enddef

def PageSlice(all_items: list<dict<any>>): list<dict<any>>
  if !paging_active
    return all_items
  endif
  # slice() excludes its end index; [a : b] would include b and show one
  # item too many per page.
  var start_idx = current_page * items_per_page
  return slice(all_items, start_idx, start_idx + items_per_page)
enddef

# Cut text to at most `cells` display cells. strcharpart() counts characters,
# but CJK and emoji take two cells each, so a character count lets a row
# overflow the pane. A wide character that would straddle the limit is
# dropped whole, so the result can be one cell short; callers pad rows to the
# pane width by strwidth().
def TruncateToWidth(text: string, cells: number): string
  if cells <= 0
    return ''
  endif
  if strwidth(text) <= cells
    return text
  endif
  # Measure the prefix, not each character alone: a combining mark is one
  # cell by itself but zero after its base character. The width of a prefix
  # never shrinks as it grows, so binary-search the longest prefix that fits
  # (O(n log n); a character-by-character scan was quadratic on a long run of
  # zero-width characters). A wide character that would straddle the limit
  # does not fit, so it is dropped whole.
  var lo: number = 0
  var hi: number = strchars(text)
  while lo < hi
    var mid: number = (lo + hi + 1) / 2
    if strwidth(strcharpart(text, 0, mid)) <= cells
      lo = mid
    else
      hi = mid - 1
    endif
  endwhile
  return strcharpart(text, 0, lo)
enddef

# A file name as the pane shows it: control characters (and Tab, which the
# display expands to the next tab stop) become '?' so a row is exactly as
# wide as strwidth() says. For DISPLAY only; opening a file uses the real name.
def DisplayName(name: string): string
  return substitute(name, '[\x00-\x1f\x7f]', '?', 'g')
enddef

def BuildPageNavRow(): string
  var tp: number = total_pages < 1 ? 1 : total_pages
  var text: string = printf(' >>> Page %d/%d  Ctrl-N Ctrl-P <<< ', current_page + 1, tp)
  text = TruncateToWidth(text, pane_width)
  var w: number = strwidth(text)
  if w < pane_width
    text = repeat(' ', (pane_width - w) / 2) .. text
  endif
  if strwidth(text) < pane_width
    text = text .. repeat(' ', pane_width - strwidth(text))
  endif
  return text
enddef

# Git integration helpers

# The directory the pane is showing: the project root in code mode, the
# listed directory otherwise. Git state follows this, not getcwd(): browsing
# into a nested repo does not chdir, and a stash, commit or push must act on
# the repo whose files are on screen. getcwd() is the fallback before the
# pane has a directory.
def GitContextDir(): string
  var dir: string = CurrentRoot()
  return empty(dir) ? getcwd() : dir
enddef

# Drop the cached root and branch when the pane has moved to another directory.
def SyncGitContext(): void
  var ctx: string = GitContextDir()
  if ctx != git_ctx_dir
    InvalidateGitCache()
    git_ctx_dir = ctx
  endif
enddef

# Every git call goes through GitCmd and GitSystem / GitSystemList, so the two
# rules below hold for all of them.
#
# 1. --literal-pathspecs: git reads a path argument as a PATHSPEC. A file named
#   [ab].txt, * or :(top)x would also match other files, and `restore` or
#   `add` would act on them too. With the option every path means itself.
# 2. Environment that points git at another repository (GIT_DIR and the
#   others below) is cleared for the call and always restored. Left set, it
#   makes git report a different repository's state for the files on screen.
const GIT_REDIRECT_ENV: list<string> = [
  'GIT_DIR', 'GIT_WORK_TREE', 'GIT_INDEX_FILE', 'GIT_OBJECT_DIRECTORY',
  'GIT_COMMON_DIR', 'GIT_NAMESPACE']

# check-ignore is the one command that refuses the option ("pathspec magic not
# supported by this command: 'literal'"). It takes plain paths and never
# expands a glob, so it needs no protection.
def GitCmd(root: string, args: string): string
  var literal: string = args =~# '^check-ignore\>' ? '' : '--literal-pathspecs '
  return 'git ' .. literal .. '-C ' .. shellescape(root) .. ' ' .. args
enddef

# Clear the repository-redirecting variables; saved receives every old value
# (v:null for an unset one), filled as it goes so a restore is complete even
# if this stops half way.
def GitEnvIsolate(saved: dict<any>): void
  for name in GIT_REDIRECT_ENV
    saved[name] = getenv(name)
    if saved[name] != v:null
      setenv(name, v:null)
    endif
  endfor
enddef

def GitEnvRestore(saved: dict<any>): void
  for [name, val] in items(saved)
    setenv(name, val)
  endfor
enddef

# Run git in root; the output as one string. v:shell_error is git's status.
def GitSystem(root: string, args: string): string
  var saved: dict<any> = {}
  try
    GitEnvIsolate(saved)
    return system(GitCmd(root, args))
  finally
    GitEnvRestore(saved)
  endtry
  return ''
enddef

# Same, the output as a list of lines.
def GitSystemList(root: string, args: string): list<string>
  var saved: dict<any> = {}
  try
    GitEnvIsolate(saved)
    return systemlist(GitCmd(root, args))
  finally
    GitEnvRestore(saved)
  endtry
  return []
enddef

def GitRoot(): string
  SyncGitContext()
  if git_root_known
    return git_root_cache
  endif
  var root: string = trim(GitSystem(git_ctx_dir, 'rev-parse --show-toplevel 2>/dev/null'))
  git_root_cache = v:shell_error == 0 ? root : ''
  git_root_known = true
  return git_root_cache
enddef

def GitBranch(): string
  SyncGitContext()
  if git_branch_known
    return git_branch_cache
  endif
  var branch: string = trim(GitSystem(git_ctx_dir, 'branch --show-current 2>/dev/null'))
  if v:shell_error != 0
    branch = ''
  elseif empty(branch)
    # A detached HEAD has no branch name; name the commit instead of
    # reporting an empty branch as "not tracked".
    var hash: string = trim(GitSystem(git_ctx_dir, 'rev-parse --short HEAD 2>/dev/null'))
    if v:shell_error == 0 && !empty(hash)
      branch = '(detached ' .. hash .. ')'
    endif
  endif
  git_branch_cache = branch
  git_branch_known = true
  return git_branch_cache
enddef

# Fold a porcelain XY pair into the single display char: M/A/D/R/?/!
def GitDisplayChar(xy: string): string
  var x: string = xy[0]
  var y: string = xy[1]
  if xy == '??'
    return '?'
  elseif x == 'U' || y == 'U' || xy == 'AA' || xy == 'DD'
    return '!'
  elseif x == 'A' || y == 'A'
    return 'A'
  elseif x == 'D' || y == 'D'
    return 'D'
  elseif x == 'R' || x == 'C'
    return 'R'
  elseif x == 'M' || y == 'M' || x == 'T' || y == 'T'
    return 'M'
  endif
  return ' '
enddef

# Parse `git status --porcelain -z` into git_status_xy and git_status_map.
# -z keeps names unquoted, so spaces, quotes and non-ASCII survive. system()
# turns each NUL into SOH (0x01). A rename or copy entry is followed by a
# separate field holding the source path, kept in git_status_orig.
def LoadGitStatus(): void
  git_status_xy = {}
  git_status_map = {}
  git_status_orig = {}
  var root: string = GitRoot()
  if empty(root)
    return
  endif
  var output: string = GitSystem(root, 'status --porcelain -z 2>/dev/null')
  if v:shell_error != 0
    return
  endif
  var fields: list<string> = split(output, "\x01")
  var i: number = 0
  while i < len(fields)
    var field: string = fields[i]
    i += 1
    if strlen(field) < 4
      continue
    endif
    var xy: string = field[0 : 1]
    var full: string = root .. '/' .. substitute(field[3 : ], '/$', '', '')
    # The source path follows when EITHER column is a rename/copy: ' R' and
    # ' C' are an intent-to-add rename, with the same extra field.
    if xy[0] == 'R' || xy[0] == 'C' || xy[1] == 'R' || xy[1] == 'C'
      if i < len(fields)
        git_status_orig[full] = root .. '/' .. fields[i]
      endif
      i += 1
    endif
    git_status_xy[full] = xy
    var ch: string = GitDisplayChar(xy)
    if ch != ' '
      git_status_map[full] = ch
    endif
  endwhile
enddef

def GitStatusMap(): dict<string>
  if empty(git_status_map) && empty(git_status_xy)
    LoadGitStatus()
  endif
  return git_status_map
enddef

# `git status` without -uall reports an untracked directory as one entry
# ('?? dir/'), not its files. A path with no entry of its own is untracked when
# one of its parent directories is. -uall would list every file, but walks the
# whole untracked tree: slow on a large one.
def LookupGitXY(path: string, verify_ignored: bool = false): string
  var xy: string = get(git_status_xy, path, '')
  if !empty(xy)
    return xy
  endif
  var root: string = git_root_cache
  var dir: string = fnamemodify(path, ':h')
  while !empty(root) && stridx(dir, root .. '/') == 0
    # A directory with its own .git is another repository (git reports it as
    # '?? dir/' too). Its files are not untracked files of this repo: their
    # status belongs to that repo, and inheriting '??' here would let \D
    # delete a tracked, modified file. A submodule has a .git file.
    if isdirectory(dir .. '/.git') || filereadable(dir .. '/.git')
      return ''
    endif
    if get(git_status_xy, dir, '') == '??'
      # git status omits ignored files, so a file under an untracked directory
      # may be ignored (build.log under newdir/). Rendering must not fork git
      # per file, so only actions ask (verify_ignored). Exit 0 = ignored; any
      # other code (1 = not ignored, 128 = error) is not proof that the file
      # is ignored, but an error is not proof that it is untracked either:
      # 128 answers '' so that no action offers to delete it.
      if verify_ignored
        GitSystem(root, 'check-ignore -q -- ' .. shellescape(path) .. ' 2>/dev/null')
        if v:shell_error == 0 || v:shell_error > 1
          return ''
        endif
      endif
      return '??'
    endif
    dir = fnamemodify(dir, ':h')
  endwhile
  return ''
enddef

def GitStatusXY(path: string): string
  if empty(git_status_map) && empty(git_status_xy)
    LoadGitStatus()
  endif
  return LookupGitXY(path)
enddef

# Re-read git status from disk and return the XY pair for one path. An action
# chosen from a file's status (stage, unstage, diff, discard) must not trust
# the cache: files change outside Vim, and a stale '??' turns "discard
# changes" into delete(). The cache is refreshed for the whole repo, so the
# pane the action returns to is current too.
def FreshGitStatusXY(path: string): string
  # InvalidateGitCache also forgets the cached root and branch: Render caches
  # "not a repository" so it does not fork git on every redraw, but an action
  # must see a `git init` (or a nested repo) done outside Vim.
  InvalidateGitCache()
  LoadGitStatus()
  return LookupGitXY(path, true)
enddef

# Run a git command in the repo root. Returns {ok, lines}: lines holds the
# output, or git's error text when ok is false. ok_codes lists the exit codes
# that mean success (git diff --no-index exits 1 when the files differ).
def GitLines(args: string, ok_codes: list<number> = [0]): dict<any>
  var root: string = GitRoot()
  var out: list<string> = GitSystemList(root, args .. ' 2>&1')
  return {ok: index(ok_codes, v:shell_error) >= 0, lines: out}
enddef

def IsInGitRepo(): bool
  var root: string = GitRoot()
  if empty(root)
    return false
  endif
  return current_dir == root || stridx(current_dir, root .. '/') == 0
enddef

def InvalidateGitCache(): void
  git_status_map = {}
  git_status_xy = {}
  git_status_orig = {}
  git_branch_cache = ''
  git_root_cache = ''
  git_branch_known = false
  git_root_known = false
enddef

def ApplyGitFilter(all_items: list<dict<any>>): list<dict<any>>
  if empty(all_items)
    return all_items
  endif
  var status_map: dict<string> = GitStatusMap()
  var result: list<dict<any>> = []
  for item in all_items
    # Keep directories and parent navigation so user can navigate into subdirs
    if get(item, 'is_parent', false) || get(item, 'is_dir', false)
      result->add(item)
      continue
    endif
    # Keep items that have git status (a file in an untracked directory
    # has the directory's)
    var ipath: string = get(item, 'path', '')
    if has_key(status_map, ipath) || LookupGitXY(ipath) == '??'
      result->add(item)
    endif
  endfor
  return result
enddef

export def ToggleGitFilter(): void
  if !IsPaneVisible() || (current_mode != 'file' && current_mode != 'code')
    return
  endif
  git_filter_active = !git_filter_active
  if git_filter_active
    current_page = 0
    nav_offset = 0
  endif
  Render()
enddef

export def GitStageToggle(): void
  if !IsPaneVisible() || (current_mode != 'file' && current_mode != 'code')
    return
  endif
  var item: dict<any> = GetSelectedItem()
  if empty(item)
    return
  endif
  var path: string = get(item, 'path', '')
  if empty(path) || get(item, 'is_dir', false)
    return
  endif

  var xy: string = FreshGitStatusXY(path)
  var name: string = get(item, 'name', path)
  if empty(xy)
    Info('vproj: No git changes for ' .. name)
    return
  endif

  # Worktree changes (Y) or untracked: stage them. Otherwise only the
  # index differs (X): unstage. git add -A also stages a worktree deletion.
  var res: dict<any>
  if xy == '??' || xy[1] != ' '
    res = GitLines('add -A -- ' .. shellescape(path))
    if res.ok
      Info('Staged: ' .. name)
    else
      Error('vproj: Failed to stage ' .. name .. ': ' .. join(res.lines, ' '))
    endif
  elseif xy[0] == 'A'
    # A new file: drop it from the index, keep it on disk.
    res = GitLines('rm --cached -q -- ' .. shellescape(path))
    if res.ok
      Info('Unstaged: ' .. name)
    else
      Error('vproj: Failed to unstage ' .. name .. ': ' .. join(res.lines, ' '))
    endif
  else
    res = GitLines('restore --staged -- ' .. shellescape(path))
    if res.ok
      Info('Unstaged: ' .. name)
    else
      Error('vproj: Failed to unstage ' .. name .. ': ' .. join(res.lines, ' '))
    endif
  endif

  InvalidateGitCache()
  Render()
enddef
export def OpenDiffPreview(): void
  if !IsPaneVisible() || (current_mode != 'file' && current_mode != 'code')
    return
  endif
  var item: dict<any> = GetSelectedItem()
  if empty(item)
    return
  endif
  var path: string = get(item, "path", "")
  if empty(path) || get(item, "is_dir", false)
    return
  endif

  # An action decides from live git state, not from a cached "not a repo".
  InvalidateGitCache()
  var root: string = GitRoot()
  if empty(root)
    echom "vproj: Not in a git repository"
    return
  endif

  if !IsRegularFile(path)
    Error("vproj: Cannot diff binary or special file")
    return
  endif

  var xy: string = FreshGitStatusXY(path)
  var name: string = get(item, "name", path)
  var res: dict<any>
  if empty(xy)
    Info("vproj: No git changes for " .. name)
    return
  elseif xy == "??"
    res = GitLines("diff --no-index -- /dev/null " .. shellescape(path), [0, 1])
  elseif xy[0] != " " && xy[1] != " "
    res = GitLines("diff HEAD -- " .. shellescape(path))
  elseif xy[0] != " "
    res = GitLines("diff --cached -- " .. shellescape(path))
  else
    res = GitLines("diff -- " .. shellescape(path))
  endif
  # Output is gathered before any window changes, so a failure leaves the
  # layout untouched.
  if !res.ok
    Error("vproj: Diff failed for " .. name .. ": " .. join(res.lines, " "))
    return
  endif
  if ShowScratchSplit('vproj-diff:' .. name, res.lines, 'diff')
    Info("Diff: " .. name)
  endif
enddef

# Columns each window of wid's row has after a vertical split of wid. With
# 'equalalways' Vim spreads the room over every window of the row that is not
# 'winfixwidth' (so two side-by-side edit windows share it); without, only wid
# is halved. The separator the new window adds is taken off the total.
def SplitShare(wid: number): number
  var wnr: number = win_id2win(wid)
  if wnr <= 0
    return 0
  endif
  if !&equalalways || &eadirection ==# 'ver'
    return (winwidth(wnr) - 1) / 2
  endif
  var row: number = win_screenpos(wnr)[0]
  var count: number = 0
  var total: number = 0
  for k in range(1, winnr('$'))
    if win_screenpos(k)[0] == row && !getwinvar(k, '&winfixwidth', 0)
      count += 1
      total += winwidth(k)
    endif
  endfor
  return (total - 1) / (count + 1)
enddef

# Show lines read-only in a new vertical split beside the edit window;
# q closes it. The user's own windows and buffers are not touched. Returns
# false when no split could be made.
def ShowScratchSplit(name: string, lines: list<string>, ftype: string): bool
  var pane_wid: number = win_getid()
  var target_wid: number = EditTargetWindow()
  if target_wid == 0
    return false
  endif
  # Refuse when the windows left after the split would be narrower than
  # MIN_EDIT_WIDTH, instead of squeezing windows to 1 column.
  if SplitShare(target_wid) < MIN_EDIT_WIDTH
    Error('vproj: terminal too narrow for the ' .. (ftype == 'diff' ? 'diff' : 'blame'))
    return false
  endif
  # The pane must not give up columns to the new split, whatever the
  # user's global 'winfixwidth' is.
  setwinvar(pane_wid, '&winfixwidth', 1)
  win_gotoid(target_wid)
  LowerCmdheight()
  var saved_minwidth: number = &winminwidth
  var saved_minheight: number = &winminheight
  set winminwidth=1 winminheight=1
  try
    rightbelow vnew
  catch
    win_gotoid(pane_wid)
    Error('vproj: Cannot open split -- ' .. v:exception)
    return false
  finally
    RestoreCmdheight()
    &winminwidth = saved_minwidth
    &winminheight = saved_minheight
  endtry
  setlocal buftype=nofile bufhidden=wipe noswapfile nobuflisted nowrap
  # A second diff of the same file while the first is open would fail with
  # E95 (buffer name in use) and leave an unnamed buffer: number the name.
  var buf_name: string = name
  var dup: number = 1
  while bufexists(buf_name)
    dup += 1
    buf_name = name .. ' (' .. dup .. ')'
  endwhile
  execute 'silent! keepalt file ' .. fnameescape(buf_name)
  setline(1, lines)
  if !empty(ftype)
    &l:filetype = ftype
  endif
  setlocal nomodifiable nomodified readonly
  nnoremap <buffer> <silent> q <Cmd>close<CR>
  cursor(1, 1)
  win_gotoid(pane_wid)
  ApplyWidth()
  return true
enddef

export def DiscardChanges(): void
  if !IsPaneVisible() || (current_mode != 'file' && current_mode != 'code')
    return
  endif
  var item: dict<any> = GetSelectedItem()
  if empty(item)
    return
  endif
  var path: string = get(item, "path", "")
  if empty(path) || get(item, "is_dir", false)
    return
  endif

  var xy: string = FreshGitStatusXY(path)
  var name: string = get(item, "name", path)
  if empty(xy)
    Info("vproj: No git changes for " .. name)
    return
  endif

  # An unmerged file: every discard below would drop conflict stages (AA ran
  # `rm --cached` and staged the deletion of a file that exists in HEAD).
  if xy[0] == "U" || xy[1] == "U" || xy == "AA" || xy == "DD"
    Error("vproj: " .. name .. " has a merge conflict -- resolve it first")
    return
  endif

  # Say exactly what will happen; each case does something different.
  # A staged rename: restoring only the new path would delete it and leave
  # the source staged as deleted. Restore both together. A copy's source
  # is untouched by the copy, so only the new path is restored.
  # LoadGitStatus stores the source path when EITHER column is R/C, so the
  # source is read once here and the re-check after the prompt compares the
  # same value. ' R' (`git mv a b; git reset; git add -N b`) is an
  # intent-to-add of the new path: it is handled like ' A' below.
  var src: string = get(git_status_orig, path, '')
  var orig: string = xy[0] == "R" ? src : ''
  var copy_of: string = xy[0] == "C" ? src : ''
  var ita: bool = xy[0] == " " && (xy[1] == "A" || xy[1] == "R" || xy[1] == "C")
  var question: string
  if xy == "??"
    question = "Delete untracked file " .. name .. "?"
  elseif !empty(orig)
    question = "Undo rename " .. fnamemodify(orig, ':t') .. " -> " .. name
      .. " and discard all changes to both?"
  elseif !empty(copy_of)
    question = "Delete " .. name .. " (a staged copy of "
      .. fnamemodify(copy_of, ':t') .. ")?"
  elseif xy[0] == "A"
    question = "Unstage new file " .. name .. "? (the file is kept)"
  elseif ita
    # Intent-to-add (`git add -N`): the content was never in git, so
    # restoring from HEAD would delete the only copy. For ' R' the old path
    # stays as it is (deleted in the worktree, still tracked).
    question = "Remove " .. name .. " from the index? (the file is kept"
      .. (xy[1] == "A" ? ")" : "; the old path is not touched)")
  else
    question = "Discard all changes to " .. name .. " (staged and unstaged)?"
  endif
  echohl WarningMsg
  var answer: string = input(question .. " y/N: ")
  echohl None
  if tolower(answer) != "y"
    echom "Cancelled"
    return
  endif

  # The answer was given against the status shown in the question. If the
  # file changed while the prompt was open, the action it approved is not the
  # action that would run: do nothing and say so.
  var xy_now: string = FreshGitStatusXY(path)
  if xy_now != xy || get(git_status_orig, path, '') != src
    Error("vproj: " .. name .. " changed while asking -- nothing was done")
    Render()
    return
  endif

  var res: dict<any>
  if xy == "??"
    # Last look before delete(): the file must still be untracked and not
    # ignored, whatever the status cache or the directory inheritance said.
    var root_now: string = GitRoot()
    var listed: list<string> = split(GitSystem(root_now,
      'ls-files -z --others --exclude-standard -- ' .. shellescape(path) .. ' 2>/dev/null'), "\x01")
    if v:shell_error != 0 || empty(root_now) || index(listed, strpart(path, strlen(root_now) + 1)) < 0
      Error("vproj: " .. name .. " is not an untracked, unignored file -- nothing was deleted")
      return
    endif
    if delete(path) == 0
      Info("Deleted: " .. name)
    else
      Error("vproj: Failed to delete " .. name)
    endif
  elseif xy[0] == "A" || ita
    # -f: with later edits in the worktree (AM) git refuses a plain
    # `rm --cached`. --cached keeps the file on disk either way.
    res = GitLines("rm --cached -f -q -- " .. shellescape(path))
    if res.ok
      Info("Unstaged: " .. name)
    else
      Error("vproj: Failed to unstage " .. name .. ": " .. join(res.lines, " "))
    endif
  elseif !empty(orig)
    res = GitLines("restore --source=HEAD --staged --worktree -- "
      .. shellescape(orig) .. " " .. shellescape(path))
    if res.ok
      Info("Reverted to HEAD: " .. fnamemodify(orig, ':t') .. " (and removed " .. name .. ")")
    else
      Error("vproj: Failed to revert " .. name .. ": " .. join(res.lines, " "))
    endif
  else
    res = GitLines("restore --source=HEAD --staged --worktree -- " .. shellescape(path))
    if res.ok
      Info("Reverted to HEAD: " .. name)
    else
      Error("vproj: Failed to revert " .. name .. ": " .. join(res.lines, " "))
    endif
  endif

  # Buffers showing the file now differ from disk; let Vim notice.
  silent! checktime
  InvalidateGitCache()
  Render()
enddef

export def GitBlame(): void
  if !IsPaneVisible() || (current_mode != 'file' && current_mode != 'code')
    return
  endif
  var item: dict<any> = GetSelectedItem()
  if empty(item)
    return
  endif
  var path: string = get(item, 'path', '')
  if empty(path) || get(item, 'is_dir', false)
    return
  endif
  if !IsRegularFile(path)
    Error('vproj: Cannot blame binary or special file')
    return
  endif
  var root: string = GitRoot()
  if empty(root)
    echom 'vproj: Not in a git repository'
    return
  endif
  var tracked: dict<any> = GitLines('ls-files -- ' .. shellescape(path))
  if !tracked.ok || empty(tracked.lines)
    echom 'vproj: File is not tracked by git'
    return
  endif
  var name: string = get(item, 'name', path)
  var res: dict<any> = GitLines('annotate -- ' .. shellescape(path))
  if !res.ok
    Error('vproj: Blame failed for ' .. name .. ': ' .. join(res.lines, ' '))
    return
  endif
  if ShowScratchSplit('vproj-blame:' .. name, res.lines, '')
    Info('Blame: ' .. name)
  endif
enddef

export def TogglePreview(): void
  if !IsPaneVisible()
    return
  endif
  if current_mode != 'file' && current_mode != 'buf'
    return
  endif
  if preview_active
    ClosePreview()
  else
    OpenPreview()
  endif
enddef

# Width of the edit window the preview will take its columns from: the
# rightmost window that is not the pane (the preview opens at the far right,
# so that window gives the columns up). With no edit window at all, what the
# pane leaves of the terminal.
def PreviewRoom(pane_wid: number): number
  var room: number = &columns - pane_width - 1
  var best_col: number = -1
  for k in range(1, winnr('$'))
    if win_getid(k) == pane_wid
      continue
    endif
    var col: number = win_screenpos(k)[1]
    if col > best_col
      best_col = col
      room = winwidth(k)
    endif
  endfor
  return room
enddef

def OpenPreview(): void
  # If a preview window already exists, close it first
  if preview_bufnr > 0 && bufexists(preview_bufnr) && bufwinnr(preview_bufnr) > 0
    ClosePreview()
  endif
  var pane_wid: number = win_getid()
  # The preview is up to PREVIEW_WIDTH columns wide, less when the room
  # beside the pane is short: the pane keeps pane_width and the edit window
  # keeps MIN_EDIT_WIDTH. If even MIN_PREVIEW_WIDTH does not fit, open
  # nothing rather than squeeze windows down to 1 column.
  var preview_width: number = min([PREVIEW_WIDTH, PreviewRoom(pane_wid) - MIN_EDIT_WIDTH - 1])
  if preview_width < MIN_PREVIEW_WIDTH
    Error('vproj: terminal too narrow for the preview')
    return
  endif
  setwinvar(pane_wid, '&winfixwidth', 1)
  # Move to a non-pane window if one exists, so botright vnew
  # splits the file area instead of nesting inside the pane.
  for wnr in range(1, winnr('$'))
    var wid: number = win_getid(wnr)
    if wid != pane_wid
      win_gotoid(wid)
      break
    endif
  endfor
  LowerCmdheight()
  var saved_minwidth: number = &winminwidth
  var saved_minheight: number = &winminheight
  set winminwidth=1 winminheight=1
  var before_buf: number = bufnr('%')
  try
    botright vnew
  catch
    win_gotoid(pane_wid)
    Error('vproj: Cannot open preview -- ' .. v:exception)
    return
  finally
    RestoreCmdheight()
    &winminwidth = saved_minwidth
    &winminheight = saved_minheight
  endtry
  preview_bufnr = bufnr('%')
  var preview_wid: number = win_getid()
  setbufvar(preview_bufnr, '&buftype', 'nofile')
  setbufvar(preview_bufnr, '&bufhidden', 'wipe')
  setbufvar(preview_bufnr, '&swapfile', 0)
  setbufvar(preview_bufnr, '&buflisted', 0)
  setbufvar(preview_bufnr, '&modifiable', 0)
  setbufvar(preview_bufnr, '&spell', 0)
  setbufvar(preview_bufnr, '&list', 0)
  setwinvar(preview_wid, '&number', 0)
  setwinvar(preview_wid, '&relativenumber', 0)
  setwinvar(preview_wid, '&signcolumn', 'no')
  setwinvar(preview_wid, '&wrap', 1)
  silent! keepalt file [Preview]
  execute 'silent! vert resize ' .. preview_width
  win_gotoid(pane_wid)
  ApplyWidth()
  # UpdatePreview returns at once unless preview_active is set, so set it
  # first or a freshly opened preview stays blank until the cursor moves.
  preview_active = true
  try
    UpdatePreview()
  catch
    echohl ErrorMsg
    echom 'vproj preview: ' .. v:exception
    echohl None
    preview_active = false
    preview_bufnr = -1
  endtry
enddef

def ClosePreview(): void
  if preview_bufnr > 0 && bufexists(preview_bufnr)
    var wnr: number = bufwinnr(preview_bufnr)
    if wnr > 0
      var orig_wid: number = win_getid()
      win_gotoid(win_getid(wnr))
      if winnr('$') > 1
        silent! close
      else
        # Last window — clear buffer instead of closing
        setbufvar(preview_bufnr, '&modifiable', 1)
        try
          silent! deletebufline(preview_bufnr, 1, '$')
        finally
          setbufvar(preview_bufnr, '&modifiable', 0)
        endtry
      endif
      if win_id2win(orig_wid) > 0
        win_gotoid(orig_wid)
      endif
      # Closing the preview hands its columns to the neighbours; the pane
      # goes back to its configured width.
      ApplyWidth()
    endif
  endif
  preview_active = false
  preview_bufnr = -1
enddef

def UpdatePreview(): void
  if !preview_active || preview_bufnr <= 0 || !bufexists(preview_bufnr)
    if preview_active && preview_bufnr > 0 && !bufexists(preview_bufnr)
      preview_active = false
      preview_bufnr = -1
    endif
    return
  endif
  try
    var item: dict<any> = GetSelectedItem()
    if empty(item)
      ClearPreview()
      return
    endif
    if get(item, 'is_parent', false)
      ClearPreview()
    elseif get(item, 'is_dir', false)
      ShowDirPreview(get(item, 'path', ''), get(item, 'name', ''))
    else
      ShowFilePreview(get(item, 'path', ''))
    endif
  catch
    ClearPreview()
  endtry
enddef

def ClearPreview(): void
  if preview_bufnr > 0 && bufexists(preview_bufnr)
    setbufvar(preview_bufnr, '&modifiable', 1)
    try
      deletebufline(preview_bufnr, 1, '$')
      setbufline(preview_bufnr, 1, '(no preview)')
    finally
      setbufvar(preview_bufnr, '&modifiable', 0)
    endtry
  endif
enddef

def ShowDirPreview(dir_path: string, dir_name: string): void
  if preview_bufnr <= 0 || !bufexists(preview_bufnr)
    return
  endif
  setbufvar(preview_bufnr, '&modifiable', 1)
  try
    deletebufline(preview_bufnr, 1, '$')
    var header: string = '-- ' .. dir_name .. '/ --'
    # deletebufline() of every line leaves one empty line: fill it, then append.
    setbufline(preview_bufnr, 1, header)
    appendbufline(preview_bufnr, 1, '')
    var raw: list<string>
    var unreadable: bool = false
    try
      raw = readdir(dir_path)
    catch
      raw = []
      unreadable = true
    endtry
    var show_dot: bool = get(g:, 'vproj_show_dotfiles', false)
    var dirs: list<string> = []
    var files: list<string> = []
    for entry in raw
      if entry[0] == '.' && !show_dot
        continue
      endif
      var full: string = dir_path .. '/' .. entry
      if isdirectory(full)
        dirs->add(entry .. '/')
      else
        files->add(entry)
      endif
    endfor
    sort(dirs)
    sort(files)
    var entries: list<string> = dirs + files
    var count: number = 0
    for entry in entries
      if count >= 100
        break
      endif
      appendbufline(preview_bufnr, '$', '  ' .. entry)
      count += 1
    endfor
    if unreadable
      appendbufline(preview_bufnr, '$', '(cannot read directory)')
    elseif count == 0
      appendbufline(preview_bufnr, '$', '(empty)')
    elseif len(entries) > 100
      appendbufline(preview_bufnr, '$', '...')
    endif
  finally
    setbufvar(preview_bufnr, '&modifiable', 0)
  endtry
enddef

def ShowFilePreview(file_path: string): void
  if preview_bufnr <= 0 || !bufexists(preview_bufnr)
    return
  endif
  setbufvar(preview_bufnr, '&modifiable', 1)
  try
    deletebufline(preview_bufnr, 1, '$')
    if !filereadable(file_path)
      setbufline(preview_bufnr, 1, '(cannot read)')
      return
    endif
    if !IsRegularFile(file_path)
      setbufline(preview_bufnr, 1, '(special file)')
      return
    endif
    if IsBinary(file_path)
      setbufline(preview_bufnr, 1, '(binary file)')
      return
    endif
    var lines: list<string>
    try
      lines = readfile(file_path, '', 200)
    catch
      setbufline(preview_bufnr, 1, '(cannot read)')
      return
    endtry
    if empty(lines)
      setbufline(preview_bufnr, 1, '(empty file)')
    else
      setbufline(preview_bufnr, 1, lines)
    endif
    # 'filetype' takes letters, digits, '.', '-' and '_' only; a name like
    # "b.x y" would raise E474 after the text is already in the buffer.
    var ext: string = fnamemodify(file_path, ':e')
    if ext =~ '^[[:alnum:]_.-]\+$'
      setbufvar(preview_bufnr, '&filetype', ext)
    endif
    var preview_wins: list<number> = win_findbuf(preview_bufnr)
    if !empty(preview_wins)
      win_execute(preview_wins[0], 'cursor(1, 1)')
    endif
  finally
    setbufvar(preview_bufnr, '&modifiable', 0)
  endtry
enddef

export def GitCommit(): void
  if !IsPaneVisible() || (current_mode != 'file' && current_mode != 'code')
    return
  endif
  # An action decides from live git state, not from a cached "not a repo".
  InvalidateGitCache()
  var root: string = GitRoot()
  if empty(root)
    Error('vproj: Not in a git repository')
    return
  endif
  var msg: string = input('Commit message: ')
  if empty(msg)
    echom 'vproj: Commit cancelled'
    return
  endif
  var output: string = GitSystem(root, 'commit -m ' .. shellescape(msg) .. ' 2>&1')
  if v:shell_error != 0
    Error('vproj: Commit failed -- ' .. substitute(output, '\n', ' ', 'g'))
  else
    var hash: string = GitSystem(root, 'rev-parse --short HEAD 2>/dev/null')
    echom 'vproj: Committed ' .. trim(hash)
  endif
  InvalidateGitCache()
  Render()
enddef

# input() returns '' for both Esc and an empty Enter. inputdialog() returns
# its third argument on Esc (the dict form of input() does not exist in every
# Vim), so a prompt where '' means something can tell the two apart.
#
# The sentinel is built once per session with unpredictable digits: a fixed
# value could be typed (Ctrl-V Ctrl-A vproj-cancel) and would then cancel.
def NewCancelSentinel(): string
  var parts: list<string> = [string(localtime()), string(reltime()[1])]
  if exists('*srand') && exists('*rand')
    # srand() only returns a seed; it leaves the user's own rand() state alone.
    var seed: list<number> = srand()
    parts->add(string(rand(seed)))
  endif
  return "\x01vproj-cancel-" .. join(parts, '-')
enddef

const INPUT_CANCELLED: string = NewCancelSentinel()

def AskOrCancel(prompt: string, text: string = ''): string
  return inputdialog(prompt, text, INPUT_CANCELLED)
enddef

# Run a network git command with terminal prompts disabled: a credential
# prompt would hang Vim, since system() has no terminal to type into.
def GitNoPrompt(args: string): string
  var saved: any = getenv('GIT_TERMINAL_PROMPT')
  var saved_ssh_command: any = getenv('GIT_SSH_COMMAND')
  setenv('GIT_TERMINAL_PROMPT', '0')
  # ssh reads passphrases and host-key confirmations from /dev/tty, which
  # GIT_TERMINAL_PROMPT does not cover. BatchMode makes ssh fail instead of
  # asking. A deliberate user choice (GIT_SSH_COMMAND or GIT_SSH) is left alone.
  # SSH_ASKPASS is not touched: ssh only uses it when it has no tty, and a
  # user's askpass helper is a legitimate non-hanging way to authenticate.
  # The variable outranks git config, so a configured core.sshCommand (-i key,
  # ProxyJump, port) is a user choice too: leave it alone.
  var configured: string = trim(GitSystem(GitRoot(), 'config --get core.sshCommand 2>/dev/null'))
  if saved_ssh_command == v:null && getenv('GIT_SSH') == v:null && empty(configured)
    setenv('GIT_SSH_COMMAND', 'ssh -o BatchMode=yes')
  endif
  try
    return GitSystem(GitRoot(), args .. ' 2>&1')
  finally
    setenv('GIT_TERMINAL_PROMPT', saved)
    setenv('GIT_SSH_COMMAND', saved_ssh_command)
  endtry
  return ''
enddef

export def GitPush(): void
  if !IsPaneVisible() || (current_mode != 'file' && current_mode != 'code')
    return
  endif
  # An action decides from live git state, not from a cached "not a repo".
  InvalidateGitCache()
  var root: string = GitRoot()
  if empty(root)
    Error('vproj: Not in a git repository')
    return
  endif
  var remote: string = GitSystem(root, 'remote 2>/dev/null')
  if empty(trim(remote))
    Error('vproj: No remote configured')
    return
  endif
  var output: string = GitNoPrompt('push')
  if v:shell_error != 0
    Error('vproj: Push failed -- ' .. substitute(output, '[\r\n]\+', ' ', 'g'))
  else
    echom 'vproj: Pushed'
  endif
  InvalidateGitCache()
  Render()
enddef

export def GitPull(): void
  if !IsPaneVisible() || (current_mode != 'file' && current_mode != 'code')
    return
  endif
  # An action decides from live git state, not from a cached "not a repo".
  InvalidateGitCache()
  var root: string = GitRoot()
  if empty(root)
    Error('vproj: Not in a git repository')
    return
  endif
  var remote: string = GitSystem(root, 'remote 2>/dev/null')
  if empty(trim(remote))
    Error('vproj: No remote configured')
    return
  endif
  var output: string = GitNoPrompt('pull --ff-only')
  if v:shell_error != 0
    Error('vproj: Pull failed -- ' .. substitute(output, '[\r\n]\+', ' ', 'g'))
  else
    echom 'vproj: Pulled -- ' .. substitute(trim(output), '[\r\n]\+', ' ', 'g')
  endif
  # Files under open buffers may have changed.
  silent! checktime
  InvalidateGitCache()
  Render()
enddef

export def GitBranchSwitch(): void
  if !IsPaneVisible() || (current_mode != 'file' && current_mode != 'code')
    return
  endif
  # An action decides from live git state, not from a cached "not a repo".
  InvalidateGitCache()
  var root: string = GitRoot()
  if empty(root)
    Error('vproj: Not in a git repository')
    return
  endif
  var branches: string = GitSystem(root, 'branch 2>/dev/null')
  if empty(trim(branches))
    Error('vproj: No branches found')
    return
  endif
  echom 'Branches:'
  for br in branches->split('\n')
    echom '  ' .. br
  endfor
  var target: string = input('Switch to branch: ')
  if empty(target)
    echom 'vproj: Branch switch cancelled'
    return
  endif
  # A leading '-' would be read as an option, not a branch name.
  if target =~ '^-'
    Error('vproj: Invalid branch name: ' .. target)
    return
  endif
  var output: string = GitSystem(root, 'switch ' .. shellescape(target) .. ' 2>&1')
  if v:shell_error != 0
    Error('vproj: Branch switch failed -- ' .. substitute(output, '\n', ' ', 'g'))
  else
    echom 'vproj: Switched to ' .. target
  endif
  # Files under open buffers may have changed.
  silent! checktime
  InvalidateGitCache()
  Render()
enddef

export def GitStashPush(): void
  if !IsPaneVisible() || (current_mode != 'file' && current_mode != 'code')
    return
  endif
  # An action decides from live git state, not from a cached "not a repo".
  InvalidateGitCache()
  var root: string = GitRoot()
  if empty(root)
    Error('vproj: Not in a git repository')
    return
  endif
  var msg: string = AskOrCancel('Stash message (empty for auto): ')
  if msg == INPUT_CANCELLED
    echom 'Cancelled'
    return
  endif
  var stashes_before: string = GitSystem(root, 'stash list 2>/dev/null')
  var cmd: string = 'stash push'
  if !empty(msg)
    cmd ..= ' -m ' .. shellescape(msg)
  endif
  var output: string = GitSystem(root, cmd .. ' 2>&1')
  if v:shell_error != 0
    Error('vproj: Stash failed -- ' .. substitute(output, '\n', ' ', 'g'))
  elseif GitSystem(root, 'stash list 2>/dev/null') ==# stashes_before
    # Exit 0 with "No local changes to save" (only untracked files): nothing
    # was stashed. Compared by the stash list, not by git's translated text.
    echom 'vproj: Nothing to stash (untracked files are not stashed)'
  else
    echom 'vproj: Changes stashed' .. (empty(msg) ? '' : ' -- ' .. msg)
  endif
  # Files under open buffers may have changed.
  silent! checktime
  InvalidateGitCache()
  Render()
enddef

export def GitStashPop(): void
  if !IsPaneVisible() || (current_mode != 'file' && current_mode != 'code')
    return
  endif
  # An action decides from live git state, not from a cached "not a repo".
  InvalidateGitCache()
  var root: string = GitRoot()
  if empty(root)
    Error('vproj: Not in a git repository')
    return
  endif
  var list_output: string = GitSystem(root, 'stash list 2>&1')
  if empty(trim(list_output))
    echom 'vproj: No stashes found'
    return
  endif
  echom 'Stash list:'
  for line in list_output->split('\n')
    echom '  ' .. line
  endfor
  var ref: string = AskOrCancel('Pop which stash? (Enter for top): ')
  if ref == INPUT_CANCELLED
    echom 'Cancelled'
    return
  endif
  if ref =~ '^-'
    Error('vproj: Invalid stash reference: ' .. ref)
    return
  endif
  var cmd: string = 'stash pop'
  if !empty(ref)
    cmd ..= ' ' .. shellescape(ref)
  endif
  var output: string = GitSystem(root, cmd .. ' 2>&1')
  if v:shell_error != 0
    Error('vproj: Stash pop failed -- ' .. substitute(output, '\n', ' ', 'g'))
  else
    echom 'vproj: Stash popped'
  endif
  # Files under open buffers may have changed.
  silent! checktime
  InvalidateGitCache()
  Render()
enddef

def IsRegularFile(path: string): bool
  var ftype: string = getftype(path)
  if ftype == 'file'
    return true
  endif
  if ftype == 'link'
    # A link loop makes resolve() throw E655; such an entry is not a file
    # that can be opened, and one bad entry must not break the listing.
    try
      return getftype(resolve(path)) == 'file'
    catch
      return false
    endtry
  endif
  return false
enddef

def ReadDir(dir: string): list<dict<any>>
  var result: list<dict<any>> = []
  # Normalize: strip trailing slash unless it is the filesystem root
  var norm_dir: string = (dir != '/' && dir =~ '/$') ? dir->substitute('/$', '', '') : dir

  # Parent directory entry (unless at filesystem root)
  if norm_dir != '/' && norm_dir != ''
    result->add({name: '..', path: fnamemodify(norm_dir, ':h'), is_parent: true, is_dir: true, size: 0})
  endif

  var entries: list<string> = []
  try
    entries = readdir(norm_dir)
  catch
    Error('vproj: Cannot read directory: ' .. norm_dir)
    return result
  endtry
  if empty(entries)
    return result
  endif

  var dirs: list<dict<any>> = []
  var files: list<dict<any>> = []

  for entry in entries
    if entry[0] == '.' && !get(g:, 'vproj_show_dotfiles', false)
      continue
    endif
    var full: string = norm_dir .. '/' .. entry
    if isdirectory(full)
      dirs->add({name: entry, path: full, is_dir: true, size: 0})
    elseif IsRegularFile(full)
      files->add({name: entry, path: full, is_dir: false, size: getfsize(full)})
    endif
  endfor

  # Sort each group alphabetically, case-insensitive
  sort(dirs, SortByName)
  sort(files, SortByName)

  result->extend(dirs)
  result->extend(files)
  return result
enddef

def BuildFileLines(file_items: list<dict<any>>): list<string>
  var result: list<string> = []
  var info_width: number = show_info_column ? 5 : 0
  var visible_idx: number = 0
  var prefix_width: number = 2

  for item in file_items
    var name: string = DisplayName(get(item, 'name', ''))
    var is_dir: bool = get(item, 'is_dir', false)
    if is_dir
      name = name .. '/'
    endif

    var info: string = ''
    if show_info_column && !is_dir
      info = FormatSize(get(item, 'size', 0))
      info = repeat(' ', info_width - strwidth(info)) .. info
    endif

    var indicator: string = NavChar(item, visible_idx)
    var name_width: number = pane_width - info_width - prefix_width
    if strwidth(name) > name_width
      name = TruncateToWidth(name, name_width)
    endif
    var line: string = indicator .. name
    var pad: number = pane_width - strwidth(line) - strwidth(info)
    if pad > 0
      line = line .. repeat(' ', pad)
    endif
    line = line .. info
    result->add(line)

    if !get(item, 'is_parent', false)
      visible_idx += 1
    endif
  endfor

  if empty(result)
    result->add('  (empty)')
  endif

  return result
enddef

# ──────────────────────────────────────────────
# Tree view (file mode — T toggles)
# ──────────────────────────────────────────────

def TreeItems(dir: string, depth: number = 0, include_parent: bool = true, visited: dict<number> = {}): list<dict<any>>
  # Vim9Script evaluates default arguments once at compile time, so = {} is shared
  # across calls. At depth=0 (top-level entry), create a fresh dict to avoid the
  # mutable-default gotcha. Recursive calls pass visited explicitly.
  if depth == 0
    return TreeItemsRec(dir, 0, include_parent, {})
  endif
  return TreeItemsRec(dir, depth, include_parent, visited)
enddef

def TreeItemsRec(dir: string, depth: number, include_parent: bool, visited: dict<number>): list<dict<any>>
  var result: list<dict<any>> = []
  var entries: list<dict<any>> = ReadDir(dir)

  if !include_parent
    entries = filter(entries, (_, E) => !get(E, 'is_parent', false))
  endif

  for entry in entries
    entry.depth = depth
    result->add(entry)
    if entry.is_dir && !get(entry, 'is_parent', false)
      if has_key(expanded_dirs, entry.path) && !has_key(visited, entry.path)
        visited[entry.path] = 1
        var children: list<dict<any>> = TreeItemsRec(entry.path, depth + 1, false, visited)
        result->extend(children)
      endif
    endif
  endfor
  return result
enddef

def BuildTreeLines(visible: list<dict<any>>): list<string>
  var result: list<string> = []
  var info_width: number = show_info_column ? 5 : 0
  var prefix_width: number = 2
  var visible_idx: number = 0

  for item in visible
    var name: string = DisplayName(get(item, 'name', ''))
    var depth: number = get(item, 'depth', 0)
    var is_dir: bool = get(item, 'is_dir', false)
    var expand_char: string = ''

    if is_dir
      # The parent row reads '../' like the plain view, but has no +/-.
      name = name .. '/'
      if !get(item, 'is_parent', false)
        expand_char = has_key(expanded_dirs, get(item, 'path', '')) ? '-' : '+'
      endif
    endif

    var indent: string = repeat('  ', depth)
    var indicator: string = NavChar(item, visible_idx)
    if !get(item, 'is_parent', false)
      visible_idx += 1
    endif

    # Format: [nav][indent][expand_char] name
    var line: string = indicator .. indent .. expand_char
    if expand_char != ''
      line = line .. ' '
    endif
    line = line .. name

    var info: string = ''
    if show_info_column && !is_dir
      info = FormatSize(get(item, 'size', 0))
      info = repeat(' ', info_width - strwidth(info)) .. info
    endif

    var name_width: number = pane_width - strwidth(indent) - strwidth(expand_char) - (expand_char != '' ? 1 : 0) - info_width - prefix_width
    if strwidth(name) > name_width
      name = TruncateToWidth(name, name_width)
      # Rebuild line with truncated name
      line = indicator .. indent .. expand_char
      if expand_char != ''
        line = line .. ' '
      endif
      line = line .. name
    endif

    var pad: number = pane_width - strwidth(line) - strwidth(info)
    if pad > 0
      line = line .. repeat(' ', pad)
    endif
    line = line .. info
    result->add(line)
  endfor

  if empty(result)
    result->add('  (empty)')
  endif

  return result
enddef

export def ToggleTreeView(): void
  if current_mode != 'file'
    return
  endif
  tree_view_active = !tree_view_active
  expanded_dirs = {}
  selected_line = FirstSelectableLine()
  current_page = 0
  Render()
enddef

def FormatSize(bytes: number): string
  if bytes < 0
    return '    -'
  elseif bytes < 1024
    return printf('%5d', bytes)
  elseif bytes < 1048576
    return printf('%4dK', bytes / 1024)
  elseif bytes < 1073741824
    return printf('%4dM', bytes / 1048576)
  elseif bytes < 10000 * 1073741824
    return printf('%4dG', bytes / 1073741824)
  elseif bytes < 10000 * 1099511627776
    # From 10000 GiB the G form needs 6 columns; the column is 5 wide.
    return printf('%4dT', bytes / 1099511627776)
  else
    return '>999T'
  endif
enddef

def CurrentRoot(): string
  return (current_mode == 'code') ? code_root : current_dir
enddef

export def NavigateUp(): void
  var root = CurrentRoot()
  if root == '/' || root == ''
    return
  endif
  if current_mode == 'code'
    code_root = fnamemodify(root, ':h')
  else
    current_dir = fnamemodify(root, ':h')
  endif
  selected_line = FirstSelectableLine()
  current_page = 0
  expanded_dirs = {}
  ClosePreview()
  InvalidateGitCache()
  Render()
enddef

def NavigateInto(subdir: string): void
  var root = CurrentRoot()
  # Strip trailing slash unless root is filesystem root
  if root != '/' && root =~ '/$'
    root = root->substitute('/$', '', '')
  endif
  var new_dir: string = root .. '/' .. subdir
  if !isdirectory(new_dir)
    return
  endif
  if current_mode == 'code'
    code_root = new_dir
  else
    current_dir = new_dir
  endif
  selected_line = FirstSelectableLine()
  current_page = 0
  ClosePreview()
  InvalidateGitCache()
  Render()
enddef

# True when wid shows an ordinary file buffer the user edits in: not the
# pane, not the preview, not a terminal, help, quickfix or other special
# buffer. Opening a file in a terminal window would end its job.
def IsEditWindow(wid: number): bool
  if wid <= 0 || win_id2win(wid) <= 0
    return false
  endif
  var bnr: number = winbufnr(wid)
  if bnr == pane_bufnr || bnr == preview_bufnr
    return false
  endif
  return getbufvar(bnr, '&buftype') == ''
enddef

# The window a file or buffer from the pane should open in: the window the
# user came from if it is still an edit window, else the first edit window
# in this tab, else a new vertical split right of the pane (a horizontal
# split would put the file inside the pane's column). Returns 0 on failure.
def EditTargetWindow(): number
  if IsEditWindow(saved_origin_wid)
    return saved_origin_wid
  endif
  for wnr in range(1, winnr('$'))
    if IsEditWindow(win_getid(wnr))
      saved_origin_wid = win_getid(wnr)
      return saved_origin_wid
    endif
  endfor
  var back_wid: number = win_getid()
  LowerCmdheight()
  var saved_minwidth: number = &winminwidth
  var saved_minheight: number = &winminheight
  set winminwidth=1 winminheight=1
  try
    botright vnew
  catch
    win_gotoid(back_wid)
    Error('vproj: Cannot open a window for the file -- ' .. v:exception)
    return 0
  finally
    RestoreCmdheight()
    &winminwidth = saved_minwidth
    &winminheight = saved_minheight
  endtry
  saved_origin_wid = win_getid()
  win_gotoid(back_wid)
  # The new window took half the screen; the pane gets its width back now,
  # not whenever a resize event happens to arrive.
  ApplyWidth()
  return saved_origin_wid
enddef

# Open path in the edit window. Returns true when the file is now shown,
# false when it was refused or the user cancelled.
def OpenFile(path: string): bool
  if !IsRegularFile(path)
    Error('vproj: Cannot open special file: ' .. fnamemodify(path, ':t'))
    return false
  endif
  if !filereadable(path)
    Error('vproj: Cannot read: ' .. path)
    return false
  endif
  # Check for binary (null bytes in first 8KB)
  if IsBinary(path)
    Error('vproj: Binary file: ' .. fnamemodify(path, ':t'))
    return false
  endif
  var pane_wid: number = win_getid()
  var target_wid: number = EditTargetWindow()
  if target_wid == 0
    return false
  endif
  win_gotoid(target_wid)
  # Already showing this file: nothing to do, and :edit! would throw away
  # its unsaved changes.
  if fnamemodify(bufname('%'), ':p') == fnamemodify(path, ':p')
    return true
  endif
  if &modified
    var choice: number = confirm(
      'Save changes to ' .. expand('%:t') .. ' before switching?',
      "&Yes\n&No\n&Cancel"
    )
    # confirm() returns 0 for Esc / Ctrl-C: that is a cancel, not a "No".
    if choice == 0 || choice == 3
      win_gotoid(pane_wid)
      return false
    endif
    if choice == 1
      try
        write
      catch
        Error('vproj: Cannot write ' .. expand('%:t') .. ' -- ' .. v:exception)
        win_gotoid(pane_wid)
        return false
      endtry
    endif
  endif
  var saved_shm: string = &shortmess
  set shortmess+=A
  try
    execute 'edit! ' .. fnameescape(path)
  finally
    &shortmess = saved_shm
  endtry
  return true
enddef

def IsBinary(path: string): bool
  # Resolve symlinks — readblob() on FIFO/socket hangs Vim
  var resolved: string = resolve(path)
  if empty(resolved)
    return false
  endif
  var ftype: string = getftype(resolved)
  if ftype != 'file'
    return false
  endif
  var blob: blob
  try
    blob = readblob(path, 0, 8192)
  catch
    Error('vproj: Cannot read binary check: ' .. path)
    return false
  endtry
  for b in blob
    if b == 0
      return true
    endif
  endfor
  return false
enddef

# ──────────────────────────────────────────────
# Document mode
# ──────────────────────────────────────────────

def BufferList(): list<dict<any>>
  var result: list<dict<any>> = []
  for info in getbufinfo({buflisted: 1})
    if !empty(info.name)
      result->add({
        name: fnamemodify(info.name, ':t'),
        path: info.name,
        bufnr: info.bufnr,
        modified: info.changed > 0,
        current: info.windows->len() > 0,
        linecount: info.linecount,
        loaded: info.loaded != 0,
      })
    endif
  endfor
  return result
enddef

# The line count in its 4-cell column: wider counts are abbreviated so the
# row never outgrows the pane ("12k+" for 10000-99999, ">99k" beyond).
def LineCountCell(n: number): string
  if n <= 9999
    return printf('%4d', n)
  elseif n <= 99999
    return printf('%2dk+', n / 1000)
  endif
  return '>99k'
enddef

def BuildBufLines(buf_items: list<dict<any>>): list<string>
  var result: list<string> = []
  var flag_width: number = show_info_column ? 7 : 0
  var visible_idx: number = 0

  for item in buf_items
    var flags: string = ''
    if show_info_column
      flags = flags .. (item.current ? '%' : ' ')
      flags = flags .. (item.modified ? '+' : ' ')
      # An unloaded buffer (:badd) reports 1 line whatever the file holds.
      flags = flags .. ' ' .. (get(item, 'loaded', true) ? LineCountCell(item.linecount) : '  --')
    endif

    var name: string = DisplayName(item.name)
    var name_width: number = pane_width - flag_width - 2
    if strwidth(name) > name_width
      name = TruncateToWidth(name, name_width)
    endif
    var indicator: string = NavChar(item, visible_idx)
    var line: string = indicator .. name
    var pad: number = pane_width - strwidth(line) - strwidth(flags)
    if pad > 0
      line = line .. repeat(' ', pad)
    endif
    line = line .. flags
    result->add(line)
    visible_idx += 1
  endfor

  if empty(result)
    result->add('  (no open buffers)')
  endif

  return result
enddef

# Returns true when the buffer is now showing in the editing window; focus is
# back in the pane either way.
def OpenBuffer(bufnr: number): bool
  if !bufexists(bufnr)
    return false
  endif
  var pane_wid: number = win_getid()
  var target_wid: number = EditTargetWindow()
  if target_wid == 0
    return false
  endif
  win_gotoid(target_wid)
  try
    execute 'buffer ' .. bufnr
  catch
    # E37: the window's buffer has unsaved changes and 'hidden' is off.
    Error('vproj: Cannot switch buffer -- ' .. v:exception)
    win_gotoid(pane_wid)
    return false
  endtry
  win_gotoid(pane_wid)
  return true
enddef

export def PromptFilter(): void
  if !IsPaneVisible()
    return
  endif
  var pattern: string = AskOrCancel('Filter: ', filter_pattern)
  if pattern == INPUT_CANCELLED
    echom 'Cancelled'
    return
  endif
  filter_pattern = pattern
  selected_line = FirstSelectableLine()
  current_page = 0
  nav_offset = 0
  Render()
enddef

# Turn `git grep -n -z` output into quickfix items: {items, binary}.
# With -z each match is file NUL lnum NUL text NL; system() turns NUL into
# SOH (0x01). Paths are relative to root, so they are made absolute for
# quickfix, which would otherwise resolve them against Vim's cwd.
# One linear pass: the output is split into lines ONCE and every later
# operation touches only its own line. (Measured: a builtin called with the
# whole output as an argument in a loop, matchstrpos() or stridx() with a
# start offset, copies the string each time: 50,000 matches took 50 s.)
# A file name may hold a newline, so a line without `SOH digits SOH` is the
# start or a middle part of a name, kept until the line that completes the
# record. The text may hold SOH: the record is cut at the FIRST `SOH digits
# SOH`, which no file name contains. A line `Binary file x matches` between
# records is counted, not turned into an item.
def ParseGrepOutput(output: string, root: string): dict<any>
  var recs: list<dict<any>> = []
  var binary: number = 0
  var pending: string = ''
  var have_pending: bool = false
  for line in split(output, "\n", 1)
    var m: list<string> = matchlist(line, '^\([^\x01]*\)\%x01\(\d\+\)\%x01\(.*\)$')
    if empty(m)
      if !have_pending && line =~# '^Binary file .* matches$' && stridx(line, "\x01") < 0
        binary += 1
      elseif have_pending
        pending ..= "\n" .. line
      else
        pending = line
        have_pending = true
      endif
      continue
    endif
    var file: string = have_pending ? pending .. "\n" .. m[1] : m[1]
    pending = ''
    have_pending = false
    if empty(file) || str2nr(m[2]) <= 0
      continue
    endif
    recs->add({
      filename: root .. '/' .. file,
      lnum: str2nr(m[2]),
      text: substitute(m[3], '^\s*', '', ''),
    })
  endfor
  return {items: recs, binary: binary}
enddef

export def GrepSearch(): void
  if !IsPaneVisible()
    return
  endif
  var pattern: string = input('Grep: ')
  if empty(pattern)
    return
  endif
  # Inside a repo search the whole worktree: --untracked adds untracked files
  # (still honouring .gitignore) to the tracked ones. Outside one, search the
  # pane's directory with --no-index.
  # An action decides from live git state, not from a cached "not a repo".
  InvalidateGitCache()
  var root: string = GitRoot()
  var scope_flag: string = '--untracked '
  if empty(root)
    root = current_dir
    scope_flag = '--no-index '
  endif
  # stdout and stderr stay apart: a warning on stderr ('error: failed to stat
  # x', exit 0) merged into stdout would be glued onto the next record's file
  # name. stderr goes to a temp file, deleted on every path.
  var errfile: string = tempname()
  var output: string = ''
  var status: number = 0
  var errlines: list<string> = []
  try
    output = GitSystem(root, 'grep ' .. scope_flag .. '-n -i -z -- ' .. shellescape(pattern)
      .. ' 2>' .. shellescape(errfile))
    status = v:shell_error
    if filereadable(errfile)
      errlines = readfile(errfile)
    endif
  finally
    delete(errfile)
  endtry
  # git grep: 0 = matches, 1 = no match, anything else = error.
  if status == 1
    echom 'vproj: no matches for: ' .. pattern
    return
  elseif status != 0
    var why: string = trim(join(errlines, ' '))
    Error('vproj: grep failed: ' .. (empty(why) ? 'exit status ' .. status : why))
    return
  endif
  var parsed: dict<any> = ParseGrepOutput(output, root)
  if empty(parsed.items)
    if parsed.binary > 0
      echom 'vproj: no text matches for: ' .. pattern .. ' (' .. parsed.binary
        .. ' binary files matched and were skipped)'
    else
      echom 'vproj: no matches for: ' .. pattern
    endif
    return
  endif
  setqflist([], ' ', {items: parsed.items, title: 'grep: ' .. pattern})
  SwitchMode('qfix')
enddef

export def Refresh(): void
  if !IsPaneVisible()
    return
  endif
  filter_pattern = ''
  git_filter_active = false
  InvalidateGitCache()
  Render()
enddef

export def ToggleInfoColumn(): void
  show_info_column = !show_info_column
  if IsPaneVisible()
    Render()
  endif
enddef

export def HandleF1(): void
  if IsPaneVisible() && bufnr('%') == pane_bufnr
    ToggleInfoColumn()
  else
    help
  endif
enddef

export def NextPage(): void
  if !IsPaneVisible() || !paging_active
    return
  endif
  if total_pages <= 1
    return
  endif
  current_page = (current_page + 1) % total_pages
  nav_offset = 0
  Render()
enddef

export def PrevPage(): void
  if !IsPaneVisible() || !paging_active
    return
  endif
  if total_pages <= 1
    return
  endif
  current_page = current_page - 1
  if current_page < 0
    current_page = total_pages - 1
  endif
  nav_offset = 0
  Render()
enddef

# Write buffer nr. On failure report it (naming the buffer), keep the buffer,
# close any split opened for the write, and return false.
def SaveBufferQuietly(nr: number): bool
  var cur_wid: number = win_getid()
  var split_wid: number = 0
  var reason: string = ''
  try
    var target_win: number = bufwinnr(nr)
    if target_win > 0
      win_execute(win_getid(target_win), 'write')
    else
      execute 'sbuffer ' .. nr
      split_wid = win_getid()
      write
    endif
  catch
    reason = v:exception
  endtry
  if split_wid > 0 && win_id2win(split_wid) > 0 && winnr('$') > 1
    win_execute(split_wid, 'close')
  endif
  win_gotoid(cur_wid)
  if empty(reason) && !empty(getbufinfo(nr)) && getbufinfo(nr)[0].changed > 0
    reason = 'buffer is still modified after :write'
  endif
  if !empty(reason)
    Error('vproj: Cannot save ' .. bufname(nr) .. ' -- ' .. reason)
    return false
  endif
  return true
enddef

export def CloseBuffer(): void
  if current_mode != 'buf' || !IsPaneVisible()
    echom 'vproj: X closes buffers in buf mode only (press B for buf mode)'
    return
  endif
  var item: dict<any> = GetSelectedItem()
  if empty(item)
    return
  endif
  if has_key(item, 'bufnr')
    var bufnr: number = item.bufnr
    var bufinfo: list<dict<any>> = getbufinfo(bufnr)
    var is_modified: bool = !empty(bufinfo) && bufinfo[0].changed > 0
    if is_modified
      var choice: number = confirm(
        'Save changes to ' .. bufname(bufnr) .. '?',
        "&Yes\n&No\n&Cancel"
      )
      if choice == 1
        if !SaveBufferQuietly(bufnr)
          return
        endif
      elseif choice == 0 || choice == 3
        # 0 is Esc / Ctrl-C: a cancel, not a "No" that discards the edits.
        return
      endif
    endif
    try
      execute 'bdelete! ' .. bufnr
    catch
      Error('vproj: Cannot close buffer -- ' .. v:exception)
      # A partly done :bdelete may have changed the list.
      Render()
      return
    endtry
    # :bdelete unlists the buffer but bufexists() stays true, so redraw
    # unconditionally: the row must go.
    selected_line = FirstSelectableLine()
    current_page = 0
    Render()
  endif
enddef

# ──────────────────────────────────────────────
# File operations (file mode) — :Copy :Delete :Rename :Move, Delete key
# ──────────────────────────────────────────────

# Path of the selected regular file, or '' after telling the user why not.
def SelectedFile(op: string): string
  if !IsPaneVisible()
    Error('vproj: ' .. op .. ' needs the project pane open')
    return ''
  endif
  if current_mode != 'file'
    Error('vproj: ' .. op .. ' works in file mode only (press F for file mode)')
    return ''
  endif
  var item: dict<any> = GetSelectedItem()
  if empty(item) || get(item, 'is_parent', false)
    Error('vproj: ' .. op .. ' -- no file selected')
    return ''
  endif
  if get(item, 'is_dir', false)
    Error('vproj: ' .. op .. ' works on files, not directories')
    return ''
  endif
  var path: string = get(item, 'path', '')
  if empty(path) || !IsRegularFile(path)
    Error('vproj: ' .. op .. ' -- file no longer exists: ' .. path)
    return ''
  endif
  return path
enddef

# Canonical spelling of a file path: the directory part is resolved, so
# a file reached through a symlinked directory matches its buffer opened via
# the real path. The last component is kept, so a symlinked file is still
# told apart from its target.
def CanonicalPath(path: string): string
  var full: string = fnamemodify(path, ':p')
  return resolve(fnamemodify(full, ':h')) .. '/' .. fnamemodify(full, ':t')
enddef

# Buffer number holding this file, or -1. Compares canonical paths instead
# of bufnr(path), because bufnr() treats its argument as a pattern.
def FileBufnr(path: string): number
  var want: string = CanonicalPath(path)
  for info in getbufinfo()
    if !empty(info.name) && CanonicalPath(info.name) == want
      return info.bufnr
    endif
  endfor
  return -1
enddef

# True when a buffer already holds the destination name. Writing the file
# there would split that buffer from its file, and :edit would show it in
# place of the renamed file.
def DestinationHasBuffer(dst: string, op: string): bool
  if FileBufnr(dst) > 0
    Error('vproj: ' .. op .. ' -- a buffer named ' .. fnamemodify(dst, ':t') .. ' is open; close it first')
    return true
  endif
  return false
enddef

# Put the selection on path if it is listed on any page, so the next key
# acts on the file the user just created or renamed.
def SelectPath(path: string): void
  var display_items = empty(filter_pattern) ? items : ApplyFilter(items)
  if git_filter_active && (current_mode == 'file' || current_mode == 'code')
    display_items = ApplyGitFilter(display_items)
  endif
  var want: string = fnamemodify(path, ':p')
  var idx: number = 0
  for item in display_items
    if fnamemodify(get(item, 'path', ''), ':p') == want && !get(item, 'is_parent', false)
      if paging_active && items_per_page > 0
        current_page = idx / items_per_page
        selected_line = FirstSelectableLine() + idx % items_per_page
      else
        selected_line = FirstSelectableLine() + idx
      endif
      Render()
      return
    endif
    idx += 1
  endfor
enddef

# True when the file has unsaved changes in a buffer. Changing the file on
# disk under those changes would split the buffer from the file.
def HasUnsavedBuffer(path: string, op: string): bool
  var bnr: number = FileBufnr(path)
  if bnr > 0 && getbufvar(bnr, '&modified')
    Error('vproj: ' .. op .. ' -- ' .. fnamemodify(path, ':t') .. ' has unsaved changes; write or discard them first')
    return true
  endif
  return false
enddef

# After a rename or move: windows showing the old file now edit the new one,
# and the buffer for the old name is wiped so buf mode lists no stale entry.
def RetargetBuffer(old_path: string, new_path: string): void
  var bnr: number = FileBufnr(old_path)
  if bnr < 0
    return
  endif
  # Keep each window's cursor and scroll position across the :edit. The
  # command string run by win_execute() cannot see this function's locals,
  # so the view travels through a script variable.
  for wid in win_findbuf(bnr)
    win_execute(wid, 'retarget_view = winsaveview()')
    win_execute(wid, 'keepalt edit ' .. fnameescape(new_path))
    win_execute(wid, 'winrestview(retarget_view)')
  endfor
  if bufexists(bnr) && empty(win_findbuf(bnr))
    execute 'bwipeout ' .. bnr
  endif
enddef

def AfterFileOp(): void
  InvalidateGitCache()
  Render()
enddef

export def DeleteSelected(): void
  var path: string = SelectedFile('Delete')
  if empty(path) || HasUnsavedBuffer(path, 'Delete')
    return
  endif
  var name: string = fnamemodify(path, ':t')
  if confirm('Delete "' .. name .. '"?', "&Yes\n&No", 2) != 1
    echom 'Cancelled'
    return
  endif
  if delete(path) != 0
    Error('vproj: Could not delete: ' .. path)
    return
  endif
  # A buffer no window shows would linger in buf mode; a shown one stays
  # so the user still sees the text and can write it back.
  var bnr: number = FileBufnr(path)
  if bnr > 0 && empty(win_findbuf(bnr))
    execute 'bwipeout ' .. bnr
  endif
  Info('Deleted: ' .. name)
  AfterFileOp()
enddef

# Copy src to a dst that does not exist yet. filecopy() is used when this
# Vim has it (not in 9.1.0016, e.g. Ubuntu 24.04); otherwise a binary-safe read/write that
# keeps the source's permissions.
def CopyFileBytes(src: string, dst: string): bool
  # call() by name: a direct filecopy() call fails to compile (E117) on a
  # Vim without it, even behind the exists() check, breaking the function.
  if exists('*filecopy')
    return !!call('filecopy', [src, dst])
  endif
  try
    if writefile(readblob(src), dst, 'b') != 0
      return false
    endif
  catch
    silent! delete(dst)
    return false
  endtry
  setfperm(dst, getfperm(src))
  return true
enddef

export def CopySelected(): void
  var src: string = SelectedFile('Copy')
  if empty(src)
    return
  endif
  var dir: string = fnamemodify(src, ':h')
  var base: string = fnamemodify(src, ':t:r')
  var ext: string = fnamemodify(src, ':e')
  var suffix: string = empty(ext) ? '' : '.' .. ext

  # First unused name: name_1.ext, name_2.ext, ... getftype() is '' only
  # when nothing exists at the path, including a dangling symlink.
  var n: number = 1
  var dst: string = dir .. '/' .. base .. '_' .. n .. suffix
  while getftype(dst) != ''
    n += 1
    dst = dir .. '/' .. base .. '_' .. n .. suffix
  endwhile

  if DestinationHasBuffer(dst, 'Copy')
    return
  endif
  # Copy what a symlink points to; copying the link itself would make the
  # copy share its content with the original.
  if !CopyFileBytes(resolve(src), dst)
    Error('vproj: Copy failed: ' .. src)
    return
  endif
  echom 'Created ' .. fnamemodify(dst, ':t')
  AfterFileOp()
  SelectPath(dst)
enddef

export def RenameSelected(): void
  var src: string = SelectedFile('Rename')
  if empty(src) || HasUnsavedBuffer(src, 'Rename')
    return
  endif
  var old_name: string = fnamemodify(src, ':t')
  var new_name: string = input('Rename to: ', old_name)
  if empty(new_name) || new_name == old_name
    echom 'Cancelled'
    return
  endif
  if new_name =~ '[/\\]'
    Error('vproj: Rename -- name cannot contain path separators (use :Move)')
    return
  endif
  if new_name == '.' || new_name == '..'
    Error('vproj: Rename -- invalid name: ' .. new_name)
    return
  endif
  var dst: string = fnamemodify(src, ':h') .. '/' .. new_name
  # rename() overwrites without warning — refuse instead.
  if getftype(dst) != ''
    Error('vproj: Rename -- already exists: ' .. new_name)
    return
  endif
  if DestinationHasBuffer(dst, 'Rename')
    return
  endif
  if rename(src, dst) != 0
    Error('vproj: Could not rename ' .. old_name .. ' to ' .. new_name)
    return
  endif
  RetargetBuffer(src, dst)
  Info('Renamed ' .. old_name .. ' -> ' .. new_name)
  AfterFileOp()
  SelectPath(dst)
enddef

export def MoveSelected(): void
  var src: string = SelectedFile('Move')
  if empty(src) || HasUnsavedBuffer(src, 'Move')
    return
  endif
  # A symlink with a relative target would dangle in another directory,
  # and a dangling link is not listed, so it could not be moved back. Vim
  # cannot read a link's raw target (and rename() misreports on dangling
  # links), so links are not moved at all. Rename keeps the directory and
  # is safe.
  if getftype(src) == 'link'
    Error('vproj: Move -- ' .. fnamemodify(src, ':t') .. ' is a symbolic link; vproj does not move links (a relative link would break)')
    return
  endif
  var name: string = fnamemodify(src, ':t')
  var answer: string = input('Move ' .. name .. ' to directory: ', fnamemodify(src, ':h') .. '/', 'dir')
  if empty(answer)
    echom 'Cancelled'
    return
  endif
  # A relative answer is relative to the file's own directory (the pane's
  # directory), not Vim's cwd. :p expands a leading ~ and makes the path
  # absolute; drop the trailing slash it leaves on directories.
  var target: string = answer
  if target !~ '^\~' && !IsAbsPath(target)
    target = fnamemodify(src, ':h') .. '/' .. target
  endif
  var dest_dir: string = simplify(fnamemodify(target, ':p'))
  if dest_dir != '/'
    dest_dir = dest_dir->substitute('/\+$', '', '')
  endif
  if !isdirectory(dest_dir)
    Error('vproj: Move -- not a directory: ' .. answer)
    return
  endif
  if resolve(dest_dir) == resolve(fnamemodify(src, ':p:h'))
    Info('vproj: Move -- ' .. name .. ' is already in ' .. dest_dir)
    return
  endif
  var dst: string = (dest_dir == '/' ? '' : dest_dir) .. '/' .. name
  # rename() overwrites without warning — refuse instead.
  if getftype(dst) != ''
    Error('vproj: Move -- already exists: ' .. dst)
    return
  endif
  if DestinationHasBuffer(dst, 'Move')
    return
  endif
  if rename(src, dst) != 0
    Error('vproj: Could not move ' .. name .. ' to ' .. dest_dir)
    return
  endif
  RetargetBuffer(src, dst)
  Info('Moved ' .. name .. ' -> ' .. dest_dir)
  AfterFileOp()
enddef

# ──────────────────────────────────────────────
# .vproj file I/O
# ──────────────────────────────────────────────

def FindVprojFile(dir: string): string
  # findfile() with ';' suffix walks up the directory tree natively
  var exact: string = findfile('.vproj', fnamemodify(dir, ':p') .. ';')
  if !empty(exact) && filereadable(exact)
    return fnamemodify(exact, ':p')
  endif
  # Fall back to wildcard pattern for hand-named .vproj files. :p leaves a
  # trailing slash on directories; strip it, or the result reads dir//x.vproj
  # and no longer compares equal to the same file spelled dir/x.vproj.
  var d: string = fnamemodify(dir, ':p')->substitute('/\+$', '', '')
  while d != '' && d != '/'
    var matches = glob(escape(d, '*?[]{}~\\') .. '/*.vproj', 0, 1)
    for m in matches
      # resolve(): a symlink to a regular file is a project file (the exact
      # `.vproj` name already accepts one); getftype() on the link itself says
      # 'link', which would reject it. Dangling links and devices stay out.
      if m !~ '[~]$' && m !~ '\.bak$' && filereadable(m) && getftype(resolve(m)) == 'file'
        return fnamemodify(m, ':p')
      endif
    endfor
    var parent = fnamemodify(d, ':h')
    if parent == d
      break
    endif
    d = parent
  endwhile
  return ''
enddef

const SECTION_MAP: dict<string> = {
  'project name': 'name',
  'project root': 'root',
  'included directories': 'included_dirs',
  'included files': 'included_files',
  'excluded directories': 'excluded_dirs',
  'excluded files': 'excluded_files',
}

# Resolve a Project Root value. Empty means the .vproj file's directory; a
# relative value is relative to that directory, not to Vim's cwd.
def ResolveProjectRoot(raw: string, vproj_path: string): string
  var base: string = fnamemodify(vproj_path, ':p:h')
  if empty(raw)
    return base
  endif
  var r: string = raw
  if r =~ '^\~'
    r = fnamemodify(r, ':p')
  elseif !IsAbsPath(r)
    r = base .. '/' .. r
  endif
  r = simplify(r)->substitute('/\+$', '', '')
  return empty(r) ? '/' : r
enddef

# Normalise a list entry: trailing slashes carry no meaning ("src/" is "src").
def NormalizeEntry(entry: string): string
  var e: string = entry->substitute('/\+$', '', '')
  return empty(e) ? entry : e
enddef

export def ParseVprojFile(path: string): dict<any>
  # root is the resolved directory used for matching; root_raw is the text
  # from the file, written back unchanged so a root that is missing today
  # (e.g. an unmounted drive) is not erased. comments keeps top-level #
  # lines so a save does not drop them.
  var p: dict<any> = {
    name: '', root: ResolveProjectRoot('', path), root_raw: '', vproj_file: path,
    included_dirs: [], included_files: [],
    excluded_dirs: [], excluded_files: [],
    comments: [],
  }
  if !filereadable(path)
    return p
  endif

  var section: string = ''
  var file_lines: list<string>
  try
    file_lines = readfile(path)
  catch
    Error('vproj: Cannot read project file: ' .. path)
    return p
  endtry

  for line in file_lines
    var t: string = trim(line)
    if empty(t)
      continue
    endif
    # Only treat # as a comment at top level (before any section), not
    # inside list sections where filenames may legitimately start with #
    if (empty(section) || section == 'name' || section == 'root') && t[0] == '#'
      p.comments->add(t)
      continue
    endif

    # Check if line starts with a known section header
    var header_type: string = ''
    var value: string = ''
    for key in keys(SECTION_MAP)
      if tolower(t) =~ '^' .. escape(key, ' ') .. '\s*:'
        header_type = SECTION_MAP[key]
        value = t->substitute('^[^:]*:\s*', '', '')
        break
      endif
    endfor

    if !empty(header_type)
      # Name and root may be inline ("Project Name: x") or on the next line.
      if !empty(value) && (header_type == 'name' || header_type == 'root')
        SetScalar(p, header_type, value, path)
        section = ''
      else
        section = header_type
        # "Excluded Files: *.swp" on the header line is the section's first
        # entry. Dropping it would also erase it from the file on the next
        # write.
        if !empty(value) && header_type != 'name' && header_type != 'root'
          p[section]->add(section =~ '_dirs$' ? NormalizeEntry(value) : value)
        endif
      endif
      continue
    endif

    if section == 'name' || section == 'root'
      SetScalar(p, section, t, path)
      section = ''
    elseif !empty(section)
      p[section]->add(section =~ '_dirs$' ? NormalizeEntry(t) : t)
    endif
  endfor
  return p
enddef

def SetScalar(p: dict<any>, field: string, value: string, path: string): void
  if field == 'name'
    p.name = value
    return
  endif
  p.root_raw = value
  var resolved: string = ResolveProjectRoot(value, path)
  if isdirectory(resolved)
    p.root = resolved
  else
    # Keep root_raw for writing; match against the .vproj directory meanwhile.
    Error('vproj: Project root not found, using the .vproj directory: ' .. resolved)
    p.root = ResolveProjectRoot('', path)
  endif
enddef

# Counter that keeps WriteVprojFile's temp names unique within one process.
var tmp_seq: number = 0

def WriteVprojFile(): bool
  if empty(project) || !has_key(project, 'vproj_file')
    return false
  endif

  var lines: list<string> = copy(get(project, 'comments', []))
  lines->add('Project Name: ' .. project.name)
  lines->add('Project Root: ' .. get(project, 'root_raw', project.root))

  lines->add('Included Directories:')
  for d in project.included_dirs
    lines->add(d)
  endfor

  lines->add('Included Files:')
  for f in project.included_files
    lines->add(f)
  endfor

  lines->add('Excluded Directories:')
  for d in project.excluded_dirs
    lines->add(d)
  endfor

  lines->add('Excluded Files:')
  for f in project.excluded_files
    lines->add(f)
  endfor

  # Atomic write: temp file + rename. Write through a symlink to its target
  # (renaming over the link would replace it with a regular file and strand
  # the real file), and carry the file's permissions across: a private 0600
  # project file must not come back 0644.
  var dest: string = resolve(project.vproj_file)
  # A read-only project file is the user's way of saying "do not change":
  # rename() would replace it and copy its read-only mode.
  if getftype(dest) != '' && filewritable(dest) != 1
    Error('vproj: ' .. dest .. ' is read-only -- not changed')
    return false
  endif
  var perm: string = getfperm(dest)
  # The temp name is unique and never an existing file (a user's own
  # "<name>.vproj.tmp" must survive); it stays in the same directory so the
  # rename is atomic.
  var tmp: string = ''
  for attempt in range(1000)
    tmp_seq += 1
    var cand: string = dest .. '.vproj-tmp.' .. getpid() .. '.' .. tmp_seq
    if getftype(cand) == ''
      tmp = cand
      break
    endif
  endfor
  if empty(tmp)
    Error('vproj: Failed to write ' .. dest .. ' -- no free temporary file name')
    return false
  endif
  # In a :def a failed writefile() throws (E482) instead of returning -1.
  var rc: number = -1
  try
    rc = writefile(lines, tmp)
  catch
    Error('vproj: Failed to write ' .. dest .. ' -- ' .. v:exception)
    silent! delete(tmp)
    return false
  endtry
  if rc != 0
    Error('vproj: Failed to write ' .. dest)
    silent! delete(tmp)
    return false
  endif
  if !empty(perm)
    setfperm(tmp, perm)
  endif
  if rename(tmp, dest) != 0
    Error('vproj: Failed to write project file: ' .. dest)
    silent! delete(tmp)
    return false
  endif
  return true
enddef

# ──────────────────────────────────────────────
# Code mode
# ──────────────────────────────────────────────

def RelPath(full: string): string
  var proot: string = get(project, 'root', '')
  var rel: string = full
  if !empty(proot) && rel->stridx(proot) == 0
      && (rel->len() == proot->len() || rel[proot->len()] == '/')
    rel = rel[proot->len() :]->substitute('^/', '', '')
  endif
  return rel
enddef

# True when entry names rel. An entry with * or ? is a glob, matched
# against the whole relative path and against its last component, so
# "*.swp" matches "a/b/x.swp". [ is literal: "[id].tsx" and "[slug]" are
# real file names (Next.js, SvelteKit), not character classes.
# Entries already reported as bad patterns: one message per entry, not one
# per file and per redraw.
var bad_pattern_reported: dict<bool> = {}

def EntryMatches(entry: string, rel: string): bool
  if rel == entry
    return true
  endif
  if entry =~ '[*?]'
    var tail: string = fnamemodify(rel, ':t')
    try
      var re: string = EntryRegex(entry)
      return rel =~ re || tail =~ re
    catch
      # A pattern Vim rejects is reported once, then compared literally, so
      # one bad entry can never throw out of CodeItems.
      if !has_key(bad_pattern_reported, entry)
        bad_pattern_reported[entry] = true
        Error('vproj: bad .vproj pattern ' .. DisplayName(entry) .. ': ' .. v:exception)
      endif
      return tail == entry
    endtry
  endif
  return false
enddef

# Regex for a list entry: only * and ? are special, every other character is
# itself (glob2regpat would also treat { } , $ ^ and \ specially).
def EntryRegex(entry: string): string
  # \%#=2 forces the NFA engine: the backtracking one (a user's
  # 'regexpengine'=1) takes exponential time on '*a*a*a*a*b' against a long
  # run of 'a'.
  var re: string = '\%#=2\m^'
  for c in split(entry, '\zs')
    if c == '*'
      re ..= '.*'
    elseif c == '?'
      re ..= '.'
    else
      re ..= escape(c, '\\.^$~[]')
    endif
  endfor
  return re .. '$'
enddef

# True when rel is the directory entry or lies under it.
def UnderDirEntry(entry: string, rel: string): bool
  if empty(entry)
    return false
  endif
  var r: string = rel
  while !empty(r) && r != '.'
    if EntryMatches(entry, r)
      return true
    endif
    var parent: string = fnamemodify(r, ':h')
    if parent == r
      break
    endif
    r = parent
  endwhile
  return false
enddef

def IsUnderIncluded(rel: string): bool
  for d in project.included_dirs
    if UnderDirEntry(d, rel)
      return true
    endif
  endfor
  for f in project.included_files
    if EntryMatches(f, rel)
      return true
    endif
  endfor
  return false
enddef

def IsUnderExcluded(rel: string): bool
  for d in project.excluded_dirs
    if UnderDirEntry(d, rel)
      return true
    endif
  endfor
  for f in project.excluded_files
    if EntryMatches(f, rel)
      return true
    endif
  endfor
  return false
enddef

def CodeItems(): list<dict<any>>
  var result: list<dict<any>> = []

  # Parent directory entry (unless at project root or filesystem root)
  if code_root != '/' && code_root != ''
    result->add({
      name: '.. ' .. fnamemodify(code_root, ':t'),
      path: fnamemodify(code_root, ':h'),
      is_parent: true,
      is_dir: true,
      included: false,
    })
  endif

  var entries: list<string> = []
  try
    entries = readdir(code_root)
  catch
    Error('vproj: Cannot read directory: ' .. code_root)
    return result
  endtry
  if empty(entries)
    return result
  endif

  var dirs_included: list<dict<any>> = []
  var files_included: list<dict<any>> = []
  var dirs_other: list<dict<any>> = []
  var files_other: list<dict<any>> = []

  for entry in entries
    if entry[0] == '.' && !get(g:, 'vproj_show_dotfiles', false)
      continue
    endif
    var full: string = code_root .. '/' .. entry
    var is_dir: bool = isdirectory(full)
    if !is_dir && !IsRegularFile(full)
      continue
    endif
    var item: dict<any> = {
      name: entry,
      path: full,
      is_dir: is_dir,
    }
    var rel: string = RelPath(full)
    if !empty(project) && !IsUnderExcluded(rel) && IsUnderIncluded(rel)
      item.included = true
    else
      item.included = false
    endif

    if item.included
      if is_dir
        dirs_included->add(item)
      else
        files_included->add(item)
      endif
    else
      if is_dir
        dirs_other->add(item)
      else
        files_other->add(item)
      endif
    endif
  endfor

  sort(dirs_included, SortByName)
  sort(files_included, SortByName)
  sort(dirs_other, SortByName)
  sort(files_other, SortByName)

  result->extend(dirs_included)
  result->extend(files_included)
  result->extend(dirs_other)
  result->extend(files_other)
  return result
enddef

def BuildCodeLines(code_items: list<dict<any>>): list<string>
  var result: list<string> = []
  var info_width: number = show_info_column ? 5 : 0
  var repo_root: string = GitRoot()
  var check_root: string = current_mode == 'code' ? code_root : current_dir
  var in_git: bool = !empty(repo_root)
        && (check_root == repo_root || stridx(check_root, repo_root .. '/') == 0)
  var status_map: dict<string> = in_git ? GitStatusMap() : {}
  var git_width: number = in_git ? 1 : 0
  var label_width: number = 4 + git_width  # "X", git_char, "+/-", " "
  var visible_idx: number = 0

  for item in code_items
    var is_parent: bool = get(item, 'is_parent', false)
    var is_dir: bool = get(item, 'is_dir', false)
    var indicator: string = NavChar(item, visible_idx)
    var git_char: string = ''
    if in_git && !is_parent && !is_dir
      git_char = get(status_map, get(item, 'path', ''), ' ')
    endif
    var prefix: string
    if is_parent
      prefix = '    ' .. (in_git ? ' ' : '')
    elseif get(item, 'included', false)
      prefix = indicator .. git_char .. '+ '
    else
      prefix = indicator .. git_char .. '- '
    endif

    var name: string = DisplayName(item.name)
    if is_dir && !is_parent
      name = name .. '/'
    endif

    var info: string = ''
    if show_info_column && !is_dir && !is_parent
      var fsize: number = getfsize(item.path)
      info = FormatSize(fsize)
      info = repeat(' ', info_width - strwidth(info)) .. info
    endif

    # Non-included items are wrapped in parentheses AFTER truncation (so the
    # closing paren is not clipped), so reserve their two cells first.
    var name_width: number = pane_width - label_width - strwidth(info)
    if !get(item, 'included', false) && !is_parent
      name_width -= 2
    endif
    if strwidth(name) > name_width
      name = TruncateToWidth(name, name_width)
    endif
    if !get(item, 'included', false) && !is_parent
      name = '(' .. name .. ')'
    endif
    var line: string = prefix .. name
    var pad: number = pane_width - strwidth(line) - strwidth(info)
    if pad > 0
      line = line .. repeat(' ', pad)
    endif
    line = line .. info
    result->add(line)

    if !is_parent
      visible_idx += 1
    endif
  endfor

  if empty(result)
    result->add('  (empty)')
  endif

  return result
enddef

# True when the .vproj format can hold this entry and read it back unchanged:
# * and ? would be globs, the parser trims blanks, control characters and
# U+FEFF do not survive a round trip, and a line that starts like a section
# header would be read as one.
def CanStoreEntry(rel: string): bool
  # U+FEFF (a BOM) is matched as its UTF-8 bytes, not as a character: it is only
  # a character when 'encoding' is utf-8, but the bytes are the same in every
  # encoding, so the check holds under LANG=C too.
  if rel =~ '[*?]' || rel != trim(rel) || rel =~ '[[:cntrl:]]' || rel =~ "\xef\xbb\xbf"
    return false
  endif
  for key in keys(SECTION_MAP)
    if tolower(rel) =~ '^' .. escape(key, ' ') .. '\s*:'
      return false
    endif
  endfor
  return true
enddef

def DoToggleInclude(action: string): void
  if current_mode != 'code' || !IsPaneVisible() || empty(project)
    if empty(project)
      echom 'vproj: No project -- Enter on status line to create one'
    endif
    return
  endif
  var item: dict<any> = GetSelectedItem()
  if empty(item)
    return
  endif
  if get(item, 'is_parent', false)
    return
  endif

  var currently_included = get(item, 'included', false)
  var do_exclude: bool
  if action == 'include'
    if currently_included | return | endif
    do_exclude = false
  elseif action == 'exclude'
    if !currently_included | return | endif
    do_exclude = true
  else
    do_exclude = currently_included
  endif

  var rel = RelPath(item.path)
  if !CanStoreEntry(rel)
    Error('vproj: ' .. rel .. ' cannot be stored in a .vproj file (glob characters, edge blanks, control characters or a header-like name)')
    return
  endif
  var inc = project.included_dirs
  var exc = project.excluded_dirs
  if !get(item, 'is_dir', false)
    inc = project.included_files
    exc = project.excluded_files
  endif

  # Snapshot project lists before mutation for rollback on write failure
  var snap_inc_dirs = copy(project.included_dirs)
  var snap_inc_files = copy(project.included_files)
  var snap_exc_dirs = copy(project.excluded_dirs)
  var snap_exc_files = copy(project.excluded_files)

  if do_exclude
    var i1 = inc->index(rel)
    if i1 >= 0
      inc->remove(i1)
    endif
    if exc->index(rel) < 0
      exc->add(rel)
    endif
  else
    var i2 = exc->index(rel)
    if i2 >= 0
      exc->remove(i2)
    endif
    if inc->index(rel) < 0
      inc->add(rel)
    endif
  endif

  # An Excluded entry that is a pattern or a parent directory still wins;
  # writing .vproj would change nothing the user can see.
  if !do_exclude && IsUnderExcluded(rel)
    project.included_dirs = snap_inc_dirs
    project.included_files = snap_inc_files
    project.excluded_dirs = snap_exc_dirs
    project.excluded_files = snap_exc_files
    Error('vproj: ' .. rel .. ' stays excluded by a pattern or parent directory in Excluded -- remove that entry first')
    return
  endif

  if !WriteVprojFile()
    # Rollback on write failure
    project.included_dirs = snap_inc_dirs
    project.included_files = snap_inc_files
    project.excluded_dirs = snap_exc_dirs
    project.excluded_files = snap_exc_files
    Error('vproj: Failed to save project -- changes reverted')
  endif
  Render()
  # The toggle can re-sort the rows (a directory moves between the included
  # and excluded groups): keep the cursor on the item the user acted on.
  SelectPath(item.path)
enddef

export def ToggleInclude(): void
  DoToggleInclude('toggle')
enddef

export def IncludeItem(): void
  DoToggleInclude('include')
enddef

export def ExcludeItem(): void
  DoToggleInclude('exclude')
enddef

export def RenameProject(): void
  if current_mode != 'code' || !IsPaneVisible()
    return
  endif

  if empty(project)
    var answer = tolower(input('No .vproj found. Create one? (y/N): '))
    if answer != 'y'
      return
    endif
    var default_name = fnamemodify(CurrentRoot(), ':t')
    var new_name = input('Project name: ', default_name)
    if empty(new_name)
      return
    endif
    if new_name =~ '[/\\]'
      echom 'vproj: Project name cannot contain path separators'
      return
    endif
    var target_path: string = CurrentRoot() .. '/' .. new_name .. '.vproj'
    if filereadable(target_path)
      var overwrite: string = tolower(input(target_path .. ' already exists. Overwrite? (y/N): '))
      if overwrite != 'y'
        return
      endif
    endif
    project = {name: new_name, root: CurrentRoot(), root_raw: CurrentRoot(), vproj_file: target_path,
      included_dirs: [], included_files: [], excluded_dirs: [], excluded_files: [], comments: []}
    code_root = CurrentRoot()
    if !WriteVprojFile()
      project = {}
      code_root = CurrentRoot()
      Error('vproj: Failed to create project file')
      return
    endif
    Render()
    return
  endif

  var default_name = project.name
  var new_name = input('Project name: ', default_name)
  if empty(new_name)
    return
  endif
  if new_name =~ '[/\\]'
    echom 'vproj: Project name cannot contain path separators'
    return
  endif

  var old_name = project.name
  var old_file = project.vproj_file
  var new_file: string = fnamemodify(old_file, ':h') .. '/' .. new_name .. '.vproj'
  # Compare resolved full paths: "dir//x.vproj" and "dir/x.vproj" are the
  # same file, and deleting the "old" one would delete the project.
  var same_file: bool = resolve(fnamemodify(old_file, ':p')) == resolve(fnamemodify(new_file, ':p'))
  if !same_file && getftype(new_file) != ''
    var overwrite: string = tolower(input(new_file .. ' already exists. Overwrite? (y/N): '))
    if overwrite != 'y'
      return
    endif
  endif
  project.name = new_name
  project.vproj_file = same_file ? old_file : new_file
  if !WriteVprojFile()
    project.name = old_name
    project.vproj_file = old_file
    Error('vproj: Failed to save renamed project -- name reverted')
    return
  endif
  if !same_file && filereadable(old_file)
    if delete(old_file) != 0
      Error('vproj: Renamed project saved, but old file ' .. old_file .. ' could not be removed')
    endif
  endif
  Render()
enddef

# ──────────────────────────────────────────────
# Qfix mode
# ──────────────────────────────────────────────

def QfixItems(): list<dict<any>>
  var result: list<dict<any>> = []
  var qflist: list<dict<any>> = getqflist()
  for entry in qflist
    if !get(entry, 'valid', true)
      continue
    endif
    var fname: string = get(entry, 'filename', '')
    if empty(fname) && get(entry, 'bufnr', 0) > 0
      fname = bufname(entry.bufnr)
    endif
    if empty(fname)
      if has_key(entry, 'module') && !empty(entry.module)
        fname = entry.module
      else
        fname = '<unknown>'
      endif
    else
      fname = fnamemodify(fname, ':.')
    endif
    # bufnr is the quickfix entry's own buffer; opening by it avoids
    # bufnr(name), which pattern-matches and can pick a different file.
    result->add({
      filename: fname,
      bufnr: get(entry, 'bufnr', 0),
      lnum: get(entry, 'lnum', 0),
      col: get(entry, 'col', 0),
      text: get(entry, 'text', ''),
    })
  endfor
  return result
enddef

def BuildQfixLines(qfix_items: list<dict<any>>): list<string>
  var result: list<string> = []
  var visible_idx: number = 0

  for item in qfix_items
    var indicator: string = NavChar(item, visible_idx)
    var lnum_str: string = string(item.lnum)
    var entry_text: string = DisplayName(item.filename .. ':' .. lnum_str .. '  ' .. item.text)
    var text_width: number = pane_width - 2  # indicator (char+space)
    if strwidth(entry_text) > text_width
      entry_text = TruncateToWidth(entry_text, text_width)
    endif
    var line: string = indicator .. entry_text
    var w: number = strwidth(line)
    if w < pane_width
      line = line .. repeat(' ', pane_width - w)
    endif
    result->add(line)
    visible_idx += 1
  endfor

  if empty(result)
    result->add('  (no quickfix items)')
  endif

  return result
enddef

# Returns true when the entry's buffer is showing in the editing window;
# focus is back in the pane either way.
def OpenQfixEntry(item: dict<any>): bool
  var bnr: number = get(item, 'bufnr', 0)
  if bnr <= 0 || !bufexists(bnr)
    Error('vproj: Cannot open: ' .. get(item, 'filename', ''))
    return false
  endif
  var pane_wid: number = win_getid()
  var target_wid: number = EditTargetWindow()
  if target_wid == 0
    return false
  endif
  win_gotoid(target_wid)
  try
    execute 'buffer ' .. bnr
  catch
    # E37: the window's buffer has unsaved changes and 'hidden' is off.
    Error('vproj: Cannot open ' .. get(item, 'filename', '') .. ' -- ' .. v:exception)
    win_gotoid(pane_wid)
    return false
  endtry
  # Quickfix col is a byte index; cursor() takes bytes, unlike the | motion.
  var lnum: number = get(item, 'lnum', 0)
  if lnum > 0
    cursor(lnum, max([1, get(item, 'col', 0)]))
  endif
  win_gotoid(pane_wid)
  return true
enddef

export def HandleEsc(): void
  if IsPaneVisible() && pane_open_mode == 'temporary'
    PaneClose()
  endif
enddef

export def HandlePaneQ(): void
  if !IsPaneVisible()
    return
  endif
  if pane_open_mode == 'permanent'
    PaneClose()
  else
    SwitchMode('qfix')
  endif
enddef

# q in the help window: close it, then hand focus and width back to the pane.
# A plain :close leaves focus in whichever window Vim picks (the empty edit
# window) and the pane a column short.
export def CloseHelp(): void
  close
  if IsPaneVisible()
    var wnr: number = bufwinnr(pane_bufnr)
    if wnr > 0
      win_gotoid(win_getid(wnr))
      ApplyWidth()
    endif
  endif
enddef

export def ShowHelp(): void
  var lines: list<string> = [
    'vproj -- key reference',
    '======================',
    'Navigation',
    '  <Down>/<Up>   move selection',
    '  Enter         open file/dir',
    '  . / Ctrl-K    parent directory',
    '  Ctrl-J        enter first subdir',
    '  Ctrl-T / B    first / last item',
    '  Ctrl-N / P    next / prev page',
    '  </>           shift nav chars',
    '',
    'Nav Chars  (a-z)',
    '  Jump to item. File/code: opens.',
    '  Buf/qfix: moves cursor only.',
    '',
    'Modes',
    '  Shift-F       file mode',
    '  Shift-B       buf mode',
    '  Shift-C       code mode',
    '  Q (temp)      qfix / (perm) close',
    '',
    'Actions',
    '  Shift-R       refresh',
    '  Shift-X       close buffer (buf)',
    '  Delete        delete file (file)',
    '  Shift-T       toggle tree view',
    '  Shift-P       toggle preview',
    '  +/-           include/exclude (code)',
    '  /             filter by name',
    '  *             grep -> quickfix',
    '  Left/Right    shrink/grow width',
    '  F1            toggle info column',
    '',
    'Git  (\\ prefix)',
    '  \\s\\d\\D\\c\\p\\u\\b\\z\\Z\\a',
    '  Ctrl-G        toggle git filter',
    '',
    'Close',
    '  Esc (temp) / Q (perm) / Tab',
    '',
    'Commands',
    '  :VprojToggle  :VprojOpen',
    '  :VprojClose   :VprojRefresh',
    '  :VprojDiag    :help vproj',
    '  :Copy :Delete :Rename :Move',
    '                selected file (file mode)',
    '',
    'Press q to close this help.',
  ]

  # Already open: go to it rather than stacking a second, broken window.
  for info in getbufinfo()
    if fnamemodify(info.name, ':t') == '[vproj-help]' && !empty(info.windows)
      win_gotoid(info.windows[0])
      return
    endif
  endfor

  var help_wid: number = 0
  var saved_winminwidth: number = &winminwidth
  var saved_winminheight: number = &winminheight
  set winminwidth=1 winminheight=1
  # The pane must not give up columns to the help window, whatever the
  # user's global 'winfixwidth' is.
  if IsPaneVisible() && bufwinnr(pane_bufnr) > 0
    setwinvar(win_getid(bufwinnr(pane_bufnr)), '&winfixwidth', 1)
  endif
  try
    leftabove vertical new
    help_wid = win_getid()
    setlocal bufhidden=wipe buftype=nofile nobuflisted noswapfile
    setlocal nonumber norelativenumber
    # fnameescape: unescaped, [vproj-help] is read as a pattern (E944).
    execute 'silent file ' .. fnameescape('[vproj-help]')
    setlocal modifiable
    setline(1, lines)
    setlocal nomodifiable
    nnoremap <buffer> <silent> q <Cmd>call vproj#CloseHelp()<CR>
    # A negative argument is RELATIVE (it shrinks), so resize only when the
    # absolute width is usable; a narrow terminal keeps the split's own width.
    var help_width: number = min([80, &columns - vproj#GetPaneWidth() - 4])
    if help_width >= 20
      execute 'vert resize ' .. help_width
    endif
    ApplyWidth()
    redraw
  catch
    # Don't leave a half-built empty window behind.
    if help_wid > 0 && win_id2win(help_wid) > 0
      win_execute(help_wid, 'close')
    endif
    Error('vproj: Cannot open help -- ' .. v:exception)
  finally
    &winminwidth = saved_winminwidth
    &winminheight = saved_winminheight
  endtry
enddef

# ──────────────────────────────────────────────
# Pane setup
# ──────────────────────────────────────────────

def SetupPaneMappings(): void
  if !IsPaneVisible()
    return
  endif

  # Navigation
  nnoremap <buffer> <silent> <Down> <Cmd>call vproj#SelectNext()<CR>
  nnoremap <buffer> <silent> <Up> <Cmd>call vproj#SelectPrev()<CR>
  nnoremap <buffer> <silent> <C-T> <Cmd>call vproj#SelectFirst()<CR>
  nnoremap <buffer> <silent> <C-B> <Cmd>call vproj#SelectLast()<CR>
  nnoremap <buffer> <silent> <C-K> <Cmd>call vproj#NavigateUp()<CR>
  nnoremap <buffer> <silent> <C-J> <Cmd>call vproj#NavigateIntoFirstDir()<CR>

  # Width
  nnoremap <buffer> <silent> <Right> <Cmd>call vproj#PaneGrow()<CR>
  nnoremap <buffer> <silent> <Left> <Cmd>call vproj#PaneShrink()<CR>

  # Activate / open
  nnoremap <buffer> <silent> <CR> <Cmd>call vproj#SelectCurrent()<CR>

  # Mode switching via Shift keys
  nnoremap <buffer> <silent> <S-F> <Cmd>call vproj#SwitchMode('file')<CR>
  nnoremap <buffer> <silent> <S-B> <Cmd>call vproj#SwitchMode('buf')<CR>
  nnoremap <buffer> <silent> <S-C> <Cmd>call vproj#SwitchMode('code')<CR>
  # Toggle tree view
  nnoremap <buffer> <silent> <nowait> T <Cmd>call vproj#ToggleTreeView()<CR>

  # Close pane (capital Q — does not conflict with nav keys)
  nnoremap <buffer> <silent> <S-Q> <Cmd>call vproj#HandlePaneQ()<CR>

  # Include / exclude (code mode)
  nnoremap <buffer> <silent> <nowait> + <Cmd>call vproj#IncludeItem()<CR>
  nnoremap <buffer> <silent> <nowait> - <Cmd>call vproj#ExcludeItem()<CR>

  # Refresh (Shift-R so lowercase r stays a nav key)
  nnoremap <buffer> <silent> R <Cmd>call vproj#Refresh()<CR>

  # Preview toggle (Shift-P so lowercase p stays a nav key)
  nnoremap <buffer> <silent> P <Cmd>call vproj#TogglePreview()<CR>

  # Paging
  nnoremap <buffer> <silent> <C-N> <Cmd>call vproj#NextPage()<CR>
  nnoremap <buffer> <silent> <C-P> <Cmd>call vproj#PrevPage()<CR>

  # Close buffer (buf mode — Shift-X so lowercase x stays a nav key)
  nnoremap <buffer> <silent> X <Cmd>call vproj#CloseBuffer()<CR>

  # Delete key: delete the selected file (file mode, confirms first)
  nnoremap <buffer> <silent> <Delete> <Cmd>call vproj#DeleteSelected()<CR>

  # Nav indicator shift
  nnoremap <buffer> <silent> <nowait> > <Cmd>call vproj#ShiftNavForward()<CR>
  nnoremap <buffer> <silent> <nowait> <lt> <Cmd>call vproj#ShiftNavBackward()<CR>

  # Filter
  nnoremap <buffer> <silent> <nowait> ? <Cmd>call vproj#ShowHelp()<CR>
  nnoremap <buffer> <silent> <nowait> / <Cmd>call vproj#PromptFilter()<CR>
  nnoremap <buffer> <silent> <nowait> * <Cmd>call vproj#GrepSearch()<CR>

  # Nav indicator direct selection (alphanumeric chars only)
  for ch in NAV_CHARS
    if ch !~ '^[[:alnum:]]$'
      continue
    endif
    execute 'nnoremap <buffer> <silent> <nowait> ' .. ch .. ' <Cmd>call vproj#VprojKey("' .. ch .. '")<CR>'
  endfor

  # Git: toggle status filter
  nnoremap <buffer> <silent> <C-G> <Cmd>call vproj#ToggleGitFilter()<CR>

  # Git actions use \ prefix
  # All lowercase a-z are reserved for nav chars
  nnoremap <buffer> <silent> \s <Cmd>call vproj#GitStageToggle()<CR>
  nnoremap <buffer> <silent> \d <Cmd>call vproj#OpenDiffPreview()<CR>
  nnoremap <buffer> <silent> \D <Cmd>call vproj#DiscardChanges()<CR>
  nnoremap <buffer> <silent> \c <Cmd>call vproj#GitCommit()<CR>
  nnoremap <buffer> <silent> \p <Cmd>call vproj#GitPush()<CR>
  nnoremap <buffer> <silent> \u <Cmd>call vproj#GitPull()<CR>
  nnoremap <buffer> <silent> \b <Cmd>call vproj#GitBranchSwitch()<CR>
  nnoremap <buffer> <silent> \z <Cmd>call vproj#GitStashPush()<CR>
  nnoremap <buffer> <silent> \Z <Cmd>call vproj#GitStashPop()<CR>
  nnoremap <buffer> <silent> \a <Cmd>call vproj#GitBlame()<CR>

  # AI prompt — same in every mode
  nnoremap <buffer> <silent> <nowait> A <Cmd>call vproj#VprojKey("A")<CR>

  # ESC closes pane in temporary mode
  nnoremap <buffer> <silent> <Esc> <Cmd>call vproj#HandleEsc()<CR>

  # Parent directory shortcut — routes through VprojKey for mode guard
  nnoremap <buffer> <silent> <nowait> . <Cmd>call vproj#VprojKey(".")<CR>
enddef

def SetupAutocommands(): void
  # A fresh pane starts with no remembered over-wide request.
  pane_width_wanted = 0
  execute 'augroup ' .. AUTOGROUP
    autocmd!
    execute 'autocmd BufWipeout <buffer> call vproj#HandleBufWipeout()'
    autocmd DirChanged global call vproj#OnDirChanged(expand('<amatch>'))
    autocmd DirChanged tabpage call vproj#OnDirChanged(expand('<amatch>'))
    autocmd DirChanged window call vproj#OnDirChanged(expand('<amatch>'))
    autocmd ColorScheme * call vproj#DefineHighlights()
    autocmd VimResized * call vproj#HandleResize()
    if exists('##WinResized')
      autocmd WinResized * call vproj#HandleResize()
    endif
  augroup END
  SetupGuardAutocommands()
enddef

# Guards that keep the pane honest, in the same group PaneClose clears (so
# closing the pane removes them). Called from SetupAutocommands, after its
# `autocmd!`, with the pane buffer current.
def SetupGuardAutocommands(): void
  execute 'augroup ' .. AUTOGROUP
    # The pane left as the only window: quit Vim as closing the last real
    # window would. Never from inside the user's own command (a :quit here
    # aborted their command line and replaced the pane with a hidden buffer):
    # the autocmd only schedules a check, which runs after the command.
    autocmd WinEnter * call vproj#ScheduleQuitCheck()
    # The cursor never rests on the separator or the page footer.
    autocmd CursorMoved <buffer> call vproj#ClampPaneCursor()
  augroup END
  # A fresh pane starts out fitted to the terminal as it is now.
  NoteTermSize()
enddef

# At most one check is pending; -1 when none is.
var quit_timer: number = -1

# WinEnter: when the pane is the last window, schedule QuitIfPaneAlone for
# after the command that caused the event. Without timers nothing is
# scheduled and the pane stays as it is (no quit, no error).
export def ScheduleQuitCheck(): void
  if quit_timer != -1 || !has('timers') || !PaneIsLastWindow()
    return
  endif
  quit_timer = timer_start(0, (_) => QuitIfPaneAlone())
enddef

# The deferred check: the layout may have changed since it was scheduled
# (the pane closed, another window opened), so ask again. Plain :quit, and
# only when no buffer is modified: with unsaved changes the pane just stays,
# silently, instead of the quit failing with E37/E162.
def QuitIfPaneAlone(): void
  quit_timer = -1
  if !PaneIsLastWindow()
    return
  endif
  if !empty(getbufinfo({bufmodified: 1}))
    return
  endif
  try
    quit
  catch
    Error('vproj: Cannot quit -- ' .. v:exception)
  endtry
enddef

# True when the pane is the only window of the only tab page. Not during
# PaneOpen/PaneClose: PaneOpen splits before it enters the pane, and
# PaneClose opens a spare window first, so neither is ever alone here.
export def PaneIsLastWindow(): bool
  if !IsPaneVisible()
    return false
  endif
  if tabpagenr('$') > 1 || winnr('$') != 1
    return false
  endif
  if getcmdwintype() != ''
    return false
  endif
  return bufnr('%') == pane_bufnr
enddef

# Keep the cursor on a row that can be selected and selected_line in step
# with it. Key handlers (SelectNext, ...) set both themselves, so this only
# acts when the cursor got somewhere else: G, L, Ctrl-F, a mouse click.
export def ClampPaneCursor(): void
  if !IsPaneVisible() || bufnr('%') != pane_bufnr
    return
  endif
  var total: number = line('$')
  var lnum: number = line('.')
  var target: number = lnum
  if SkipNonSelectable(lnum)
    var last: number = total
    while last > 1 && SkipNonSelectable(last)
      last -= 1
    endwhile
    # The footer is below the items: go to the last item. The separator is
    # above them: go to the first.
    target = lnum > last ? last : FirstSelectableLine()
    target = min([target, total])
    cursor(target, 1)
  endif
  # A pane that fits its window never needs to be scrolled (Ctrl-F, Ctrl-D).
  if total <= winheight(0) && line('w0') > 1
    winrestview({topline: 1})
  endif
  if target != selected_line
    selected_line = target
    UpdateCursorHighlight()
    UpdatePreview()
  endif
enddef

def ApplyStaticHighlights(): void
  if !IsPaneVisible()
    return
  endif

  var label: string = get(MODE_LABELS, current_mode, '')
  if empty(label)
    return
  endif

  var pattern: string = '\V' .. escape(label, '\')
  var wnr: number = bufwinnr(pane_bufnr)
  if wnr <= 0
    return
  endif
  var orig_wid: number = win_getid()
  var pane_wid: number = win_getid(wnr)
  win_gotoid(pane_wid)
  # Clear old static highlights before creating new ones
  for id in match_ids
    silent! matchdelete(id, pane_wid)
  endfor
  var group: string = get(MODE_HIGHLIGHT_GROUPS, current_mode, 'VprojModeFile')
  match_ids = []
  silent! match_ids->add(matchadd(group, pattern, 10, MATCH_AUTO_ID))
  # Highlight nav indicator characters in blue (priority 11 = above cursorline)
  silent! match_ids->add(matchadd('VprojNavIndicator', '^[.a-z]', 11, MATCH_AUTO_ID))
  win_gotoid(orig_wid)
enddef

def UpdateCursorHighlight(): void
  if !IsPaneVisible()
    return
  endif
  var wnr: number = bufwinnr(pane_bufnr)
  if wnr <= 0
    return
  endif
  var orig_wid: number = win_getid()
  win_gotoid(win_getid(wnr))
  if cursor_match_id > 0
    silent! matchdelete(cursor_match_id)
  endif
  var cur_pattern: string = '\%' .. selected_line .. 'l'
  silent! cursor_match_id = matchadd('VprojCursorLine', cur_pattern, 9, MATCH_AUTO_ID)
  win_gotoid(orig_wid)
enddef

def ClearPaneHighlights(): void
  # Always clear ID lists, even if deletion fails (stale window IDs)
  var ids_to_clear: list<number> = match_ids
  match_ids = []
  if cursor_match_id > 0
    ids_to_clear->add(cursor_match_id)
    cursor_match_id = -1
  endif
  if empty(ids_to_clear) || !IsPaneVisible()
    return
  endif
  var wnr: number = bufwinnr(pane_bufnr)
  if wnr <= 0
    return
  endif
  var orig_wid: number = win_getid()
  win_gotoid(win_getid(wnr))
  for id in ids_to_clear
    silent! matchdelete(id)
  endfor
  win_gotoid(orig_wid)
enddef

def ApplyWidth(): void
  if !IsPaneVisible()
    return
  endif
  var wnr: number = bufwinnr(pane_bufnr)
  if wnr <= 0
    return
  endif
  var orig_wid: number = win_getid()
  win_gotoid(win_getid(wnr))
  silent! execute 'vert resize ' .. pane_width
  win_gotoid(orig_wid)
  NoteTermSize()
enddef

# Session persistence
def SessionFilePath(): string
  var cache_val: any = getenv('XDG_CACHE_HOME')
  if type(cache_val) == v:t_string && !empty(cache_val)
    return cache_val .. '/vproj/session'
  endif
  var cache: string = expand('~/.cache')
  if cache =~ '^\~'
    cache = substitute(cache, '\~', $HOME, '')
  endif
  # macOS: XDG spec uses ~/Library/Caches
  if !isdirectory(cache) && isdirectory(expand('~/Library/Caches'))
    cache = expand('~/Library/Caches')
  endif
  return cache .. '/vproj/session'
enddef

def SessionError(msg: string): void
  session_error = msg
  Error(msg)
enddef

# Saving the session creates files on the user's machine (rule 5), so it
# happens only when the user turned it on: g:vproj_save_session = 1. Anything
# else, including an unset or malformed value, means no write. Reading an
# existing session file on open (LoadSession) needs no opt-in.
def SessionSaveEnabled(): bool
  var flag: any = get(g:, 'vproj_save_session', 0)
  if type(flag) == v:t_bool
    return flag
  endif
  return type(flag) == v:t_number && flag != 0
enddef

def SaveSession(): void
  session_error = ''
  if !SessionSaveEnabled()
    return
  endif
  var path: string = SessionFilePath()
  var dir: string = fnamemodify(path, ':h')
  if !isdirectory(dir)
    var made: bool = false
    try
      made = mkdir(dir, 'p') == 1
    catch
      made = false
    endtry
    if !made && !isdirectory(dir)
      SessionError('vproj: could not create session directory ' .. dir)
      return
    endif
  endif
  var lines: list<string> = []
  lines->add('mode=' .. current_mode)
  if !empty(current_dir)
    lines->add('dir=' .. current_dir)
  endif
  lines->add('width=' .. pane_width)
  lines->add('info=' .. (show_info_column ? '1' : '0'))
  lines->add('git_filter=' .. (git_filter_active ? '1' : '0'))
  # Write the new file first; keep the old one as .bak only once the new
  # one is safely on disk. writefile() and rename() report failure by
  # return value, so check both.
  var tmp: string = path .. '.tmp'
  var written: bool = false
  try
    written = writefile(lines, tmp) == 0
  catch
    written = false
  endtry
  if !written
    silent! delete(tmp)
    SessionError('vproj: could not save session to ' .. tmp)
    return
  endif
  if filereadable(path) && rename(path, path .. '.bak') != 0
    silent! delete(tmp)
    SessionError('vproj: could not rotate session file ' .. path)
    return
  endif
  if rename(tmp, path) != 0
    silent! delete(tmp)
    SessionError('vproj: could not save session to ' .. path)
  endif
enddef

def LoadSession(): void
  var path: string = SessionFilePath()
  if !filereadable(path)
    return
  endif
  var lines: list<string>
  try
    lines = readfile(path)
  catch
    return
  endtry
  var saved_mode: string = ''
  for line in lines
    var eq: number = stridx(line, '=')
    if eq < 1
      continue
    endif
    var key: string = trim(line[ : eq - 1])
    var val: string = trim(line[eq + 1 : ])
    if key == 'mode' && !empty(val)
      if val == 'ind' || val == 'log'
        val = 'file'
      elseif val == 'git'
        val = 'code'
      endif
      if index(MODE_KEYS, val) >= 0
        saved_mode = val
      endif
    elseif key == 'dir' && !empty(val) && isdirectory(val) && val !~ '^//[^/]'
      current_dir = val
    elseif key == 'width'
      var w: number = str2nr(val)
      if w >= MIN_WIDTH && w <= MAX_WIDTH
        pane_width = min([w, SafeMaxWidth()])
      endif
    elseif key == 'info'
      show_info_column = (val == '1')
    elseif key == 'git_filter'
      git_filter_active = (val == '1')
    endif
  endfor
  if !empty(saved_mode)
    current_mode = saved_mode
    if current_mode == 'code'
      LoadCodeProject()
    endif
  endif
  ApplyWidth()
enddef

export def DefineHighlights(): void
  # ── Git status — linked to built-in Vim diff groups ──
  # When these groups change (e.g. on :colorscheme), the linked groups
  # follow automatically — no ColorScheme handler needed for these.
  highlight default link VprojGitModified DiffChange
  highlight default link VprojGitAdded DiffAdd
  highlight default link VprojGitDeleted DiffDelete
  highlight default link VprojGitRenamed Title
  highlight default link VprojGitUntracked Comment
  highlight default link VprojGitConflict ErrorMsg
  highlight default link VprojGitIgnored Ignore

  # ── Mode labels — linked to semantic groups for colorscheme compatibility ──
  highlight default link VprojModeFile Title
  highlight default link VprojModeBuf Directory
  highlight default link VprojModeCode Special
  highlight default link VprojModeQfix Question

  # ── Cursor, navigation, info ──
  highlight default link VprojCursorLine CursorLine
  highlight default VprojNavIndicator guifg=#569CD6 ctermfg=75
  highlight default link VprojInfoColumn Directory
  highlight default link VprojParentDir String
  highlight default link VprojDirName Directory
  highlight default link VprojSeparator Comment
  highlight default link VprojStatusLine StatusLine
enddef
