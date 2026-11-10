vim9script

# Enforces the ASCII-only rule (CLAUDE.md, doc/constraints.md): every piece of
# text vproj itself prints -- pane rows, status line, messages, help text, the
# chat banner -- is ASCII. Comments may be UTF-8. User data (file names) is not
# in the source, so it is unaffected.
#
# The check is line-based so it is simple to state and to run: a source line
# may contain non-ASCII only if it is a comment-only line (first non-blank
# character is #). A code line with a trailing comment must therefore be ASCII.
# Run: vim -N -u NONE -i NONE -S tests/unit/test_ascii_ui.vim -c 'cquit!'

set nomore
var failures: number = 0
var repo: string = fnamemodify(expand('<script>:p'), ':h:h:h')

def Assert(cond: bool, msg: string): void
  if !cond
    echohl ErrorMsg | echom 'FAIL: ' .. msg | echohl None
    failures += 1
  else
    echom 'PASS: ' .. msg
  endif
enddef

# Lines (as "N: text") that break the rule.
def Violations(lines: list<string>): list<string>
  var bad: list<string> = []
  var n: number = 0
  for line in lines
    n += 1
    if line =~ '[^\x00-\x7F]' && line !~ '^\s*#'
      bad->add(n .. ': ' .. strcharpart(trim(line), 0, 70))
    endif
  endfor
  return bad
enddef

# The scanner itself must be able to fail: a rule that cannot fire is not a
# rule (these checks would otherwise pass on an empty or broken scanner).
Assert(len(Violations(["echom 'a — b'"])) == 1, 'scanner: an em dash in a string is a violation')
Assert(len(Violations(["var x = 1  # note — here"])) == 1, 'scanner: non-ASCII in a trailing comment is a violation')
Assert(len(Violations(["# a comment — with a dash"])) == 0, 'scanner: a comment-only line may hold UTF-8')
Assert(len(Violations(["    # indented ══ comment"])) == 0, 'scanner: an indented comment-only line may hold UTF-8')
Assert(len(Violations(["echom 'plain ascii -- fine'"])) == 0, 'scanner: plain ASCII is fine')

var files: list<string> = [
  'src/plugin/vproj.vim',
  'src/autoload/vproj.vim',
  'src/autoload/vproj/ai.vim',
  'src/autoload/vproj/agent.vim',
  'bin/vproj-ai-chat',
  'install.sh',
]
for f in files
  var path: string = repo .. '/' .. f
  Assert(filereadable(path), f .. ' is readable')
  if !filereadable(path)
    continue
  endif
  var lines: list<string> = readfile(path)
  Assert(len(lines) > 10, f .. ' was read (' .. len(lines) .. ' lines)')
  var bad: list<string> = Violations(lines)
  Assert(empty(bad), f .. ': no non-ASCII outside comment-only lines' .. (empty(bad) ? '' : ' -- ' .. len(bad) .. ' found, first: ' .. bad[0]))
endfor

echom ''
if failures == 0
  echom 'ALL TESTS PASSED.'
else
  echohl ErrorMsg | echom failures .. ' TEST(S) FAILED.' | echohl None
  cquit!
endif
qa!
