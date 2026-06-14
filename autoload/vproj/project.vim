vim9script

# autoload/vproj/project.vim — vim9script project root detection and file scanner.

export const RootMarkers: list<string> = [
  '.git',
  'package.json',
  'pyproject.toml',
  'Cargo.toml',
  'Makefile',
  'go.mod',
  'build.gradle',
  'pom.xml',
  'composer.json',
  'Gemfile',
  'mix.exs',
  'setup.py',
  'setup.cfg',
  'CMakeLists.txt',
  'meson.build',
]

const ExcludedDirs: list<string> = [
  '.git',
  'node_modules',
  '__pycache__',
  '.svn',
  '.hg',
  'target',
  'build',
  'dist',
  '.next',
]

# FindRoot walks up from start (or cwd) looking for project root markers.
# Returns the first directory containing any root marker, or start if none found.
export def FindRoot(start: string = ''): string
  var dir: string = start->empty() ? getcwd() : start
  dir = fnamemodify(dir, ':p')->substitute('/$', '', '')

  while true
    for marker in RootMarkers
      var markerPath: string = dir .. '/' .. marker
      if isdirectory(markerPath) || filereadable(markerPath)
        return dir
      endif
    endfor

    var parent: string = fnamemodify(dir, ':h')
    if parent == dir || parent == '/'
      # Reached filesystem root without finding a project marker.
      # Return the original starting directory instead of root.
      return start->empty() ? getcwd() : start
    endif
    dir = parent
  endwhile
  return dir
enddef

# ScanFiles recursively scans root for files and directories.
# opts.max_files limits the result count (default 5000).
# max_depth is fixed at 10 levels.
# Returns a sorted list of {name, path, is_dir} dicts (dirs first, then files).
export def ScanFiles(root: string, opts: dict<any> = {}): list<dict<any>>
  var max_files: number = get(opts, 'max_files', 5000)
  var result: list<dict<any>> = []
  const MAX_DEPTH: number = 10

  def ScanDir(dir: string, depth: number): void
    if depth > MAX_DEPTH || len(result) >= max_files
      return
    endif

    var entries: list<string> = []
    try
      entries = readdir(dir)
    catch
      return
    endtry
    var dirs: list<dict<any>> = []
    var files: list<dict<any>> = []

    for entry in entries
      var full: string = dir .. '/' .. entry

      # Skip symlinks entirely.
      if getftype(full) == 'link'
        continue
      endif

      if isdirectory(full)
        # Skip excluded directories.
        if ExcludedDirs->index(entry) >= 0
          continue
        endif
        dirs->add({name: entry .. '/', path: full, is_dir: true})
      elseif filereadable(full)
        files->add({name: entry, path: full, is_dir: false})
      endif
    endfor

    # Sort dirs by name, then files by name.
    sort(dirs, (a, b) => a.name < b.name ? -1
          \ : a.name > b.name ? 1
          \ : 0)
    sort(files, (a, b) => a.name < b.name ? -1
          \ : a.name > b.name ? 1
          \ : 0)

    for d in dirs
      if len(result) >= max_files
        return
      endif
      result->add(d)
      ScanDir(d.path, depth + 1)
    endfor

    for f in files
      if len(result) >= max_files
        return
      endif
      result->add(f)
    endfor
  enddef

  ScanDir(root, 0)
  return result
enddef
