vim9script

# Integration test: file operations in file mode —
# :Copy :Delete :Rename :Move and the pane's <Delete> key.
# Run: vim -N -u NONE -S tests/integration/test_file_ops.vim -c 'qall!'
#
# Each answer is queued with test_feedinput() before the call that prompts.
# A refusal must happen before any prompt, so those cases queue nothing:
# a prompt reached by mistake reads EOF from stdin and the run fails.

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

def PaneLines(): list<string>
  var pbuf = bufnr('VPROJ')
  return pbuf <= 0 ? [] : getbufline(pbuf, 1, '$')
enddef

def PaneCursorText(): string
  var pbuf = bufnr('VPROJ')
  var wins = win_findbuf(pbuf)
  if empty(wins)
    return ''
  endif
  return get(getbufline(pbuf, line('.', wins[0])), 0, '')
enddef

def PaneLists(name: string): bool
  for l in PaneLines()
    if l =~ '\V' .. escape(name, '\') .. '\s' || l =~ '\V' .. escape(name, '\') .. '\$'
      return true
    endif
  endfor
  return false
enddef

# Move the pane selection onto the entry whose line shows `name`.
def SelectName(name: string): bool
  vproj#SelectFirst()
  for _ in range(60)
    if PaneCursorText() =~ '\V\<' .. escape(name, '\') .. '\>'
      return true
    endif
    vproj#SelectNext()
  endfor
  return false
enddef

def Reopen(): void
  if vproj#IsPaneVisible()
    vproj#PaneClose()
  endif
  vproj#PaneOpen()
  vproj#SwitchMode('file')
enddef

# ── Fixture ──
var tmpdir: string = resolve(fnamemodify(tempname(), ':p')) .. '_vproj_fileops'
mkdir(tmpdir .. '/sub', 'p')
mkdir(tmpdir .. '/other', 'p')
writefile(['alpha'], tmpdir .. '/alpha.txt')
writefile(['bravo'], tmpdir .. '/bravo.txt')
writefile(['make'], tmpdir .. '/Makefile')
writefile(['taken'], tmpdir .. '/taken.txt')
writefile(['in other'], tmpdir .. '/other/bravo.txt')
writefile(['dirty'], tmpdir .. '/dirty.txt')
writefile(['follow'], tmpdir .. '/follow.txt')
execute 'cd ' .. fnameescape(tmpdir)
Reopen()

# ── Surface ──
Assert(exists(':Copy') == 2, ':Copy command defined')
Assert(exists(':Delete') == 2, ':Delete command defined')
Assert(exists(':Rename') == 2, ':Rename command defined')
Assert(exists(':Move') == 2, ':Move command defined')
var pane_wid: number = win_findbuf(bufnr('VPROJ'))[0]
var del_map: string = ''
win_execute(pane_wid, 'del_map = maparg("<Delete>", "n")')
Assert(del_map =~ 'DeleteSelected', '<Delete> mapped in pane buffer')

# ── Copy ──
Assert(SelectName('alpha.txt'), 'select alpha.txt')
Copy
Assert(filereadable(tmpdir .. '/alpha_1.txt'), 'Copy creates alpha_1.txt')
Assert(readfile(tmpdir .. '/alpha_1.txt') == ['alpha'], 'Copy preserves contents')
Assert(PaneLists('alpha_1.txt'), 'pane lists alpha_1.txt after Copy')
Assert(SelectName('alpha.txt'), 'reselect alpha.txt')
Copy
Assert(filereadable(tmpdir .. '/alpha_2.txt'), 'second Copy skips taken name → alpha_2.txt')
Assert(readfile(tmpdir .. '/alpha.txt') == ['alpha'], 'Copy leaves source intact')
Assert(SelectName('Makefile'), 'select Makefile')
Copy
Assert(filereadable(tmpdir .. '/Makefile_1'), 'Copy of extensionless file → Makefile_1')

# ── Delete ──
Assert(SelectName('alpha_2.txt'), 'select alpha_2.txt')
test_feedinput('n')
Delete
Assert(filereadable(tmpdir .. '/alpha_2.txt'), 'Delete answered No keeps file')
test_feedinput("\<CR>")
Delete
Assert(filereadable(tmpdir .. '/alpha_2.txt'), 'Delete default (Enter) is No')
test_feedinput('y')
Delete
Assert(!filereadable(tmpdir .. '/alpha_2.txt'), 'Delete answered Yes removes file')
Assert(!PaneLists('alpha_2.txt'), 'pane drops alpha_2.txt after Delete')

# Delete key routes to the same operation
Assert(SelectName('Makefile_1'), 'select Makefile_1')
test_feedinput('y')
win_execute(pane_wid, 'call vproj#DeleteSelected()')
Assert(!filereadable(tmpdir .. '/Makefile_1'), 'DeleteSelected (Delete key) removes file')

# Unsaved buffer blocks Delete
execute 'badd ' .. fnameescape(tmpdir .. '/dirty.txt')
var dirty_bnr: number = bufnr(tmpdir .. '/dirty.txt')
bufload(dirty_bnr)
setbufline(dirty_bnr, 1, 'changed')
Assert(!!getbufvar(dirty_bnr, '&modified'), 'dirty.txt buffer is modified')
Assert(SelectName('dirty.txt'), 'select dirty.txt')
Delete
Assert(filereadable(tmpdir .. '/dirty.txt'), 'Delete refused while buffer has unsaved changes')
Assert(SelectName('dirty.txt'), 'select dirty.txt again')
Rename
Assert(filereadable(tmpdir .. '/dirty.txt'), 'Rename refused while buffer has unsaved changes')
setbufvar(dirty_bnr, '&modified', false)

# Directory refused
Assert(SelectName('sub'), 'select sub/')
Delete
Assert(isdirectory(tmpdir .. '/sub'), 'Delete refuses a directory')

# ── Rename ──
Assert(SelectName('bravo.txt'), 'select bravo.txt')
test_feedinput("\<C-U>charlie.txt\<CR>")
Rename
Assert(filereadable(tmpdir .. '/charlie.txt') && !filereadable(tmpdir .. '/bravo.txt'), 'Rename bravo → charlie')
Assert(readfile(tmpdir .. '/charlie.txt') == ['bravo'], 'Rename keeps contents')
Assert(PaneLists('charlie.txt') && !PaneLists('bravo.txt'), 'pane shows new name only')

Assert(SelectName('charlie.txt'), 'select charlie.txt')
test_feedinput("\<C-U>taken.txt\<CR>")
Rename
Assert(filereadable(tmpdir .. '/charlie.txt'), 'Rename onto existing name refused — source kept')
Assert(readfile(tmpdir .. '/taken.txt') == ['taken'], 'Rename onto existing name refused — target untouched')

Assert(SelectName('charlie.txt'), 'select charlie.txt')
test_feedinput("\<C-U>sub/x.txt\<CR>")
Rename
Assert(filereadable(tmpdir .. '/charlie.txt') && !filereadable(tmpdir .. '/sub/x.txt'), 'Rename with / refused')

Assert(SelectName('charlie.txt'), 'select charlie.txt')
test_feedinput("\<C-U>\<CR>")
Rename
Assert(filereadable(tmpdir .. '/charlie.txt'), 'Rename with empty answer cancels')

# Rename follows a buffer shown in a window
execute 'botright split ' .. fnameescape(tmpdir .. '/follow.txt')
var follow_wid: number = win_getid()
var old_follow_bnr: number = bufnr('%')
win_gotoid(pane_wid)
Assert(SelectName('follow.txt'), 'select follow.txt')
test_feedinput("\<C-U>followed.txt\<CR>")
Rename
Assert(filereadable(tmpdir .. '/followed.txt'), 'Rename of open file succeeds')
Assert(fnamemodify(bufname(winbufnr(follow_wid)), ':t') == 'followed.txt', 'window follows renamed file')
Assert(!bufexists(old_follow_bnr), 'old buffer wiped after Rename')
win_execute(follow_wid, 'close')

# ── Move ──
Assert(SelectName('charlie.txt'), 'select charlie.txt')
test_feedinput("\<C-U>" .. tmpdir .. "/sub\<CR>")
Move
Assert(filereadable(tmpdir .. '/sub/charlie.txt') && !filereadable(tmpdir .. '/charlie.txt'), 'Move charlie.txt → sub/')
Assert(!PaneLists('charlie.txt'), 'pane drops moved file')

writefile(['bravo again'], tmpdir .. '/bravo.txt')
vproj#Refresh()
Assert(SelectName('bravo.txt'), 'select new bravo.txt')
test_feedinput("\<C-U>" .. tmpdir .. "/other/\<CR>")
Move
Assert(filereadable(tmpdir .. '/bravo.txt'), 'Move onto existing file refused — source kept')
Assert(readfile(tmpdir .. '/other/bravo.txt') == ['in other'], 'Move onto existing file refused — target untouched')

Assert(SelectName('bravo.txt'), 'select bravo.txt')
test_feedinput("\<C-U>" .. tmpdir .. "/nope\<CR>")
Move
Assert(filereadable(tmpdir .. '/bravo.txt'), 'Move to missing directory refused')

Assert(SelectName('bravo.txt'), 'select bravo.txt')
test_feedinput("\<C-U>" .. tmpdir .. "/taken.txt\<CR>")
Move
Assert(filereadable(tmpdir .. '/bravo.txt') && readfile(tmpdir .. '/taken.txt') == ['taken'], 'Move to a file path refused')

# ── Mode guard ──
vproj#SwitchMode('buf')
var before: list<string> = sort(readdir(tmpdir))
Copy
Delete
Rename
Move
Assert(sort(readdir(tmpdir)) == before, 'commands do nothing outside file mode')
vproj#SwitchMode('file')

# ── Pane closed guard ──
vproj#PaneClose()
Copy
Assert(sort(readdir(tmpdir)) == before, 'Copy does nothing with pane closed')

# ── Cleanup ──
execute 'cd ' .. fnameescape(saved_cwd)
delete(tmpdir, 'rf')

echom ''
if failures == 0
  echom 'ALL TESTS PASSED.'
else
  echohl ErrorMsg | echom failures .. ' TEST(S) FAILED.' | echohl None
  cquit!
endif
qa!
