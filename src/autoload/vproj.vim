vim9script

# autoload/vproj.vim — VPROJ project manager

# Script-local state
var pane_bufnr: number = -1
var pane_width: number = 40
var current_mode: string = 'file'
var selected_line: number = 1
var current_dir: string = ''
var items: list<dict<any>> = []

# Project state (code mode)
var project: dict<any> = {}
var code_root: string = ''

const MODE_KEYS: list<string> = ['file', 'doc', 'code']
const MODE_LABELS: dict<string> = {file: '[F]ile', doc: '[D]oc', code: '[C]ode'}
const MIN_WIDTH: number = 20
const MAX_WIDTH: number = 80
const AUTOGROUP: string = 'VprojPane'

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

  # Reuse existing buffer if it still exists
  if pane_bufnr > 0 && bufexists(pane_bufnr)
    execute 'topleft vert sbuffer ' .. pane_bufnr
    execute 'vert resize ' .. pane_width
    Render()
    return
  endif

  execute 'topleft vert new'
  pane_bufnr = bufnr('%')

  setbufvar(pane_bufnr, '&buftype', 'nofile')
  setbufvar(pane_bufnr, '&bufhidden', 'wipe')
  setbufvar(pane_bufnr, '&swapfile', 0)
  setbufvar(pane_bufnr, '&buflisted', 0)
  setbufvar(pane_bufnr, '&modifiable', 0)
  setbufvar(pane_bufnr, '&cursorline', 1)
  setbufvar(pane_bufnr, '&number', 0)
  setbufvar(pane_bufnr, '&relativenumber', 0)
  setbufvar(pane_bufnr, '&signcolumn', 'no')
  setbufvar(pane_bufnr, '&winfixwidth', 1)

  silent! keepalt file VPROJ

  execute 'vert resize ' .. pane_width

  SetupAutocommands()
  current_dir = getcwd()
  if empty(current_dir)
    current_dir = expand('~')
  endif
  Render()
  SetupPaneMappings()
enddef

export def PaneClose(): void
  if pane_bufnr <= 0 || !bufexists(pane_bufnr)
    pane_bufnr = -1
    return
  endif

  var wnr: number = bufwinnr(pane_bufnr)
  if wnr > 0
    win_execute(win_getid(wnr), 'close')
  endif
enddef

export def HandleBufWipeout(): void
  pane_bufnr = -1
  selected_line = 3
enddef

# ──────────────────────────────────────────────
# Navigation
# ──────────────────────────────────────────────

export def SelectNext(): void
  if !IsPaneVisible()
    return
  endif

  var total: number = line('$', pane_bufnr)
  var next_line: number = selected_line + 1

  while next_line <= total
    if next_line == 1 || (current_mode != 'code' && next_line == 2)
      next_line += 1
      continue
    endif
    break
  endwhile
  if next_line > total
    next_line = (current_mode == 'code') ? 2 : 3
  endif

  selected_line = next_line
  cursor(selected_line, 1)
enddef

export def SelectPrev(): void
  if !IsPaneVisible()
    return
  endif

  var total: number = line('$', pane_bufnr)
  var prev_line: number = selected_line - 1

  while prev_line >= 1
    if prev_line == 1 || (current_mode != 'code' && prev_line == 2)
      prev_line -= 1
      continue
    endif
    break
  endwhile
  if prev_line < 1
    prev_line = total
  endif

  selected_line = prev_line
  cursor(selected_line, 1)
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

  # Item selection — dispatch by mode
  var idx: number = selected_line - 3  # offset past menu + separator/status
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
  if key == 'code' && empty(project)
    LoadProject()
  endif
  selected_line = (key == 'code') ? 2 : 3
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
    lines->add(BuildProjectStatusLine())
    lines->extend(BuildCodeLines(items))
  else
    lines->add(repeat('-', pane_width))
    if current_mode == 'file'
      items = ReadDir(current_dir)
      lines->extend(BuildFileLines(items))
    elseif current_mode == 'doc'
      items = BufferList()
      lines->extend(BuildDocLines(items))
    endif
  endif

  setbufvar(pane_bufnr, '&modifiable', 1)
  deletebufline(pane_bufnr, 1, '$')
  setbufline(pane_bufnr, 1, lines)
  setbufvar(pane_bufnr, '&modifiable', 0)

  ClearPaneHighlights()
  HighlightCurrentMode()

  if selected_line > len(lines)
    if current_mode == 'code'
      selected_line = len(lines) >= 2 ? 2 : 1
    else
      selected_line = len(lines) > 2 ? 3 : 1
    endif
  endif
  if selected_line < 1
    selected_line = 1
  endif
  cursor(selected_line, 1)
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

def ReadDir(dir: string): list<dict<any>>
  var result: list<dict<any>> = []

  # Parent directory entry (unless at filesystem root)
  if dir != '/' && dir != ''
    result->add({name: '..', path: fnamemodify(dir, ':h'), is_parent: true, is_dir: true, size: 0})
  endif

  var entries: list<string> = readdir(dir)
  if empty(entries)
    return result
  endif

  var dirs: list<dict<any>> = []
  var files: list<dict<any>> = []

  for entry in entries
    var full: string = dir .. '/' .. entry
    if isdirectory(full)
      dirs->add({name: entry, path: full, is_dir: true, size: 0})
    else
      files->add({name: entry, path: full, is_dir: false, size: getfsize(full)})
    endif
  endfor

  # Sort each group alphabetically, case-insensitive
  var SortFn = (a: dict<any>, b: dict<any>): number =>
        tolower(a.name) < tolower(b.name) ? -1 : tolower(a.name) > tolower(b.name) ? 1 : 0

  sort(dirs, SortFn)
  sort(files, SortFn)

  result->extend(dirs)
  result->extend(files)
  return result
enddef

def BuildFileLines(file_items: list<dict<any>>): list<string>
  var result: list<string> = []
  var info_width: number = 5

  for item in file_items
    var name: string = item.name
    if item.is_dir
      name = name .. '/'
    endif

    var info: string = ''
    if !item.is_dir
      info = FormatSize(item.size)
    endif
    # Right-align info column
    info = repeat(' ', info_width - strwidth(info)) .. info

    # Build line: "  name  ...  info"
    var name_width: number = pane_width - info_width - 1
    if strwidth(name) > name_width
      name = strcharpart(name, 0, name_width)
    endif
    var line: string = '  ' .. name
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
  selected_line = 3
  Render()
enddef

def NavigateInto(subdir: string): void
  var root = CurrentRoot()
  var new_dir: string = root .. '/' .. subdir
  if !isdirectory(new_dir)
    return
  endif
  if current_mode == 'code'
    code_root = new_dir
  else
    current_dir = new_dir
  endif
  selected_line = 3
  Render()
enddef

def OpenFile(path: string): void
  if !filereadable(path)
    return
  endif
  # Check for binary (null bytes in first 8KB)
  if IsBinary(path)
    echohl WarningMsg
    echo 'Binary file: ' .. fnamemodify(path, ':t')
    echohl None
    return
  endif
  PaneClose()
  execute 'edit ' .. fnameescape(path)
enddef

def IsBinary(path: string): bool
  var blob: blob = readblob(path, 0, 8192)
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
  var flag_width: number = 6

  for item in buf_items
    var flags: string = ''
    flags = flags .. (item.current ? '%' : ' ')
    flags = flags .. (item.modified ? '+' : ' ')
    flags = flags .. ' ' .. printf('%4d', item.linecount)

    var name: string = item.name
    var name_width: number = pane_width - flag_width - 1
    if strwidth(name) > name_width
      name = strcharpart(name, 0, name_width)
    endif
    var line: string = '  ' .. name
    var pad: number = pane_width - strwidth(line) - strwidth(flags)
    if pad > 0
      line = line .. repeat(' ', pad)
    endif
    line = line .. flags
    result->add(line)
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
  PaneClose()
  execute 'buffer ' .. bufnr
enddef

export def Refresh(): void
  if !IsPaneVisible()
    return
  endif
  Render()
enddef

export def CloseBuffer(): void
  if current_mode != 'doc' || !IsPaneVisible()
    return
  endif
  var idx: number = selected_line - 3
  if idx < 0 || idx >= len(items)
    return
  endif
  var item: dict<any> = items[idx]
  if has_key(item, 'bufnr')
    silent! execute 'bdelete ' .. item.bufnr
    selected_line = 3
    Render()
  endif
enddef

# ──────────────────────────────────────────────
# .vproj file I/O
# ──────────────────────────────────────────────

def FindVprojFile(dir: string): string
  var d: string = dir
  while d != '' && d != '/' && d != '/home'
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

def ParseVprojFile(path: string): dict<any>
  var p: dict<any> = {
    name: '', root: '', vproj_file: path,
    included_dirs: [], included_files: [],
    excluded_dirs: [], excluded_files: [],
  }
  if !filereadable(path) | return p | endif

  var section: string = ''
  for line in readfile(path)
    var t: string = line->substitute('^\s\+', '', '')->substitute('\s\+$', '', '')
    if empty(t) || t[0] == '#' | continue | endif

    if t =~ ':$'
      section = get(SECTION_MAP, tolower(t->substitute(':$', '', '')), '')
      continue
    endif

    if section == 'name' || section == 'root'
      p[section] = t
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
    rename(tmp, project.vproj_file)
  endif
enddef

# ──────────────────────────────────────────────
# Code mode
# ──────────────────────────────────────────────

def LoadProject(): void
  var vproj_path: string = FindVprojFile(current_dir)
  if !empty(vproj_path)
    project = ParseVprojFile(vproj_path)
    if !empty(project.root)
      code_root = project.root
    else
      code_root = current_dir
    endif
  else
    project = {}
    code_root = current_dir
  endif
enddef

def RelPath(full: string): string
  var rel: string = full
  if !empty(project.root) && rel->stridx(project.root) == 0
    rel = rel[project.root->len() :]->substitute('^/', '', '')
  endif
  return rel
enddef

def IsItemIncluded(item: dict<any>): bool
  if empty(project) | return false | endif
  var rel = RelPath(item.path)
  if project.excluded_dirs->index(rel) >= 0 || project.excluded_files->index(rel) >= 0
    return false
  endif
  return project.included_dirs->index(rel) >= 0 || project.included_files->index(rel) >= 0
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

  var entries: list<string> = readdir(code_root)
  if empty(entries)
    return result
  endif

  var dirs_included: list<dict<any>> = []
  var files_included: list<dict<any>> = []
  var dirs_other: list<dict<any>> = []
  var files_other: list<dict<any>> = []

  for entry in entries
    var full: string = code_root .. '/' .. entry
    var is_dir: bool = isdirectory(full)
    var item: dict<any> = {
      name: entry,
      path: full,
      is_dir: is_dir,
      size: is_dir ? 0 : getfsize(full),
    }
    item.included = IsItemIncluded(item)

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

  var SortFn = (a: dict<any>, b: dict<any>): number =>
        tolower(a.name) < tolower(b.name) ? -1 : tolower(a.name) > tolower(b.name) ? 1 : 0

  sort(dirs_included, SortFn)
  sort(files_included, SortFn)
  sort(dirs_other, SortFn)
  sort(files_other, SortFn)

  result->extend(dirs_included)
  result->extend(files_included)
  result->extend(dirs_other)
  result->extend(files_other)
  return result
enddef

def BuildCodeLines(code_items: list<dict<any>>): list<string>
  var result: list<string> = []
  var label_width: number = 4  # "  + " or "  - " or "    "

  for item in code_items
    var is_parent: bool = get(item, 'is_parent', false)
    var prefix: string
    if is_parent
      prefix = '    '
    elseif get(item, 'included', false)
      prefix = '  + '
    else
      prefix = '  - '
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
  endfor

  if empty(result)
    result->add('  (empty)')
  endif

  return result
enddef

def BuildProjectStatusLine(): string
  if empty(project) || empty(project.name)
    var line: string = '* (no project found)'
    if strwidth(line) < pane_width
      line = line .. repeat(' ', pane_width - strwidth(line))
    endif
    return line
  endif

  var line: string = project.name
  if !empty(code_root) && code_root != project.root
    line = line .. '  ' .. code_root
  endif
  if strwidth(line) < pane_width
    line = line .. repeat(' ', pane_width - strwidth(line))
  endif
  return line
enddef

def ToggleList(list_a: list<string>, list_b: list<string>, rel: string): void
  var i = list_a->index(rel)
  if i >= 0 | list_a->remove(i) | endif
  if list_b->index(rel) < 0 | list_b->add(rel) | endif
enddef

export def ToggleInclude(): void
  if current_mode != 'code' || !IsPaneVisible() | return | endif
  var idx: number = selected_line - 3
  if idx < 0 || idx >= len(items) | return | endif
  var item: dict<any> = items[idx]
  if get(item, 'is_parent', false) | return | endif

  var rel = RelPath(item.path)
  var inc = project.included_dirs
  var exc = project.excluded_dirs
  if !get(item, 'is_dir', false)
    inc = project.included_files
    exc = project.excluded_files
  endif

  if get(item, 'included', false)
    ToggleList(inc, exc, rel)
  else
    ToggleList(exc, inc, rel)
  endif

  WriteVprojFile()
  Render()
enddef

export def RenameProject(): void
  if current_mode != 'code' || !IsPaneVisible() | return | endif

  var default_name = !empty(get(project, 'name', '')) ? project.name : fnamemodify(current_dir, ':t')
  var new_name = input('Project name: ', default_name)
  if empty(new_name) || new_name == default_name | return | endif

  if empty(project)
    project = {name: new_name, root: current_dir, vproj_file: current_dir .. '/' .. new_name .. '.vproj', included_dirs: [], included_files: [], excluded_dirs: [], excluded_files: []}
    code_root = current_dir
  else
    var old = project.vproj_file
    project.name = new_name
    project.vproj_file = fnamemodify(old, ':h') .. '/' .. new_name .. '.vproj'
    if old != project.vproj_file && filereadable(old) | delete(old) | endif
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

  # Width
  nnoremap <buffer> <silent> <Right> <Cmd>call vproj#PaneGrow()<CR>
  nnoremap <buffer> <silent> <Left> <Cmd>call vproj#PaneShrink()<CR>

  # Activate / open
  nnoremap <buffer> <silent> <CR> <Cmd>call vproj#SelectCurrent()<CR>

  # Mode switching
  nnoremap <buffer> <silent> <S-F> <Cmd>call vproj#SwitchMode('file')<CR>
  nnoremap <buffer> <silent> <S-D> <Cmd>call vproj#SwitchMode('doc')<CR>
  nnoremap <buffer> <silent> <S-C> <Cmd>call vproj#SwitchMode('code')<CR>

  # Include / exclude (code mode)
  nnoremap <buffer> <silent> + <Cmd>call vproj#ToggleInclude()<CR>
  nnoremap <buffer> <silent> - <Cmd>call vproj#ToggleInclude()<CR>

  # Refresh
  nnoremap <buffer> <silent> r <Cmd>call vproj#Refresh()<CR>

  # Close buffer (doc mode)
  nnoremap <buffer> <silent> d <Cmd>call vproj#CloseBuffer()<CR>

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
  var orig_wid: number = win_getid()
  win_gotoid(win_getid(wnr))
  silent! matchadd('VprojModeCurrent', pattern, 10, -1)
  win_gotoid(orig_wid)
enddef

def ClearPaneHighlights(): void
  if !IsPaneVisible()
    return
  endif
  var wnr: number = bufwinnr(pane_bufnr)
  var orig_wid: number = win_getid()
  win_gotoid(win_getid(wnr))
  silent! clearmatches()
  win_gotoid(orig_wid)
enddef

def ApplyWidth(): void
  if !IsPaneVisible()
    return
  endif
  var wnr: number = bufwinnr(pane_bufnr)
  var orig_wid: number = win_getid()
  win_gotoid(win_getid(wnr))
  execute 'vert resize ' .. pane_width
  win_gotoid(orig_wid)
enddef

export def DefineHighlights(): void
  if hlexists('VprojModeCurrent')
    return
  endif
  highlight VprojModeCurrent cterm=bold,underline gui=bold,underline
enddef
