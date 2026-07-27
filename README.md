# vproj

Vim project manager. A sidebar pane for browsing files, switching buffers,
and managing project structure. Navigate with the keyboard — no commands needed.

## Install

**Option 1 — Install script (recommended):**

```bash
git clone https://github.com/clearbellpaleforest/vproj.git ~/dev/vproj
cd ~/dev/vproj
bash install.sh
```

The script creates `~/.vim/pack/bundle/start/vproj/` with symlinks to `plugin/`,
`autoload/`, and `doc/`. Vim's native package system loads the plugin automatically.

**Option 2 — Manual symlinks:**

Replace `~/.vim` with `$XDG_CONFIG_HOME/vim` if you use XDG.

```bash
mkdir -p ~/.vim/pack/bundle/start/vproj
ln -s ~/dev/vproj/src/plugin   ~/.vim/pack/bundle/start/vproj/plugin
ln -s ~/dev/vproj/src/autoload ~/.vim/pack/bundle/start/vproj/autoload
ln -s ~/dev/vproj/src/doc      ~/.vim/pack/bundle/start/vproj/doc
vim -c "helptags ~/.vim/pack/bundle/start/vproj/doc" -c q
```

**Option 3 — Plugin manager (vim-plug):**

```vim
Plug 'clearbellpaleforest/vproj'
```

## Key Map

`Tab` toggles the pane. `Shift-Tab` toggles in permanent mode (stays open until
you close it). Inside the pane:

### Navigation

| Key | Action |
|-----|--------|
| `<Down>` / `<Up>` | Move selection down / up |
| `Enter` | Open file, enter directory, or cycle mode (on menu line) |
| `.` | Parent directory (file and code mode) |
| `Ctrl-K` | Parent directory |
| `Ctrl-J` | Enter first subdirectory |
| `Ctrl-T` | Jump to first item |
| `Ctrl-B` | Jump to last item |
| `Ctrl-N` / `Ctrl-P` | Next / previous page |
| `<` / `>` | Shift nav indicators backward / forward |

### Nav Characters

Each line shows a colored character (`a` through `z`). Press that letter to
jump directly to the item. In file and code mode, opens the file or enters the
directory. In buf and qfix mode, moves the cursor without opening files.

All lowercase `a`–`z` are nav characters. Additional navigation uses arrow keys
and Ctrl-combinations.

### Mode Switching

Each mode has a distinct color on the menu line.

| Key | Mode | Color | Shows |
|-----|------|-------|-------|
| `Shift-F` | File | Yellow | Directory browsing, file sizes |
| `Shift-B` | Buf | Green | Open buffers with flags + line counts |
| `Shift-C` | Code | Blue | Project tree from .vproj |
| `Q` (temp mode) | Qfix | Blue | Quickfix list |
| `Enter` on menu line | — | — | Cycle to next mode |

`Q` in temporary mode switches to qfix. `Q` in permanent mode closes the pane.

### Git Actions

All git actions use the `\` prefix (file and code mode).

| Key | Action |
|-----|--------|
| `\s` | Stage / unstage file under cursor |
| `\d` | Open diff preview in vertical split |
| `\D` | Discard file changes (with confirmation) |
| `\c` | Commit with message prompt |
| `\p` | Push to remote |
| `\u` | Pull --ff-only from remote |
| `\b` | Switch branch (with prompt) |
| `\z` | Stash changes (optional message) |
| `\Z` | Pop a stash (shows list, select by index) |
| `\a` | Blame file under cursor |
| `Ctrl-G` | Toggle showing only git-changed files |

### Actions

| Key | Action |
|-----|--------|
| `Shift-R` | Refresh listing |
| `Shift-X` | Close selected buffer (buf mode only) |
| `Shift-T` | Toggle tree view (file mode) |
| `Shift-P` | Toggle file preview split |
| `+` / `-` | Include / exclude item (code mode) |
| `/` | Filter files by name pattern |
| `*` | Grep project and populate quickfix |
| `<Left>` / `<Right>` | Shrink / grow pane width |
| `F1` | Toggle info column (inside pane) |

### Close

| Key | Action |
|-----|--------|
| `Q` (perm mode) | Close pane |
| `Esc` | Close pane (temporary mode only) |
| `Tab` | Close pane (or toggle when outside pane) |

### Passthrough

These standard Vim keys work as usual inside the pane:

`0` `$` `^` `gg` `G` `H` `L` `Ctrl-F` `Ctrl-B` `Ctrl-D`
`Ctrl-U` `Ctrl-W` `%` `{` `}` `(` `)`

## Commands

`:VprojToggle`, `:VprojOpen`, `:VprojClose`, `:VprojRefresh`, `:VprojDiag`

## Configuration

```vim
" Show hidden files (starting with .). Default: hidden.
let g:vproj_show_dotfiles = 1

" Initial pane width in columns (20–80). Default: 40.
let g:vproj_pane_width_default = 40

" Per-mode width overrides. 0 = use default.
let g:vproj_pane_width_file = 0
let g:vproj_pane_width_buf = 0
let g:vproj_pane_width_code = 0
let g:vproj_pane_width_qfix = 0
```

## Remap

```vim
" Change the toggle key
nmap <F2> <Plug>VprojToggle

" Disable default Tab
nunmap <Tab>
```

## .vproj File Format

Code Mode reads a `.vproj` file at the project root to determine which files
and directories to include. Example:

```
Project Name: my-project
Project Root: /home/user/dev/my-project
Included Directories:
src
Included Files:
README.md
Excluded Directories:
.git
node_modules
Excluded Files:
.env
```

Lines starting with `#` are comments. See `:help vproj-file-format` for details.

## Requirements

Vim 9.0 or later.
