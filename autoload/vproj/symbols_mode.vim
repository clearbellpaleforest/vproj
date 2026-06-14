vim9script

# autoload/vproj/symbols_mode.vim — vim9script symbols mode using ctags
# Provides Direct Selection Navigation over symbols in the current file.

# Module-level state
var Items: list<dict<any>> = []
var LabelMap: dict<any> = {}
var Lines: list<string> = []
var Config: dict<any> = {}

# Map ctags kind letters to display icons.
# ctags --fields=nK outputs a single-letter kind in the K: field.
const KindIcons: dict<string> = {
  f: 'f',   # function
  c: 'C',   # class
  m: 'm',   # member
  v: 'v',   # variable
  s: 'S',   # struct
  t: 'T',   # typedef
  i: 'I',   # interface
  p: 'p',   # prototype
  g: 'g',   # enum
  u: 'u',   # union
  d: 'm',   # macro (display as member)
  e: 'm',   # enumerator (display as member)
  x: '?',   # external
  z: '?',   # other
}

# Create a new Symbols mode dict.
# cfg: dict<any> — configuration (may contain 'labels' key with tiers/overflow_style).
# Returns the mode dict with name, key, icon, enabled, Refresh, Render, Select.
export def Create(cfg: dict<any>): dict<any>
  Config = cfg

  var mode: dict<any> = {
    name: 'Symbols',
    key: 's',
    icon: 'S',
    enabled: true,
    actions: {},
  }

  mode.Refresh = function('vproj#symbols_mode#Refresh')
  mode.Render = function('vproj#symbols_mode#RenderSym')
  mode.Select = function('vproj#symbols_mode#SelectSym')

  return mode
enddef

# Refresh — parse ctags output for the current file and populate Items.
export def Refresh()
  Items = []

  var filepath: string = expand('%:p')
  if filepath == ''
    # No file open — nothing to symbol-index
    Items = [{name: '(no symbols available)', path: '', line: 0, kind: '?'}]
    return
  endif

  var ctags_cmd: string = 'ctags -f - --fields=nK ' .. shellescape(filepath) .. ' 2>/dev/null'
  var raw: list<string> = systemlist(ctags_cmd)

  if empty(raw)
    Items = [{name: '(no symbols available)', path: '', line: 0, kind: '?'}]
    return
  endif

  for line in raw
    # ctags -f - output: symbol_name<TAB>file_path<TAB>line_number;"<TAB>kind:letter
    # Fields are tab-separated. First field is symbol name, last fields have K: and n:.
    var fields: list<string> = split(line, "\t")
    if len(fields) < 3
      continue
    endif

    var symbol_name: string = fields[0]
    var kind: string = '?'
    var line_number: number = 0

    # Parse kind and line from the remaining fields.
    # The last fields contain things like: kind:f  line:42
    for i in range(1, len(fields) - 1)
      var f: string = fields[i]
      if f =~ '^kind:'
        var raw_kind: string = f[5 : ]
        if raw_kind != ''
          kind = get(KindIcons, raw_kind, '?')
        endif
      elseif f =~ '^line:'
        var num_str: string = f[5 : ]
        if num_str != ''
          line_number = str2nr(num_str)
        endif
      elseif f =~ '^n:'
        # Short form: n:42 (Neovim-compatible ctags)
        var num_str: string = f[2 : ]
        if num_str != ''
          line_number = str2nr(num_str)
        endif
      endif
    endfor

    # Fallback: if no line found, try the second field (ctags sometimes puts line number there)
    if line_number == 0 && len(fields) >= 2
      var maybe_line: string = fields[1]
      if maybe_line =~ '^\d\+$'
        line_number = str2nr(maybe_line)
      endif
    endif

    var display_name: string = kind .. ' ' .. symbol_name .. ':' .. line_number
    add(Items, {name: display_name, path: filepath, line: line_number, kind: kind, symbol_name: symbol_name})
  endfor

  if empty(Items)
    Items = [{name: '(no symbols available)', path: '', line: 0, kind: '?'}]
  endif
enddef

# RenderSym — call labels#BuildMap on Items, prepend source line.
export def RenderSym(): dict<any>
  var label_cfg: dict<any> = get(Config, 'labels', {})
  var result: dict<any> = vproj#labels#BuildMap(Items, label_cfg)

  LabelMap = result.label_map
  Lines = result.lines

  # Prepend "Source: ctags" line
  var all_lines: list<string> = ['Source: ctags']
  if !empty(Lines)
    all_lines->extend(['']->extend(Lines))
  endif

  return {label_map: LabelMap, lines: all_lines}
enddef

# SelectSym — jump to the symbol corresponding to label.
export def SelectSym(label: string): any
  if !has_key(LabelMap, label)
    return v:null
  endif

  var item: dict<any> = LabelMap[label]

  # Error item (no symbols / no file open)
  if item.line == 0
    return false
  endif

  # Jump to the file and line in the main editing window
  var main_win = vproj#sidebar#GetMainWin()
  if main_win > 0
    win_gotoid(main_win)
  endif
  execute 'edit ' .. fnameescape(item.path)
  execute '' .. item.line

  var side_win = vproj#sidebar#GetWin()
  if side_win > 0
    win_gotoid(side_win)
  endif

  # Record in workspace if available (graceful fallback)
  try
    call vproj#workspace#RecordSymbol({
      name: item->get('symbol_name', ''),
      path: item.path,
      line: item.line,
      kind: item->get('kind', '?'),
    })
  catch
    # vproj#workspace may not exist yet — silently ignore
  endtry

  return true
enddef
