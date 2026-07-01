vim9script

# Integration test: Special characters in filenames
# Run: vim -N -u NONE -S tests/integration/test_special_chars.vim

set rtp+=src
runtime! plugin/vproj.vim
set nomore

var failures: number = 0
var saved_cwd: string = getcwd()

def Assert(cond: bool, msg: string): void
  if !cond
    echohl ErrorMsg | echom 'FAIL: ' .. msg | echohl None
    failures += 1
  else
    echom 'PASS: ' .. msg
  endif
enddef

def PaneCursorLine(): number
  var pbuf = bufnr('VPROJ')
  var wins = win_findbuf(pbuf)
  return empty(wins) ? -1 : line('.', wins[0])
enddef

def PaneContains(pattern: string): bool
  var pbuf = bufnr('VPROJ')
  if pbuf <= 0 | return false | endif
  var lines = getbufline(pbuf, 1, '$')
  for line in lines
    if line =~ pattern | return true | endif
  endfor
  return false
enddef

# ── Create temp dir with special-char filenames ──
var tmpdir: string = '/tmp/vproj_test_special_' .. strftime('%s')
mkdir(tmpdir, 'p')

# Files with various special characters
var special_names: list<string> = [
  'file with spaces.txt',
  'file(with)parens.txt',
  'file[with]brackets.txt',
  'file-with-dashes.txt',
  'file_with_underscores.txt',
  'file:colon.txt',
  "file's apostrophe.txt",
  'UPPERCASE_FILE.txt',
  'file#hash.txt',
  'file%percent.txt',
  'file!exclaim.txt',
]

for name in special_names
  writefile(['content'], tmpdir .. '/' .. name)
endfor

# Subdir with special chars
mkdir(tmpdir .. '/dir with spaces')
writefile(['nested'], tmpdir .. '/dir with spaces/nested.txt')

# ── Open pane in temp dir ──
execute 'cd' tmpdir
vproj#PaneOpen()
vproj#SwitchMode('file')

Assert(vproj#IsPaneVisible(), 'pane visible in special-char directory')
Assert(PaneCursorLine() == 3, 'cursor on first selectable item')

# ── Navigate through items without crashing ──
var max_iter: number = 30
var i: number = 0
while i < max_iter
  var cline: number = PaneCursorLine()
  if cline > 0
    var bline: list<string> = getbufline(bufnr('VPROJ'), cline)
    if !empty(bline) && bline[0] =~ 'file with spaces'
      break
    endif
  endif
  vproj#SelectNext()
  i += 1
endwhile
Assert(i < max_iter, 'found "file with spaces" in listing')

# ── Open file with spaces — verify it actually opened ──
var wins_before_file: number = winnr('$')
try
  execute "normal \<CR>"
  Assert(vproj#IsPaneVisible(), 'pane stays visible after opening spaced file')
  # Verify a new window was created for the opened file
  Assert(winnr('$') == wins_before_file, 'opening spaced file: reuses right panel (no new window)')
  # Verify the file exists as a buffer
  Assert(bufexists('file with spaces.txt'), 'opening spaced file: buffer exists for spaced name')
catch
  Assert(false, 'open spaced file error: ' .. v:exception)
endtry

# Close the opened file window and return to pane
var pane_wnr: number = bufwinnr(bufnr('VPROJ'))
var pane_wid: number = pane_wnr > 0 ? win_getid(pane_wnr) : 0
var all_wins: list<number> = range(1, winnr('$'))
for wnr in all_wins
  if wnr != pane_wnr
    var wid: number = win_getid(wnr)
    win_gotoid(wid)
    close!
    break
  endif
endfor
if pane_wid > 0
  win_gotoid(pane_wid)
endif

# ── Navigate into dir with spaces — verify nested content shown ──
vproj#SelectFirst()
i = 0
while i < max_iter
  var cline2: number = PaneCursorLine()
  if cline2 > 0
    var bline2: list<string> = getbufline(bufnr('VPROJ'), cline2)
    if !empty(bline2) && bline2[0] =~ 'dir with spaces'
      break
    endif
  endif
  vproj#SelectNext()
  i += 1
endwhile
Assert(i < max_iter, 'found "dir with spaces" in listing')

try
  execute "normal \<CR>"
  Assert(vproj#IsPaneVisible(), 'pane stays visible after navigating into spaced dir')
  # Verify nested file "nested.txt" appears in the listing
  Assert(PaneContains('nested.txt'), 'navigated into spaced dir: nested.txt appears in listing')
catch
  Assert(false, 'navigate into spaced dir error: ' .. v:exception)
endtry

# ── Navigate back up — verify original items reappear ──
vproj#SelectFirst()
try
  execute "normal \<CR>"
  Assert(vproj#IsPaneVisible(), 'pane stays visible after navigating back up')
  # Verify one of the original root items appears again
  Assert(PaneContains('file with spaces.txt'), 'navigated back up: file with spaces reappears')
catch
  Assert(false, 'navigate up error: ' .. v:exception)
endtry

# ── Cleanup ──
vproj#PaneClose()
execute 'cd' saved_cwd
silent! call delete(tmpdir, 'rf')
call delete(expand('~/.cache/vproj/session'))

echom ''
if failures == 0
  echom 'ALL SPECIAL CHARS TESTS PASSED.'
else
  echohl ErrorMsg
  echom failures .. ' SPECIAL CHARS TEST(S) FAILED.'
  echohl None
  cquit!
endif
qa!
