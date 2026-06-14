vim9script

# autoload/nam/outline_mode.vim — filetype-aware structural outline parser
# Generates structural outlines for the current buffer based on filetype.
# Part of the Nam plugin's Direct Selection Navigation system.

# Module-level state (singleton)
var Items: list<dict<any>> = []
var LabelMap: dict<any> = {}
var Lines: list<string> = []
var Config: dict<any> = {}
var SourceBuf: number = 0

# Reference to the mode dict returned by Create(), for syncing state fields.
var ModeDict: dict<any> = {}

# Create(cfg) — returns the Outline mode dict.
#
# The returned dict has:
#   name, key, icon, enabled, actions
#   items, label_map, lines (populated at runtime)
#   Refresh, Render, Select (function refs to autoload'd defs)
export def Create(cfg: dict<any>): dict<any>
  Config = cfg
  var mode: dict<any> = {
    name: 'Outline',
    key: 'o',
    icon: 'O',
    enabled: true,
    actions: {},
    items: [],
    label_map: {},
    lines: [],
    Refresh: function(nam#outline_mode#Refresh),
    Render: function(nam#outline_mode#RenderOut),
    Select: function(nam#outline_mode#SelectOut),
  }
  ModeDict = mode
  return mode
enddef

# Refresh — reads the current buffer, detects filetype, and parses outline items.
export def Refresh()
  Items = []
  SourceBuf = bufnr('%')
  if SourceBuf <= 0
    return
  endif

  var ft: string = &filetype

  if ft == 'markdown' || ft == 'md'
    ParseMarkdown()
  elseif ft == 'lua'
    ParseLua()
  elseif ft == 'vim'
    ParseVim()
  elseif ft == 'python'
    ParsePython()
  else
    ParseGeneric()
  endif

  if empty(Items)
    add(Items, {name: '(no outline)', line: 0})
  endif
  if !empty(ModeDict)
    ModeDict.items = Items
  endif
enddef

# RenderOut — builds label_map and display lines via nam#labels#BuildMap.
export def RenderOut(): dict<any>
  var lbl_cfg: dict<any> = get(Config, 'labels', {})
  var result: dict<any> = nam#labels#BuildMap(Items, lbl_cfg)
  LabelMap = result.label_map
  Lines = result.lines
  if !empty(ModeDict)
    ModeDict.label_map = LabelMap
    ModeDict.lines = Lines
  endif
  return result
enddef

# SelectOut — jumps to the source line identified by label.
#
# Returns v:null if label not found, false for placeholder items (line 0),
# true after a successful jump.
export def SelectOut(label: string): any
  if empty(LabelMap) || !has_key(LabelMap, label)
    return v:null
  endif
  var item: dict<any> = LabelMap[label]
  if item.line == 0
    return false
  endif
  var main_win = nam#sidebar#GetMainWin()
  if main_win > 0
    win_gotoid(main_win)
  endif
  if SourceBuf > 0 && bufexists(SourceBuf)
    execute 'buffer ' .. SourceBuf
  endif
  cursor(item.line + 1, 1)
  var side_win = nam#sidebar#GetWin()
  if side_win > 0
    win_gotoid(side_win)
  endif
  return true
enddef


# ── Markdown parser ──────────────────────────────────────────────────
# Handles ATX headings (# through ######) with level-based indentation,
# setext headings (=== for h1, --- for h2), and fenced code block skipping.

def ParseMarkdown()
  var lines: list<string> = getbufline(SourceBuf, 1, '$')
  var in_code: bool = false
  var i: number = 0
  while i < len(lines)
    var trimmed: string = trim(lines[i])
    var line_no: number = i
    if empty(trimmed)
      i += 1
      continue
    endif

    # Track fenced code blocks (``` ... ```)
    if trimmed =~ '^```'
      in_code = !in_code
      i += 1
      continue
    endif

    if !in_code
      # ATX heading: line starts with one or more # followed by a space
      if match(trimmed, '^#') == 0
        var hashes: string = matchstr(trimmed, '^#\+')
        var level: number = len(hashes)
        if level <= 6
          var after: string = strcharpart(trimmed, level)
          if !empty(after) && strcharpart(after, 0, 1) == ' '
            var indent: string = repeat('  ', level - 1)
            var heading_text: string = substitute(trimmed, '^#\+\s*', '', '')
            add(Items, {name: indent .. heading_text, line: line_no})
          endif
        endif
      else
        # Setext heading: check if the next line is === (h1) or --- (h2)
        if i + 1 < len(lines)
          var next_trimmed: string = trim(lines[i + 1])
          if next_trimmed =~ '^=\+$'
            add(Items, {name: trimmed, line: line_no})
          elseif next_trimmed =~ '^-\+$'
            add(Items, {name: '  ' .. trimmed, line: line_no})
          endif
        endif
      endif
    endif
    i += 1
  endwhile
enddef


# ── Lua parser ───────────────────────────────────────────────────────
# Extracts: local function, function, M. assignments, return { ... }.
# Skips content inside multi-line [[ ... ]] long strings.

def ParseLua()
  var lines: list<string> = getbufline(SourceBuf, 1, '$')
  var in_long: bool = false

  for i in range(len(lines))
    var trimmed: string = trim(lines[i])
    if empty(trimmed)
      continue
    endif
    var line_no: number = i

    # Track multi-line string literals ([[ ... ]])
    if trimmed =~ '\[\[' && trimmed !~ '\]\]'
      in_long = true
      continue
    elseif trimmed =~ '\]\]'
      in_long = false
      continue
    endif
    if in_long
      continue
    endif

    # Skip lines where 'function' appears inside a string assignment
    if trimmed =~ '="[^"]*function' || trimmed =~ "='[^']*function"
      continue
    endif

    # local function name
    if trimmed =~ '^local\s\+function\s\+'
      var name: string = matchstr(trimmed, '^local\s\+function\s\+\zs[^ (]\+\ze')
      if !empty(name)
        add(Items, {name: 'local function ' .. name, line: line_no})
      endif
    # function name
    elseif trimmed =~ '^function\s\+'
      var name: string = matchstr(trimmed, '^function\s\+\zs[^ (]\+\ze')
      if !empty(name)
        add(Items, {name: 'function ' .. name, line: line_no})
      endif
    # M.name =
    elseif trimmed =~ '^M\.\w\+\s*='
      var name: string = matchstr(trimmed, '^M\.\zs\w\+\ze\s*=')
      if !empty(name) && name !~ '^_'
        add(Items, {name: 'M.' .. name, line: line_no})
      endif
    # return { ... }
    elseif trimmed =~ '^return\s*{'
      add(Items, {name: 'return { ... }', line: line_no})
    endif
  endfor
enddef


# ── Vimscript parser ─────────────────────────────────────────────────
# Extracts: function!, function, command!/command (with -flag skipping), def.

def ParseVim()
  var lines: list<string> = getbufline(SourceBuf, 1, '$')
  for i in range(len(lines))
    var trimmed: string = trim(lines[i])
    if empty(trimmed)
      continue
    endif
    var line_no: number = i

    # function! name
    if trimmed =~ '^function!\s\+'
      var name: string = matchstr(trimmed, '^function!\s\+\zs[^ (]\+\ze')
      if !empty(name)
        add(Items, {name: 'function! ' .. name, line: line_no})
      endif
    # function name
    elseif trimmed =~ '^function\s\+'
      var name: string = matchstr(trimmed, '^function\s\+\zs[^ (]\+\ze')
      if !empty(name)
        add(Items, {name: 'function ' .. name, line: line_no})
      endif
    # command! or command (skip -flags before the command name)
    elseif trimmed =~ '^command!\s\+' || trimmed =~ '^command\s\+'
      var has_bang: bool = trimmed =~ '^command!'
      var rest: string = substitute(trimmed, '^command!\?\s*', '', '')
      var cmd_name: string = ''
      for token in split(rest)
        if token !~ '^-'
          cmd_name = token
          break
        endif
      endfor
      if !empty(cmd_name)
        var prefix: string = has_bang ? 'command! ' : 'command '
        add(Items, {name: prefix .. cmd_name, line: line_no})
      endif
    # def name (Vim9)
    elseif trimmed =~ '^def\s\+'
      var name: string = matchstr(trimmed, '^def\s\+\zs\w\+\ze')
      if !empty(name)
        add(Items, {name: 'def ' .. name, line: line_no})
      endif
    endif
  endfor
enddef


# ── Python parser ────────────────────────────────────────────────────
# Extracts: class, def, async def.

def ParsePython()
  var lines: list<string> = getbufline(SourceBuf, 1, '$')
  for i in range(len(lines))
    var trimmed: string = trim(lines[i])
    if empty(trimmed)
      continue
    endif
    var line_no: number = i

    if trimmed =~ '^class\s\+'
      var name: string = matchstr(trimmed, '^class\s\+\zs\w\+\ze')
      if !empty(name)
        add(Items, {name: 'class ' .. name, line: line_no})
      endif
    elseif trimmed =~ '^def\s\+'
      var name: string = matchstr(trimmed, '^def\s\+\zs\w\+\ze')
      if !empty(name)
        add(Items, {name: 'def ' .. name, line: line_no})
      endif
    elseif trimmed =~ '^async\s\+def\s\+'
      var name: string = matchstr(trimmed, '^async\s\+def\s\+\zs\w\+\ze')
      if !empty(name)
        add(Items, {name: 'def ' .. name, line: line_no})
      endif
    endif
  endfor
enddef


# ── Generic fallback parser ──────────────────────────────────────────
# Shows the first 50 non-blank lines, each truncated to 40 characters.

def ParseGeneric()
  var lines: list<string> = getbufline(SourceBuf, 1, '$')
  var count: number = 0
  for i in range(len(lines))
    if count >= 50
      break
    endif
    var trimmed: string = trim(lines[i])
    if empty(trimmed)
      continue
    endif
    if len(trimmed) > 40
      trimmed = strcharpart(trimmed, 0, 40) .. '...'
    endif
    add(Items, {name: trimmed, line: i})
    count += 1
  endfor
enddef
