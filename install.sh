#!/bin/bash
# install.sh — Install vproj to ~/.vim/pack/bundle/start/vproj
#
# Usage:
#   git clone https://github.com/clearbellpaleforest/vproj.git ~/dev/vproj
#   cd ~/dev/vproj
#   bash install.sh
set -e

# Path helpers, POSIX sh only. No `readlink -f` / `-m` (GNU-only; macOS before
# 12.3 and the BSDs lack them): a directory is resolved with `cd -P ... && pwd
# -P`, a path that may not exist yet by resolving its deepest existing
# ancestor and re-appending the rest, a symlink with plain `readlink PATH`
# (or `ls -ld` when there is no readlink).

# Print the target of the symlink $1 (an absolute path). Fails if it cannot.
vproj_link_target() {
  if command -v readlink >/dev/null 2>&1; then
    readlink "$1" 2>/dev/null && return 0
  fi
  _vl_out=$(ls -ld "$1" 2>/dev/null) || return 1
  case $_vl_out in
    *" -> "*) printf '%s\n' "${_vl_out#* -> }" ;;
    *) return 1 ;;
  esac
}

# Print the absolute, symlink-free form of $1, which need not exist: symlinks
# are followed (a dangling one by its target), ".." after a missing component
# is dropped textually like `readlink -m`. Fails on a symlink loop.
vproj_realpath() {
  _vr_p=$1
  case $_vr_p in /*) ;; *) _vr_p=$PWD/$_vr_p ;; esac
  _vr_rest=
  _vr_skip=0
  _vr_hops=0
  while :; do
    while [ "${_vr_p%/}" != "$_vr_p" ]; do _vr_p=${_vr_p%/}; done
    if [ -z "$_vr_p" ]; then
      _vr_p=/
    fi
    if [ -L "$_vr_p" ]; then
      _vr_hops=$((_vr_hops + 1))
      [ "$_vr_hops" -le 40 ] || return 1
      _vr_t=$(vproj_link_target "$_vr_p") || return 1
      case $_vr_t in
        /*) _vr_p=$_vr_t ;;
        *) _vr_p=${_vr_p%/*}/$_vr_t ;;
      esac
    elif [ -d "$_vr_p" ]; then
      _vr_d=$(cd -P -- "$_vr_p" 2>/dev/null && pwd -P) || return 1
      [ "$_vr_d" = / ] && _vr_d=
      printf '%s\n' "$_vr_d$_vr_rest"
      return 0
    elif [ "$_vr_p" = / ]; then
      return 1
    else
      _vr_base=${_vr_p##*/}
      _vr_p=${_vr_p%/*}
      case $_vr_base in
        .) ;;
        ..) _vr_skip=$((_vr_skip + 1)) ;;
        *)
          if [ "$_vr_skip" -gt 0 ]; then
            _vr_skip=$((_vr_skip - 1))
          else
            _vr_rest=/$_vr_base$_vr_rest
          fi
          ;;
      esac
    fi
  done
}

# Same, with python3's realpath as the last resort when the above fails.
vproj_resolve() {
  vproj_realpath "$1" && return 0
  if command -v python3 >/dev/null 2>&1; then
    python3 -c 'import os,sys;print(os.path.realpath(sys.argv[1]))' "$1" && return 0
  fi
  echo "install.sh: cannot resolve $1" >&2
  return 1
}

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

# Refuse before changing anything. Links are made only after every check has
# passed, so a refusal never leaves a partial install.
#
# 1. TARGET_DIR must not be the repo or inside it (e.g. a symlink into it):
#    the links would then be created inside the repo itself.
REPO_REAL="$(vproj_resolve "$SRC_DIR")" || exit 1
TARGET_REAL="$(vproj_resolve "$TARGET_DIR")" || exit 1
case "$TARGET_REAL/" in
  "$REPO_REAL"/*)
    echo "install.sh: $TARGET_DIR resolves to $TARGET_REAL, which is the vproj repo or inside it; nothing changed. Point it elsewhere." >&2
    exit 1
    ;;
esac

# 2. An existing real file or directory at a destination is the user's:
#    refuse instead of writing into it. An existing symlink is replaced.
LINKS="plugin:src/plugin autoload:src/autoload doc:src/doc bin:bin"
refused=0
for pair in $LINKS; do
  name="${pair%%:*}"
  dest="$TARGET_DIR/$name"
  if [ -e "$dest" ] && [ ! -L "$dest" ]; then
    echo "install.sh: $dest exists and is not a symlink; move it away and re-run." >&2
    refused=1
  fi
done
if [ "$refused" -ne 0 ]; then
  echo "install.sh: nothing changed." >&2
  exit 1
fi

mkdir -p "$TARGET_DIR"

# Link one directory of the repo into the install directory. Safe to re-run:
# an existing symlink is replaced in place (-n: do not follow it into the
# repo directory it points at, which would put a link inside the repo). A
# link that pointed somewhere else is announced.
link_dir() {
  ld_src="$1"
  ld_dest="$TARGET_DIR/$2"
  if [ -L "$ld_dest" ] && [ "$(vproj_resolve "$ld_dest")" != "$(vproj_resolve "$ld_src")" ]; then
    echo "install.sh: re-pointing $2: $(vproj_link_target "$ld_dest") -> $ld_src"
  fi
  # BSD and GNU ln both have -s -f -n; if this ln lacks one, replace by hand.
  if ! ln -sfn "$ld_src" "$ld_dest" 2>/dev/null; then
    [ -L "$ld_dest" ] && rm -f "$ld_dest"
    ln -s "$ld_src" "$ld_dest"
  fi
}

for pair in $LINKS; do
  link_dir "$SRC_DIR/${pair#*:}" "${pair%%:*}"
done

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
