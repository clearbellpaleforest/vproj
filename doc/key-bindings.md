# Key Bindings

All keys below except `Tab` and `Shift-Tab` are buffer-local to the pane.
Lowercase `a-z` are navigation characters: each one jumps to the item that
shows that letter. Every action therefore uses a Shift key, a Ctrl key, or
a `\` prefix.

## Opening/Closing

| Key | Action |
|-----|--------|
| `Tab` | Toggle pane (temporary mode); global mapping, also closes it from inside the pane |
| `Shift-Tab` | Toggle pane (permanent mode) |
| `Esc` | Close pane (temporary mode only) |
| `Q` | Permanent mode: close pane. Temporary mode: switch to Qfix mode |

The alternate toggle key, pressed while the pane is open, switches between
temporary and permanent mode without closing the pane. `Tab` and `Shift-Tab`
are the defaults; remap through `<Plug>VprojToggle` and
`<Plug>VprojTogglePermanent`.

## Mode Switching

| Key | Mode |
|-----|------|
| `Shift-F` | File mode |
| `Shift-B` | Buffer mode |
| `Shift-C` | Code mode |
| `Q` (temporary mode) | Quickfix mode |
| `Enter` on the mode menu line (line 1) | Cycle File, Buf, Code, Qfix |

Reach the menu line with `Up` from the first item. There is no Log mode.

## Navigation

| Key | Action |
|-----|--------|
| `Down` / `Up` | Move selection down / up (wraps) |
| `.` or `Ctrl-K` | Go to parent directory (file and code mode) |
| `Ctrl-J` | Enter the first subdirectory |
| `Ctrl-T` / `Ctrl-B` | Jump to first / last item |
| `Enter` | Enter directory / open file / cycle mode (menu line) |
| `Ctrl-N` / `Ctrl-P` | Next / previous page |
| `>` / `<` | Letter the next / previous 26 items (more than 26 shown) |
| `a-z` | Nav character: jump to the item with that letter |

Nav characters open files and enter directories in file and code mode. In
buf and qfix mode they only move the cursor; press `Enter` to open.

`Enter` on a file (or buffer, or quickfix entry) opens it in the edit window.
In a temporary pane (`Tab`) the pane then closes; in a permanent pane
(`Shift-Tab`) it stays open and keeps focus.

## Actions

| Key | Action |
|-----|--------|
| `R` | Refresh |
| `X` | Close buffer (buf mode) |
| `Delete` | Delete the selected file (file mode, confirms; same as `:VprojDelete`) |
| `+` / `-` | Include / exclude item (code mode) |
| `F1` | Toggle info column (in the pane; outside it opens `:help`) |
| `T` | Toggle tree view (file mode) |
| `P` | Toggle file preview (file mode) |
| `/` | Filter by name |
| `*` | Grep project (fills the quickfix list) |
| `A` | AI chat terminal (all modes) |
| `?` | Key reference window (`q` closes it) |

## File Operations

Act on the file selected in the pane (file mode, files only):

| Command | Action |
|---------|--------|
| `:VprojCopy` | Copy to the first unused `name_N.ext` in the same directory |
| `:VprojDelete` | Delete, after a confirm prompt (default No); same as `Delete` |
| `:VprojRename` | Rename within the directory |
| `:VprojMove` | Move to another directory |

`:Copy`, `:Delete`, `:Rename` and `:Move` are short aliases, defined only
when no other plugin (for example vim-eunuch) already owns the name. The
`:Vproj*` names always exist.

## Git Actions (\ prefix)

File and code modes. All git actions use the `\` prefix, freeing lowercase
a-z for nav chars. Press `\` then the action key (e.g., `\s` to stage).

| Key | Action |
|-----|--------|
| `\s` | Stage / unstage file |
| `\d` | Diff preview (`q` closes) |
| `\D` | Discard changes (asks first) |
| `\c` | Commit |
| `\p` | Push |
| `\u` | Pull (ff-only) |
| `\b` | Switch branch |
| `\z` | Stash |
| `\Z` | Stash pop |
| `\a` | Blame (`q` closes) |
| `Ctrl-G` | Toggle git-filtered view (no `\` prefix) |

## Width

| Key | Action |
|-----|--------|
| `Left` | Shrink pane |
| `Right` | Grow pane |

## Add-ons

| Key / command | Action |
|---------------|--------|
| `A` (in the pane) | AI chat terminal (`vproj#ai#`) |
| `:VprojAiPrompt [prompt]` | One-shot AI prompt; `<Plug>VprojAiPrompt` |
| `:VprojAgent` | Run a coding-agent CLI in a terminal split; `<Plug>VprojAgent` has no default key |
