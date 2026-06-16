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

## Usage

`F4` toggles the project pane. Inside the pane:

| Key | Action |
|-----|--------|
| j / k | Move selection |
| h | Parent directory |
| l | Open file or enter directory |
| Enter | Open file or switch buffer |
| F | File mode — browse directories |
| D | Doc mode — switch open buffers |
| C | Code mode — project tree |
| r | Refresh |
| d | Close selected buffer (doc mode) |
| + / - | Include / exclude item (code mode) |
| Left / Right | Shrink / grow pane |
| . | Parent directory |
| q | Close pane |

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
