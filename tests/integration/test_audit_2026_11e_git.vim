vim9script

# Regression tests for the 2026-11e git audit. Each block pins one reproduced
# defect; the comment names what used to happen.
# Run: vim -N -u NONE -i NONE --not-a-term -S tests/integration/test_audit_2026_11e_git.vim -c 'cquit!'
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
var root: string = resolve(fnamemodify(tempname(), ':p')) .. '_vproj_audit11e'
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

def PaneHas(name: string): bool
  return !empty(filter(PaneLines(), (_, l) => l =~ '\V' .. escape(name, '\')))
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

def Porcelain(dir: string, path: string): string
  return trim(Git(dir, 'status --porcelain -- ' .. shellescape(path)), "\n", 2)
enddef

def Lines(path: string): list<string>
  return filereadable(path) ? readfile(path) : ['<missing>']
enddef

def LoadStatusCache(): void
  vproj#ToggleGitFilter()
  vproj#ToggleGitFilter()
enddef

# Run whatever test_feedinput() left unread, so a prompt that (correctly)
# never appeared cannot swallow keys meant for a later test. Only for calls
# that must NOT prompt: when a prompt consumed its keys, this Esc would reach
# the pane and close it.
def DrainInput(): void
  feedkeys("\<Esc>", 'xt')
enddef

const CANCEL_KEY: string = "\<C-c>"

def Msgs(): string
  return execute('messages')
enddef

# ── 1. \D on an intent-to-add file must not delete it ──
# Used to: `git add -N n.txt` gives ' A'; xy[0] is ' ', so the file fell to
# `restore --source=HEAD --staged --worktree`, which deleted n.txt (its content
# was never in git).
var d1: string = Repo('ita', ['base.txt'])
writefile(['precious work'], d1 .. '/n.txt')
Git(d1, 'add -N n.txt')
Assert(Porcelain(d1, 'n.txt') == ' A n.txt', 'ita fixture: status is " A": ' .. Porcelain(d1, 'n.txt'))
Fresh(d1)
Assert(SelectName('n.txt'), 'ita: n.txt listed')
test_feedinput("y\<CR>")
vproj#DiscardChanges()
Assert(filereadable(d1 .. '/n.txt'), 'ita: n.txt still exists after \D')
Assert(Lines(d1 .. '/n.txt') == ['precious work'], 'ita: content intact: ' .. string(Lines(d1 .. '/n.txt')))
Assert(Porcelain(d1, 'n.txt') == '?? n.txt', 'ita: file is untracked again: ' .. Porcelain(d1, 'n.txt'))

# ── 2. \D must not delete a gitignored file inside an untracked directory ──
# Used to: git status omits ignored files, so build.log under untracked
# newdir/ inherited '??' from the directory and \D deleted it.
var d2: string = Repo('ign', ['base.txt', '.gitignore'])
writefile(['*.log'], d2 .. '/.gitignore')
Git(d2, 'add .gitignore')
Git(d2, 'commit -qm ignore')
mkdir(d2 .. '/newdir', 'p')
writefile(['log'], d2 .. '/newdir/build.log')
writefile(['keep'], d2 .. '/newdir/keep.txt')
Fresh(d2 .. '/newdir')
LoadStatusCache()
Assert(SelectName('build.log'), 'ignored: build.log listed')
test_feedinput("y\<CR>")
vproj#DiscardChanges()
Assert(filereadable(d2 .. '/newdir/build.log'), 'ignored: build.log survives \D')
# Positive control: a genuinely untracked file in the same directory is still
# offered for deletion and deleted.
Assert(SelectName('keep.txt'), 'ignored: keep.txt listed')
test_feedinput("y\<CR>")
vproj#DiscardChanges()
Assert(!filereadable(d2 .. '/newdir/keep.txt'), 'ignored: genuinely untracked keep.txt is still deletable')

# ── 3. \D on an unmerged file refuses ──
# Used to: AA ran `rm --cached -f`, staging a deletion of a file that exists
# in HEAD and losing the conflict stages.
var d3: string = Repo('conf', ['a.txt'])
Git(d3, 'checkout -q -b side')
writefile(['side a'], d3 .. '/a.txt')
writefile(['side c'], d3 .. '/c.txt')
Git(d3, 'add -A')
Git(d3, 'commit -qm side')
Git(d3, 'checkout -q main')
writefile(['main a'], d3 .. '/a.txt')
writefile(['main c'], d3 .. '/c.txt')
Git(d3, 'add -A')
Git(d3, 'commit -qm main')
Git(d3, 'merge side')
Assert(Porcelain(d3, 'a.txt') == 'UU a.txt', 'conflict fixture: UU: ' .. Porcelain(d3, 'a.txt'))
Assert(Porcelain(d3, 'c.txt') =~ '^\(AA\|UU\) c.txt', 'conflict fixture: c.txt conflicted: ' .. Porcelain(d3, 'c.txt'))
var aa_dir: string = root .. '/conf_aa'
mkdir(aa_dir, 'p')
Git(aa_dir, 'init -q -b main')
writefile(['base'], aa_dir .. '/base.txt')
Git(aa_dir, 'add -A')
Git(aa_dir, 'commit -qm init')
Git(aa_dir, 'checkout -q -b side')
writefile(['side new'], aa_dir .. '/new.txt')
Git(aa_dir, 'add -A')
Git(aa_dir, 'commit -qm side')
Git(aa_dir, 'checkout -q main')
writefile(['main new'], aa_dir .. '/new.txt')
Git(aa_dir, 'add -A')
Git(aa_dir, 'commit -qm main')
Git(aa_dir, 'merge side')
Assert(Porcelain(aa_dir, 'new.txt') == 'AA new.txt', 'conflict fixture: AA: ' .. Porcelain(aa_dir, 'new.txt'))

for [dir, nm, code] in [[d3, 'a.txt', 'UU'], [aa_dir, 'new.txt', 'AA']]
  Fresh(dir)
  var before_status: string = Git(dir, 'status --porcelain')
  var before_content: list<string> = Lines(dir .. '/' .. nm)
  Assert(SelectName(nm), code .. ': ' .. nm .. ' listed')
  :messages clear
  test_feedinput("y\<CR>")
  vproj#DiscardChanges()
  DrainInput()
  Assert(Git(dir, 'status --porcelain') == before_status, code .. ': status untouched: ' .. Git(dir, 'status --porcelain'))
  Assert(Lines(dir .. '/' .. nm) == before_content, code .. ': content untouched')
  Assert(Msgs() =~ 'has a merge conflict -- resolve it first', code .. ': clear refusal message: ' .. Msgs())
endfor

# ── 4. A cached "not a repo" must not outlive `git init` ──
# Used to: GitRoot cached the negative answer; after `git init` outside Vim,
# \s said "No git changes" until Refresh.
var d4: string = root .. '/late_repo'
mkdir(d4, 'p')
writefile(['x'], d4 .. '/x.txt')
Fresh(d4)
LoadStatusCache()
Git(d4, 'init -q -b main')
Assert(SelectName('x.txt'), 'late init: x.txt listed')
vproj#GitStageToggle()
Assert(Porcelain(d4, 'x.txt') == 'A  x.txt', 'late init: \s stages in the new repo: ' .. Porcelain(d4, 'x.txt'))

# GitCommit also re-checks before deciding "Not in a git repository".
var d4b: string = root .. '/late_repo2'
mkdir(d4b, 'p')
writefile(['x'], d4b .. '/x.txt')
Fresh(d4b)
LoadStatusCache()
Git(d4b, 'init -q -b main')
Git(d4b, 'add -A')
test_feedinput("late commit\<CR>")
vproj#GitCommit()
Assert(trim(Git(d4b, 'log --format=%s')) == 'late commit', 'late init: commit works: ' .. trim(Git(d4b, 'log --format=%s')))

# ── 5. GitNoPrompt leaves a configured core.sshCommand alone ──
# Used to: GIT_SSH_COMMAND (set by GitNoPrompt) outranks core.sshCommand, so
# the user's configured ssh command was bypassed on push/pull.
var bin: string = root .. '/bin'
mkdir(bin, 'p')
var marker: string = root .. '/cfg_ssh.marker'
var def_log: string = root .. '/def_ssh.log'
writefile(['#!/bin/sh', 'echo "ARGS: $*" >> ' .. marker, 'exit 255'], bin .. '/cfgssh')
setfperm(bin .. '/cfgssh', 'rwxr-xr-x')
writefile(['#!/bin/sh', 'echo "ENV: ${GIT_SSH_COMMAND-<unset>}" >> ' .. def_log, 'echo "ARGS: $*" >> ' .. def_log, 'exit 255'], bin .. '/ssh')
setfperm(bin .. '/ssh', 'rwxr-xr-x')
$PATH = bin .. ':' .. saved_path
setenv('GIT_SSH_COMMAND', v:null)
setenv('GIT_SSH', v:null)

var d5: string = Repo('sshcfg', ['x.txt'])
Git(d5, 'remote add origin ssh://u@example.invalid/x.git')
Git(d5, 'config core.sshCommand ' .. shellescape(bin .. '/cfgssh -o Cfg=1'))
Git(d5, 'config branch.main.remote origin')
Git(d5, 'config branch.main.merge refs/heads/main')
Fresh(d5)
delete(marker)
vproj#GitPush()
Assert(filereadable(marker), 'sshCommand: push used the configured core.sshCommand')
Assert(filereadable(marker) && join(readfile(marker), ' ') =~ 'Cfg=1', 'sshCommand: configured args seen')
Assert(getenv('GIT_SSH_COMMAND') == v:null, 'sshCommand: push left GIT_SSH_COMMAND unset')
delete(marker)
vproj#GitPull()
Assert(filereadable(marker), 'sshCommand: pull used the configured core.sshCommand')
Assert(getenv('GIT_SSH_COMMAND') == v:null, 'sshCommand: pull left GIT_SSH_COMMAND unset')

# Nothing configured: the BatchMode default still applies.
var d5b: string = Repo('sshdef', ['x.txt'])
Git(d5b, 'remote add origin ssh://u@example.invalid/x.git')
Git(d5b, 'config branch.main.remote origin')
Git(d5b, 'config branch.main.merge refs/heads/main')
Fresh(d5b)
delete(def_log)
vproj#GitPush()
Assert(filereadable(def_log) && join(readfile(def_log), ' ') =~ 'BatchMode=yes', 'sshCommand: default path still adds BatchMode: ' .. string(Lines(def_log)))
Assert(getenv('GIT_SSH_COMMAND') == v:null, 'sshCommand: default path restores env')
$PATH = saved_path

# ── 6. Esc is cancel, not "empty" ──
# CANCEL_KEY is Ctrl-C: it takes the same cancel path through inputdialog()
# as Esc, but a lone Esc fed with test_feedinput() makes Vim wait for the rest
# of a possible key code and die on EOF when stdout is a file (as in
# tests/run_all.sh). Esc itself was verified by hand with stdout on a pipe.
# Used to: Esc returned '' from input(), which GitStashPush read as "auto
# message" (stashing the tree), GitStashPop as "top stash" (popping it) and
# PromptFilter as "clear the filter".
var d6: string = Repo('esc', ['base.txt', 'other.txt'])
writefile(['changed'], d6 .. '/base.txt')
Fresh(d6)
:messages clear
test_feedinput(CANCEL_KEY)
vproj#GitStashPush()
Assert(empty(trim(Git(d6, 'stash list'))), 'esc: stash push cancelled, no stash: ' .. Git(d6, 'stash list'))
Assert(Lines(d6 .. '/base.txt') == ['changed'], 'esc: working tree untouched')
Assert(Msgs() =~ 'Cancelled', 'esc: stash push says Cancelled: ' .. Msgs())
# Enter on an empty prompt keeps its meaning: auto-message stash.
test_feedinput("\<CR>")
vproj#GitStashPush()
Assert(!empty(trim(Git(d6, 'stash list'))), 'enter: empty message still stashes')
Assert(Lines(d6 .. '/base.txt') == ['base.txt'], 'enter: tree restored by stash')

:messages clear
test_feedinput(CANCEL_KEY)
vproj#GitStashPop()
Assert(!empty(trim(Git(d6, 'stash list'))), 'esc: stash pop cancelled, stash kept')
Assert(Lines(d6 .. '/base.txt') == ['base.txt'], 'esc: pop did not touch the tree')
Assert(Msgs() =~ 'Cancelled', 'esc: stash pop says Cancelled: ' .. Msgs())
test_feedinput("\<CR>")
vproj#GitStashPop()
Assert(empty(trim(Git(d6, 'stash list'))), 'enter: empty ref pops the top stash')
Assert(Lines(d6 .. '/base.txt') == ['changed'], 'enter: pop restored the change')

# PromptFilter: Esc keeps an active filter; emptied Enter clears it.
Fresh(d6)
test_feedinput("base\<CR>")
vproj#PromptFilter()
Assert(PaneHas('base.txt') && !PaneHas('other.txt'), 'filter: set to "base": ' .. string(PaneLines()))
test_feedinput(CANCEL_KEY)
vproj#PromptFilter()
Assert(PaneHas('base.txt') && !PaneHas('other.txt'), 'esc: filter kept: ' .. string(PaneLines()))
test_feedinput("\<C-u>\<CR>")
vproj#PromptFilter()
Assert(PaneHas('base.txt') && PaneHas('other.txt'), 'enter on emptied prompt clears the filter: ' .. string(PaneLines()))

# ── 7. Untracked-only stash reports honestly ──
# Used to: "Changes stashed" although git stash saved nothing.
var d7: string = Repo('untracked_only', ['base.txt'])
writefile(['u'], d7 .. '/new_untracked.txt')
Fresh(d7)
:messages clear
test_feedinput("\<CR>")
vproj#GitStashPush()
Assert(Msgs() !~ 'Changes stashed', 'nothing to stash: no false success: ' .. Msgs())
Assert(Msgs() =~ 'Nothing to stash (untracked files are not stashed)', 'nothing to stash: honest message: ' .. Msgs())
Assert(filereadable(d7 .. '/new_untracked.txt'), 'nothing to stash: file untouched')

# ── 8. GrepSearch with a newline in a file name ──
# Used to: output was split on "\n", so the name "g\nnl.txt" produced a bogus
# quickfix entry for "g" and dropped the real one.
var d8: string = Repo('grepnl', ['base.txt'])
writefile(['needle one'], d8 .. "/g\nnl.txt")
writefile(['needle two'], d8 .. '/plain.txt')
Git(d8, 'add -A')
Git(d8, 'commit -qm files')
Fresh(d8)
setqflist([], 'f')
test_feedinput("needle\<CR>")
vproj#GrepSearch()
var qf_names: list<string> = mapnew(getqflist(), (_, e) => bufname(e.bufnr))
sort(qf_names)
Assert(qf_names == [d8 .. "/g\nnl.txt", d8 .. '/plain.txt'], 'grep: newline name parsed whole: ' .. string(qf_names))
Assert(len(getqflist()) == 2, 'grep: exactly two entries')

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
