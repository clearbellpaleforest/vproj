vim9script

# Module-level state
var Pins: list<string> = []
var Bookmarks: list<dict<any>> = []
var RecentSymbols: list<dict<any>> = []
var Config: dict<any> = {}

# ──────────────────────────────────────────────
# Setup
# ──────────────────────────────────────────────

export def Setup(cfg: dict<any>)
  Config = cfg
  Pins = []
  Bookmarks = []
  RecentSymbols = []
enddef

# ──────────────────────────────────────────────
# Pinned buffers
# ──────────────────────────────────────────────

export def PinBuffer(): bool
  var path = expand('%:p')
  if empty(path) || index(Pins, path) >= 0
    return false
  endif
  add(Pins, path)
  return true
enddef

export def UnpinBuffer(): bool
  var path = expand('%:p')
  var idx = index(Pins, path)
  if idx < 0
    return false
  endif
  remove(Pins, idx)
  return true
enddef

export def IsPinned(path: string): bool
  return index(Pins, path) >= 0
enddef

export def GetPinned(): list<string>
  return copy(Pins)
enddef

# ──────────────────────────────────────────────
# Bookmarks
# ──────────────────────────────────────────────

export def AddBookmark(name: string): bool
  var path = expand('%:p')
  if empty(path)
    return false
  endif
  var pos = getcurpos()
  var bm: dict<any> = {
    name: name,
    path: path,
    line: pos[1],
    col: pos[2],
    timestamp: localtime(),
  }
  if empty(name)
    return false
  endif
  # Update existing bookmark with the same name, or add new
  for idx in range(len(Bookmarks))
    if has_key(Bookmarks[idx], 'name') && Bookmarks[idx].name == name
      Bookmarks[idx] = bm
      return true
    endif
  endfor
  add(Bookmarks, bm)
  return true
enddef

export def JumpToBookmark(name: string): bool
  for bm in Bookmarks
    if has_key(bm, 'name') && bm.name == name
      if !has_key(bm, 'path') || type(bm.path) != v:t_string || empty(bm.path)
        return false
      endif
      execute 'edit! ' .. fnameescape(bm.path)
      var line: number = get(bm, 'line', 1)
      var col: number = get(bm, 'col', 1)
      if type(line) == v:t_number && type(col) == v:t_number
        cursor(line, col)
      endif
      return true
    endif
  endfor
  return false
enddef

export def GetBookmarks(): list<dict<any>>
  return copy(Bookmarks)
enddef

# ──────────────────────────────────────────────
# Recent symbols (LRU, max 100)
# ──────────────────────────────────────────────

export def RecordSymbol(sym: dict<any>): bool
  if !has_key(sym, 'name') || !has_key(sym, 'path')
    return false
  endif
  if type(sym.name) != v:t_string || type(sym.path) != v:t_string
    return false
  endif
  # Dedupe: if same name+path already exists, remove the old entry first
  var i = 0
  while i < len(RecentSymbols)
    if has_key(RecentSymbols[i], 'name') && has_key(RecentSymbols[i], 'path')
      if RecentSymbols[i].name == sym.name && RecentSymbols[i].path == sym.path
        remove(RecentSymbols, i)
        break
      endif
    endif
    i += 1
  endwhile

  # Prepend new entry
  var entry: dict<any> = {
    name: sym.name,
    path: sym.path,
    line: get(sym, 'line', 0),
    kind: get(sym, 'kind', ''),
    timestamp: localtime(),
  }
  insert(RecentSymbols, entry, 0)

  # Enforce 100-entry cap
  if len(RecentSymbols) > 100
    RecentSymbols = RecentSymbols[: 99]
  endif
  return true
enddef

export def GetRecentSymbols(limit: number = 20): list<dict<any>>
  var n = limit < len(RecentSymbols) ? limit : len(RecentSymbols)
  return n == 0 ? [] : copy(RecentSymbols[: n - 1])
enddef

# ──────────────────────────────────────────────
# Persistence integration
# ──────────────────────────────────────────────

export def GetState(): dict<any>
  var state = vproj#persistence#GetState()
  state->extend({
    pinned_buffers: copy(Pins),
    bookmarks: copy(Bookmarks),
    recent_symbols: copy(RecentSymbols),
  })
  return state
enddef

export def Save()
  vproj#persistence#Save()
enddef

export def Restore(): dict<any>
  vproj#persistence#Restore()
  var state = vproj#persistence#GetState()
  if has_key(state, 'pinned_buffers') && type(state.pinned_buffers) == v:t_list
    Pins = state.pinned_buffers
  endif
  if has_key(state, 'bookmarks') && type(state.bookmarks) == v:t_list
    Bookmarks = state.bookmarks
  endif
  if has_key(state, 'recent_symbols') && type(state.recent_symbols) == v:t_list
    RecentSymbols = state.recent_symbols
  endif
  return state
enddef

# RestorePins replaces the internal pin list (called by persistence.Restore).
export def RestorePins(pins: list<string>)
  Pins = copy(pins)
enddef

# RestoreBookmarks replaces the internal bookmark list (called by persistence.Restore).
export def RestoreBookmarks(bms: list<dict<any>>)
  Bookmarks = copy(bms)
enddef

# RestoreSymbols replaces the internal symbol list (called by persistence.Restore).
export def RestoreSymbols(syms: list<dict<any>>)
  RecentSymbols = copy(syms)
enddef

# ──────────────────────────────────────────────
# Named workspace CRUD
# ──────────────────────────────────────────────

def WorkspaceDir(): string
  var ws: any = get(Config, 'workspace', {})
  if type(ws) != v:t_dict
    return expand('~/.local/share/vproj/workspaces/')
  endif
  return ws->get('path', expand('~/.local/share/vproj/workspaces/'))
enddef

def ValidateWorkspaceDir(dir: string): bool
  if empty(dir) || dir !~# '^/\|^\~/'
    return false
  endif
  var expanded: string = expand(dir)
  if empty(expanded) || expanded !~# '^/'
    return false
  endif
  # Reject path traversal and glob metacharacters (mirrors persistence.vim)
  if expanded =~# '/\.\./\|/\.\.$\|/\./\|/\.$\|[\*\?\[\]]'
    return false
  endif
  return true
enddef

def SanitizeName(name: string): string
  return substitute(name, '[^a-zA-Z0-9_-]', '_', 'g')
enddef

export def SaveWorkspace(name: string): bool
  var safe = SanitizeName(name)
  if empty(safe)
    return false
  endif
  var dir = WorkspaceDir()
  if !ValidateWorkspaceDir(dir)
    return false
  endif
  if !isdirectory(dir)
    mkdir(dir, 'p')
  endif
  try
    writefile([json_encode(vproj#workspace#GetState())], dir .. '/' .. safe .. '.json')
    return true
  catch
    return false
  endtry
enddef

export def LoadWorkspace(name: string): dict<any>
  var safe = SanitizeName(name)
  var dir = WorkspaceDir()
  var filepath = dir .. '/' .. safe .. '.json'
  try
    var lines = readfile(filepath)
    var state = json_decode(join(lines, ''))
    if has_key(state, 'pinned_buffers') && type(state.pinned_buffers) == v:t_list
      Pins = state.pinned_buffers
    endif
    if has_key(state, 'bookmarks') && type(state.bookmarks) == v:t_list
      Bookmarks = state.bookmarks
    endif
    if has_key(state, 'recent_symbols') && type(state.recent_symbols) == v:t_list
      RecentSymbols = state.recent_symbols
    endif
    return state
  catch
    return {}
  endtry
enddef

export def ListWorkspaces(): list<string>
  var dir = WorkspaceDir()
  if !isdirectory(dir)
    return []
  endif
  var files = readdir(dir, (f: string): bool => f =~ '\.json$')
  return files->map((_, f: string): string => f[: -6])
enddef

export def DeleteWorkspace(name: string): bool
  var safe = SanitizeName(name)
  if empty(safe)
    return false
  endif
  var dir = WorkspaceDir()
  if !ValidateWorkspaceDir(dir)
    return false
  endif
  var filepath = dir .. '/' .. safe .. '.json'
  if filepath !~# '/workspaces/' || filepath !~# '\.json$'
    return false
  endif
  try
    delete(filepath)
    return true
  catch
    return false
  endtry
enddef
