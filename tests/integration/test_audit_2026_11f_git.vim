vim9script

# Regression tests for the 2026-11f git audit (round 2). Each block pins one
# reproduced defect; the comment names what used to happen.
# Run: vim -N -u NONE -i NONE --not-a-term -S tests/integration/test_audit_2026_11f_git.vim -c 'cquit!'
#
# Hermetic: the session cache and every fixture live under tempname(). Prompts
# are answered with test_feedinput() queued before the call that prompts.

$XDG_CACHE_HOME = tempname()
execute 'set rtp^=' .. fnameescape(fnamemodify(expand('<script>:p'), ':h:h:h') .. '/src')
runtime! plugin/vproj.vim
set nomore
set columns=160 lines=40
set ttimeout ttimeoutlen=0
$GIT_AUTHOR_NAME = 't'
$GIT_AUTHOR_EMAIL = 't@t'
$GIT_COMMITTER_NAME = 't'
$GIT_COMMITTER_EMAIL = 't@t'

var failures: number = 0
var saved_cwd: string = getcwd()
var saved_path: string = $PATH
var root: string = resolve(fnamemodify(tempname(), ':p')) .. '_vproj_audit11f'
mkdir(root, 'p')

def Assert(cond: bool, msg: string): void
  if !cond
    echohl ErrorMsg | echom 'FAIL: ' .. msg | echohl None
    failures += 1
  else
    echom 'PASS: ' .. msg
  endif
enddef

def Geometry(): void
  # A terminal-less Vim goes back to 80x24 after any system() call.
  set columns=160 lines=40
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

# Select by a word-bounded regex (names made of word characters).
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

# Select by a literal substring: names such as [ab].txt or * have no word
# boundary at their start. `exact` is also required to be the whole name cell.
def SelectLit(name: string): bool
  vproj#SelectFirst()
  for _ in range(80)
    var t: string = PaneCursorText()
    if stridx(t, name) >= 0 && t !~ '^\s*\(\.\.\|\.\)/\?\s*$'
      return true
    endif
    vproj#SelectNext()
  endfor
  return false
enddef

def PaneHas(name: string): bool
  return !empty(filter(PaneLines(), (_, l) => stridx(l, name) >= 0))
enddef

def Fresh(dir: string): void
  if vproj#IsPaneVisible()
    vproj#PaneClose()
  endif
  silent! only!
  silent! :%bwipeout!
  execute 'cd ' .. fnameescape(dir)
  Geometry()
  vproj#PaneOpen()
  vproj#SwitchMode('file')
  # A terminal-less Vim drops to 80x24 at the first system() call an action
  # makes; a narrow pane keeps room for the split that diff and blame open.
  vproj#SetPaneWidth(20)
enddef

def Git(dir: string, args: string): string
  return system('git -C ' .. shellescape(dir) .. ' ' .. args .. ' 2>&1')
enddef

def Repo(name: string, files: list<string>): string
  var d: string = root .. '/' .. name
  mkdir(d, 'p')
  for f in files
    mkdir(fnamemodify(d .. '/' .. f, ':h'), 'p')
    writefile([f], d .. '/' .. f)
  endfor
  Git(d, 'init -q -b main')
  Git(d, 'add -A')
  Git(d, 'commit -qm init')
  return d
enddef

def Edit(d: string, files: list<string>): void
  for f in files
    writefile([f, 'edit'], d .. '/' .. f)
  endfor
enddef

def Porcelain(dir: string): list<string>
  return split(Git(dir, 'status --porcelain'), "\n")
enddef

def Lines(path: string): list<string>
  return filereadable(path) ? readfile(path) : ['<missing>']
enddef

def Msgs(): string
  return execute('messages')
enddef

def LoadStatusCache(): void
  vproj#ToggleGitFilter()
  vproj#ToggleGitFilter()
enddef

# Answer a prompt with y and run \D on the named file.
def Discard(name: string): bool
  var ok: bool = SelectLit(name)
  if ok
    test_feedinput("y\<CR>")
    vproj#DiscardChanges()
  endif
  return ok
enddef

# ── 1. A path is a pathspec: \D on a file named [ab].txt discarded a.txt and
#    b.txt too ──
# Used to: `git restore --source=HEAD --staged --worktree -- [ab].txt` also
# matched a.txt and b.txt and silently threw their uncommitted edits away.
var gl: string = Repo('glob_d', ['a.txt', 'b.txt', '[ab].txt'])
Edit(gl, ['a.txt', 'b.txt', '[ab].txt'])
Fresh(gl)
Assert(Discard('[ab].txt'), 'glob \D: [ab].txt selected')
Assert(Lines(gl .. '/[ab].txt') == ['[ab].txt'], 'glob \D: [ab].txt itself is reverted: ' .. string(Lines(gl .. '/[ab].txt')))
Assert(Lines(gl .. '/a.txt') == ['a.txt', 'edit'], 'glob \D: a.txt keeps its uncommitted edit: ' .. string(Lines(gl .. '/a.txt')))
Assert(Lines(gl .. '/b.txt') == ['b.txt', 'edit'], 'glob \D: b.txt keeps its uncommitted edit: ' .. string(Lines(gl .. '/b.txt')))
Assert(Porcelain(gl) == [' M a.txt', ' M b.txt'], 'glob \D: status is exactly a.txt and b.txt modified: ' .. string(Porcelain(gl)))

# \s (git add -A -- path) on the same name stages only that file.
var gs: string = Repo('glob_s', ['a.txt', 'b.txt', '[ab].txt'])
Edit(gs, ['a.txt', 'b.txt', '[ab].txt'])
Fresh(gs)
Assert(SelectLit('[ab].txt'), 'glob \s: [ab].txt selected')
vproj#GitStageToggle()
Assert(split(Git(gs, 'diff --cached --name-only'), "\n") == ['[ab].txt'], 'glob \s: only [ab].txt is staged: ' .. string(split(Git(gs, 'diff --cached --name-only'), "\n")))
# ... and unstaging it (restore --staged) touches only it as well.
Edit(gs, ['a.txt'])
Git(gs, 'add a.txt')
Fresh(gs)
Assert(SelectLit('[ab].txt'), 'glob \s unstage: [ab].txt selected')
vproj#GitStageToggle()
Assert(split(Git(gs, 'diff --cached --name-only'), "\n") == ['a.txt'], 'glob \s unstage: a.txt stays staged: ' .. string(split(Git(gs, 'diff --cached --name-only'), "\n")))

# \d: the diff holds [ab].txt only.
var gd: string = Repo('glob_diff', ['a.txt', 'b.txt', '[ab].txt'])
Edit(gd, ['a.txt', 'b.txt', '[ab].txt'])
Fresh(gd)
Assert(SelectLit('[ab].txt'), 'glob \d: [ab].txt selected')
vproj#OpenDiffPreview()
var diff_bufs: list<dict<any>> = filter(getbufinfo(), (_, b) => stridx(b.name, 'vproj-diff:') >= 0)
Assert(len(diff_bufs) == 1, 'glob \d: a diff buffer opened')
var diff_text: list<string> = empty(diff_bufs) ? [] : getbufline(diff_bufs[0].bufnr, 1, '$')
Assert(!empty(filter(copy(diff_text), (_, l) => stridx(l, 'diff --git a/[ab].txt') == 0)), 'glob \d: the diff is of [ab].txt')
Assert(empty(filter(copy(diff_text), (_, l) => stridx(l, 'a/a.txt') >= 0 || stridx(l, 'a/b.txt') >= 0)), 'glob \d: a.txt and b.txt are not in the diff')

# \a (blame): a tracked [ab].txt is blamed; an UNTRACKED one is "not tracked"
# although the pathspec [ab].txt matches the tracked a.txt (ls-files said
# "tracked", then blame failed with an error).
var gb: string = Repo('glob_blame', ['a.txt', 'b.txt', '[ab].txt'])
Fresh(gb)
Assert(SelectLit('[ab].txt'), 'glob \a: [ab].txt selected')
vproj#GitBlame()
var blame_bufs: list<dict<any>> = filter(getbufinfo(), (_, b) => stridx(b.name, 'vproj-blame:') >= 0)
Assert(len(blame_bufs) == 1 && !empty(filter(getbufline(blame_bufs[0].bufnr, 1, '$'), (_, l) => l =~ '\[ab\]\.txt$')), 'glob \a: a tracked [ab].txt is blamed')
var gb2: string = Repo('glob_blame2', ['a.txt', 'b.txt'])
writefile(['untracked'], gb2 .. '/[ab].txt')
Fresh(gb2)
Assert(SelectLit('[ab].txt'), 'glob \a untracked: [ab].txt selected')
:messages clear
vproj#GitBlame()
Assert(Msgs() =~ 'File is not tracked by git', 'glob \a untracked: says not tracked: ' .. substitute(Msgs(), '\n', ' | ', 'g'))
Assert(Msgs() !~ 'Blame failed', 'glob \a untracked: no blame error')

# A file named * would match every file in the directory.
var gst: string = Repo('glob_star', ['a.txt', '*'])
Edit(gst, ['a.txt', '*'])
Fresh(gst)
Assert(Discard('*'), 'star \D: * selected')
Assert(Lines(gst .. '/*') == ['*'], 'star \D: the file * is reverted: ' .. string(Lines(gst .. '/*')))
Assert(Lines(gst .. '/a.txt') == ['a.txt', 'edit'], 'star \D: a.txt keeps its edit: ' .. string(Lines(gst .. '/a.txt')))

# Pathspec magic in a name: absolute paths never start with ':', so this
# passes without the option too (a control, not a red-at-HEAD test).
var gm: string = Repo('glob_magic', ['x', 'y', ':(top)x', ':!x'])
Edit(gm, ['x', 'y', ':(top)x', ':!x'])
Fresh(gm)
Assert(Discard(':(top)x'), 'magic \D: :(top)x selected')
Assert(Lines(gm .. '/:(top)x') == [':(top)x'], 'magic \D: :(top)x reverted')
Assert(Lines(gm .. '/x') == ['x', 'edit'], 'magic \D: x keeps its edit')
Assert(Discard(':!x'), 'magic \D: :!x selected')
Assert(Lines(gm .. '/:!x') == [':!x'], 'magic \D: :!x reverted')
Assert(Lines(gm .. '/y') == ['y', 'edit'], 'magic \D: y keeps its edit')

# An untracked file named [ab].txt is deleted alone (ls-files --others re-verify).
var gu: string = Repo('glob_untracked', ['a.txt', 'b.txt'])
writefile(['untracked'], gu .. '/[ab].txt')
writefile(['untracked a'], gu .. '/c.txt')
Fresh(gu)
Assert(Discard('[ab].txt'), 'untracked glob \D: [ab].txt selected')
Assert(!filereadable(gu .. '/[ab].txt'), 'untracked glob \D: the untracked [ab].txt is deleted')
Assert(filereadable(gu .. '/a.txt') && filereadable(gu .. '/b.txt') && filereadable(gu .. '/c.txt'), 'untracked glob \D: nothing else is touched')

# git diff --no-index -- /dev/null <untracked> still works with the option.
var gn: string = Repo('glob_noindex', ['a.txt'])
writefile(['brand new'], gn .. '/[n].txt')
Fresh(gn)
Assert(SelectLit('[n].txt'), 'no-index \d: [n].txt selected')
vproj#OpenDiffPreview()
var ni_bufs: list<dict<any>> = filter(getbufinfo(), (_, b) => stridx(b.name, 'vproj-diff:[n].txt') >= 0)
Assert(len(ni_bufs) >= 1 && !empty(filter(getbufline(ni_bufs[-1].bufnr, 1, '$'), (_, l) => l ==# '+brand new')), 'no-index \d: the untracked file diff shows its content')

# ── 1b. Repository-redirecting environment ──
# Used to: GIT_DIR / GIT_WORK_TREE in Vim's environment pointed git at another
# repository; with an empty one every tracked file looked untracked and \D
# deleted a modified tracked file.
var other: string = root .. '/other_empty'
mkdir(other, 'p')
Git(other, 'init -q -b main')

# vars: name -> value set while the action runs. Returns whether f.txt was
# reverted correctly (exists, back to its committed content) and each variable
# was restored afterwards.
def EnvScenario(label: string, vars: dict<string>): void
  var d: string = root .. '/env_' .. label
  mkdir(d, 'p')
  Git(d, 'init -q -b main')
  writefile(['f.txt'], d .. '/f.txt')
  Git(d, 'add -A')
  Git(d, 'commit -qm init')
  writefile(['f.txt', 'edit'], d .. '/f.txt')
  Fresh(d)
  var before: dict<any> = {}
  for [k, v] in items(vars)
    before[k] = getenv(k)
    setenv(k, v)
  endfor
  var ok: bool = SelectLit('f.txt')
  if ok
    test_feedinput("y\<CR>")
    vproj#DiscardChanges()
  endif
  var after: dict<any> = {}
  for k in keys(vars)
    after[k] = getenv(k)
  endfor
  for [k, v] in items(before)
    setenv(k, v)
  endfor
  Assert(ok, 'env ' .. label .. ': f.txt selected')
  Assert(filereadable(d .. '/f.txt'), 'env ' .. label .. ': tracked f.txt still exists after \D')
  Assert(Lines(d .. '/f.txt') == ['f.txt'], 'env ' .. label .. ': f.txt was reverted in ITS repository: ' .. string(Lines(d .. '/f.txt')))
  var restored: bool = true
  for [k, v] in items(vars)
    if after[k] != v
      restored = false
    endif
  endfor
  Assert(restored, 'env ' .. label .. ': the variables are restored after the call: ' .. string(after))
enddef

Assert(getenv('GIT_DIR') == v:null && getenv('GIT_WORK_TREE') == v:null, 'env fixture: GIT_DIR/GIT_WORK_TREE start unset')
EnvScenario('dirtree', {GIT_DIR: other .. '/.git', GIT_WORK_TREE: root .. '/env_dirtree'})
EnvScenario('index', {GIT_INDEX_FILE: root .. '/no_such_index'})
# Each of the other variables, set to a value that makes git fail or look at
# nothing, must not reach vproj's git calls.
EnvScenario('commondir', {GIT_COMMON_DIR: root .. '/no_such_common'})
EnvScenario('objdir', {GIT_OBJECT_DIRECTORY: root .. '/no_such_objects'})
EnvScenario('namespace', {GIT_NAMESPACE: 'vproj-bogus-ns'})
EnvScenario('gitdir_only', {GIT_DIR: other .. '/.git'})
Assert(getenv('GIT_DIR') == v:null && getenv('GIT_INDEX_FILE') == v:null, 'env: nothing leaked into the test process')

# GIT_NAMESPACE changes nothing for local commands, but a push to a local
# remote runs receive-pack with it and stores the refs under
# refs/namespaces/<ns>/: the push would land in the wrong place.
var gns: string = Repo('env_ns_push', ['f.txt'])
var gns_bare: string = root .. '/env_ns_push_remote.git'
system('git init -q --bare ' .. shellescape(gns_bare))
Git(gns, 'remote add origin ' .. shellescape(gns_bare))
Git(gns, 'config push.default current')
Fresh(gns)
setenv('GIT_NAMESPACE', 'vproj-bogus-ns')
vproj#GitPush()
setenv('GIT_NAMESPACE', v:null)
var ns_refs: string = system('git -C ' .. shellescape(gns_bare) .. ' for-each-ref --format="%(refname)"')
Assert(ns_refs =~ 'refs/heads/main' && ns_refs !~ 'namespaces', 'env GIT_NAMESPACE: the push landed in refs/heads, not in a namespace: ' .. substitute(ns_refs, '\n', ' ', 'g'))

# Variables the user did NOT set stay unset (v:null-safe restore); GIT_SSH and
# the prompt variables of the network helpers are untouched by the isolation.
$GIT_SSH_COMMAND = 'ssh -o Foo=bar'
EnvScenario('plain', {GIT_DIR: other .. '/.git', GIT_WORK_TREE: other})
Assert(getenv('GIT_SSH_COMMAND') == 'ssh -o Foo=bar', 'env: GIT_SSH_COMMAND is left alone')
unlet $GIT_SSH_COMMAND

# ── 1c. grep must search the right repository with GIT_DIR set ──
var gr0: string = Repo('grep_env', ['hay.txt'])
writefile(['needle in hay'], gr0 .. '/hay.txt')
Git(gr0, 'add -A')
Git(gr0, 'commit -qm hay')
Fresh(gr0)
setqflist([], 'f')
setenv('GIT_DIR', other .. '/.git')
setenv('GIT_WORK_TREE', other)
test_feedinput("needle\<CR>")
vproj#GrepSearch()
setenv('GIT_DIR', v:null)
setenv('GIT_WORK_TREE', v:null)
Assert(mapnew(getqflist(), (_, e) => bufname(e.bufnr)) == [gr0 .. '/hay.txt'], 'grep with GIT_DIR set: finds the match in the pane repository: ' .. string(mapnew(getqflist(), (_, e) => bufname(e.bufnr))))

# ── 2. GrepSearch ──
# (a) stderr no longer merges into stdout.
# Used to: an unreadable untracked file made git print an 'error:' line on
# stderr (exit 0); `2>&1` glued it onto the next record's file name.
var ga: string = Repo('grep_err', ['a.txt'])
writefile(['needle a'], ga .. '/a.txt')
Git(ga, 'add -A')
Git(ga, 'commit -qm a')
writefile(['needle u'], ga .. '/m_unreadable.txt')
writefile(['needle z'], ga .. '/z.txt')
setfperm(ga .. '/m_unreadable.txt', '---------')
Fresh(ga)
setqflist([], 'f')
if filereadable(ga .. '/m_unreadable.txt')
  Assert(true, 'grep stderr: skipped, this user can read a mode-000 file (root?)')
else
  test_feedinput("needle\<CR>")
  vproj#GrepSearch()
  var ga_names: list<string> = mapnew(getqflist(), (_, e) => bufname(e.bufnr))
  Assert(ga_names == [ga .. '/a.txt', ga .. '/z.txt'], 'grep stderr: no warning text in any file name: ' .. string(ga_names))
  Assert(empty(filter(copy(ga_names), (_, n) => !filereadable(n))), 'grep stderr: every quickfix file is openable')
endif
setfperm(ga .. '/m_unreadable.txt', 'rw-------')

# An error exit (invalid regex) reports git's own stderr text.
Fresh(ga)
:messages clear
test_feedinput("\\(\<CR>")
vproj#GrepSearch()
Assert(Msgs() =~ 'vproj: grep failed: .*\S', 'grep error: reported with git text: ' .. substitute(Msgs(), '\n', ' | ', 'g'))
Assert(Msgs() !~ 'no matches', 'grep error: not reported as "no matches"')

# (b) the parser is linear.
# Used to: matchstrpos with a start offset in a loop was quadratic: 20,000
# matches took 4 s, 50,000 plus a 3 MB line 37 s with Vim frozen.
# A fixed wall-clock bound measures how busy the machine is (it failed under
# CPU starvation although the parser was fine), so the check is the SCALING:
# an 8x larger result must take far less than 64x as long (linear ~8x,
# quadratic ~64x). Both timings slow down together on a loaded machine.
var gp: string = Repo('grep_perf', ['seed.txt'])
var small_lines: list<string> = []
for i in range(6250)
  small_lines->add('alpha ' .. i)
endfor
var big_lines: list<string> = []
for i in range(50000)
  big_lines->add('beta ' .. i)
endfor
writefile(small_lines, gp .. '/small.txt')
writefile(big_lines, gp .. '/big.txt')
writefile([repeat('x', 3000000) .. ' huge'], gp .. '/huge.txt')
Git(gp, 'add -A')
Git(gp, 'commit -qm big')
Fresh(gp)

def TimedGrep(pat: string): float
  setqflist([], 'f')
  test_feedinput(pat .. "\<CR>")
  var t0: list<number> = reltime()
  vproj#GrepSearch()
  return reltimefloat(reltime(t0))
enddef

TimedGrep('seed')
var t_small: float = TimedGrep('alpha')
Assert(len(getqflist()) == 6250, 'grep perf: 6,250 entries for the small result: ' .. len(getqflist()))
var t_big: float = TimedGrep('beta')
Assert(len(getqflist()) == 50000, 'grep perf: 50,000 entries for the big result: ' .. len(getqflist()))
var ratio: float = t_big / (t_small > 0.001 ? t_small : 0.001)
Assert(ratio < 24.0, 'grep perf: 8x the matches took ' .. printf('%.1f', ratio) .. 'x the time (linear ~8, quadratic ~64; ' .. printf('%.2f', t_small) .. ' s -> ' .. printf('%.2f', t_big) .. ' s)')
Assert(t_big < 60.0, 'grep perf: the 50,000-match grep finishes (hang guard): ' .. printf('%.2f', t_big) .. ' s')
TimedGrep('huge')
Assert(len(getqflist()) == 1, 'grep perf: a 3 MB single line yields one entry: ' .. len(getqflist()))
setqflist([], 'f')
Geometry()

# Identity with the old parser on a mixed fixture: new line in a name, SOH in
# the text, leading white space, nested directories, several matches per file.
def OldParse(output: string, rootdir: string): list<list<any>>
  var res: list<list<any>> = []
  var pos: number = 0
  while pos < strlen(output)
    var rec: list<any> = matchstrpos(output, '\_.\{-}\%x01\d\+\%x01[^\n]*\n', pos)
    if rec[1] < 0
      break
    endif
    pos = rec[2]
    var m: list<string> = matchlist(rec[0], '^\(\_.\{-}\)\%x01\(\d\+\)\%x01\([^\n]*\)\n$')
    if empty(m) || empty(m[1]) || str2nr(m[2]) <= 0
      continue
    endif
    res->add([rootdir .. '/' .. m[1], str2nr(m[2]), substitute(m[3], '^\s*', '', '')])
  endwhile
  return res
enddef

var gx: string = Repo('grep_mixed', ['seed.txt'])
mkdir(gx .. '/sub/deep', 'p')
writefile(['needle top', '   indented needle', 'none', 'NEEDLE upper'], gx .. '/top.txt')
writefile(["nee\x01dle with soh", "needle\x01\x01x"], gx .. '/soh.txt')
writefile(['needle in sub'], gx .. '/sub/deep/n.txt')
writefile(['needle in newline name'], gx .. "/g\nnl.txt")
writefile(['needle in 12 name'], gx .. '/12.txt')
Git(gx, 'add -A')
Git(gx, 'commit -qm mixed')
var raw: string = system('git -C ' .. shellescape(gx) .. ' grep --untracked -n -i -z -I -- needle 2>&1')
var expected: list<list<any>> = OldParse(raw, gx)
Fresh(gx)
setqflist([], 'f')
test_feedinput("needle\<CR>")
vproj#GrepSearch()
var got: list<list<any>> = mapnew(getqflist(), (_, e) => [bufname(e.bufnr), e.lnum, e.text])
Assert(len(expected) >= 7, 'grep parser: the fixture has the expected record count: ' .. len(expected))
Assert(got == expected, 'grep parser: identical to the old parser: ' .. string(got) .. ' vs ' .. string(expected))
Assert(!empty(filter(copy(got), (_, r) => r[0] == gx .. "/g\nnl.txt")), 'grep parser: g<NL>nl.txt attributed to its own name')
Assert(!empty(filter(copy(got), (_, r) => r[2] =~ "\x01")), 'grep parser: text containing SOH is kept whole')

# (c) -I hid binary-only matches as "no matches".
var gbin: string = Repo('grep_bin', ['seed.txt'])
writefile(0z6e6565646c6500.62696e0a, gbin .. '/a.bin', 'b')
Git(gbin, 'add -A')
Git(gbin, 'commit -qm bin')
Fresh(gbin)
setqflist([], 'f')
:messages clear
test_feedinput("needle\<CR>")
vproj#GrepSearch()
Assert(empty(getqflist()), 'grep binary: no quickfix entries for a binary-only match')
Assert(Msgs() =~ 'vproj: no text matches for: needle (1 binary files matched and were skipped)', 'grep binary: says why: ' .. substitute(Msgs(), '\n', ' | ', 'g'))
# A binary notice before a text record must not be glued to that record's name.
writefile(['needle text'], gbin .. '/b.txt')
Git(gbin, 'add -A')
Git(gbin, 'commit -qm text')
Fresh(gbin)
setqflist([], 'f')
test_feedinput("needle\<CR>")
vproj#GrepSearch()
var gbn: list<string> = mapnew(getqflist(), (_, e) => bufname(e.bufnr))
Assert(gbn == [gbin .. '/b.txt'], 'grep binary: notice is not turned into an entry or a file name: ' .. string(gbn))
:messages clear
Fresh(gbin)
test_feedinput("zzznomatch\<CR>")
vproj#GrepSearch()
Assert(Msgs() =~ 'vproj: no matches for: zzznomatch' && Msgs() !~ 'binary', 'grep binary: a plain miss still says "no matches"')

# ── 3. \D on an intent-to-add RENAME ──
# Used to: orig was read only for xy[0] == 'R' but the loader stores the source
# for either column, so the post-prompt re-check compared '' with 'old' and
# always said "changed while asking".
var gi: string = Repo('ita_rename', ['old.txt', 'keep.txt'])
Git(gi, 'mv old.txt new.txt')
Git(gi, 'reset -q')
Git(gi, 'add -N new.txt')
Assert(index(Porcelain(gi), ' R old.txt -> new.txt') >= 0 || index(Porcelain(gi), ' R new.txt -> old.txt') >= 0 || !empty(filter(Porcelain(gi), (_, l) => l =~ '^ R ')), 'ita rename fixture: status is " R": ' .. string(Porcelain(gi)))
Fresh(gi)
:messages clear
Assert(Discard('new.txt'), 'ita rename: new.txt selected')
Assert(Msgs() !~ 'changed while asking', 'ita rename: not aborted by the re-check: ' .. substitute(Msgs(), '\n', ' | ', 'g'))
Assert(Lines(gi .. '/new.txt') == ['old.txt'], 'ita rename: the file is kept with its content: ' .. string(Lines(gi .. '/new.txt')))
Assert(sort(Porcelain(gi)) == [' D old.txt', '?? new.txt'], 'ita rename: new.txt left the index, old.txt untouched: ' .. string(Porcelain(gi)))
Assert(Msgs() =~ 'Unstaged: new.txt', 'ita rename: reported as removed from the index')

# ── 4. The cancel sentinel cannot be typed ──
# Used to: "\x01vproj-cancel" typed with Ctrl-V Ctrl-A was taken as Esc.
var gc: string = Repo('cancel', ['base.txt'])
Fresh(gc)
:messages clear
test_feedinput("\<C-v>\<C-a>vproj-cancel\<CR>")
vproj#PromptFilter()
Assert(Msgs() !~ 'Cancelled', 'sentinel: the old fixed sentinel typed by hand does not cancel: ' .. substitute(Msgs(), '\n', ' | ', 'g'))
Assert(!PaneHas('base.txt'), 'sentinel: the typed text became the filter (base.txt filtered out)')
Fresh(gc)
:messages clear
test_feedinput("\<C-c>")
vproj#PromptFilter()
Assert(Msgs() =~ 'Cancelled', 'sentinel: Ctrl-C still cancels the prompt')
Assert(PaneHas('base.txt'), 'sentinel: a cancelled filter leaves the list alone')

# ── 5. Info() keeps the full text of destructive messages ──
# Used to: 'Deleted: <long name>' was shortened with '...' in the message
# history too, so :messages lost what was deleted.
var long_name: string = repeat('n', 200) .. '.txt'
var gm5: string = root .. '/info5'
mkdir(gm5, 'p')
writefile(['x'], gm5 .. '/' .. long_name)
Fresh(gm5)
Assert(SelectLit('nnnn'), 'info: long file selected')
:messages clear
var h_before: list<number> = mapnew(range(1, winnr('$')), (_, n) => winheight(n))
var ch_before: number = &cmdheight
test_feedinput("y")
vproj#DeleteSelected()
var m5: string = Msgs()
Assert(!filereadable(gm5 .. '/' .. long_name), 'info: the file was deleted')
var full_hits: number = len(split(m5, 'Deleted: ' .. long_name, 1)) - 1
Assert(full_hits == 1, 'info: :messages holds the FULL deleted name once: ' .. full_hits)
Assert(m5 !~ 'Deleted: n\+\.\.\.', 'info: the shortened form is not recorded as well')
Assert(&cmdheight == ch_before, 'info: cmdheight is restored: ' .. &cmdheight)
Assert(mapnew(range(1, winnr('$')), (_, n) => winheight(n)) == h_before, 'info: window heights are unchanged')

# Moved: a long destination directory.
var deep: string = gm5 .. '/' .. repeat('d', 100) .. '/' .. repeat('e', 100)
mkdir(deep, 'p')
writefile(['y'], gm5 .. '/mv.txt')
Fresh(gm5)
Assert(SelectLit('mv.txt'), 'info: mv.txt selected')
:messages clear
test_feedinput("\<C-u>" .. deep .. "\<CR>")
vproj#MoveSelected()
Assert(filereadable(deep .. '/mv.txt'), 'info: mv.txt was moved')
Assert(Msgs() =~ 'Moved mv.txt -> ' .. escape(deep, '.'), 'info: :messages holds the FULL Moved text')

# ── 6a. The nested-repo guard in LookupGitXY, on a DISPLAY path ──
# The ls-files re-verify of \D masks the guard; the git filter does not use it.
# A file inside a nested repo under an untracked directory must not be listed
# as a change of the outer repo.
var gnr: string = Repo('nested_disp', ['top.txt'])
mkdir(gnr .. '/sub', 'p')
writefile(['inner.txt'], gnr .. '/sub/inner.txt')
Git(gnr .. '/sub', 'init -q')
Git(gnr .. '/sub', 'add -A')
Git(gnr .. '/sub', 'commit -qm init')
mkdir(gnr .. '/plain', 'p')
writefile(['plain.txt'], gnr .. '/plain/plain.txt')
Fresh(gnr)
vproj#ToggleTreeView()
Assert(SelectName('sub'), 'nested display: sub/ listed')
vproj#SelectCurrent()
Assert(SelectName('plain'), 'nested display: plain/ listed')
vproj#SelectCurrent()
Assert(PaneHas('inner.txt'), 'nested display: inner.txt is shown unfiltered (the fixture works)')
vproj#ToggleGitFilter()
Assert(vproj#IsGitFilterActive(), 'nested display: git filter is on')
Assert(!PaneHas('inner.txt'), 'nested display: inner.txt (nested repo) is NOT listed as a change')
Assert(PaneHas('plain.txt'), 'nested display: plain.txt (genuinely untracked) IS listed: the filter works')
vproj#ToggleGitFilter()

# ── 6b. Layer i (check-ignore) alone decides for an ignored file ──
# Layer ii (the ls-files re-verify before delete) refuses the delete anyway,
# and \s does not delete at all: so the message is what pins layer i.
var gl1: string = Repo('layers', ['base.txt', '.gitignore'])
writefile(['*.log'], gl1 .. '/.gitignore')
Git(gl1, 'add .gitignore')
Git(gl1, 'commit -qm ignore')
mkdir(gl1 .. '/newdir', 'p')
writefile(['log'], gl1 .. '/newdir/build.log')
# keep.txt makes newdir/ show as untracked; a directory holding only ignored
# files is not listed by git status at all, and the test would pass without
# either layer.
writefile(['keep'], gl1 .. '/newdir/keep.txt')
Fresh(gl1 .. '/newdir')
LoadStatusCache()
Assert(SelectLit('build.log'), 'layer i: build.log listed')
:messages clear
vproj#GitStageToggle()
Assert(Msgs() =~ 'No git changes for build.log', 'layer i: \s on an ignored file says "No git changes": ' .. substitute(Msgs(), '\n', ' | ', 'g'))
Assert(Git(gl1, 'diff --cached --name-only') == '', 'layer i: nothing was staged')
:messages clear
# No prompt is expected, so nothing is fed: a prompt would read the (empty)
# stdin and end Vim, which fails the file.
vproj#DiscardChanges()
Assert(Msgs() =~ 'No git changes for build.log', 'layer i: \D on an ignored file says "No git changes" (not the layer-ii refusal): ' .. substitute(Msgs(), '\n', ' | ', 'g'))
Assert(filereadable(gl1 .. '/newdir/build.log'), 'layer i: build.log survives')

# ── 6c. Layer ii (ls-files --others re-verify) alone decides ──
# A fake `git` first in PATH commits the file the moment vproj runs the
# pre-delete `ls-files --others`: the status the prompt was answered against
# was '??', the re-verify finds it tracked. Nothing else in the flow can
# notice (the status re-check and check-ignore have already run).
var real_git: string = exepath('git')
var gl2: string = Repo('layer2', ['base.txt'])
mkdir(gl2 .. '/newdir', 'p')
writefile(['keep me'], gl2 .. '/newdir/keep.txt')
var bin2: string = root .. '/bin_seam'
mkdir(bin2, 'p')
var marker: string = root .. '/seam_fired'
writefile([
  '#!/bin/sh',
  'case "$*" in',
  '  *ls-files*--others*)',
  '    if [ ! -e ' .. shellescape(marker) .. ' ]; then',
  '      : > ' .. shellescape(marker),
  '      ' .. shellescape(real_git) .. ' -C ' .. shellescape(gl2) .. ' add -f -- newdir/keep.txt',
  '    fi ;;',
  'esac',
  'exec ' .. shellescape(real_git) .. ' "$@"',
], bin2 .. '/git')
setfperm(bin2 .. '/git', 'rwxr-xr-x')
Fresh(gl2 .. '/newdir')
LoadStatusCache()
Assert(SelectLit('keep.txt'), 'layer ii: keep.txt listed')
$PATH = bin2 .. ':' .. saved_path
:messages clear
test_feedinput("y\<CR>")
vproj#DiscardChanges()
$PATH = saved_path
Geometry()
Assert(filereadable(marker), 'layer ii: the seam fired on the pre-delete ls-files')
Assert(Lines(gl2 .. '/newdir/keep.txt') == ['keep me'], 'layer ii: the file that became tracked was NOT deleted: ' .. string(Lines(gl2 .. '/newdir/keep.txt')))
Assert(Msgs() =~ 'is not an untracked, unignored file', 'layer ii: refused by the re-verify: ' .. substitute(Msgs(), '\n', ' | ', 'g'))

# ── 6d. 11c section 16 again, asserting that the select succeeded ──
# The original only checks the file's content inside `if SelectName(...)`, so
# a failed select passed it vacuously.
var d16: string = Repo('nest16_par', ['top.txt'])
var d16in: string = d16 .. '/sub'
mkdir(d16in, 'p')
writefile(['inner.txt'], d16in .. '/inner.txt')
Git(d16in, 'init -q')
Git(d16in, 'add -A')
Git(d16in, 'commit -qm init')
writefile(['inner.txt', 'uncommitted edit'], d16in .. '/inner.txt')
Fresh(d16)
vproj#ToggleTreeView()
Assert(SelectName('sub'), 'nested untracked: sub/ is listed in the tree')
vproj#SelectCurrent()
var inner_selected: bool = SelectName('inner.txt')
Assert(inner_selected, 'nested untracked: inner.txt is selectable in the tree (the \D below really ran)')
if inner_selected
  :messages clear
  vproj#DiscardChanges()
  Assert(Msgs() =~ 'No git changes\|not an untracked\|nothing', 'nested untracked: \D refused or found nothing: ' .. substitute(Msgs(), '\n', ' | ', 'g'))
endif
Assert(Lines(d16in .. '/inner.txt') == ['inner.txt', 'uncommitted edit'], 'nested untracked: the inner repo file was not deleted or reverted by the outer repo, got ' .. string(Lines(d16in .. '/inner.txt')))

# ── Cleanup ──
$PATH = saved_path
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
