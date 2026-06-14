vim9script

# autoload/nam/files_mode.vim — vim9script Files mode with paging.
# Module-level state: Items, LabelMap, Lines, Config, CurrentPage (number),
# TotalPages (number), AllFiles (list<dict<any>>).

var Items: list<dict<any>> = []
var LabelMap: dict<any> = {}
var Lines: list<string> = []
var Config: dict<any> = {}
var CurrentPage: number = 0
var TotalPages: number = 1
var AllFiles: list<dict<any>> = []

# Create returns a mode dict for the Files view.
export def Create(cfg: dict<any>): dict<any>
  Config = cfg
  var mode: dict<any> = {
    name: 'Files',
    key: 'f',
    icon: 'F',
    enabled: cfg->get('modes', {})->get('files', {})->get('enabled', true),
    PrevPage: function(PrevPage),
    NextPage: function(NextPage),
    Refresh: function(Refresh),
    Render: function(RenderFiles),
    Select: function(SelectFile),
  }
  return mode
enddef

# Refresh scans the project and sets up paging.
export def Refresh()
  var root = nam#project#FindRoot(getcwd())
  AllFiles = nam#project#ScanFiles(root, {max_files: 5000})
  CurrentPage = 0
  TotalPages = max([1, float2nr(ceil(len(AllFiles) / 30.0))])
enddef

# RenderFiles produces the current page lines and label map.
export def RenderFiles(): dict<any>
  var page_items: list<dict<any>> = []
  if len(AllFiles) > 0
    var start = CurrentPage * 30
    var end = min([start + 30, len(AllFiles)]) - 1
    page_items = AllFiles[start : end]
  endif
  var labels_cfg = Config->get('labels', {})
  var result = nam#labels#BuildMap(page_items, labels_cfg)
  LabelMap = result->get('label_map', {})
  Lines = result->get('lines', [])
  Lines->add('')
  Lines->add($'[Page {CurrentPage + 1}/{TotalPages}]  [ ] next  [ [ ] prev')
  return {label_map: LabelMap, lines: Lines}
enddef

# SelectFile opens the file associated with the given label.
export def SelectFile(label: string): any
  var item = LabelMap->get(label)
  if item->empty()
    return v:null
  endif
  if item->has_key('path')
    # Switch to main editing window before opening the file.
    var main_win = nam#sidebar#GetMainWin()
    if main_win > 0
      win_gotoid(main_win)
    endif
    execute $'edit {fnameescape(item->get("path"))}'
    var side_win = nam#sidebar#GetWin()
    if side_win > 0
      win_gotoid(side_win)
    endif
    return true
  endif
  return v:null
enddef

# PrevPage decrements the page if possible.
export def PrevPage(): bool
  if CurrentPage > 0
    CurrentPage -= 1
    return true
  endif
  return false
enddef

# NextPage increments the page if possible.
export def NextPage(): bool
  if CurrentPage < TotalPages - 1
    CurrentPage += 1
    return true
  endif
  return false
enddef
