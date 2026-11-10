# Installing vproj

## Requirements

- Vim 9.0+ compiled with `+vim9script`
- `git` on PATH for the git actions and project grep
- The AI add-on (`A` key) also needs `+terminal`, `bash` and `curl`

## Installation

The plugin lives under `src/` in the repository, so the repository root is
not itself a plugin directory. Cloning it straight into `pack/` does not work.

### Install script (recommended)

```bash
git clone https://github.com/clearbellpaleforest/vproj.git ~/dev/vproj
cd ~/dev/vproj
bash install.sh
```

`install.sh` creates `~/.vim/pack/bundle/start/vproj/` (or
`$XDG_CONFIG_HOME/vim/pack/bundle/start/vproj/` when `XDG_CONFIG_HOME` is set,
or `~/.config/vim/...` when `~/.config/vim` exists) and symlinks `plugin/`,
`autoload/` and `doc/` from `src/`, and `bin/` from the repository root. It
then builds the help tags. Vim's native package system loads the plugin on
start; no `packadd` is needed. Re-running the script is safe. It refuses to
write into an existing real (non-symlink) directory.

### Manual symlinks

```bash
mkdir -p ~/.vim/pack/bundle/start/vproj
ln -s ~/dev/vproj/src/plugin   ~/.vim/pack/bundle/start/vproj/plugin
ln -s ~/dev/vproj/src/autoload ~/.vim/pack/bundle/start/vproj/autoload
ln -s ~/dev/vproj/src/doc      ~/.vim/pack/bundle/start/vproj/doc
ln -s ~/dev/vproj/bin          ~/.vim/pack/bundle/start/vproj/bin
vim -c "helptags ~/.vim/pack/bundle/start/vproj/doc" -c q
```

### vim-plug

```vim
Plug 'clearbellpaleforest/vproj', {'rtp': 'src'}
```

The `{'rtp': 'src'}` option is required: it points Vim at `src/`.

## Verify

Start Vim and press `Tab` to open the project pane. `:help vproj` opens the
help file.
