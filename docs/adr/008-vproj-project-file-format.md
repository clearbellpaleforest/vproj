# ADR 008: .vproj Project File Format

- **Status**: Accepted
- **Date**: 2026-06-14
- **Author**: Aldous Thoreau
- **Supersedes**: [003-session-persistence.md](003-session-persistence.md)

## Context

The previous codebase used JSON session files for persistence and a separate
named-workspace system. There was no concept of a "project" as a first-class
entity with explicit include/exclude lists.

## Decision

Projects shall be stored in **`.vproj` files** in the project root directory.
The file format is line-oriented plain text, one directive per line.

### File Format

```
Project Name: vproj
Project Root: /home/user/dev/vproj
Included Directories:
  src
  doc
  tests
Included Files:
  README.md
  LICENSE
Excluded Directories:
  .git
  node_modules
  __pycache__
Excluded Files:
  *.swp
  *.swo
```

### Format Rules

1. **Line-oriented** — one directive or entry per line.
2. **Indented entries** — items under a directive are indented with 2 spaces.
3. **Glob patterns** — excluded files may use shell-style globs (`*.swp`, `*.o`).
4. **Comment lines** — lines starting with `#` are ignored.
5. **Trailing whitespace** — insignificant, stripped on parse.

### Project Discovery

When the hotkey is pressed:
1. Look for a `.vproj` file in the current directory.
2. If not found, traverse upward through parent directories.
3. If found in a parent directory, the project in that parent directory is
   opened but the **current root** is set to the current working directory.
4. If no `.vproj` file is found and traversal reaches `/home` or `/`, the
   pane opens with status `* (no project found)` and all files shown as
   unincluded (in parentheses).
5. Pressing Enter on the status line allows the user to set/change the
   project name, defaulting to the current directory name. Setting the name
   for the first time creates a new `.vproj` file. Changing the name renames
   the existing file.

## Options Considered

### Option A: Line-Oriented Plain Text (Chosen)
- **Pros**: Human-readable, easy to edit by hand, Vim-friendly
- **Cons**: Requires a custom parser

### Option B: JSON (Previous)
- **Pros**: Structured, standard
- **Cons**: Harder to edit by hand, quotes and brackets add noise

### Option C: Vim Script
- **Pros**: Natively executable
- **Cons**: RCE risk, too powerful for a config file

## Consequences

- **Positive**: `.vproj` files are readable and editable outside Vim.
- **Positive**: Project discovery is automatic — no explicit "open project" step.
- **Negative**: Custom parser required (though simple — line-by-line with prefix
  matching).
- **Negative**: The project file must be manually created for new projects
  (mitigated by the Enter-on-status-line creation flow).

## References

- [009-navigation-indicator-system](009-navigation-indicator-system.md)
- [010-mode-architecture](010-mode-architecture.md)
