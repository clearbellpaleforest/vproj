# vproj

Vim project manager. A sidebar pane for browsing files and switching buffers.

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

`F4` toggles the pane (outside the pane). Inside the pane:

### Navigation

| Key | Action |
|-----|--------|
| `j` / `<Down>` | Move selection down |
| `k` / `<Up>` | Move selection up |
| `h` | Parent directory |
| `l` / `Enter` | Open file or enter directory |
| `.` | Parent directory |

### Mode Switching

| Key | Action |
|-----|--------|
| `F` | File mode — browse directories |
| `D` | Doc mode — switch open buffers |
| `C` | Code mode — project tree |
| `Enter` on menu line | Cycle to next mode |

### Actions

| Key | Action |
|-----|--------|
| `r` | Refresh listing |
| `x` | Close selected buffer (doc mode) |
| `+` / `-` | Include / exclude item (code mode) |
| `<Left>` / `<Right>` | Shrink / grow pane width |

### Close

| Key | Action |
|-----|--------|
| `q` | Close pane |
| `F4` | Close pane |

### Standard Vim Keys (passthrough)

These work as usual — we don't override them:

| Key(s) | Behavior |
|--------|----------|
| `f` `t` `T` | Find character on current line |
| `w` `b` `e` | Word motions |
| `0` `^` `$` | Line start / end |
| `gg` `G` | Buffer top / bottom |
| `/` `?` `n` `N` | Search |
| `y` | Yank (copy filename) |
| `Ctrl-F` `Ctrl-B` | Page down / up |
| `Ctrl-D` `Ctrl-U` | Half-page down / up |
| `Ctrl-W` keys | Window management |
| `%` `{` `}` `(` `)` | Jump / matching pair |
| `H` `M` `L` | High / middle / low of screen |
| `zz` `zt` `zb` | Scroll cursor to center / top / bottom |

Or use commands: `:VprojToggle`, `:VprojOpen`, `:VprojClose`, `:VprojRefresh`.

Use `let g:vproj_show_dotfiles = 1` to show hidden files.

See `:help vproj` for full documentation.

## Remap

```vim
" Change the toggle key
nmap <F2> <Plug>VprojToggle

" Disable default F4
nunmap <F4>
```

## Requirements

Vim 9.0 or later.
