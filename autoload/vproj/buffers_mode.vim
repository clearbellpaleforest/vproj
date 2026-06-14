vim9script

# Buffers mode for the Nam plugin.
#
# Lists open buffers with status indicators and DSN (Direct Selection
# Navigation) labels.  Implements the standard Vproj mode interface:
# Create(cfg) -> {Refresh, Render, Select, ...}
#
# Module-level state (singleton per session)
var Items: list<dict<any>> = []
var LabelMap: dict<any> = {}
var Lines: list<string> = []
var Config: dict<any> = {}

# GetBufferStatus assembles the status-indicator string for buffer {buf}.
# Returns a string composed of zero or more of:
#   *  modified
#   R  readonly
#   T  terminal
#   P  pinned (via vproj#workspace#IsPinned, if available)
def GetBufferStatus(buf: number): string
  if buf <= 0 || !bufexists(buf)
    return ''
  endif
  var status = ''
  try
    if getbufvar(buf, '&modified')
      status ..= '*'
    endif
  catch
  endtry
  try
    if getbufvar(buf, '&readonly')
      status ..= 'R'
    endif
  catch
  endtry
  try
    if getbufvar(buf, '&buftype') == 'terminal'
      status ..= 'T'
    endif
  catch
  endtry
  if exists('*vproj#workspace#IsPinned')
    try
      var bname: string = bufname(buf)
      if bname != '' && vproj#workspace#IsPinned(bname)
        status ..= 'P'
      endif
    catch
    endtry
  endif
  return status
enddef

# Create returns a mode dict for the buffers mode.
#
# @param {dict<any>} cfg — full Nam configuration dict (see config.vim).
# @returns {dict<any>} mode dict with keys:
#   name, key, icon, enabled, Refresh (funcref), Render (funcref),
#   Select (funcref).
export def Create(cfg: dict<any>): dict<any>
  Config = cfg
  var enabled: bool = true
  if has_key(cfg, 'modes') && has_key(cfg.modes, 'buffers')
    enabled = cfg.modes.buffers->get('enabled', true)
  endif
  var mode: dict<any> = {
    name: 'Buffers',
    key: 'b',
    icon: 'B',
    enabled: enabled,
  }
  mode->extend({
    Refresh: function('vproj#buffers_mode#Refresh'),
    Render: function('vproj#buffers_mode#RenderBuf'),
    Select: function('vproj#buffers_mode#SelectBuf'),
  })
  return mode
enddef

# Refresh scans all buffer numbers, collecting listed buffers and their
# status indicators.  Populates the module-level Items list.
export def Refresh(): void
  Items = []
  for buf in range(1, bufnr('$'))
    if !bufexists(buf) || bufname(buf) ==# 'vproj://sidebar'
      continue
    endif
    # Skip sidebar and unlisted buffers
    if bufname(buf) ==# '' || bufname(buf) ==# 'vproj://sidebar'
      continue
    endif
    var name: string = bufname(buf)
    if name == ''
      name = '[No Name]'
    else
      name = fnamemodify(name, ':t')
    endif
    var status: string = GetBufferStatus(buf)
    if status != ''
      name ..= ' ' .. status
    endif
    add(Items, {name: name, buf: buf, status: status})
  endfor
enddef

# RenderBuf feeds the current Items through the DSN label engine.
#
# Calls vproj#labels#BuildMap to produce a label_map dict and display
# lines list.  Both are stored in module-level state.
#
# @returns {dict<any>} result with keys 'label_map' and 'lines'.
export def RenderBuf(): dict<any>
  var labels_result: dict<any> =
      vproj#labels#BuildMap(Items, Config->get('labels', {}))
  LabelMap = labels_result.label_map
  Lines = labels_result.lines
  return labels_result
enddef

# SelectBuf handles a DSN label keypress.
#
# Looks up {label} in LabelMap and opens the corresponding buffer.
#
# @param {string} label — the DSN key(s) the user pressed.
# @returns {any} true on successful buffer switch, false if the buffer
#   no longer exists, v:null if the label is unknown.
export def SelectBuf(label: string): any
  if !has_key(LabelMap, label)
    return v:null
  endif
  var item: dict<any> = LabelMap[label]
  if has_key(item, 'buf')
    var nr: number = item.buf
    if bufexists(nr)
      var main_win = vproj#sidebar#GetMainWin()
      if main_win > 0
        win_gotoid(main_win)
      endif
      execute 'buffer ' .. nr
      var side_win = vproj#sidebar#GetWin()
      if side_win > 0
        win_gotoid(side_win)
      endif
      return true
    endif
  endif
  return false
enddef
