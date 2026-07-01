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

The script creates `~/.vim/pack/bundle/start/vproj/` with symlinks to `plugin/`, `autoload/`, and `doc/`. Vim's native package system will load the plugin automatically.

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

`Tab` toggles the pane. `Shift-Tab` toggles in permanent mode (stays open until you close it). Inside the pane:

### Navigation

| Key | Action |
|-----|--------|
| `j` / `<Down>` | Move selection down |
| `k` / `<Up>` | Move selection up |
| `h` | Parent directory |
| `Enter` | Open file or enter directory |
| `.` | Parent directory |
| `Ctrl-T` | Jump to first item |
| `Ctrl-B` | Jump to last item |
| `Ctrl-K` | Parent directory |
| `Ctrl-J` | Enter first subdirectory |

### Mode Switching

Each mode has a distinct color on the menu line so you know what you're in:

| Key | Mode | Color | Shows |
|-----|------|-------|-------|
| `Shift-F` | File | Yellow | Directory browsing, file sizes |
| `Shift-B` | Buf | Green | Open buffers with flags + line counts |
| `Shift-C` | Code | Blue | Project tree from .vproj |
| `q` | Qfix | Blue | Quickfix list entries (in temp mode; closes pane in permanent mode) |
| `Shift-L` | Log | Cyan | Git commit log — `Enter` for full diff |
| `Enter` on menu line | — | — | Cycle to next mode |

### Git Actions (file and code mode)

| Key | Action |
|-----|--------|
| `s` | Stage / unstage file under cursor |
| `d` | Open diff preview in vertical split |
| `D` | Discard file changes (with confirmation) |
| `c` | Commit with message prompt |
| `P` | Push to remote |
| `U` | Pull --ff-only from remote |
| `b` | Switch branch (with prompt) |
| `z` | Stash changes |
| `Z` | Pop a stash |
| `a` | Blame file under cursor |
| `Ctrl-G` | Toggle showing only git-changed files (file mode) |

### Actions

| Key | Action |
|-----|--------|
| `r` | Refresh listing |
| `x` | Close selected buffer (buf mode only) |
| `+` / `-` | Include / exclude item (code mode) |
| `T` | Toggle tree view (file mode — indented with expand/collapse) |
| `p` | Toggle file preview split (updates on cursor move) |
| `/` | Filter files by name pattern |
| `*` | Grep project and populate quickfix |
| `<Left>` / `<Right>` | Shrink / grow pane width |
| `F1` | Toggle info column (inside pane) |
| `>` / `<` | Shift nav indicators forward / backward |
| Nav characters | Jump to item by nav character (orange) |

### Paging

| Key | Action |
|-----|--------|
| `Ctrl-N` | Next page |
| `Ctrl-P` | Previous page |

### Close

| Key | Action |
|-----|--------|
| `Q` | Close pane |
| `Tab` | Close pane (or toggle when outside pane) |

### Standard Vim Keys (passthrough)

These work as usual inside the pane — we don't override them:

| Key(s) | Behavior |
|--------|----------|
| `0` `^` `$` | Line start / end |
| `?` | Search backward |
| `Ctrl-F` | Page down |
| `Ctrl-D` `Ctrl-U` | Half-page down / up |
| `Ctrl-W` keys | Window management |
| `%` `{` `}` `(` `)` | Jump / matching pair |

Or use commands: `:VprojToggle`, `:VprojOpen`, `:VprojClose`, `:VprojRefresh`, `:VprojDiag`.

Use `let g:vproj_show_dotfiles = 1` to show hidden files.

See `:help vproj` for full documentation.

## .vproj File Format

Code Mode reads a `.vproj` file at the project root to determine which files and directories to include. Example:

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

## Remap

```vim
" Change the toggle key
nmap <F2> <Plug>VprojToggle

" Disable default Tab
nunmap <Tab>
```

## Requirements

Vim 9.0 or later.
