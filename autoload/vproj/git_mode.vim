vim9script

# autoload/vproj/git_mode.vim — vim9script git status mode
# Displays staged/unstaged/untracked/conflict files with DSN labels.
# Supports actions: stage file, unstage file, view diff.
#
# Mode interface:
#   Create(cfg) -> mode dict
#   Refresh()   — fetch git status via vproj#git
#   RenderGit() — build labeled lines
#   SelectGit() — open a file by label
#   StageItem() — stage a file by label
#   UnstageItem() — unstage a file by label
#   ShowDiffItem() — show diff in scratch buffer

# Module-level state: persists across mode switch within a session.
var Items: list<dict<any>> = []
var LabelMap: dict<any> = {}
var Lines: list<string> = []
var Config: dict<any> = {}

# Create a new git mode instance dict.
# The returned dict conforms to the Vproj mode interface and stores
# funcrefs to the module-level functions below.
export def Create(cfg: dict<any>): dict<any>
  Config = cfg
  Items = []
  LabelMap = {}
  Lines = []

  var modes_cfg: dict<any> = get(Config, 'modes', {})
  var git_cfg: dict<any> = get(modes_cfg, 'git', {})

  return {
    name: 'Git',
    key: 'g',
    icon: 'G',
    enabled: get(git_cfg, 'enabled', true),
    StageFile: function('vproj#git_mode#StageItem'),
    UnstageFile: function('vproj#git_mode#UnstageItem'),
    ShowDiff: function('vproj#git_mode#ShowDiffItem'),
    Refresh: function('vproj#git_mode#Refresh'),
    Render: function('vproj#git_mode#RenderGit'),
    Select: function('vproj#git_mode#SelectGit'),
  }
enddef

# Refresh git status and rebuild the Items list.
# Falls back to an error item when the current directory is not a git repo.
export def Refresh(): void
  var status = vproj#git#GetStatus()

  if type(status) != v:t_dict || !get(status, 'ok', false)
    Items = [{name: '(not a git repository)', path: '', category: 'error'}]
    return
  endif

  Items = []

  for entry in status->get('items', [])
    var prefix: string = entry->get('prefix', '?')
    var path: string = entry->get('path', '')
    var name: string = prefix .. ' ' .. path
    add(Items, {name: name, path: path, category: entry->get('category', 'unknown')})
  endfor
enddef

# Render the current Items into labeled lines and update module-level
# LabelMap and Lines. Returns the raw result from labels#BuildMap:
#   {label_map: dict<any>, lines: list<string>}
export def RenderGit(): dict<any>
  if empty(Items)
    return vproj#labels#BuildMap([{name: '(no changes)', category: 'info'}], get(Config, 'labels', {}))
  endif
  var result = vproj#labels#BuildMap(Items, get(Config, 'labels', {}))
  LabelMap = result.label_map
  Lines = result.lines
  return result
enddef

# Select an item by label and open its file.
# Returns:
#   v:null — label not found
#   false  — error/category item (not a real file)
#   true   — file opened successfully
export def SelectGit(label: string): any
  if !has_key(LabelMap, label)
    return v:null
  endif
  var item = LabelMap[label]
  if has_key(item, 'category') && (item.category == 'error' || item.category == 'info')
    return false
  endif
  if !has_key(item, 'path') || type(item.path) != v:t_string || empty(item.path)
    return false
  endif
  var main_win = vproj#sidebar#GetMainWin()
  if main_win > 0
    win_gotoid(main_win)
  endif
  execute 'edit ' .. fnameescape(item.path)
  var side_win = vproj#sidebar#GetWin()
  if side_win > 0
    win_gotoid(side_win)
  endif
  return true
enddef

# Stage the file identified by the given label.
# Returns false when the label is invalid or the item has no path.
export def StageItem(label: string): bool
  if !has_key(LabelMap, label)
    return false
  endif
  var item = LabelMap[label]
  if !has_key(item, 'path') || type(item.path) != v:t_string || empty(item.path)
    return false
  endif
  vproj#git#StageFile(item.path)
  Refresh()
  return true
enddef

# Unstage the file identified by the given label.
# Returns false when the label is invalid or the item has no path.
export def UnstageItem(label: string): bool
  if !has_key(LabelMap, label)
    return false
  endif
  var item = LabelMap[label]
  if !has_key(item, 'path') || type(item.path) != v:t_string || empty(item.path)
    return false
  endif
  vproj#git#UnstageFile(item.path)
  Refresh()
  return true
enddef

# Show git diff for the file identified by the given label.
# Opens the diff output in a new scratch buffer in a split window.
# Returns false when the label is invalid, the item has no path,
# or the diff produces no output.
export def ShowDiffItem(label: string): bool
  if !has_key(LabelMap, label)
    return false
  endif
  var item = LabelMap[label]
  if !has_key(item, 'path') || type(item.path) != v:t_string || empty(item.path)
    return false
  endif
  var staged: bool = item.category == 'staged'
  var diff_lines: list<string> = vproj#git#GetDiff(item.path, staged)
  if empty(diff_lines)
    return false
  endif

  # Create a scratch buffer for the diff output.
  var buf: number = bufadd('')
  setbufvar(buf, '&buftype', 'nofile')
  setbufvar(buf, '&bufhidden', 'wipe')
  setbufvar(buf, '&swapfile', false)
  setbufvar(buf, '&filetype', 'diff')
  setbufline(buf, 1, diff_lines)

  # Open the scratch buffer in a new split window.
  execute 'belowright split'
  execute 'buffer ' .. buf

  return true
enddef
