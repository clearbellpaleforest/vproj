vim9script

# autoload/vproj/persistence.vim — vim9script per-project session persistence
#
# Saves and restores workspace state to JSON files in
# $XDG_CACHE_HOME/vproj/ or ~/.cache/vproj/. Each project gets its own session
# file keyed by a djb2 hash of the project root. A special "global" session
# is used when no project root is available.
#
# Module-level state:
#   Config     - dict<any> configuration passed via Setup()
#   StateFiles - dict<string> caching resolved file paths by state key

var Config: dict<any> = {}
var StateFiles: dict<string> = {}

# --------------------------------------------------------------------------
# Internal Utilities
# --------------------------------------------------------------------------

# MAX_RESTORE_BUFFERS caps the number of buffers that Restore will reopen.
# Prevents a corrupted or malicious session file from attempting to open
# an unbounded number of buffers.
const MAX_RESTORE_BUFFERS: number = 50

# Hash generates a djb2-style hash of a string, returned as a hex string.
# Used to key session files by project root path.
def Hash(str: string): string
  var h: number = 5381
  for ch in str->split('\zs')
    h = h * 33 + char2nr(ch)
  endfor
  return printf('%x', h)
enddef

# ResolveCacheHome returns the base cache directory for nam state files,
# reading $XDG_CACHE_HOME and falling back to ~/.cache when unset or empty.
# The returned path is validated: it must expand to a plausible directory
# path. If $XDG_CACHE_HOME is set but empty or non-absolute, the fallback
# is used. Returns the cache home directory with no trailing slash.
def ResolveCacheHome(): string
  var raw: any = getenv('XDG_CACHE_HOME')
  if empty(raw) || raw ==# ''
    return expand('~') .. '/.cache'
  endif
  var expanded: string = expand(raw)
  if empty(expanded) || expanded !~# '^/\|^\~/'
    return expand('~') .. '/.cache'
  endif
  # Reject path traversal components and glob metacharacters
  if expanded =~# '/\.\./\|/\.\.$\|/\./\|/\.$\|[\*\?\[\]]'
    return expand('~') .. '/.cache'
  endif
  return expanded
enddef

# ValidateSessionPath guards Clear/ClearAll against accidentally deleting
# files outside the expected nam cache directory. Returns true if the given
# filepath is under a valid nam session directory (has '/vproj/session_' in it
# and the base directory exists), false otherwise.
def ValidateSessionPath(filepath: string): bool
  if empty(filepath) || filepath !~# '/vproj/session_'
    return false
  endif
  var dir: string = fnamemodify(filepath, ':h')
  if !isdirectory(dir)
    return false
  endif
  return true
enddef

# GetStateFile resolves the path to the session state file for a given
# project root. Uses $XDG_CACHE_HOME/vproj/session_<hash>.json when a project
# root is provided, or $XDG_CACHE_HOME/vproj/session_global.json for global
# state. Falls back to ~/.cache/vproj/ when $XDG_CACHE_HOME is not set.
# Results are cached in StateFiles to avoid re-computation.
def GetStateFile(project_root: string): string
  var key: string = empty(project_root) ? 'global' : Hash(project_root)
  if has_key(StateFiles, key)
    return StateFiles[key]
  endif
  var dir: string = ResolveCacheHome() .. '/vproj'
  var filepath: string = dir .. '/session_' .. key .. '.json'
  StateFiles[key] = filepath
  return filepath
enddef

# EnsureCacheDir creates the cache directory for the given project root
# if it does not already exist. Parent directories are created as needed.
def EnsureCacheDir(project_root: string)
  var filepath: string = GetStateFile(project_root)
  var dir: string = fnamemodify(filepath, ':h')
  if dir !~# '/vproj$'
    return
  endif
  if !isdirectory(dir)
    mkdir(dir, 'p')
  endif
enddef

# AtomicWrite writes lines to a file using a temp-then-rename pattern.
# Prevents session file corruption if Vim crashes mid-write.
# Returns true on success, false on failure.
def AtomicWrite(filepath: string, lines: list<string>): bool
  var tmp: string = filepath .. '.tmp.' .. reltimefloat(reltime())
  try
    writefile(lines, tmp)
  catch
    delete(tmp)
    return false
  endtry
  try
    rename(tmp, filepath)
  catch
    delete(tmp)
    return false
  endtry
  return true
enddef

# --------------------------------------------------------------------------
# State Assembly
# --------------------------------------------------------------------------

# GetState assembles the current workspace state into a dict suitable for
# JSON serialization. Captures open buffers, cursor positions, the active
# mode, sidebar visibility, project root, and window layout.
export def GetState(): dict<any>
  var state: dict<any> = {
    version: 2,
    timestamp: localtime(),
    sidebar_open: false,
    current_mode: '',
    project_root: '',
    buffers: [],
    cursor_positions: {},
    window_layout: '',
  }

  # Collect open, listed buffers with names and their cursor positions
  var bufs: list<string> = []
  var cursor_positions: dict<any> = {}
  for info in getbufinfo({buflisted: 1})
    if info.loaded && info.name != ''
      add(bufs, info.name)
      cursor_positions[info.name] = {line: info.lnum, col: info.col}
    endif
  endfor
  state.buffers = bufs
  state.cursor_positions = cursor_positions

  # Determine current mode from the mode registry
  try
    var mode: dict<any> = vproj#modes#GetCurrent()
    if !empty(mode) && has_key(mode, 'key')
      state.current_mode = mode.key
    endif
  catch
    # Mode registry not available
  endtry

  # Determine sidebar state
  try
    state.sidebar_open = vproj#sidebar#IsOpen()
  catch
    # Sidebar not available
  endtry

  # Determine current project root
  try
    if exists('*vproj#project#FindRoot')
      state.project_root = vproj#project#FindRoot()
    endif
  catch
    # Project module not available
  endtry

  # Capture window layout (executable command string for restore)
  state.window_layout = winrestcmd()

  # Include workspace data (pins, bookmarks, symbols) in the session
  try
    if exists('*vproj#workspace#GetPinned')
      state.pinned_buffers = vproj#workspace#GetPinned()
      state.bookmarks = vproj#workspace#GetBookmarks()
      state.recent_symbols = vproj#workspace#GetRecentSymbols(100)
    endif
  catch
  endtry

  return state
enddef

# --------------------------------------------------------------------------
# Public API
# --------------------------------------------------------------------------

# Save serialises the current workspace state and writes it to the per-project
# session file. If project_root is empty, it auto-detects the current project
# root via vproj#project#FindRoot(). Returns true on success, false on failure.
export def Save(project_root: string = ''): bool
  var root: string = project_root
  if empty(root)
    try
      if exists('*vproj#project#FindRoot')
        root = vproj#project#FindRoot()
      endif
    catch
    endtry
  endif
  EnsureCacheDir(root)
  var state: dict<any> = GetState()
  var encoded: string = json_encode(state)
  var lines: list<string> = [encoded]
  return AtomicWrite(GetStateFile(root), lines)
enddef

# Restore loads a previously saved workspace state for a given project and
# applies it: opens buffers, restores cursor positions, reapplies window
# layout, and reactivates the saved mode and sidebar state.
# Returns true if a session file was found and restored, false otherwise.
export def Restore(project_root: string = ''): bool
  var root: string = project_root
  if empty(root)
    try
      if exists('*vproj#project#FindRoot')
        root = vproj#project#FindRoot()
      endif
    catch
    endtry
  endif
  var filepath: string = GetStateFile(root)
  if !filereadable(filepath)
    return false
  endif
  var lines: list<string> = readfile(filepath)
  if empty(lines)
    return false
  endif
  var json_text: string = lines->join("\n")
  var decoded: any
  try
    decoded = json_decode(json_text)
  catch
    return false
  endtry
  if type(decoded) != v:t_dict
    return false
  endif
  var state: dict<any> = decoded

  # Validate minimum required fields
  if !has_key(state, 'version') || type(state.version) != v:t_number
    return false
  endif

  # Restore open buffers (capped to prevent abuse from corrupted/malicious session files)
  var restored_bufs: number = 0
  if has_key(state, 'buffers') && type(state.buffers) == v:t_list
    for bufpath in state.buffers
      if restored_bufs >= MAX_RESTORE_BUFFERS
        break
      endif
      if type(bufpath) == v:t_string && bufpath != '' && bufpath =~# '^[/~]'
        try
          execute 'badd ' .. fnameescape(bufpath)
          restored_bufs += 1
        catch
        endtry
      endif
    endfor
  endif

  # Restore cursor positions for each buffer via the "." mark
  if has_key(state, 'cursor_positions') && type(state.cursor_positions) == v:t_dict
    for bufpath in keys(state.cursor_positions)
      var pos: any = state.cursor_positions[bufpath]
      if type(pos) == v:t_dict && has_key(pos, 'line') && type(pos.line) == v:t_number
        var bufnr: number = bufnr(bufpath)
        if bufnr > 0
          var col: number = get(pos, 'col', 1)
          try
            setpos('.', [bufnr, pos.line, col, 0])
          catch
          endtry
        endif
      endif
    endfor
  endif

  # Restore window layout (split sizes and positions).
  # Validate against a strict pattern: only resize and vertical resize
  # commands that winrestcmd() produces. Rejects any injected Ex commands.
  if has_key(state, 'window_layout') && type(state.window_layout) == v:t_string && state.window_layout != ''
    try
      var valid_layout: bool = true
      for cmd_line in split(state.window_layout, '\n')
        if cmd_line !~# '^\(resize\|vertical resize\)\s\+\d\+$'
          valid_layout = false
          break
        endif
      endfor
      if valid_layout
        execute state.window_layout
      endif
    catch
    endtry
  endif

  # Restore the current mode in the sidebar
  if has_key(state, 'current_mode') && type(state.current_mode) == v:t_string && state.current_mode != ''
    try
      vproj#modes#Switch(state.current_mode)
    catch
    endtry
  endif

  # Restore sidebar state (open if it was open when saved)
  if has_key(state, 'sidebar_open') && type(state.sidebar_open) == v:t_bool && state.sidebar_open
    try
      if !vproj#sidebar#IsOpen()
        vproj#sidebar#Open()
      endif
    catch
    endtry
  endif

  # Restore workspace data (pins, bookmarks, recent symbols)
  if has_key(state, 'pinned_buffers') && type(state.pinned_buffers) == v:t_list
    try
      vproj#workspace#RestorePins(state.pinned_buffers)
    catch
    endtry
  endif
  if has_key(state, 'bookmarks') && type(state.bookmarks) == v:t_list
    try
      vproj#workspace#RestoreBookmarks(state.bookmarks)
    catch
    endtry
  endif
  if has_key(state, 'recent_symbols') && type(state.recent_symbols) == v:t_list
    try
      vproj#workspace#RestoreSymbols(state.recent_symbols)
    catch
    endtry
  endif

  return true
enddef

# Clear deletes the session state file for the given project root, including
# any stale .tmp.* files from interrupted atomic writes.
export def Clear(project_root: string = '')
  var root: string = project_root
  if empty(root)
    try
      if exists('*vproj#project#FindRoot')
        root = vproj#project#FindRoot()
      endif
    catch
    endtry
  endif
  var filepath: string = GetStateFile(root)
  if !ValidateSessionPath(filepath)
    return
  endif
  if filereadable(filepath)
    delete(filepath)
  endif
  # Clean up any stale temp files from interrupted atomic writes
  var tmp_files: list<string> = glob(filepath .. '.tmp.*', false, true)
  for f in tmp_files
    delete(f)
  endfor
enddef

# ClearAll deletes all known per-project session files and their stale
# .tmp.* files, then resets the internal StateFiles cache.
export def ClearAll()
  for key in keys(StateFiles)
    var filepath: string = StateFiles[key]
    if !ValidateSessionPath(filepath)
      continue
    endif
    if filereadable(filepath)
      delete(filepath)
    endif
    # Clean up any stale temp files from interrupted atomic writes
    var tmp_files: list<string> = glob(filepath .. '.tmp.*', false, true)
    for f in tmp_files
      delete(f)
    endfor
  endfor
  StateFiles = {}
enddef

# --------------------------------------------------------------------------
# Setup & Initialization
# --------------------------------------------------------------------------

# Setup initialises the persistence module with the user's configuration.
# It cleans up stale .tmp.* files from previous crashes, optionally restores
# the previous session if auto_restore is enabled, and registers a VimLeave
# autocmd for auto-save if auto_save is enabled.
#
# Configuration dict (cfg) may contain:
#   workspace.auto_restore - bool, restore previous session on startup
#   workspace.auto_save    - bool, save session on VimLeave
export def Setup(cfg: dict<any>)
  if type(cfg) != v:t_dict
    return
  endif
  Config = cfg

  # Clean up stale .tmp.* files left by interrupted atomic writes.
  # Vim crashes between writefile() and rename() orphan these files.
  var vproj_dir: string = ResolveCacheHome() .. '/vproj'
  if isdirectory(vproj_dir)
    var stale: list<string> = glob(vproj_dir .. '/session_*.tmp.*', false, true)
    for f in stale
      delete(f)
    endfor
  endif

  # Auto-restore workspace state on startup
  if has_key(Config, 'workspace') && type(Config.workspace) == v:t_dict
    if has_key(Config.workspace, 'auto_restore')
        && type(Config.workspace.auto_restore) == v:t_bool
        && Config.workspace.auto_restore
      try
        var project_root: string = ''
        if exists('*vproj#project#FindRoot')
          project_root = vproj#project#FindRoot()
        endif
        Restore(project_root)
      catch
        # Silently continue if restore fails
      endtry
    endif
  endif

  # Auto-save workspace state on VimLeave
  if has_key(Config, 'workspace') && type(Config.workspace) == v:t_dict
    if has_key(Config.workspace, 'auto_save')
        && type(Config.workspace.auto_save) == v:t_bool
        && Config.workspace.auto_save
      augroup VprojPersistence
        autocmd!
        autocmd VimLeave * call vproj#persistence#Save()
      augroup END
    endif
  endif
enddef
