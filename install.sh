#!/bin/bash
# install.sh — Install vproj to ~/.vim/pack/bundle/start/vproj
#
# Usage:
#   git clone https://github.com/clearbellpaleforest/vproj.git ~/dev/vproj
#   cd ~/dev/vproj
#   bash install.sh
set -e

SRC_DIR="$(cd "$(dirname "$0")" && pwd)"
TARGET_DIR="$HOME/.vim/pack/bundle/start/vproj"

mkdir -p "$TARGET_DIR"
ln -sf "$SRC_DIR/src/plugin" "$TARGET_DIR/plugin"
ln -sf "$SRC_DIR/src/autoload" "$TARGET_DIR/autoload"
ln -sf "$SRC_DIR/src/doc" "$TARGET_DIR/doc"
vim --cmd "helptags $TARGET_DIR/doc" --cmd "q" 2>/dev/null || true

echo "vproj installed. Start Vim and press F4 to open the project pane."
echo "Run :help vproj for documentation."
