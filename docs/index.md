# Vproj — Direct Selection Navigation for Vim

Vproj is a Vim plugin that replaces cursor-based tree navigation with
**Direct Selection Navigation (DSN)** — single-keystroke file access
that eliminates cursor traversal.

Every file, buffer, symbol, and git status entry is addressed by a
keyboard label in a flat sidebar. Press the label, open the file.
No cursor movement, no tree expansion, no search.

The sidebar is a command palette disguised as an IDE panel. Selection
cost is O(1) regardless of list size.

Vproj is written in pure VimScript (vim9script). No +lua, no Python,
no external dependencies required. Works on Vim 8.2+.

## Features

- **5 Modes**: Buffers, Files, Git, Symbols, Outline
- **36 Single-Key Labels**: 4 tiers of direct selection keys
- **Session Persistence**: Auto-save/restore workspace state
- **Named Workspaces**: Save/load named workspace configurations
- **Bookmarks**: Jump-to-position bookmarks
- **Git Integration**: Stage, unstage, and diff from the sidebar
- **Zero Dependencies**: Pure Vim9Script — no +lua, no Python

## Requirements

- Vim 8.2 or later

Optional but recommended:
- ctags (for symbols and outline modes)
- Git (for git status integration)
