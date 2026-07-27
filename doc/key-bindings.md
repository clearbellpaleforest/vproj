# Key Bindings

## Opening/Closing

| Key | Action |
|-----|--------|
| `Tab` | Toggle pane (temporary mode) |
| `Shift-Tab` | Toggle pane (permanent mode) |
| `Esc` | Close pane (temporary mode only) |
| `Q` | Close pane (always) |

## Mode Switching

| Key | Mode |
|-----|------|
| `Shift-F` | File mode |
| `Shift-B` | Buffer mode |
| `Shift-C` | Code mode |
| `Enter` on menu | Quickfix mode (via `[Q]fix` menu item) |

## Navigation

| Key | Action |
|-----|--------|
| `j` / `k` | Move cursor down / up |
| `h` / `.` | Go to parent directory |
| `Enter` | Enter directory / open file |
| `Ctrl-N` / `Ctrl-P` | Next / previous page |
| `>` / `<` | Shift nav indicators |
| `a-z, A-Z, 1-9` | Quick nav (jump to item by nav char) |

## Actions

| Key | Action |
|-----|--------|
| `r` | Refresh |
| `x` | Close buffer (buf mode) |
| `+` / `-` | Include / exclude item (code mode) |
| `F1` | Toggle info column |
| `T` | Toggle tree view (file mode) |
| `p` | Toggle file preview (file mode) |
| `/` | Filter files by name |
| `*` | Grep project (quickfix) |

## Git Actions (\ prefix)

All git actions use `\` prefix, freeing lowercase a-z for nav chars.
Press `\` then the action key (e.g., `\s` to stage).

| Key | Action |
|-----|--------|
| `\s` | Stage / unstage file |
| `\d` | Diff preview |
| `\D` | Discard changes |
| `\c` | Commit |
| `\p` | Push |
| `\u` | Pull (ff-only) |
| `\b` | Switch branch |
| `\z` | Stash |
| `\Z` | Stash pop |
| `\a` | Blame |
| `Ctrl-G` | Toggle git-filtered view |

## Width

| Key | Action |
|-----|--------|
| `Left` | Shrink pane |
| `Right` | Grow pane |
