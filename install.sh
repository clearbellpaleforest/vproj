#!/bin/bash
# install.sh — Install vproj to ~/.vim/pack/bundle/start/vproj
#
# Usage:
#   git clone https://github.com/clearbellpaleforest/vproj.git ~/dev/vproj
#   cd ~/dev/vproj
#   bash install.sh
set -e

SRC_DIR="$(cd "$(dirname "$0")" && pwd)"

# Respect XDG if set, otherwise default to ~/.vim
# Vim's 'packpath' includes ~/.vim regardless, but some distributions
# patch this — check XDG_CONFIG_HOME first.
if [ -n "$XDG_CONFIG_HOME" ]; then
  TARGET_DIR="$XDG_CONFIG_HOME/vim/pack/bundle/start/vproj"
elif [ -d "$HOME/.config/vim" ]; then
  TARGET_DIR="$HOME/.config/vim/pack/bundle/start/vproj"
else
  TARGET_DIR="$HOME/.vim/pack/bundle/start/vproj"
fi

mkdir -p "$TARGET_DIR"

# Link one directory of the repo into the install directory. Safe to re-run:
# an existing symlink is replaced in place (-n: do not follow it into the
# repo directory it points at, which would put a link inside the repo). An
# existing real file or directory is the user's, so refuse instead of
# writing into it.
link_dir() {
  local src="$1" name="$2"
  local dest="$TARGET_DIR/$name"
  if [ -e "$dest" ] && [ ! -L "$dest" ]; then
    echo "install.sh: $dest exists and is not a symlink; move it away and re-run." >&2
    exit 1
  fi
  ln -sfn "$src" "$dest"
}

link_dir "$SRC_DIR/src/plugin" plugin
link_dir "$SRC_DIR/src/autoload" autoload
link_dir "$SRC_DIR/src/doc" doc
link_dir "$SRC_DIR/bin" bin

# Build the help tags. $TARGET_DIR/doc links to src/doc, so this rewrites
# src/doc/tags in the repo.
if ! command -v vim >/dev/null 2>&1; then
  echo "install.sh: vim not found; links are in place but :help vproj has no tags." >&2
  exit 1
fi
VPROJ_DOC_DIR="$TARGET_DIR/doc" vim -N -u NONE -i NONE -es \
  -c "try | execute 'helptags ' . fnameescape(\$VPROJ_DOC_DIR) | catch | cquit | endtry" \
  -c 'qa!' </dev/null || {
  echo "install.sh: helptags failed for $TARGET_DIR/doc; :help vproj may not work." >&2
  exit 1
}

echo "vproj installed. Start Vim and press Tab to open the project pane."
echo "Run :help vproj for documentation."
