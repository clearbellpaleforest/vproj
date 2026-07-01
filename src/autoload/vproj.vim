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
var paging_active: bool = false
var nav_offset: number = 0
var original_cwd: string = ''
var saved_shortmess: string = ''
var filter_pattern: string = ''
var git_filter_active: bool = false

# Git integration cache
var git_status_map: dict<string> = {}
var git_branch_cache: string = ''
var git_root_cache: string = ''

# Project state (code mode)
var project: dict<any> = {}
var code_root: string = ''



# Tree view state (file mode — T toggles)
var tree_view_active: bool = false
var expanded_dirs: dict<number> = {}

# Preview state (file modes — p toggles)
var preview_active: bool = false
var preview_bufnr: number = -1

const MODE_KEYS: list<string> = ['file', 'buf', 'code', 'qfix', 'log']
const MODE_LABELS: dict<string> = {file: '[F]ile', buf: '[B]uf', code: '[C]ode', qfix: '[q]fix', log: '[L]og'}
const MODE_HIGHLIGHT_GROUPS: dict<string> = {
  file: 'VprojModeFile', buf: 'VprojModeBuf', code: 'VprojModeCode',
  qfix: 'VprojModeQfix', log: 'VprojModeLog',
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
const LOG_SEP_LINE: number = 2
const FIRST_LOG_ITEM_LINE: number = 3
const NAV_CHARS: list<string> = [
  'e', 'f', 'g', 'i', 'l', 'm', 'n', 'o', 't', 'u', 'v', 'w', 'y',
  'E', 'G', 'H', 'I', 'J', 'K', 'M', 'N', 'O', 'R', 'S', 'V', 'W', 'X', 'Y',
  '1', '2', '3', '4', '5', '6', '7', '8', '9',
]
const MIN_WIDTH: number = 20
const MAX_WIDTH: number = 80
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

def Error(msg: string): void
  echohl ErrorMsg
  echom msg
  echohl None
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

def NavChar(item: dict<any>, visible_idx: number): string
  if get(item, 'is_parent', false)
    return '  '
  endif
  var nav_idx = visible_idx + nav_offset
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
    pane_open_mode = 'temporary'
    PaneOpen()
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
    pane_open_mode = 'permanent'
    PaneOpen()
    silent! doautocmd <nomodeline> User VprojPaneOpenedPermanent
  endif
enddef

export def PaneOpen(): void
  if IsPaneVisible()
    return
  endif

  if saved_shortmess == ''
    saved_shortmess = &shortmess
    set shortmess+=S
  endif

  pane_width = get(g:, 'vproj_pane_width_default', 40)
  if type(pane_width) != v:t_number || pane_width < MIN_WIDTH
    pane_width = MIN_WIDTH
  endif
  if pane_width > MAX_WIDTH
    pane_width = MAX_WIDTH
  endif
  # Don't let the pane consume the entire screen — leave at least 20 cols
  var safe_max: number = &columns - 20
  if safe_max < MIN_WIDTH
    safe_max = MIN_WIDTH
  endif
  if pane_width > safe_max
    pane_width = safe_max
  endif

  # Reuse existing buffer if it still exists
  DefineHighlights()
  if pane_bufnr > 0 && bufexists(pane_bufnr)
    # Switch to a window without winfixheight/winfixwidth so splits succeed.
    # Plugins like NERDTree/Tagbar set these, which may block splits (E36).
    # Only search windows in the current tab — do not switch tabs.
    var current_tab: number = tabpagenr()
    var found_clear: bool = false
    for info in getwininfo()
      if get(info, 'tabpage', 0) == current_tab
          && !getwinvar(info.winid, '&winfixheight', 0)
          && !getwinvar(info.winid, '&winfixwidth', 0)
        win_gotoid(info.winid)
        found_clear = true
        break
      endif
    endfor
    if !found_clear
      # Fall back: find window without winfixheight (needed for :new)
      for info in getwininfo()
        if get(info, 'tabpage', 0) == current_tab
            && !getwinvar(info.winid, '&winfixheight', 0)
          win_gotoid(info.winid)
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
        Error('vproj: Cannot open pane (reuse) — ' .. v:exception .. ' (' .. &columns .. ' cols, ' .. winnr('$') .. ' wins)')
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
    try
      LoadSession()
    catch
      echom 'vproj: session load error: ' .. v:exception
    endtry
    try
      Render()
    catch
      echom 'vproj: render error: ' .. v:exception
    endtry
    silent! doautocmd <nomodeline> User VprojPaneReady
    return
  endif

  # Switch to a window without winfixheight/winfixwidth so splits succeed.
  # Only search windows in the current tab — do not switch tabs.
  var current_tab: number = tabpagenr()
  var found_clear: bool = false
  for info in getwininfo()
    if get(info, 'tabpage', 0) == current_tab
        && !getwinvar(info.winid, '&winfixheight', 0)
        && !getwinvar(info.winid, '&winfixwidth', 0)
      win_gotoid(info.winid)
      found_clear = true
      break
    endif
  endfor
  if !found_clear
    for info in getwininfo()
      if get(info, 'tabpage', 0) == current_tab
          && !getwinvar(info.winid, '&winfixheight', 0)
        win_gotoid(info.winid)
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
      Error('vproj: Cannot open pane (new) — ' .. v:exception .. ' (' .. &columns .. ' cols, ' .. winnr('$') .. ' wins)')
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
  original_cwd = current_dir
  selected_line = FirstSelectableLine()
  try
    LoadSession()
  catch
    echom 'vproj: session load error: ' .. v:exception
  endtry
  try
    Render()
  catch
    echom 'vproj: render error: ' .. v:exception
  endtry
  SetupPaneMappings()
  silent! doautocmd <nomodeline> User VprojPaneReady
enddef

export def PaneClose(): void
  ClosePreview()
  SaveSession()
  var did_enew: bool = false
  if pane_bufnr > 0 && bufexists(pane_bufnr)
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
  execute 'augroup ' .. AUTOGROUP .. ' | autocmd! | augroup END'
  HandleBufWipeout()
  silent! doautocmd <nomodeline> User VprojPaneClosed
enddef

export def HandleBufWipeout(): void
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
  original_cwd = ''
  git_status_map = {}
  git_branch_cache = ''
  git_root_cache = ''
  if saved_shortmess != ''
    &shortmess = saved_shortmess
    saved_shortmess = ''
  endif
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
  echom 'saved_shortmess: "' .. saved_shortmess .. '"'
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

export def OnDirChanged(): void
  InvalidateGitCache()
  if !IsPaneVisible() || current_mode == 'code'
    return
  endif
  # Only react to global dir changes, not window-local changes from
  # other windows (which would overwrite current_dir with wrong value).
  if get(v:event, 'scope', 'global') == 'window' && bufnr('%') != pane_bufnr
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

def SkipNonSelectable(line: number): bool
  if line == MODE_MENU_LINE
    return true
  endif
  if current_mode != 'code' && current_mode != 'qfix' && current_mode != 'log' && line == FILE_STATUS_SEP_LINE
    return true
  endif
  if current_mode == 'code' && line == CODE_SEP_LINE
    return true
  endif
  if current_mode == 'qfix' && line == QFIX_SEP_LINE
    return true
  endif
  if current_mode == 'log' && line == LOG_SEP_LINE
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
  elseif current_mode == 'log'
    return FIRST_LOG_ITEM_LINE
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
  for item in items
    if get(item, 'is_dir', false) && !get(item, 'is_parent', false)
      NavigateInto(get(item, 'name', ''))
      return
    endif
  endfor
enddef

export def GetNavOffset(): number
  return nav_offset
enddef

export def SelectByNavChar(ch: string): void
  if !IsPaneVisible()
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
        return
      endif
      visible_idx += 1
    endif
    line_offset += 1
  endfor
enddef

export def ShiftNavForward(): void
  if !IsPaneVisible()
    return
  endif
  if nav_offset < len(NAV_CHARS) - 1
    nav_offset += 1
    Render()
  endif
enddef

export def ShiftNavBackward(): void
  if !IsPaneVisible()
    return
  endif
  if nav_offset > 0
    nav_offset -= 1
    Render()
  endif
enddef

export def SelectCurrent(): void
  if !IsPaneVisible()
    return
  endif

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
      OpenFile(get(item, 'path', ''))
    endif
  elseif current_mode == 'buf'
    if has_key(item, 'bufnr')
      OpenBuffer(item.bufnr)
    endif
  elseif current_mode == 'code'
    if get(item, 'is_parent', false)
      NavigateUp()
    elseif get(item, 'is_dir', false)
      NavigateInto(get(item, 'name', ''))
    else
      OpenFile(get(item, 'path', ''))
    endif
  elseif current_mode == 'qfix'
    if has_key(item, 'filename') && has_key(item, 'lnum')
      OpenQfixEntry(item)
    endif
  elseif current_mode == 'log'
    if has_key(item, 'hash')
      OpenCommitDetail(item)
    endif
  endif
enddef

# ──────────────────────────────────────────────
# Mode switching
# ──────────────────────────────────────────────

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
    var vproj_path: string = FindVprojFile(current_dir)
    if empty(vproj_path)
      cwd = getcwd()
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
  endif
  selected_line = FirstSelectableLine()
  # Apply mode-specific width config if set
  var mode_width: number = 0
  if mode == 'file'
    mode_width = get(g:, 'vproj_pane_width_file', 0)
  elseif mode == 'buf'
    mode_width = get(g:, 'vproj_pane_width_buf', 0)
  elseif mode == 'code'
    mode_width = get(g:, 'vproj_pane_width_code', 0)
  elseif mode == 'qfix'
    mode_width = get(g:, 'vproj_pane_width_qfix', 0)
  elseif mode == 'log'
    mode_width = get(g:, 'vproj_pane_width_log', 0)
  endif
  if type(mode_width) == v:t_number && mode_width >= MIN_WIDTH && mode_width <= MAX_WIDTH
    pane_width = mode_width
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

export def PaneGrow(): void
  if pane_width >= MAX_WIDTH
    return
  endif
  pane_width += 1
  ApplyWidth()
  Render()
enddef

export def PaneShrink(): void
  if pane_width <= MIN_WIDTH
    return
  endif
  pane_width -= 1
  ApplyWidth()
  Render()
enddef

export def SetPaneWidth(w: number): void
  if w < MIN_WIDTH || w > MAX_WIDTH
    return
  endif
  pane_width = w
  ApplyWidth()
  Render()
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
  elseif current_mode == 'log'
    items = LogItems()
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
    elseif current_mode == 'log'
      lines->extend(BuildLogLines(visible))
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
  UpdateCursorHighlight()

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
  MoveCursor(selected_line)
  UpdatePreview()
enddef

def BuildModeMenu(): string
  var parts: list<string> = []
  for key in MODE_KEYS
    parts->add(MODE_LABELS[key])
  endfor
  var line: string = join(parts, '  ')
  if !empty(filter_pattern)
    line = line .. ' *'
  endif
  if git_filter_active
    line = line .. ' [G]'
  endif
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
  elseif current_mode == 'log'
    mode_letter = 'l'
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
      add(parts, fnamemodify(root, ':~'))
    endif
  endif

  # 3. Git overlay: ⎇ branch [N]M [N]? [N]A
  var branch: string = GitBranch()
  if !empty(branch)
    var git_part: string = '⎇ ' .. branch
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

  var w: number = strwidth(result)
  if w > pane_width
    result = strcharpart(result, 0, pane_width)
  elseif w < pane_width
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
  var start_idx = current_page * items_per_page
  var end_idx = start_idx + items_per_page
  if end_idx > len(all_items)
    end_idx = len(all_items)
  endif
  return all_items[start_idx : end_idx]
enddef

def BuildPageNavRow(): string
  var tp: number = total_pages < 1 ? 1 : total_pages
  var text: string = printf(' >>> Page %d/%d  Ctrl-N Ctrl-P <<< ', current_page + 1, tp)
  if strwidth(text) > pane_width
    text = strcharpart(text, 0, pane_width)
  endif
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

def GitRoot(): string
  if !empty(git_root_cache)
    return git_root_cache
  endif
  var root: string = trim(system('git -C ' .. shellescape(getcwd()) .. ' rev-parse --show-toplevel 2>/dev/null'))
  var shell_err: number = v:shell_error
  if shell_err == 0
    git_root_cache = root
    return root
  endif
  return ''
enddef

def GitBranch(): string
  if !empty(git_branch_cache)
    return git_branch_cache
  endif
  var branch: string = trim(system('git -C ' .. shellescape(getcwd()) .. ' branch --show-current 2>/dev/null'))
  var shell_err: number = v:shell_error
  if shell_err == 0
    git_branch_cache = branch
    return branch
  endif
  return ''
enddef

def GitStatusMap(): dict<string>
  if !empty(git_status_map)
    return git_status_map
  endif
  var root: string = GitRoot()
  if empty(root)
    return {}
  endif
  var output: string = system('git -C ' .. shellescape(root) .. ' status --porcelain 2>/dev/null')
  var shell_err: number = v:shell_error
  if shell_err != 0
    return {}
  endif
  var result: dict<string> = {}
  for line in output->split('\n')
    if empty(line) || strwidth(line) < 3
      continue
    endif
    var fname: string = line[3 : ]
    # Handle renames (old -> new)
    var arrow: number = stridx(fname, ' -> ')
    if arrow > 0
      fname = fname[arrow + 4 : ]
    endif
    # Handle quoted filenames
    if fname[0] == '"'
      fname = fname[1 : -1]
      fname = substitute(fname, '\\n', nr2char(10), 'g')
      fname = substitute(fname, '\\t', nr2char(9), 'g')
      fname = substitute(fname, '\\\\', '\\', 'g')
      fname = substitute(fname, '\\"', '"', 'g')
    endif
    # Map porcelain status to single char: M/A/D/?
    var x: string = line[0]
    var y: string = line[1]
    var status: string = ' '
    if x == '?' && y == '?'
      status = '?'
    elseif x == 'A' || y == 'A'
      status = 'A'
    elseif x == 'D' || y == 'D'
      status = 'D'
    elseif x == 'M' || y == 'M'
      status = 'M'
    elseif x == 'U' || y == 'U'
      status = '!'
    elseif x == 'R'
      status = 'R'
    endif
    if status != ' '
      result[root .. '/' .. fname] = status
    endif
  endfor
  git_status_map = result
  return result
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
  git_branch_cache = ''
  git_root_cache = ''
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
    # Keep items that have git status
    if has_key(status_map, get(item, 'path', ''))
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

  var status_map: dict<string> = GitStatusMap()
  var st: string = get(status_map, path, '')
  var name: string = get(item, 'name', path)
  if empty(st)
    echom 'vproj: No git changes for ' .. name
    return
  endif

  if st == '?'
    system('git add ' .. shellescape(path) .. ' 2>/dev/null')
    if v:shell_error == 0
      echom 'Staged: ' .. name
    else
      Error('vproj: Failed to stage ' .. name)
    endif
  elseif st == 'A' || st == 'M' || st == 'R'
    system('git reset HEAD -- ' .. shellescape(path) .. ' 2>/dev/null')
    if v:shell_error == 0
      echom 'Unstaged: ' .. name
    else
      Error('vproj: Failed to unstage ' .. name)
    endif
  elseif st == 'D'
    system('git rm --cached -- ' .. shellescape(path) .. ' 2>/dev/null')
    if v:shell_error == 0
      echom 'Staged deletion: ' .. name
    else
      Error('vproj: Failed to stage deletion of ' .. name)
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

  var root: string = GitRoot()
  if empty(root)
    echom "vproj: Not in a git repository"
    return
  endif

  if !IsRegularFile(path)
    Error("vproj: Cannot diff binary or special file")
    return
  endif

  var status_map: dict<string> = GitStatusMap()
  var st: string = get(status_map, path, "")
  var cmd: string = ""

  if st == "?" || empty(st)
    cmd = "git diff --no-index /dev/null " .. shellescape(path)
  elseif st == "A" || st == "M" || st == "R"
    cmd = "git diff --cached -- " .. shellescape(path)
  else
    cmd = "git diff -- " .. shellescape(path)
  endif

  var pane_wid: number = win_getid()
  if OpenInRightPanel() < 0
    return
  endif
  enew
  setlocal buftype=nofile
  setlocal bufhidden=wipe
  setlocal noswapfile
  setlocal nobuflisted
  setlocal filetype=diff
  setlocal syntax=diff
  setlocal wrap=0
  setlocal readonly
  nnoremap <buffer> <silent> q <Cmd>close<CR>
  nnoremap <buffer> <silent> do <Nop>
  nnoremap <buffer> <silent> dp <Nop>
  silent execute 'read !' .. cmd
  if v:shell_error != 0
    close
    win_gotoid(pane_wid)
    Error('vproj: Diff failed for ' .. get(item, "name", path))
    return
  endif
  cursor(1, 1)
  delete _
  setlocal nomodifiable
  setlocal nomodified

  win_gotoid(pane_wid)
  echom "Diff: " .. get(item, "name", path)
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

  var status_map: dict<string> = GitStatusMap()
  var st: string = get(status_map, path, "")
  var name: string = get(item, "name", path)
  if empty(st)
    echom "vproj: No git changes for " .. name
    return
  endif

  echohl WarningMsg
  var answer: string = input("Discard changes to " .. name .. "? y/N: ")
  echohl None
  if tolower(answer) != "y"
    echom "Cancelled"
    return
  endif

  if st == "?"
    var abs_path: string = fnamemodify(path, ':p')
    delete(abs_path)
    if !filereadable(abs_path)
      echom "Deleted: " .. name
    else
      echom "Failed to delete: " .. name
    endif
  elseif st == "A"
    system("git reset HEAD -- " .. shellescape(path) .. " 2>/dev/null")
    if v:shell_error == 0
      echom "Unstaged: " .. name
    else
      Error("vproj: Failed to unstage " .. name)
    endif
  elseif st == "M" || st == "R"
    system("git checkout -- " .. shellescape(path) .. " 2>/dev/null")
    if v:shell_error == 0
      echom "Reverted: " .. name
    else
      Error("vproj: Failed to revert " .. name)
    endif
  elseif st == "D"
    system("git checkout HEAD -- " .. shellescape(path) .. " 2>/dev/null")
    if v:shell_error == 0
      echom "Restored: " .. name
    else
      Error("vproj: Failed to restore " .. name)
    endif
  endif

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
  var tracked: string = system('git -C ' .. shellescape(root) .. ' ls-files ' .. shellescape(path) .. ' 2>/dev/null')
  if empty(trim(tracked))
    echom 'vproj: File is not tracked by git'
    return
  endif
  var pane_wid: number = win_getid()
  if OpenInRightPanel() < 0
    return
  endif
  enew
  setlocal buftype=nofile
  setlocal bufhidden=wipe
  setlocal noswapfile
  setlocal nobuflisted
  setlocal wrap=0
  setlocal readonly
  nnoremap <buffer> <silent> q <Cmd>close<CR>
  nnoremap <buffer> <silent> do <Nop>
  nnoremap <buffer> <silent> dp <Nop>
  silent execute 'read !git -C ' .. shellescape(root) .. ' annotate -- ' .. shellescape(path)
  if v:shell_error != 0
    close
    win_gotoid(pane_wid)
    Error('vproj: Blame failed for ' .. get(item, 'name', path))
    return
  endif
  cursor(1, 1)
  delete _
  setlocal nomodifiable
  setlocal nomodified
  win_gotoid(pane_wid)
  echom 'Blame: ' .. get(item, 'name', path)
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

def OpenPreview(): void
  # If a preview window already exists, close it first
  if preview_bufnr > 0 && bufexists(preview_bufnr) && bufwinnr(preview_bufnr) > 0
    ClosePreview()
  endif
  var pane_wid: number = win_getid()
  # Move to a non-pane window if one exists in the current tab, so botright vnew
  # splits the file area instead of nesting inside the pane.
  # Only search windows in the current tab — do not switch tabs.
  var current_tab: number = tabpagenr()
  for info in getwininfo()
    if info.winid != pane_wid && get(info, 'tabpage', 0) == current_tab
      win_gotoid(info.winid)
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
    Error('vproj: Cannot open preview — ' .. v:exception)
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
  silent! vert resize 40
  win_gotoid(pane_wid)
  try
    UpdatePreview()
    preview_active = true
  catch
    echohl ErrorMsg
    echom 'vproj preview: ' .. v:exception
    echohl None
    preview_active = false
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
      appendbufline(preview_bufnr, 1, '(no preview)')
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
    appendbufline(preview_bufnr, 0, header)
    appendbufline(preview_bufnr, 1, '')
    var raw: list<string>
    try
      raw = readdir(dir_path)
    catch
      raw = []
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
    if count == 0
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
      appendbufline(preview_bufnr, 0, '(cannot read)')
      return
    endif
    if !IsRegularFile(file_path)
      appendbufline(preview_bufnr, 0, '(special file)')
      return
    endif
    if IsBinary(file_path)
      appendbufline(preview_bufnr, 0, '(binary file)')
      return
    endif
    var lines: list<string>
    try
      lines = readfile(file_path, '', 200)
    catch
      appendbufline(preview_bufnr, 0, '(cannot read)')
      return
    endtry
    if empty(lines)
      appendbufline(preview_bufnr, 0, '(empty file)')
    else
      appendbufline(preview_bufnr, 0, lines)
    endif
    var ext: string = fnamemodify(file_path, ':e')
    if !empty(ext)
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
  var output: string = system('git -C ' .. shellescape(root) .. ' commit -m ' .. shellescape(msg) .. ' 2>&1')
  if v:shell_error != 0
    echom 'vproj: Commit failed — ' .. substitute(output, '\n', ' ', 'g')
  else
    var hash: string = system('git -C ' .. shellescape(root) .. ' rev-parse --short HEAD 2>/dev/null')
    echom 'vproj: Committed ' .. trim(hash)
  endif
  InvalidateGitCache()
  Render()
enddef

export def GitPush(): void
  if !IsPaneVisible() || (current_mode != 'file' && current_mode != 'code')
    return
  endif
  var root: string = GitRoot()
  if empty(root)
    Error('vproj: Not in a git repository')
    return
  endif
  var remote: string = system('git -C ' .. shellescape(root) .. ' remote 2>/dev/null')
  if empty(trim(remote))
    Error('vproj: No remote configured')
    return
  endif
  var output: string = system('git -C ' .. shellescape(root) .. ' push 2>&1')
  if v:shell_error != 0
    echom 'vproj: Push failed — ' .. substitute(output, '\n', ' ', 'g')
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
  var root: string = GitRoot()
  if empty(root)
    Error('vproj: Not in a git repository')
    return
  endif
  var remote: string = system('git -C ' .. shellescape(root) .. ' remote 2>/dev/null')
  if empty(trim(remote))
    Error('vproj: No remote configured')
    return
  endif
  var output: string = system('git -C ' .. shellescape(root) .. ' pull --ff-only 2>&1')
  if v:shell_error != 0
    echom 'vproj: Pull failed — ' .. substitute(output, '\n', ' ', 'g')
  else
    echom 'vproj: Pulled — ' .. substitute(trim(output), '\n', ' ', 'g')
  endif
  InvalidateGitCache()
  Render()
enddef

export def GitBranchSwitch(): void
  if !IsPaneVisible() || (current_mode != 'file' && current_mode != 'code')
    return
  endif
  var root: string = GitRoot()
  if empty(root)
    Error('vproj: Not in a git repository')
    return
  endif
  var branches: string = system('git -C ' .. shellescape(root) .. ' branch 2>/dev/null')
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
  var output: string = system('git -C ' .. shellescape(root) .. ' checkout ' .. shellescape(target) .. ' 2>&1')
  if v:shell_error != 0
    echom 'vproj: Checkout failed — ' .. substitute(output, '\n', ' ', 'g')
  else
    echom 'vproj: Switched to ' .. target
  endif
  InvalidateGitCache()
  Render()
enddef

export def GitStashPush(): void
  if !IsPaneVisible() || (current_mode != 'file' && current_mode != 'code')
    return
  endif
  var root: string = GitRoot()
  if empty(root)
    Error('vproj: Not in a git repository')
    return
  endif
  var msg: string = input('Stash message (empty for auto): ')
  var cmd: string = 'git -C ' .. shellescape(root) .. ' stash push'
  if !empty(msg)
    cmd ..= ' -m ' .. shellescape(msg)
  endif
  var output: string = system(cmd .. ' 2>&1')
  if v:shell_error != 0
    echom 'vproj: Stash failed — ' .. substitute(output, '\n', ' ', 'g')
  else
    echom 'vproj: Changes stashed' .. (empty(msg) ? '' : ' — ' .. msg)
  endif
  InvalidateGitCache()
  Render()
enddef

export def GitStashPop(): void
  if !IsPaneVisible() || (current_mode != 'file' && current_mode != 'code')
    return
  endif
  var root: string = GitRoot()
  if empty(root)
    Error('vproj: Not in a git repository')
    return
  endif
  var list_output: string = system('git -C ' .. shellescape(root) .. ' stash list 2>&1')
  if empty(trim(list_output))
    echom 'vproj: No stashes found'
    return
  endif
  echom 'Stash list:'
  for line in list_output->split('\n')
    echom '  ' .. line
  endfor
  var ref: string = input('Pop which stash? (Enter for top): ')
  var cmd: string = 'git -C ' .. shellescape(root) .. ' stash pop'
  if !empty(ref)
    cmd ..= ' ' .. shellescape(ref)
  endif
  var output: string = system(cmd .. ' 2>&1')
  if v:shell_error != 0
    echom 'vproj: Stash pop failed — ' .. substitute(output, '\n', ' ', 'g')
  else
    echom 'vproj: Stash popped'
  endif
  InvalidateGitCache()
  Render()
enddef

def IsRegularFile(path: string): bool
  var ftype: string = getftype(path)
  if ftype == 'file'
    return true
  endif
  if ftype == 'link' && getftype(resolve(path)) == 'file'
    return true
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
  # Git status: 1-char indicator (space if no status or not in git repo)
  var in_git: bool = IsInGitRepo()
  var status_map: dict<string> = in_git ? GitStatusMap() : {}
  var git_width: number = in_git ? 2 : 0
  var prefix_width: number = 2 + git_width

  for item in file_items
    var name: string = get(item, 'name', '')
    var is_dir: bool = get(item, 'is_dir', false)
    if is_dir
      name = name .. '/'
    endif

    var info: string = ''
    if show_info_column && !is_dir
      info = FormatSize(get(item, 'size', 0))
      info = repeat(' ', info_width - strwidth(info)) .. info
    endif

    # Build line with nav indicator, optional git status, and name
    var indicator: string = NavChar(item, visible_idx)
    var git_char: string = ' '
    if in_git && !get(item, 'is_parent', false) && !is_dir
      var st: string = get(status_map, get(item, 'path', ''), '')
      git_char = empty(st) ? ' ' : st
    endif
    var name_width: number = pane_width - info_width - prefix_width
    if strwidth(name) > name_width
      name = strcharpart(name, 0, name_width)
    endif
    var line: string = indicator .. (in_git ? git_char : '') .. name
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
  var in_git: bool = IsInGitRepo()
  var status_map: dict<string> = in_git ? GitStatusMap() : {}
  var git_width: number = in_git ? 2 : 0
  var prefix_width: number = 2 + git_width
  var visible_idx: number = 0

  for item in visible
    var name: string = get(item, 'name', '')
    var depth: number = get(item, 'depth', 0)
    var is_dir: bool = get(item, 'is_dir', false)
    var expand_char: string = ''

    if is_dir && !get(item, 'is_parent', false)
      expand_char = has_key(expanded_dirs, get(item, 'path', '')) ? '-' : '+'
      name = name .. '/'
    endif

    var indent: string = repeat('  ', depth)
    var indicator: string = NavChar(item, visible_idx)
    if !get(item, 'is_parent', false)
      visible_idx += 1
    endif

    var git_char: string = ' '
    if in_git && !get(item, 'is_parent', false) && !is_dir
      var st: string = get(status_map, get(item, 'path', ''), '')
      git_char = empty(st) ? ' ' : st
    endif

    # Format: [nav][git][indent][expand_char] name
    var line: string = indicator .. (in_git ? git_char .. ' ' : '') .. indent .. expand_char
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
      name = strcharpart(name, 0, name_width)
      # Rebuild line with truncated name
      line = indicator .. (in_git ? git_char .. ' ' : '') .. indent .. expand_char
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
  else
    return printf('%4dG', bytes / 1073741824)
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

def OpenInRightPanel(): number
  # If only the pane window exists, create a new vertical split on the right.
  # If a non-pane window already exists, move there (reuse it).
  # Returns with cursor in the target window.
  var pane_wid: number = win_getid()
  LowerCmdheight()
  var saved_minwidth: number = &winminwidth
  var saved_minheight: number = &winminheight
  set winminwidth=1 winminheight=1
  try
    var found_non_pane: bool = false
    var current_tab: number = tabpagenr()
    for info in getwininfo()
      if info.winid != pane_wid && get(info, 'tabpage', 0) == current_tab
        win_gotoid(info.winid)
        found_non_pane = true
        break
      endif
    endfor
    if !found_non_pane
      botright vnew
    endif
  catch
    win_gotoid(pane_wid)
    Error('vproj: Cannot open right panel — ' .. v:exception)
    return -1
  finally
    RestoreCmdheight()
    &winminwidth = saved_minwidth
    &winminheight = saved_minheight
  endtry
  return 0
enddef

def OpenFile(path: string): void
  if !IsRegularFile(path)
    Error('vproj: Cannot open special file: ' .. fnamemodify(path, ':t'))
    return
  endif
  if !filereadable(path)
    Error('vproj: Cannot read: ' .. path)
    return
  endif
  # Check for binary (null bytes in first 8KB)
  if IsBinary(path)
    Error('vproj: Binary file: ' .. fnamemodify(path, ':t'))
    return
  endif
  var pane_wid: number = win_getid()
  if OpenInRightPanel() < 0
    return
  endif
  execute 'edit ' .. fnameescape(path)
  win_gotoid(pane_wid)
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
      })
    endif
  endfor
  return result
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
      flags = flags .. ' ' .. printf('%4d', item.linecount)
    endif

    var name: string = item.name
    var name_width: number = pane_width - flag_width - 2
    if strwidth(name) > name_width
      name = strcharpart(name, 0, name_width)
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

def OpenBuffer(bufnr: number): void
  if !bufexists(bufnr)
    return
  endif
  var pane_wid: number = win_getid()
  if winnr('$') < 2
    LowerCmdheight()
    var saved_minwidth: number = &winminwidth
    var saved_minheight: number = &winminheight
    set winminwidth=1 winminheight=1
    try
      rightbelow split
    catch
      Error('vproj: Cannot open buffer — ' .. v:exception)
      return
    finally
      RestoreCmdheight()
      &winminwidth = saved_minwidth
      &winminheight = saved_minheight
    endtry
  else
    wincmd p
  endif
  execute 'buffer ' .. bufnr
  win_gotoid(pane_wid)
enddef

export def PromptFilter(): void
  if !IsPaneVisible()
    return
  endif
  var pattern: string = input('Filter: ', filter_pattern)
  filter_pattern = pattern
  selected_line = FirstSelectableLine()
  current_page = 0
  nav_offset = 0
  Render()
enddef

export def GrepSearch(): void
  if !IsPaneVisible()
    return
  endif
  var pattern: string = input('Grep: ')
  if empty(pattern)
    return
  endif
  var root: string = GitRoot()
  if empty(root)
    root = current_dir
  endif
  var cmd: string = 'git -C ' .. shellescape(root) .. ' grep -n -i -z -- ' .. shellescape(pattern) .. ' 2>&1'
  var output: string = system(cmd)
  var shell_err: number = v:shell_error
  if shell_err != 0
    Error('vproj: no matches for: ' .. pattern)
    return
  endif
  var qflist: list<dict<any>> = []
  var nul: string = nr2char(0)
  var parts: list<string> = split(output, nul)
  if !empty(parts) && parts[-1] == ''
    parts = parts[: -2]
  endif
  var i: number = 0
  while i + 1 < len(parts)
    var fname: string = parts[i]
    var linenum_text: string = parts[i + 1]
    var colon: number = stridx(linenum_text, ':')
    if colon > 0
      var lnum: number = str2nr(linenum_text[: colon - 1])
      var text: string = linenum_text[colon + 1 :]
      if !empty(fname) && lnum > 0
        qflist->add({
          filename: fname,
          lnum: lnum,
          text: substitute(text, '^\s*', '', ''),
        })
      endif
    endif
    i += 2
  endwhile
  if empty(qflist)
    Error('vproj: no matches for: ' .. pattern)
    return
  endif
  setqflist([], ' ', {items: qflist, title: 'grep: ' .. pattern})
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
  Render()
enddef

export def CloseBuffer(): void
  if current_mode != 'buf' || !IsPaneVisible()
    echom 'vproj: x closes buffers in buf mode only (press b for buf mode)'
    return
  endif
  var item: dict<any> = GetSelectedItem()
  if empty(item)
    return
  endif
  if has_key(item, 'bufnr')
    try
      execute 'bdelete! ' .. item.bufnr
    catch
      Error('vproj: Cannot close buffer — ' .. v:exception)
      return
    endtry
    if !bufexists(item.bufnr)
      selected_line = FirstSelectableLine()
      current_page = 0
      Render()
    endif
  endif
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
  # Fall back to wildcard pattern for hand-named .vproj files
  var d: string = fnamemodify(dir, ':p')
  while d != '' && d != '/'
    var matches = glob(escape(d, '*?[]{}~\\') .. '/*.vproj', 0, 1)
    for m in matches
      if m !~ '[~]$' && m !~ '\.bak$' && filereadable(m) && getftype(m) == 'file'
        return m
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

export def ParseVprojFile(path: string): dict<any>
  var p: dict<any> = {
    name: '', root: '', vproj_file: path,
    included_dirs: [], included_files: [],
    excluded_dirs: [], excluded_files: [],
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
    # Only skip # comments at top level (before any section), not inside
    # list sections where filenames may legitimately start with #
    if (empty(section) || section == 'name' || section == 'root') && t[0] == '#'
      continue
    endif

    # Check if line starts with a known section header
    var header_type: string = ''
    for key in keys(SECTION_MAP)
      if tolower(t) =~ '^' .. escape(key, ' ') .. '\s*:'
        header_type = SECTION_MAP[key]
        # Extract value after colon for name/root inline format
        var after_colon: string = t->substitute('^[^:]*:\s*', '', '')
        if !empty(after_colon) && (header_type == 'name' || header_type == 'root')
          p[header_type] = after_colon
          if header_type == 'root'
            p[header_type] = p[header_type]->substitute('/$', '', '')
            p[header_type] = fnamemodify(p[header_type], ':p')->substitute('/$', '', '')
            if !isdirectory(p[header_type])
              Error('vproj: Invalid project root in .vproj: ' .. p[header_type])
              p[header_type] = ''
            endif
          endif
          section = ''
        else
          section = header_type
        endif
        break
      endif
    endfor
    if !empty(header_type)
      continue
    endif

    if section == 'name' || section == 'root'
      p[section] = t
      if section == 'root'
        p[section] = p[section]->substitute('/$', '', '')
        p[section] = fnamemodify(p[section], ':p')->substitute('/$', '', '')
        if !isdirectory(p[section])
          Error('vproj: Invalid project root in .vproj: ' .. p[section])
          p[section] = ''
        endif
      endif
      section = ''
    elseif !empty(section)
      p[section]->add(t)
    endif
  endfor
  return p
enddef

def WriteVprojFile(): bool
  if empty(project) || !has_key(project, 'vproj_file')
    return false
  endif

  var lines: list<string> = []
  lines->add('Project Name: ' .. project.name)
  lines->add('Project Root: ' .. project.root)

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

  # Atomic write: temp file + rename
  var tmp: string = project.vproj_file .. '.tmp'
  if writefile(lines, tmp) == 0
    if rename(tmp, project.vproj_file) == 0
      return true
    endif
    Error('vproj: Failed to write project file: ' .. project.vproj_file)
    silent! delete(tmp)
  else
    Error('vproj: Failed to write ' .. project.vproj_file)
  endif
  return false
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

def IsUnderIncluded(rel: string): bool
  for d in project.included_dirs
    if rel == d
      return true
    endif
    if !empty(d) && stridx(rel, d .. '/') == 0
      return true
    endif
  endfor
  return project.included_files->index(rel) >= 0
enddef

def IsUnderExcluded(rel: string): bool
  for d in project.excluded_dirs
    if rel == d
      return true
    endif
    if !empty(d) && stridx(rel, d .. '/') == 0
      return true
    endif
  endfor
  return project.excluded_files->index(rel) >= 0
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

    var name: string = item.name
    if is_dir && !is_parent
      name = name .. '/'
    endif

    var info: string = ''
    if show_info_column && !is_dir && !is_parent
      var fsize: number = getfsize(item.path)
      info = FormatSize(fsize)
      info = repeat(' ', info_width - strwidth(info)) .. info
    endif

    # Non-included items in parentheses after truncation (so closing paren not clipped)
    var name_width: number = pane_width - label_width - strwidth(info)
    if strwidth(name) > name_width
      name = strcharpart(name, 0, name_width)
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

  if !WriteVprojFile()
    # Rollback on write failure
    project.included_dirs = snap_inc_dirs
    project.included_files = snap_inc_files
    project.excluded_dirs = snap_exc_dirs
    project.excluded_files = snap_exc_files
    Error('vproj: Failed to save project — changes reverted')
  endif
  Render()
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
    project = {name: new_name, root: CurrentRoot(), vproj_file: target_path, included_dirs: [], included_files: [], excluded_dirs: [], excluded_files: []}
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
  project.name = new_name
  project.vproj_file = fnamemodify(old_file, ':h') .. '/' .. new_name .. '.vproj'
  if !WriteVprojFile()
    project.name = old_name
    project.vproj_file = old_file
    Error('vproj: Failed to save renamed project — name reverted')
    return
  endif
  if old_file != project.vproj_file && filereadable(old_file)
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
    result->add({
      filename: fname,
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
    var entry_text: string = item.filename .. ':' .. lnum_str .. '  ' .. item.text
    var text_width: number = pane_width - 2  # indicator (char+space)
    if strwidth(entry_text) > text_width
      entry_text = strcharpart(entry_text, 0, text_width)
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

def OpenQfixEntry(item: dict<any>): void
  if empty(get(item, 'filename', ''))
    return
  endif
  var pane_wid: number = win_getid()
  # Find or create a non-pane window
  if winnr('$') < 2
    LowerCmdheight()
    var saved_minwidth: number = &winminwidth
    var saved_minheight: number = &winminheight
    set winminwidth=1 winminheight=1
    try
      rightbelow split
    catch
      Error('vproj: Cannot open qfix entry — ' .. v:exception)
      return
    finally
      RestoreCmdheight()
      &winminwidth = saved_minwidth
      &winminheight = saved_minheight
    endtry
  else
    wincmd p
  endif
  # Open the file
  var fname: string = get(item, 'filename', '')
  if empty(fname)
    win_gotoid(pane_wid)
    return
  endif
  var bufnr: number = bufnr(fname)
  if bufnr >= 1
    execute 'buffer ' .. bufnr
  elseif filereadable(fname)
    execute 'edit ' .. fnameescape(fname)
  else
    Error('vproj: Cannot open: ' .. fname)
    win_gotoid(pane_wid)
    return
  endif
  # Jump to line/column
  if get(item, 'lnum', 0) > 0
    execute 'normal! ' .. get(item, 'lnum', 0) .. 'G'
  endif
  if get(item, 'col', 0) > 0
    execute 'normal! ' .. get(item, 'col', 0) .. '|'
  endif
  win_gotoid(pane_wid)
enddef

def LogItems(): list<dict<any>>
  var root: string = GitRoot()
  if empty(root)
    return []
  endif
  var output: string = system('git -C ' .. shellescape(root) .. ' log --oneline --decorate -n 100 2>/dev/null')
  if v:shell_error != 0 || empty(output)
    return []
  endif
  var result: list<dict<any>> = []
  for line in output->split('\n')
    if empty(line)
      continue
    endif
    var space_idx: number = stridx(line, ' ')
    if space_idx < 1
      continue
    endif
    var hash: string = line[ : space_idx - 1]
    var rest: string = line[space_idx + 1 : ]
    result->add({hash: hash, subject: rest})
  endfor
  return result
enddef

def OpenCommitDetail(item: dict<any>): void
  var hash: string = get(item, 'hash', '')
  if empty(hash)
    return
  endif
  var root: string = GitRoot()
  if empty(root)
    return
  endif
  var pane_wid: number = win_getid()
  LowerCmdheight()
  var saved_minwidth: number = &winminwidth
  var saved_minheight: number = &winminheight
  set winminwidth=1 winminheight=1
  try
    if winnr('$') < 2
      rightbelow split
    else
      wincmd p
    endif
    rightbelow vsplit
  catch
    win_gotoid(pane_wid)
    Error('vproj: Cannot create commit view — ' .. v:exception)
    return
  finally
    RestoreCmdheight()
    &winminwidth = saved_minwidth
    &winminheight = saved_minheight
  endtry
  enew
  setlocal buftype=nofile
  setlocal bufhidden=wipe
  setlocal noswapfile
  setlocal nobuflisted
  setlocal filetype=git
  setlocal wrap=0
  setlocal readonly
  nnoremap <buffer> <silent> q <Cmd>close<CR>
  nnoremap <buffer> <silent> do <Nop>
  nnoremap <buffer> <silent> dp <Nop>
  var show_cmd: string = 'git -C ' .. shellescape(root) .. ' show --stat --format=fuller ' .. shellescape(hash)
  silent execute 'read !' .. show_cmd
  if v:shell_error != 0
    close
    win_gotoid(pane_wid)
    Error('vproj: Failed to show commit ' .. hash)
    return
  endif
  cursor(1, 1)
  delete _
  setlocal nomodifiable
  setlocal nomodified

  win_gotoid(pane_wid)
  echom 'Commit: ' .. hash
enddef

def BuildLogLines(log_items: list<dict<any>>): list<string>
  var result: list<string> = []
  if empty(log_items)
    result->add('  (no commits)')
    return result
  endif
  var visible_idx: number = 0
  for item in log_items
    var nav: string = NavChar(item, visible_idx)
    var hash: string = item.hash
    var subject: string = item.subject
    var line: string = nav .. ' ' .. hash .. ' ' .. subject
    var w: number = strwidth(line)
    if w > pane_width
      line = strcharpart(line, 0, pane_width)
    elseif w < pane_width
      line = line .. repeat(' ', pane_width - w)
    endif
    result->add(line)
    visible_idx += 1
  endfor
  return result
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
  nnoremap <buffer> <silent> <nowait> j <Cmd>call vproj#SelectNext()<CR>
  nnoremap <buffer> <silent> <nowait> k <Cmd>call vproj#SelectPrev()<CR>
  nnoremap <buffer> <silent> h <Cmd>call vproj#NavigateUp()<CR>
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
  nnoremap <buffer> <silent> <S-L> <Cmd>call vproj#SwitchMode('log')<CR>

  # Toggle tree view
  nnoremap <buffer> <silent> T <Cmd>call vproj#ToggleTreeView()<CR>

  # Qfix / close (q in permanent mode closes pane; in temporary switches to qfix)
  nnoremap <buffer> <silent> <nowait> q <Cmd>call vproj#HandlePaneQ()<CR>

  # Include / exclude (code mode)
  nnoremap <buffer> <silent> + <Cmd>call vproj#IncludeItem()<CR>
  nnoremap <buffer> <silent> - <Cmd>call vproj#ExcludeItem()<CR>

  # Refresh
  nnoremap <buffer> <silent> <nowait> r <Cmd>call vproj#Refresh()<CR>

  # Preview toggle
  nnoremap <buffer> <silent> p <Cmd>call vproj#TogglePreview()<CR>

  # Paging
  nnoremap <buffer> <silent> <C-N> <Cmd>call vproj#NextPage()<CR>
  nnoremap <buffer> <silent> <C-P> <Cmd>call vproj#PrevPage()<CR>

  # Close buffer (buf mode)
  nnoremap <buffer> <silent> <nowait> x <Cmd>call vproj#CloseBuffer()<CR>

  # Nav indicator shift
  nnoremap <buffer> <silent> <nowait> > <Cmd>call vproj#ShiftNavForward()<CR>
  nnoremap <buffer> <silent> <lt> <Cmd>call vproj#ShiftNavBackward()<CR>

  # Filter
  nnoremap <buffer> <silent> / <Cmd>call vproj#PromptFilter()<CR>
  nnoremap <buffer> <silent> * <Cmd>call vproj#GrepSearch()<CR>

  # Nav indicator direct selection (alphanumeric chars only)
  for ch in NAV_CHARS
    if ch !~ '^[[:alnum:]]$'
      continue
    endif
    execute 'nnoremap <buffer> <silent> <nowait> ' .. ch .. ' <Cmd>call vproj#SelectByNavChar("' .. ch .. '")<CR>'
  endfor

  # Git: toggle status filter
  nnoremap <buffer> <silent> <C-G> <Cmd>call vproj#ToggleGitFilter()<CR>

  # Git: stage/unstage file
  nnoremap <buffer> <silent> <nowait> s <Cmd>call vproj#GitStageToggle()<CR>

  # Git: diff preview and discard
  nnoremap <buffer> <silent> <nowait> d <Cmd>call vproj#OpenDiffPreview()<CR>
  nnoremap <buffer> <silent> D <Cmd>call vproj#DiscardChanges()<CR>

  # Git: whole-repo actions
  nnoremap <buffer> <silent> <nowait> c <Cmd>call vproj#GitCommit()<CR>
  nnoremap <buffer> <silent> P <Cmd>call vproj#GitPush()<CR>
  nnoremap <buffer> <silent> U <Cmd>call vproj#GitPull()<CR>
  nnoremap <buffer> <silent> <nowait> b <Cmd>call vproj#GitBranchSwitch()<CR>

  # Git: stash and blame
  nnoremap <buffer> <silent> <nowait> z <Cmd>call vproj#GitStashPush()<CR>
  nnoremap <buffer> <silent> <nowait> Z <Cmd>call vproj#GitStashPop()<CR>
  nnoremap <buffer> <silent> a <Cmd>call vproj#GitBlame()<CR>

  # Close pane
  nnoremap <buffer> <silent> Q <Cmd>call vproj#PaneClose()<CR>

  # ESC closes pane in temporary mode
  nnoremap <buffer> <silent> <Esc> <Cmd>call vproj#HandleEsc()<CR>

  # Parent directory shortcut
  nnoremap <buffer> <silent> . <Cmd>call vproj#NavigateUp()<CR>
enddef

def SetupAutocommands(): void
  execute 'augroup ' .. AUTOGROUP
    autocmd!
    execute 'autocmd BufWipeout <buffer> call vproj#HandleBufWipeout()'
    autocmd DirChanged global call vproj#OnDirChanged()
    autocmd DirChanged window call vproj#OnDirChanged()
    autocmd ColorScheme * call vproj#DefineHighlights()
  augroup END
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
  # Highlight nav indicator characters in cyan (priority 11 = above cursorline)
  silent! match_ids->add(matchadd('VprojNavIndicator', '^[a-zA-Z0-9]', 11, MATCH_AUTO_ID))
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
enddef

# Session persistence
def SessionFilePath(): string
  var cache_val: any = getenv('XDG_CACHE_HOME')
  var cache: string = (type(cache_val) == v:t_string && !empty(cache_val)) ? cache_val : expand('~/.cache')
  return cache .. '/vproj/session'
enddef

def SaveSession(): void
  var path: string = SessionFilePath()
  var dir: string = fnamemodify(path, ':h')
  if !isdirectory(dir)
    try
      mkdir(dir, 'p')
    catch
      return
    endtry
  endif
  var lines: list<string> = []
  lines->add('mode=' .. current_mode)
  if !empty(current_dir)
    lines->add('dir=' .. current_dir)
  endif
  lines->add('width=' .. pane_width)
  lines->add('info=' .. (show_info_column ? '1' : '0'))
  lines->add('open=' .. pane_open_mode)
  lines->add('git_filter=' .. (git_filter_active ? '1' : '0'))
  var tmp: string = path .. '.tmp'
  try
    writefile(lines, tmp)
    rename(tmp, path)
  catch
    silent! delete(tmp)
  endtry
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
      if val == 'ind'
        val = 'log'
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
        pane_width = w
      endif
    elseif key == 'info'
      show_info_column = (val == '1')
    elseif key == 'open' && !empty(val)
      if val == 'temporary' || val == 'permanent'
        pane_open_mode = val
      endif
    elseif key == 'git_filter'
      git_filter_active = (val == '1')
    endif
  endfor
  if !empty(saved_mode)
    current_mode = saved_mode
    if current_mode == 'code'
      var vproj_path: string = FindVprojFile(current_dir)
      if !empty(vproj_path)
        project = ParseVprojFile(vproj_path)
        code_root = !empty(get(project, 'root', '')) ? get(project, 'root', '') : current_dir
      else
        project = {}
        code_root = current_dir
      endif
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

  # ── Mode labels — hardcoded backgrounds for visual distinction ──
  highlight default VprojModeFile ctermfg=0   ctermbg=178 cterm=bold guifg=#1A1A1A guibg=#D7AF00 gui=bold
  highlight default VprojModeBuf ctermfg=0   ctermbg=76  cterm=bold guifg=#1A1A1A guibg=#5FD700 gui=bold
  highlight default VprojModeCode ctermfg=0   ctermbg=75  cterm=bold guifg=#1A1A1A guibg=#5FAFFF gui=bold

  highlight default VprojModeQfix ctermfg=0   ctermbg=39  cterm=bold guifg=#1A1A1A guibg=#00AFFF gui=bold
  highlight default VprojModeLog ctermfg=0   ctermbg=44  cterm=bold guifg=#1A1A1A guibg=#00D7D7 gui=bold

  # ── Cursor, navigation, info ──
  highlight default link VprojCursorLine CursorLine
  highlight default link VprojNavIndicator Special
  highlight default link VprojInfoColumn Directory
  highlight default link VprojParentDir String
  highlight default link VprojDirName Directory
  highlight default link VprojSeparator Comment
  highlight default link VprojStatusLine StatusLine
enddef
