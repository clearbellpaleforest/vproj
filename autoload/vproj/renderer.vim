vim9script

var SeparatorLine: string = ''

export def Setup(cfg: dict<any>)
  SeparatorLine = repeat(nr2char(0x2500), cfg.width)
enddef

export def RenderFull(buf: number, mode_name: string, modes: list<dict<any>>, body: list<string>)
  if !bufexists(buf)
    return
  endif

  # Short names for mode tabs (must fit in sidebar width)
  var short_names: dict<string> = {
    Buffers: 'Buf',
    Files: 'File',
    Symbols: 'Sym',
    Git: 'Git',
    Outline: 'Out',
  }
  var tabs: list<string> = []
  for m in modes
    var short = get(short_names, m.name, m.name)
    var label = '[' .. m.key .. ']' .. short
    if m.name == mode_name
      tabs->add('%' .. label .. '%')
    else
      tabs->add(label)
    endif
  endfor
  var tab_line = tabs->join(' ')

  var header: list<string> = [
    'PROJECT [' .. mode_name .. ']',
    '',
    tab_line,
    SeparatorLine,
  ]

  var all_lines: list<string> = header->extend(body)

  setbufvar(buf, '&modifiable', true)
  deletebufline(buf, 1, '$')
  setbufline(buf, 1, all_lines)
  setbufvar(buf, '&modifiable', false)
enddef
