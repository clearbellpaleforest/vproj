vim9script

# Regression tests for the 2026-11 "e" audit, code-mode and buf-mode defects.
# Each block names what used to happen.
# Run: vim -N -u NONE -i NONE --not-a-term -S tests/integration/test_audit_2026_11e_code.vim -c 'cquit!'

$XDG_CACHE_HOME = tempname()
execute 'set rtp^=' .. fnameescape(fnamemodify(expand('<script>:p'), ':h:h:h') .. '/src')
runtime! plugin/vproj.vim
set nomore
set columns=160 lines=40
set ttimeout ttimeoutlen=0

var failures: number = 0
var saved_cwd: string = getcwd()
var root: string = resolve(fnamemodify(tempname(), ':p')) .. '_vproj_audit_e_code'
mkdir(root, 'p')

def Assert(cond: bool, msg: string): void
  if !cond
    echohl ErrorMsg | echom 'FAIL: ' .. msg | echohl None
    failures += 1
  else
    echom 'PASS: ' .. msg
  endif
enddef

def PaneWid(): number
  var wins = win_findbuf(bufnr('VPROJ'))
  return empty(wins) ? 0 : wins[0]
enddef

def PaneLines(): list<string>
  var pbuf = bufnr('VPROJ')
  return pbuf <= 0 ? [] : getbufline(pbuf, 1, '$')
enddef

def PaneCursorText(): string
  var wid = PaneWid()
  var lnum = wid == 0 ? -1 : line('.', wid)
  return lnum < 1 ? '' : get(PaneLines(), lnum - 1, '')
enddef

def SelectName(name: string): bool
  vproj#SelectFirst()
  for _ in range(80)
    if PaneCursorText() =~ '\V\<' .. escape(name, '\') .. '\>'
      return true
    endif
    vproj#SelectNext()
  endfor
  return false
enddef

# Select the first row that is neither the parent row nor the .vproj file:
# names with blanks, control characters or glob characters cannot be found
# by SelectName.
def SelectOdd(): bool
  vproj#SelectFirst()
  for _ in range(10)
    var t: string = PaneCursorText()
    if !empty(t) && t !~ '^ *\.\.' && t !~ 'p\.vproj' && t !~ '^ *(none)'
      return true
    endif
    vproj#SelectNext()
  endfor
  return false
enddef

def Fresh(dir: string): void
  if vproj#IsPaneVisible()
    vproj#PaneClose()
  endif
  silent! only!
  silent! :%bwipeout!
  execute 'cd ' .. fnameescape(dir)
  vproj#PaneOpen()
  vproj#SwitchMode('file')
enddef

def Fixture(name: string, files: list<string>): string
  var d: string = root .. '/' .. name
  mkdir(d, 'p')
  for f in files
    mkdir(fnamemodify(d .. '/' .. f, ':h'), 'p')
    writefile(['x'], d .. '/' .. f)
  endfor
  return d
enddef

def Proj(inc_dirs: list<string>, inc_files: list<string>, exc_dirs: list<string>, exc_files: list<string>): list<string>
  return ['Project Name: p', 'Project Root: ', 'Included Directories:'] + inc_dirs
    + ['Included Files:'] + inc_files + ['Excluded Directories:'] + exc_dirs
    + ['Excluded Files:'] + exc_files
enddef

def Lines(path: string): list<string>
  return filereadable(path) ? readfile(path) : ['<missing>']
enddef

def Msgs(): string
  return execute('messages')
enddef

# ── 1. A failed write is an error and the toggle is reverted ──
# Used to: writefile() == 0 threw E482 inside the :def, so the error branch and
# the snapshot revert never ran; the pane showed the toggle as applied and a
# later write persisted it silently.
# The failure is made independent of chmod (root ignores it): the .vproj is a
# symlink whose target is deleted after the project loaded.
var d1: string = Fixture('wfail', ['a.txt', 'b.txt'])
var d1real: string = root .. '/wfail_real'
mkdir(d1real, 'p')
var orig1: list<string> = Proj([], ['a.txt'], [], [])
writefile(orig1, d1real .. '/p.vproj')
system('ln -s ' .. shellescape(d1real .. '/p.vproj') .. ' ' .. shellescape(d1 .. '/p.vproj'))
Fresh(d1)
vproj#SwitchMode('code')
Assert(SelectName('b.txt'), 'write fail: b.txt is listed')
Assert(match(PaneLines(), '- (b\.txt)') >= 0, 'write fail: precondition, b.txt is not included')
delete(d1real, 'rf')
var err1: string = ''
try
  vproj#IncludeItem()
catch
  err1 = v:exception
endtry
Assert(empty(err1), 'write fail: no exception escapes: ' .. err1)
Assert(Msgs() =~ 'Failed to write.*p\.vproj', 'write fail: the error names the file')
Assert(match(PaneLines(), '- (b\.txt)') >= 0 && match(PaneLines(), '+ b\.txt') < 0, 'write fail: b.txt still shown as not included')
# The target comes back; a later toggle of ANOTHER item must not carry b.txt along.
mkdir(d1real, 'p')
writefile(orig1, d1real .. '/p.vproj')
Assert(SelectName('a.txt'), 'write fail: a.txt is listed')
vproj#ExcludeItem()
Assert(Lines(d1real .. '/p.vproj') == Proj([], [], [], ['a.txt']),
  'write fail: the later write holds only its own change, got ' .. string(Lines(d1real .. '/p.vproj')))

# ── 2. A user's own <name>.vproj.tmp is never touched ──
# Used to: the fixed temp name dest .. '.tmp' was overwritten and then
# consumed by rename.
var d2: string = Fixture('usertmp', ['a.txt', 'b.txt'])
writefile(Proj([], ['a.txt'], [], []), d2 .. '/p.vproj')
var mine2: list<string> = ['my own notes', 'do not touch']
writefile(mine2, d2 .. '/p.vproj.tmp')
Fresh(d2)
vproj#SwitchMode('code')
Assert(SelectName('b.txt'), 'user tmp: b.txt is listed')
vproj#IncludeItem()
Assert(Lines(d2 .. '/p.vproj') == Proj([], ['a.txt', 'b.txt'], [], []), 'user tmp: the include was written')
Assert(Lines(d2 .. '/p.vproj.tmp') == mine2, 'user tmp: p.vproj.tmp survives byte for byte')
var leftovers2: list<string> = readdir(d2)->filter((_, n) => n =~ 'tmp' && n != 'p.vproj.tmp')
Assert(empty(leftovers2), 'user tmp: no temp file is left behind: ' .. string(leftovers2))

# ── 3. Entries match literally except * and ? ──
# Used to: glob2regpat() threw on an unbalanced { } \( \) \+ (code mode died on
# every render), passed $ and ^ through, and made {a,b} and , special.
var names3: list<string> = ['x.js', 'x.ts', '~$x.docx', '$b', 'a,b1', 'z{', '}k', 'y.{js',
  'z\(', 'z\)', 'z\+', 'q$', 'f.{js,ts}']
var d3: string = Fixture('globs', names3)
var cases3: list<list<any>> = [
  ['*{', ['z{']],
  ['?{', ['z{']],
  ['}*', ['}k']],
  ['*.{js', ['y.{js']],
  ['*\(', ['z\(']],
  ['*\)', ['z\)']],
  ['*\+', ['z\+']],
  ['~$*', ['~$x.docx']],
  ['$*', ['$b']],
  ['*$', ['q$']],
  ['a,b*', ['a,b1']],
  ['*.{js,ts}', ['f.{js,ts}']],
  ['*.js', ['x.js']],
  ['?.ts', ['x.ts']],
]
for c in cases3
  var entry: string = c[0]
  writefile(Proj([], ['*'], [], [entry]), d3 .. '/p.vproj')
  var err3: string = ''
  var got3: list<string> = []
  try
    Fresh(d3)
    vproj#SwitchMode('code')
    var pl: list<string> = PaneLines()
    for n in names3
      if match(pl, '\V- (' .. escape(n, '\') .. ')') >= 0
        got3->add(n)
      endif
    endfor
  catch
    err3 = v:exception
  endtry
  Assert(empty(err3), 'glob "' .. entry .. '": code mode renders without an exception: ' .. err3)
  Assert(sort(copy(got3)) == sort(copy(c[1])), 'glob "' .. entry .. '": excludes exactly ' .. string(c[1]) .. ', got ' .. string(got3))
endfor

# ── 4. Names that cannot round-trip through a .vproj are refused ──
# Used to: they were written anyway; read back they were trimmed, matched as
# a glob (a file called ?), or parsed as a section header.
var odd: list<list<any>> = [
  ['glob question', '?'],
  ['glob star', '*'],
  ['glob inside', 'a*b'],
  ['leading blank', ' lead.txt'],
  ['trailing blank', 'trail.txt '],
  ['control char', "ctl\x01.txt"],
  ['carriage return', "cr\r.txt"],
  ['embedded BOM', "bom﻿.txt"],
  ['header-like', 'Included Files: x'],
]
var n4: number = 0
for o in odd
  n4 += 1
  var d4: string = root .. '/odd' .. n4
  mkdir(d4, 'p')
  writefile(['x'], d4 .. '/' .. o[1])
  var base4: list<string> = Proj([], [], [], [])
  writefile(base4, d4 .. '/p.vproj')
  var before4: string = string(readblob(d4 .. '/p.vproj'))
  Fresh(d4)
  vproj#SwitchMode('code')
  Assert(SelectOdd(), o[0] .. ': the file is listed')
  var err4: string = ''
  try
    vproj#IncludeItem()
  catch
    err4 = v:exception
  endtry
  Assert(empty(err4), o[0] .. ': no exception: ' .. err4)
  Assert(string(readblob(d4 .. '/p.vproj')) == before4, o[0] .. ': .vproj is byte-identical')
  Assert(Msgs() =~ 'cannot be stored in a \.vproj file', o[0] .. ': the refusal message is shown')
endfor
# A plain name still works.
var d4ok: string = Fixture('odd_ok', ['plain.txt'])
writefile(Proj([], [], [], []), d4ok .. '/p.vproj')
Fresh(d4ok)
vproj#SwitchMode('code')
Assert(SelectName('plain.txt'), 'plain name: listed')
vproj#IncludeItem()
Assert(Lines(d4ok .. '/p.vproj') == Proj([], ['plain.txt'], [], []), 'plain name: still written')

# ── 5. The cursor follows a directory that re-sorts ──
# Used to: '-' on src/ moved it below docs/ but the cursor stayed on row 1, so
# '+' then included docs/ instead of undoing the exclude.
var d5: string = Fixture('follow', ['src/a.txt', 'docs/b.txt'])
var orig5: list<string> = Proj(['src'], [], [], [])
writefile(orig5, d5 .. '/p.vproj')
Fresh(d5)
vproj#SwitchMode('code')
Assert(SelectName('src'), 'follow: src is listed')
vproj#ExcludeItem()
Assert(PaneCursorText() =~ '(src/)\|(src)', 'follow: the cursor is on src after it moved: "' .. PaneCursorText() .. '"')
vproj#IncludeItem()
Assert(Lines(d5 .. '/p.vproj') == orig5, 'follow: - then + leaves the file as it started, got ' .. string(Lines(d5 .. '/p.vproj')))

# ── 6. X in buf mode removes the row ──
# Used to: :bdelete leaves bufexists() true, so the pane was never redrawn and
# the next X on the stale row errored E516.
var d6: string = Fixture('closebuf', ['a6.txt', 'b6.txt', 'c6.txt'])
Fresh(d6)
wincmd p
for f in ['a6.txt', 'b6.txt', 'c6.txt']
  execute 'edit ' .. fnameescape(d6 .. '/' .. f)
endfor
vproj#SwitchMode('buf')
Assert(SelectName('b6.txt'), 'closebuf: b6.txt is listed')
vproj#CloseBuffer()
var pl6: list<string> = PaneLines()
Assert(match(pl6, 'b6\.txt') < 0, 'closebuf: the pane no longer lists b6.txt: ' .. string(pl6))
Assert(match(pl6, 'a6\.txt') >= 0 && match(pl6, 'c6\.txt') >= 0, 'closebuf: the other buffers are still listed')
Assert(PaneCursorText() =~ '[ac]6\.txt', 'closebuf: the selection is on a listed buffer: "' .. PaneCursorText() .. '"')
var err6: string = ''
try
  vproj#CloseBuffer()
catch
  err6 = v:exception
endtry
Assert(empty(err6), 'closebuf: a second X acts on a live row: ' .. err6)
Assert(match(PaneLines(), '[ac]6\.txt') >= 0 && PaneCursorText() =~ '[ac]6\.txt', 'closebuf: after the second X one listed buffer is still selected')

# ── 7. A big line count does not widen the row ──
# Used to: printf('%4d') of 12345 is 5 cells in a 4-cell column, so the row was
# wider than the pane and the flags were clipped.
var d7: string = Fixture('bigbuf', ['big7_' .. repeat('n', 50) .. '.txt'])
Fresh(d7)
wincmd p
execute 'edit ' .. fnameescape(d7 .. '/big7_' .. repeat('n', 50) .. '.txt')
setline(1, repeat(['l'], 12345))
vproj#SwitchMode('buf')
Assert(vproj#GetPaneWidth() == 40, 'bigbuf: precondition, pane width is 40')
var row7: string = ''
for l in PaneLines()
  if l =~ 'big7'
    row7 = l
  endif
endfor
Assert(!empty(row7), 'bigbuf: the buffer is listed')
Assert(strwidth(row7) == 40, 'bigbuf: the row is exactly the pane width, got ' .. strwidth(row7) .. ': "' .. row7 .. '"')
Assert(row7 =~ '%+', 'bigbuf: the current and modified flags are visible: "' .. row7 .. '"')

# ── Cleanup ──
if vproj#IsPaneVisible()
  vproj#PaneClose()
endif
silent! only!
silent! :%bwipeout!
execute 'cd ' .. fnameescape(saved_cwd)
delete(root, 'rf')

echom ''
if failures == 0
  echom 'ALL TESTS PASSED.'
else
  echohl ErrorMsg | echom failures .. ' TEST(S) FAILED.' | echohl None
  cquit!
endif
qa!
