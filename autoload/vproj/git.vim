vim9script

# autoload/vproj/git.vim — Git porcelain parser
# Provides status, stage, unstage, and diff operations via git CLI.
# Uses systemlist() / system() with shellescape() for all git commands.

# GetStatus runs git status --porcelain and returns parsed results.
# Returns: {ok: true, items: [{path, category, prefix}]} on success,
#          {ok: false, error: 'not a git repository'} on failure.
# Category is one of: 'staged', 'unstaged', 'untracked', 'conflict'.
# Prefix is one of:   'S',        'M',        'U',         'C'.
export def GetStatus(): dict<any>
  var root: string = vproj#project#FindRoot()
  var lines: list<string> = systemlist(
      'git -C ' .. shellescape(root) .. ' status --porcelain 2>/dev/null')
  if v:shell_error != 0
    return {ok: false, error: 'not a git repository'}
  endif

  var items: list<dict<any>> = []
  for line in lines
    # Minimum line length: 2 chars XY + 1 space separator.
    if line->len() < 3
      continue
    endif

    var x: string = line[0]
    var y: string = line[1]
    var path: string = line[3 : ]->trim()

    # Handle renames: git outputs "oldpath -> newpath", extract new name.
    if x == 'R' || y == 'R'
      var arrow: number = stridx(path, ' -> ')
      if arrow >= 0
        path = path[arrow + 4 : ]
      endif
    endif

    var entry: dict<any> = {path: path, category: '', prefix: ''}

    # Categorize by status codes (X = index, Y = working tree).
    if x == '?' && y == '?'
      entry.category = 'untracked'
      entry.prefix = 'U'
    elseif x == 'U' || y == 'U' || (x == 'A' && y == 'A') || (x == 'D' && y == 'D')
      entry.category = 'conflict'
      entry.prefix = 'C'
    elseif x != ' ' && x != '?'
      entry.category = 'staged'
      entry.prefix = 'S'
    elseif y != ' ' && y != '?'
      entry.category = 'unstaged'
      entry.prefix = 'M'
    endif

    items->add(entry)
  endfor

  return {ok: true, items: items}
enddef

# StageFile stages a file using git add.
# Returns true on success (exit code 0), false otherwise.
export def StageFile(filepath: string): bool
  var root: string = vproj#project#FindRoot()
  system('git -C ' .. shellescape(root) .. ' add ' .. shellescape(filepath)
      .. ' 2>/dev/null')
  return v:shell_error == 0
enddef

# UnstageFile unstages a file using git reset HEAD.
# Returns true on success (exit code 0), false otherwise.
export def UnstageFile(filepath: string): bool
  var root: string = vproj#project#FindRoot()
  system('git -C ' .. shellescape(root) .. ' reset HEAD ' .. shellescape(filepath)
      .. ' 2>/dev/null')
  return v:shell_error == 0
enddef

# GetDiff returns the git diff for a file as a list of lines.
# Returns an empty list on error.
export def GetDiff(filepath: string, staged: bool = false): list<string>
  var root: string = vproj#project#FindRoot()
  var flag: string = staged ? ' --cached' : ''
  var lines: list<string> = systemlist(
      'git -C ' .. shellescape(root) .. ' diff' .. flag .. ' ' .. shellescape(filepath)
      .. ' 2>/dev/null')
  if v:shell_error != 0
    return []
  endif
  return lines
enddef
