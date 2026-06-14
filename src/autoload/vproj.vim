vim9script

# autoload/vproj.vim — VPROJ project manager

# Script-local state
var pane_bufnr: number = -1
var pane_width: number = 40
var current_mode: string = 'file'
var selected_line: number = 1
var current_dir: string = ''
var items: list<dict<any>> = []

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

  cursor(selected_line, 1)
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
  selected_line = 1
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

  # Skip separator (line 2) and mode menu (line 1)
  var last: number = total
  while next_line <= last
    if next_line == 2 || next_line == 1
      next_line += 1
      continue
    endif
    break
  endwhile
  if next_line > last
    next_line = 3  # wrap to first item
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
    if prev_line == 2 || prev_line == 1
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

  # Mode menu line: switch mode based on cursor column
  if selected_line == 1
    var col: number = col('.')
    if col <= 6
      SwitchMode('file')
    elseif col <= 13
      SwitchMode('doc')
    else
      SwitchMode('code')
    endif
    return
  endif

  # Item selection — dispatch by mode
  var idx: number = selected_line - 3  # offset past menu + separator
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
  selected_line = 3  # reset to first item
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

  # Line 2: separator
  lines->add(repeat('-', pane_width))

  # Lines 3+: mode-specific items
  if current_mode == 'file'
    items = ReadDir(current_dir)
    lines->extend(BuildFileLines(items))
  elseif current_mode == 'doc'
    items = BufferList()
    lines->extend(BuildDocLines(items))
  endif

  setbufvar(pane_bufnr, '&modifiable', 1)
  deletebufline(pane_bufnr, 1, '$')
  setbufline(pane_bufnr, 1, lines)
  setbufvar(pane_bufnr, '&modifiable', 0)

  ClearPaneHighlights()
  HighlightCurrentMode()

  if selected_line > len(lines)
    selected_line = len(lines) > 2 ? 3 : 1
  endif
  if selected_line < 1
    selected_line = 1
  endif
  cursor(selected_line, 1)
enddef

def BuildModeMenu(): string
  var parts: list<string> = []
  for key in MODE_KEYS
    parts->add(get(MODE_LABELS, key, key))
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
      name = name[: name_width - 1]
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

export def NavigateUp(): void
  if current_dir == '/' || current_dir == ''
    return
  endif
  current_dir = fnamemodify(current_dir, ':h')
  selected_line = 3
  Render()
enddef

def NavigateInto(subdir: string): void
  var new_dir: string = current_dir .. '/' .. subdir
  if !isdirectory(new_dir)
    return
  endif
  current_dir = new_dir
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
  var blob: any = readblob(path, 0, 8192)
  if type(blob) != v:t_blob
    return false
  endif
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
      name = name[: name_width - 1]
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

# ──────────────────────────────────────────────
# Pane setup
# ──────────────────────────────────────────────

def SetupPaneMappings(): void
  if !IsPaneVisible()
    return
  endif

  # Navigation
  nnoremap <buffer> <silent> <Down> :call vproj#SelectNext()<CR>
  nnoremap <buffer> <silent> <Up> :call vproj#SelectPrev()<CR>
  nnoremap <buffer> <silent> j :call vproj#SelectNext()<CR>
  nnoremap <buffer> <silent> k :call vproj#SelectPrev()<CR>

  # Width
  nnoremap <buffer> <silent> <Right> :call vproj#PaneGrow()<CR>
  nnoremap <buffer> <silent> <Left> :call vproj#PaneShrink()<CR>

  # Activate / open
  nnoremap <buffer> <silent> <CR> :call vproj#SelectCurrent()<CR>

  # Close
  nnoremap <buffer> <silent> q :call vproj#PaneClose()<CR>
  nnoremap <buffer> <silent> <F4> :call vproj#PaneClose()<CR>

  # Parent directory shortcut
  nnoremap <buffer> <silent> . :call vproj#NavigateUp()<CR>
enddef

def SetupAutocommands(): void
  augroup VprojPane
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
