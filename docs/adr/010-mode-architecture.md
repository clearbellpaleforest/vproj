# ADR 010: Mode Architecture

- **Status**: Accepted
- **Date**: 2026-06-14
- **Author**: Aldous Thoreau

## Context

The previous codebase had 5 modes (Buffers, Files, Git, Symbols, Outline) with
single-letter hotkeys (`b`, `f`, `g`, `s`, `o`). This consumed label keys and
mixed concerns (git status alongside file browsing, code symbols alongside
project structure).

## Decision

Three modes, accessed via Shift-letter hotkeys to avoid consuming navigation
indicator keys:

### Mode Selection Hotkeys

| Key | Mode | Purpose |
|-----|------|---------|
| `Shift-F` | File Mode | General file browsing and selection |
| `Shift-D` | Document Mode | Open buffer management |
| `Shift-C` | Code Mode | Project structure management |

### File Mode (F)

**Purpose**: General file browsing and selection.

**Display**:
- Directories and files in the current directory
- File size information in the info column (e.g., ` 324K`, `  45M`)
- Parent directory represented by `..`

**Info Column**: Exactly 5 characters, right-aligned, space-padded file sizes.

**Navigation**:
- Enter on `..` → navigate up a directory
- Ctrl-K → navigate up a directory
- Ctrl-J → navigate down into the first listed subdirectory (no-op if none)

**Status Label**: Shows current path. If it won't fit the pane width,
right-align the label.

### Document Mode (D)

**Purpose**: Management of open Vim buffers.

**Display**:
- Buffer names
- Modification status
- Active buffer status
- Line count (when buffer is loaded)

**Info Column**: Uses Vim's buffer flags (derived from `getbufinfo()`).
Flags include: `%` (current), `#` (alternate), `a` (active), `h` (hidden),
`+` (modified), `-` (modifiable off), `=` (readonly).

Buffer state shall be derived from `getbufinfo()` rather than reimplemented
from scratch.

### Code Mode (C)

**Purpose**: Management of project structure.

**Display**:
- Line 1: Mode menu
- Line 2: Project name with base directory as label
- Line 3: `.. [dir name]` for parent navigation
- Project tree (directories and files) shown relative to current root
- Below: non-included files/directories in parentheses

**Current Root**: The active subtree root. Initially the project root.
Navigating into a subdirectory changes the current root. Navigating up
via `..` moves toward the project root. Files outside the current root
are not displayed.

**Included/Excluded**: Files explicitly included in `.vproj` are always
shown. Excluded files are hidden. Non-included files in the current
directory are listed last, in parentheses.

## Options Considered

### Option A: Three Modes with Shift Hotkeys (Chosen)
- **Pros**: Doesn't consume single-char nav indicators, clean separation
- **Cons**: Shift-letter hotkeys are slightly slower to type

### Option B: Five Modes with Single-Letter Hotkeys (Previous)
- **Pros**: Faster single-key mode switching
- **Cons**: Consumes 5 of 36 nav indicator keys

## Consequences

- **Positive**: Mode hotkeys don't compete with nav indicator keys.
- **Positive**: Cleaner separation: file browsing, buffer management, project
  structure are distinct concerns.
- **Negative**: Git status and ctags symbols (previously separate modes) are
  deferred to future versions or integrated into File/Code mode.

## References

- [009-navigation-indicator-system](009-navigation-indicator-system.md)
- [011-display-management](011-display-management.md)
