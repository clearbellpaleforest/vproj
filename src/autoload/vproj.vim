vim9script

# autoload/vproj.vim — VPROJ project manager

# Script-local state
var pane_bufnr: number = -1
var pane_width: number = 40
var current_mode: string = 'file'
var selected_line: number = 1
var current_dir: string = ''
var items: list<dict<any>> = []
var show_info_column: bool = true
var current_page: number = 0
var items_per_page: number = 1
var paging_active: bool = false
var nav_offset: number = 0

# Project state (code mode)
var project: dict<any> = {}
var code_root: string = ''
var project_prompted: bool = false

const MODE_KEYS: list<string> = ['file', 'doc', 'code']
const MODE_LABELS: dict<string> = {file: '[F]ile', doc: '[D]oc', code: '[C]ode'}
const NAV_CHARS: list<string> = [
  'a', 'b', 'c', 'd', 'e', 'g', 'i', 'm', 'n', 'o', 'p', 's', 't', 'u', 'v', 'w', 'y', 'z',
  'A', 'B', 'E', 'G', 'H', 'I', 'J', 'K', 'L', 'M', 'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z',
  '1', '2', '3', '4', '5', '6', '7', '8', '9',
]
const MIN_WIDTH: number = 20
const MAX_WIDTH: number = 80
const AUTOGROUP: string = 'VprojPane'
var match_ids: list<number> = []

def SortByName(A: dict<any>, B: dict<any>): number
  return tolower(A.name) < tolower(B.name) ? -1 : tolower(A.name) > tolower(B.name) ? 1 : 0
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
    PaneClose()
  else
    PaneOpen()
  endif
enddef

export def PaneOpen(): void
  if IsPaneVisible()
    return
  endif

  pane_width = get(g:, 'vproj_pane_width_default', 40)
  if pane_width < MIN_WIDTH | pane_width = MIN_WIDTH | endif
  if pane_width > MAX_WIDTH | pane_width = MAX_WIDTH | endif

  # Reuse existing buffer if it still exists
  DefineHighlights()
  if pane_bufnr > 0 && bufexists(pane_bufnr)
    execute 'topleft vert sbuffer ' .. pane_bufnr
    execute 'vert resize ' .. pane_width
    selected_line = FirstSelectableLine()
    SetupPaneMappings()
    Render()
    return
  endif

  var prev_buf: number = bufnr('%')
  execute 'topleft vert new'
  var new_buf: number = bufnr('%')
  if new_buf == prev_buf
    echom 'vproj: Could not create pane buffer'
    return
  endif
  pane_bufnr = new_buf

  setbufvar(pane_bufnr, '&buftype', 'nofile')
  setbufvar(pane_bufnr, '&bufhidden', 'wipe')
  setbufvar(pane_bufnr, '&swapfile', 0)
  setbufvar(pane_bufnr, '&buflisted', 0)
  setbufvar(pane_bufnr, '&modifiable', 0)
  setbufvar(pane_bufnr, '&cursorline', 0)
  setbufvar(pane_bufnr, '&number', 0)
  setbufvar(pane_bufnr, '&relativenumber', 0)
  setbufvar(pane_bufnr, '&signcolumn', 'no')
  setbufvar(pane_bufnr, '&winfixwidth', 1)
  setbufvar(pane_bufnr, '&foldenable', 0)
  setbufvar(pane_bufnr, '&wrap', 0)
  setbufvar(pane_bufnr, '&spell', 0)
  setbufvar(pane_bufnr, '&list', 0)

  silent! keepalt file VPROJ

  execute 'vert resize ' .. pane_width

  SetupAutocommands()
  current_dir = getcwd()
  if empty(current_dir)
    current_dir = expand('~')
  endif
  selected_line = FirstSelectableLine()
  Render()
  SetupPaneMappings()
enddef

export def PaneClose(): void
  items = []
  current_page = 0
  nav_offset = 0
  match_ids = []
  if pane_bufnr <= 0 || !bufexists(pane_bufnr)
    pane_bufnr = -1
    return
  endif

  var wnr: number = bufwinnr(pane_bufnr)
  if wnr > 0
    if winnr('$') < 2
      new
    endif
    win_execute(win_getid(wnr), 'close')
  endif
enddef

export def HandleBufWipeout(): void
  ClearPaneHighlights()
  match_ids = []
  pane_bufnr = -1
  selected_line = FirstSelectableLine()
  items = []
enddef

export def OnDirChanged(): void
  if !IsPaneVisible() || current_mode == 'code'
    return
  endif
  var cwd: string = getcwd()
  if cwd != current_dir
    current_dir = cwd
    selected_line = FirstSelectableLine()
    current_page = 0
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
  win_execute(win_getid(wnr), 'call cursor(' .. lnum .. ', 1)')
enddef

def SkipNonSelectable(line: number): bool
  if line == 1
    return true
  endif
  if current_mode != 'code' && line == 2
    return true
  endif
  if paging_active
    var total: number = getbufinfo(pane_bufnr)[0].linecount
    if line == total
      return true
    endif
  endif
  return false
enddef

def FirstSelectableLine(): number
  return 3
enddef

def ItemIndex(): number
  return (selected_line - FirstSelectableLine()) + (current_page * items_per_page)
enddef

export def SelectNext(): void
  if !IsPaneVisible()
    return
  endif

  var total: number = getbufinfo(pane_bufnr)[0].linecount
  var next_line: number = selected_line + 1

  while next_line <= total && SkipNonSelectable(next_line)
    next_line += 1
  endwhile
  if next_line > total
    next_line = FirstSelectableLine()
  endif

  selected_line = next_line
  MoveCursor(selected_line)
  ClearPaneHighlights()
  HighlightCurrentMode()
enddef

export def SelectPrev(): void
  if !IsPaneVisible()
    return
  endif

  var total: number = getbufinfo(pane_bufnr)[0].linecount
  var prev_line: number = selected_line - 1

  while prev_line >= 1 && SkipNonSelectable(prev_line)
    prev_line -= 1
  endwhile
  if prev_line < 1
    prev_line = total
  endif

  selected_line = prev_line
  MoveCursor(selected_line)
  ClearPaneHighlights()
  HighlightCurrentMode()
enddef

export def SelectFirst(): void
  if !IsPaneVisible()
    return
  endif
  selected_line = FirstSelectableLine()
  MoveCursor(selected_line)
  ClearPaneHighlights()
  HighlightCurrentMode()
enddef

export def SelectLast(): void
  if !IsPaneVisible()
    return
  endif
  var total: number = getbufinfo(pane_bufnr)[0].linecount
  if total < 1
    return
  endif
  selected_line = total
  while selected_line >= 1 && SkipNonSelectable(selected_line)
    selected_line -= 1
  endwhile
  MoveCursor(selected_line)
  ClearPaneHighlights()
  HighlightCurrentMode()
enddef

export def NavigateIntoFirstDir(): void
  if !IsPaneVisible()
    return
  endif
  for item in items
    if get(item, 'is_dir', false) && !get(item, 'is_parent', false)
      NavigateInto(item.name)
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
  var paginated = PaginateItems(items)
  var visible_idx = 0
  var line_offset = 0
  for item in paginated
    if !get(item, 'is_parent', false)
      var nc = NavChar(item, visible_idx)
      if nc[0] == ch
        selected_line = FirstSelectableLine() + line_offset
        MoveCursor(selected_line)
        ClearPaneHighlights()
        HighlightCurrentMode()
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
  if selected_line == 1
    var idx = index(MODE_KEYS, current_mode)
    var next_idx = (idx + 1) % len(MODE_KEYS)
    SwitchMode(MODE_KEYS[next_idx])
    return
  endif

  # Code mode: status line (line 2) triggers rename
  if current_mode == 'code' && selected_line == 2
    RenameProject()
    return
  endif

  # Item selection — dispatch by mode (account for pagination)
  var idx: number = ItemIndex()
  if idx < 0 || idx >= len(items)
    return
  endif

  var item: dict<any> = items[idx]
  if current_mode == 'file'
    if get(item, 'is_parent', false)
      NavigateUp()
    elseif get(item, 'is_dir', false)
      NavigateInto(item.name)
    else
      OpenFile(item.path)
    endif
  elseif current_mode == 'doc'
    if has_key(item, 'bufnr')
      OpenBuffer(item.bufnr)
    endif
  elseif current_mode == 'code'
    if get(item, 'is_parent', false)
      NavigateUp()
    elseif get(item, 'is_dir', false)
      NavigateInto(item.name)
    else
      OpenFile(item.path)
    endif
  endif
enddef

# ──────────────────────────────────────────────
# Mode switching
# ──────────────────────────────────────────────

export def SwitchMode(key: string): void
  if index(MODE_KEYS, key) < 0
    return
  endif
  current_mode = key
  if key != 'code'
    current_dir = getcwd()
  endif
  if key == 'code'
    var vproj_path: string = FindVprojFile(current_dir)
    if !empty(vproj_path)
      project = ParseVprojFile(vproj_path)
      code_root = !empty(project.root) ? project.root : current_dir
      project_prompted = false
    elseif empty(project) && !project_prompted
      project = {}
      code_root = current_dir
      AutoPromptCreateProject()
    endif
  endif
  selected_line = 3
  # Apply mode-specific width config if set
  var mode_width: number = 0
  if key == 'file'
    mode_width = get(g:, 'vproj_pane_width_file', 0)
  elseif key == 'doc'
    mode_width = get(g:, 'vproj_pane_width_doc', 0)
  elseif key == 'code'
    mode_width = get(g:, 'vproj_pane_width_code', 0)
  endif
  if mode_width >= MIN_WIDTH && mode_width <= MAX_WIDTH
    pane_width = mode_width
    ApplyWidth()
  endif
  current_page = 0
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

# ──────────────────────────────────────────────
# Display
# ──────────────────────────────────────────────

def Render(): void
  if !IsPaneVisible()
    return
  endif

  var lines: list<string> = []

  # Line 1: mode menu
  var menu: string = BuildModeMenu()
  lines->add(menu)

  # Line 2: separator (file/doc) or project status (code)
  if current_mode == 'code'
    items = CodeItems()
    var status: string
    if empty(project) || empty(project.name)
      status = '* (no project found)'
    else
      status = '* ' .. project.name
      if !empty(code_root) && code_root != project.root
        status = status .. '  ' .. code_root
      endif
    endif
    if strwidth(status) < pane_width
      status = status .. repeat(' ', pane_width - strwidth(status))
    endif
    lines->add(status)
    lines->extend(BuildCodeLines(PaginateItems(items)))
  else
    lines->add(repeat('-', pane_width))
    if current_mode == 'file'
      items = ReadDir(current_dir)
      lines->extend(BuildFileLines(PaginateItems(items)))
    elseif current_mode == 'doc'
      items = BufferList()
      lines->extend(BuildDocLines(PaginateItems(items)))
    endif
  endif

  if paging_active
    lines->add(BuildPageNavRow())
  endif

  setbufvar(pane_bufnr, '&modifiable', 1)
  deletebufline(pane_bufnr, 1, '$')
  setbufline(pane_bufnr, 1, lines)
  setbufvar(pane_bufnr, '&modifiable', 0)
  setbufvar(pane_bufnr, '&modified', 0)

  ClearPaneHighlights()
  HighlightCurrentMode()

  if selected_line > len(lines)
    selected_line = FirstSelectableLine()
  endif
  if selected_line < FirstSelectableLine()
    selected_line = FirstSelectableLine()
  endif
  MoveCursor(selected_line)
enddef

def BuildModeMenu(): string
  var parts: list<string> = []
  for key in MODE_KEYS
    parts->add(MODE_LABELS[key])
  endfor
  var line: string = join(parts, '  ')
  var w: number = strwidth(line)
  if w < pane_width
    line = line .. repeat(' ', pane_width - w)
  endif
  return line
enddef

def PaginateItems(full_items: list<dict<any>>): list<dict<any>>
  var win_height: number = winheight(bufwinnr(pane_bufnr))
  items_per_page = win_height - 2
  if items_per_page < 1
    items_per_page = 1
  endif
  if len(full_items) > items_per_page
    items_per_page = win_height - 3
    if items_per_page < 1
      items_per_page = 1
    endif
  endif
  paging_active = len(full_items) > items_per_page
  if !paging_active
    current_page = 0
    return full_items
  endif
  var total_pages = (len(full_items) + items_per_page - 1) / items_per_page
  if current_page >= total_pages
    current_page = total_pages - 1
  endif
  if current_page < 0
    current_page = 0
  endif
  var start_idx = current_page * items_per_page
  var end_idx = start_idx + items_per_page
  if end_idx > len(full_items)
    end_idx = len(full_items)
  endif
  return full_items[start_idx : end_idx]
enddef

def BuildPageNavRow(): string
  var total_pages = (len(items) + items_per_page - 1) / items_per_page
  if total_pages < 1
    total_pages = 1
  endif
  var text: string = printf(' >>> Page %d/%d  Ctrl-N Ctrl-P <<< ', current_page + 1, total_pages)
  var w: number = strwidth(text)
  if w < pane_width
    text = repeat(' ', (pane_width - w) / 2) .. text
  endif
  if strwidth(text) < pane_width
    text = text .. repeat(' ', pane_width - strwidth(text))
  endif
  return text
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
    echom 'vproj: Cannot read directory: ' .. norm_dir
    return result
  endtry
  if empty(entries)
    return result
  endif

  var dirs: list<dict<any>> = []
  var files: list<dict<any>> = []

  for entry in entries
    if entry[0] == '.' && !exists('g:vproj_show_dotfiles')
      continue
    endif
    var full: string = norm_dir .. '/' .. entry
    if isdirectory(full)
      dirs->add({name: entry, path: full, is_dir: true, size: 0})
    elseif getftype(full) == 'file'
      files->add({name: entry, path: full, is_dir: false, size: getfsize(full)})
    elseif getftype(full) == 'link' && getftype(resolve(full)) == 'file'
      files->add({name: entry, path: full, is_dir: false, size: getfsize(full)})
    endif
  endfor

  # Sort each group alphabetically, case-insensitive
  sort(dirs, 'SortByName')
  sort(files, 'SortByName')

  result->extend(dirs)
  result->extend(files)
  return result
enddef

def BuildFileLines(file_items: list<dict<any>>): list<string>
  var result: list<string> = []
  var info_width: number = show_info_column ? 5 : 0
  var visible_idx: number = 0

  for item in file_items
    var name: string = item.name
    if item.is_dir
      name = name .. '/'
    endif

    var info: string = ''
    if show_info_column && !item.is_dir
      info = FormatSize(item.size)
      info = repeat(' ', info_width - strwidth(info)) .. info
    endif

    # Build line with nav indicator prefix
    var indicator: string = NavChar(item, visible_idx)
    var name_width: number = pane_width - info_width - 2
    if strwidth(name) > name_width
      name = strcharpart(name, 0, name_width)
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

def FormatSize(bytes: number): string
  if bytes < 0
    return '    -'
  elseif bytes < 1000
    return printf('%5d', bytes)
  elseif bytes < 1000000
    return printf('%4dK', bytes / 1000)
  elseif bytes < 1000000000
    return printf('%4dM', bytes / 1000000)
  else
    return printf('%4dG', bytes / 1000000000)
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
  Render()
enddef

def OpenFile(path: string): void
  if !filereadable(path)
    echom 'vproj: Cannot read: ' .. path
    return
  endif
  # Check for binary (null bytes in first 8KB)
  if IsBinary(path)
    echohl WarningMsg
    echom 'vproj: Binary file: ' .. fnamemodify(path, ':t')
    echohl None
    return
  endif
  if winnr('$') < 2
    rightbelow split
  else
    wincmd p
  endif
  execute 'edit ' .. fnameescape(path)
  wincmd p
enddef

def IsBinary(path: string): bool
  # Resolve symlinks — readblob() on FIFO/socket hangs Vim
  var resolved: string = resolve(path)
  var ftype: string = getftype(resolved)
  if ftype != 'file' && ftype != ''
    return false
  endif
  var blob: blob
  try
    blob = readblob(path, 0, 8192)
  catch
    echom 'vproj: Cannot read binary check: ' .. path
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

def BuildDocLines(buf_items: list<dict<any>>): list<string>
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
  if winnr('$') < 2
    rightbelow split
  else
    wincmd p
  endif
  execute 'buffer ' .. bufnr
  wincmd p
enddef

export def Refresh(): void
  if !IsPaneVisible()
    return
  endif
  Render()
enddef

export def ToggleInfoColumn(): void
  show_info_column = !show_info_column
  if IsPaneVisible()
    Render()
  endif
enddef

export def NextPage(): void
  if !IsPaneVisible() || !paging_active
    return
  endif
  var total_pages = (len(items) + items_per_page - 1) / items_per_page
  if total_pages <= 1
    return
  endif
  current_page = (current_page + 1) % total_pages
  selected_line = FirstSelectableLine()
  Render()
enddef

export def PrevPage(): void
  if !IsPaneVisible() || !paging_active
    return
  endif
  var total_pages = (len(items) + items_per_page - 1) / items_per_page
  if total_pages <= 1
    return
  endif
  current_page = current_page - 1
  if current_page < 0
    current_page = total_pages - 1
  endif
  selected_line = FirstSelectableLine()
  Render()
enddef

export def CloseBuffer(): void
  if current_mode != 'doc' || !IsPaneVisible()
    echom 'vproj: x closes buffers in doc mode only (press D for doc mode)'
    return
  endif
  var idx: number = ItemIndex()
  if idx < 0 || idx >= len(items)
    return
  endif
  var item: dict<any> = items[idx]
  if has_key(item, 'bufnr')
    execute 'bdelete ' .. item.bufnr
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
  var d: string = fnamemodify(dir, ':p')
  while d != '' && d != '/'
    # Check exact .vproj first (fast stat, no directory scan)
    var exact: string = d .. '.vproj'
    if filereadable(exact)
      return exact
    endif
    # Fall back to wildcard pattern for hand-named .vproj files
    var matches = glob(d .. '/*.vproj', 0, 1)
    if matches->len() > 0
      return matches[0]
    endif
    d = fnamemodify(d, ':h')
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
    echom 'vproj: Cannot read project file: ' .. path
    return p
  endtry

  for line in file_lines
    var t: string = line->substitute('^\s\+', '', '')->substitute('\s\+$', '', '')
    if empty(t) || t[0] == '#'
      continue
    endif

    # Check if line starts with a known section header
    var matched_section: string = ''
    for key in keys(SECTION_MAP)
      if tolower(t) =~ '^' .. escape(key, ' ') .. '\s*:'
        matched_section = SECTION_MAP[key]
        # Extract value after colon for name/root inline format
        var after_colon: string = t->substitute('^[^:]*:\s*', '', '')
        if !empty(after_colon) && (matched_section == 'name' || matched_section == 'root')
          p[matched_section] = after_colon
          if matched_section == 'root'
            p[matched_section] = p[matched_section]->substitute('/*$', '', '')
            p[matched_section] = expand(p[matched_section])
          endif
          section = ''
        else
          section = matched_section
        endif
        break
      endif
    endfor
    if !empty(matched_section)
      continue
    endif

    if section == 'name' || section == 'root'
      p[section] = t
      if section == 'root'
        p[section] = p[section]->substitute('/*$', '', '')
        p[section] = expand(p[section])
      endif
      section = ''
    elseif !empty(section)
      p[section]->add(t)
    endif
  endfor
  return p
enddef

def WriteVprojFile(): void
  if empty(project) || !has_key(project, 'vproj_file')
    return
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
    if rename(tmp, project.vproj_file) != 0
      echohl WarningMsg
      echom 'vproj: Failed to write project file: ' .. project.vproj_file
      echohl None
      silent! delete(tmp)
    endif
  else
    echohl WarningMsg
    echom 'vproj: Failed to write ' .. project.vproj_file
    echohl None
  endif
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
    echom 'vproj: Cannot read directory: ' .. code_root
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
    if entry[0] == '.' && !exists('g:vproj_show_dotfiles')
      continue
    endif
    var full: string = code_root .. '/' .. entry
    var is_dir: bool = isdirectory(full)
    if !is_dir && getftype(full) != 'file'
      if getftype(full) != 'link' || getftype(resolve(full)) != 'file'
	continue
      endif
    endif
    var item: dict<any> = {
      name: entry,
      path: full,
      is_dir: is_dir,
    }
    var rel: string = RelPath(full)
    if !empty(project)
        && project.excluded_dirs->index(rel) < 0
        && project.excluded_files->index(rel) < 0
        && (project.included_dirs->index(rel) >= 0 || project.included_files->index(rel) >= 0)
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

  sort(dirs_included, 'SortByName')
  sort(files_included, 'SortByName')
  sort(dirs_other, 'SortByName')
  sort(files_other, 'SortByName')

  result->extend(dirs_included)
  result->extend(files_included)
  result->extend(dirs_other)
  result->extend(files_other)
  return result
enddef

def BuildCodeLines(code_items: list<dict<any>>): list<string>
  var result: list<string> = []
  var label_width: number = 4  # "X + " or "X - " or "    "
  var visible_idx: number = 0

  for item in code_items
    var is_parent: bool = get(item, 'is_parent', false)
    var indicator: string = NavChar(item, visible_idx)
    var prefix: string
    if is_parent
      prefix = '    '
    elseif get(item, 'included', false)
      prefix = indicator .. '+ '
    else
      prefix = indicator .. '- '
    endif

    var name: string = item.name
    if get(item, 'is_dir', false) && !is_parent
      name = name .. '/'
    endif

    # Non-included items in parentheses
    if !get(item, 'included', false) && !is_parent
      name = '(' .. name .. ')'
    endif

    var name_width: number = pane_width - label_width
    if strwidth(name) > name_width
      name = strcharpart(name, 0, name_width)
    endif
    var line: string = prefix .. name
    var w: number = strwidth(line)
    if w < pane_width
      line = line .. repeat(' ', pane_width - w)
    endif
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
  var idx: number = ItemIndex()
  if idx < 0 || idx >= len(items)
    return
  endif
  var item: dict<any> = items[idx]
  if get(item, 'is_parent', false)
    return
  endif

  var currently_included = get(item, 'included', false)
  if action == 'include' && currently_included
    return
  endif
  if action == 'exclude' && !currently_included
    return
  endif

  var rel = RelPath(item.path)
  var inc = project.included_dirs
  var exc = project.excluded_dirs
  if !get(item, 'is_dir', false)
    inc = project.included_files
    exc = project.excluded_files
  endif

  if currently_included
    var i1 = inc->index(rel)
    if i1 >= 0
      inc->remove(i1)
    endif
    if exc->index(rel) < 0
      exc->add(rel)
    endif
    var opp_exc = get(item, 'is_dir', false) ? project.excluded_files : project.excluded_dirs
    var iopp = opp_exc->index(rel)
    if iopp >= 0
      opp_exc->remove(iopp)
    endif
  else
    var i2 = exc->index(rel)
    if i2 >= 0
      exc->remove(i2)
    endif
    if inc->index(rel) < 0
      inc->add(rel)
    endif
    var opp_inc = get(item, 'is_dir', false) ? project.included_files : project.included_dirs
    var iopp = opp_inc->index(rel)
    if iopp >= 0
      opp_inc->remove(iopp)
    endif
  endif

  WriteVprojFile()
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

var is_interactive: number = -1

def AutoPromptCreateProject(): void
  if is_interactive < 0
    is_interactive = system('test -t 0; echo $?')->trim() == '0' ? 1 : 0
  endif
  if !is_interactive
    return
  endif
  var vproj_path: string = FindVprojFile(current_dir)
  if !empty(vproj_path)
    return
  endif
  var answer = input('No .vproj found. Create one? (y/N): ')
  if answer != 'y' && answer != 'Y'
    project_prompted = true
    return
  endif
  var dirname = fnamemodify(current_dir, ':t')
  var proj_name = input('Project name: ', dirname)
  if empty(proj_name)
    project_prompted = true
    return
  endif
  if proj_name =~ '[/\\]'
    echom 'vproj: Project name cannot contain path separators'
    return
  endif
  project = {
    name: proj_name,
    root: current_dir,
    vproj_file: current_dir .. '/' .. proj_name .. '.vproj',
    included_dirs: [],
    included_files: [],
    excluded_dirs: [],
    excluded_files: [],
  }
  code_root = current_dir
  WriteVprojFile()
  current_mode = 'code'
  selected_line = 2
  current_page = 0
enddef

export def RenameProject(): void
  if current_mode != 'code' || !IsPaneVisible()
    return
  endif

  var default_name = !empty(get(project, 'name', '')) ? project.name : fnamemodify(current_dir, ':t')
  var new_name = input('Project name: ', default_name)
  if empty(new_name) || new_name == default_name
    return
  endif
  if new_name =~ '[/\\]'
    echom 'vproj: Project name cannot contain path separators'
    return
  endif

  if empty(project)
    project = {name: new_name, root: current_dir, vproj_file: current_dir .. '/' .. new_name .. '.vproj', included_dirs: [], included_files: [], excluded_dirs: [], excluded_files: []}
    code_root = current_dir
  else
    var old = project.vproj_file
    project.name = new_name
    project.vproj_file = fnamemodify(old, ':h') .. '/' .. new_name .. '.vproj'
    if old != project.vproj_file && filereadable(old)
      if delete(old) != 0
        echom 'vproj: Warning: Could not delete ' .. old
      endif
    endif
  endif

  WriteVprojFile()
  Render()
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
  nnoremap <buffer> <silent> j <Cmd>call vproj#SelectNext()<CR>
  nnoremap <buffer> <silent> k <Cmd>call vproj#SelectPrev()<CR>
  nnoremap <buffer> <silent> h <Cmd>call vproj#NavigateUp()<CR>
  nnoremap <buffer> <silent> l <Cmd>call vproj#SelectCurrent()<CR>
  nnoremap <buffer> <silent> <C-T> <Cmd>call vproj#SelectFirst()<CR>
  nnoremap <buffer> <silent> <C-B> <Cmd>call vproj#SelectLast()<CR>
  nnoremap <buffer> <silent> <C-K> <Cmd>call vproj#NavigateUp()<CR>
  nnoremap <buffer> <silent> <C-J> <Cmd>call vproj#NavigateIntoFirstDir()<CR>

  # Width
  nnoremap <buffer> <silent> <Right> <Cmd>call vproj#PaneGrow()<CR>
  nnoremap <buffer> <silent> <Left> <Cmd>call vproj#PaneShrink()<CR>

  # Activate / open
  nnoremap <buffer> <silent> <CR> <Cmd>call vproj#SelectCurrent()<CR>

  # Mode switching
  nnoremap <buffer> <silent> F <Cmd>call vproj#SwitchMode('file')<CR>
  nnoremap <buffer> <silent> D <Cmd>call vproj#SwitchMode('doc')<CR>
  nnoremap <buffer> <silent> C <Cmd>call vproj#SwitchMode('code')<CR>

  # Include / exclude (code mode)
  nnoremap <buffer> <silent> + <Cmd>call vproj#IncludeItem()<CR>
  nnoremap <buffer> <silent> - <Cmd>call vproj#ExcludeItem()<CR>

  # Refresh
  nnoremap <buffer> <silent> r <Cmd>call vproj#Refresh()<CR>

  # Toggle info column
  nnoremap <buffer> <silent> <F1> <Cmd>call vproj#ToggleInfoColumn()<CR>

  # Paging
  nnoremap <buffer> <silent> <C-N> <Cmd>call vproj#NextPage()<CR>
  nnoremap <buffer> <silent> <C-P> <Cmd>call vproj#PrevPage()<CR>

  # Close buffer (doc mode)
  nnoremap <buffer> <silent> x <Cmd>call vproj#CloseBuffer()<CR>

  # Nav indicator shift
  nnoremap <buffer> <silent> <TAB> <Cmd>call vproj#ShiftNavForward()<CR>
  nnoremap <buffer> <silent> <S-TAB> <Cmd>call vproj#ShiftNavBackward()<CR>

  # Nav indicator direct selection
  for ch in NAV_CHARS
    execute 'nnoremap <buffer> <silent> ' .. ch .. ' <Cmd>call vproj#SelectByNavChar("' .. ch .. '")<CR>'
  endfor

  # Close pane
  nnoremap <buffer> <silent> q <Cmd>call vproj#PaneClose()<CR>
  nnoremap <buffer> <silent> <F4> <Cmd>call vproj#PaneClose()<CR>

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

def HighlightCurrentMode(): void
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
  win_gotoid(win_getid(wnr))
  match_ids->add(matchadd('VprojModeCurrent', pattern, 10, -1))
  # Highlight selected line (cursorline replacement, skips menu/separator)
  var cur_pattern: string = '\%' .. selected_line .. 'l'
  match_ids->add(matchadd('VprojCursorLine', cur_pattern, 9, -1))
  # Highlight nav indicator characters in cyan
  match_ids->add(matchadd('VprojNavIndicator', '^\(\a\|\d\)', 8, -1))
  win_gotoid(orig_wid)
enddef

def ClearPaneHighlights(): void
  # Always clear the ID list, even if deletion fails (stale window IDs)
  var ids_to_clear: list<number> = match_ids
  match_ids = []
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
  execute 'vert resize ' .. pane_width
  win_gotoid(orig_wid)
enddef

export def DefineHighlights(): void
  highlight default VprojModeCurrent cterm=bold,underline gui=bold,underline
  highlight default VprojCursorLine cterm=reverse gui=reverse
  highlight default VprojNavIndicator ctermfg=cyan guifg=cyan
  highlight default VprojInfoColumn ctermfg=green guifg=green
  highlight default VprojParentDir ctermfg=blue guifg=blue
  highlight default VprojDirName cterm=bold gui=bold
  highlight default VprojSeparator ctermfg=darkgrey guifg=darkgrey
  highlight default VprojStatusLine cterm=reverse gui=reverse
enddef
