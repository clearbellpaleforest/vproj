#!/usr/bin/env bash
# NAM plugin installer — one-command setup for Vim/Neovim
#
# SECURITY: Do NOT pipe this script directly through bash from the internet.
# Instead, download it first, inspect it, then run:
#
#   wget https://github.com/clearbellpaleforest/vproj/raw/main/install.sh
#   chmod +x install.sh
#   ./install.sh
#
# Or clone the repo and run from source:
#   git clone https://github.com/clearbellpaleforest/vproj
#   cd nam && bash install.sh
#
# Usage:
#   ./install.sh            Install for any detected platform (default: both)
#   ./install.sh --vim      Install for Vim only
#   ./install.sh --nvim     Install for Neovim only
#   ./install.sh --both     Explicitly install for both
#   ./install.sh --check    Verify installation state without making changes
#   ./install.sh --uninstall  Remove NAM plugin files
#   ./install.sh --help     Show this message
#
# All original flags (--vim, --nvim, --both, no-arg) behave identically
# to previous versions. Existing installations are preserved and updated.

set -euo pipefail

PLUGIN_NAME="vproj"
PLUGIN_REPO="https://github.com/clearbellpaleforest/${PLUGIN_NAME}"
VIM_PACK="${HOME}/.vim/pack/bundle/start/${PLUGIN_NAME}"
NVIM_PACK="${HOME}/.local/share/nvim/site/pack/bundle/start/${PLUGIN_NAME}"

# All files that must exist for a valid installation
REQUIRED_FILES=(
    lua/vproj/init.lua
    lua/vproj/config.lua
    lua/vproj/core/navigation.lua
    lua/vproj/core/project.lua
    lua/vproj/core/persistence.lua
    lua/vproj/adapters/compat.lua
    lua/vproj/adapters/git.lua
    lua/vproj/adapters/lsp.lua
    lua/vproj/adapters/treesitter.lua
    lua/vproj/modes/init.lua
    lua/vproj/modes/buffers.lua
    lua/vproj/modes/files.lua
    lua/vproj/modes/git.lua
    lua/vproj/modes/symbols.lua
    lua/vproj/modes/outline.lua
    lua/vproj/ui/labels.lua
    lua/vproj/ui/renderer.lua
    lua/vproj/ui/sidebar.lua
    lua/vproj/utils/events.lua
    lua/vproj/utils/cache.lua
    plugin/vproj.lua
)

# ── Terminal colors ────────────────────────────────────────────────
if [ -t 1 ]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    BOLD='\033[1m'
    NC='\033[0m'
else
    RED=''; GREEN=''; YELLOW=''; BLUE=''; BOLD=''; NC=''
fi

# ── Output helpers ─────────────────────────────────────────────────
ok()     { echo -e "${GREEN}  OK${NC}  $*"; }
info()   { echo -e "${BLUE}  ..${NC}  $*"; }
warn()   { echo -e "${YELLOW} WARN${NC}  $*"; }
fail()   { echo -e "${RED} FAIL${NC}  $*"; }
header() { echo -e "\n${BOLD}==${NC} $* ${BOLD}=="; }

# ── Cleanup trap ───────────────────────────────────────────────────
# On non-zero exit, remove any directories we created during install
_INSTALLED_DIRS=()
_cleanup() {
    local ec=$?
    if [ "$ec" -ne 0 ] && [ ${#_INSTALLED_DIRS[@]} -gt 0 ]; then
        echo ""
        warn "Installation did not complete. Cleaning up partial files..."
        for d in "${_INSTALLED_DIRS[@]}"; do
            if [ -d "$d" ]; then
                rm -rf "$d" 2>/dev/null
                info "Removed incomplete: ${d}"
            fi
        done
    fi
    exit "$ec"
}
trap _cleanup EXIT

# ── Path helpers ───────────────────────────────────────────────────
# Where is THIS script located? Used to detect local-repo installs.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd 2>/dev/null || pwd)"

is_repo_root() {
    # True if we are inside the vproj source tree
    [ -f "${SCRIPT_DIR}/lua/vproj/init.lua" ] && [ -f "${SCRIPT_DIR}/plugin/vproj.lua" ]
}

# ── Verification helpers ───────────────────────────────────────────

# Verify all required plugin files exist under a given pack directory.
verify_files() {
    local dir="$1"
    local label="$2"
    local missing=0

    for f in "${REQUIRED_FILES[@]}"; do
        if [ ! -f "${dir}/${f}" ]; then
            fail "Missing required file: ${dir}/${f}"
            missing=1
        fi
    done

    if [ "$missing" -eq 1 ]; then
        fail "${label} installation at ${dir} is incomplete or corrupted"
        return 1
    fi
    ok "All ${label} plugin files present at ${dir}"
    return 0
}

# Verify file checksums against the SHA256SUMS manifest bundled
# with the repository. Only works when run from the repo root or
# when the manifest exists alongside the installed files.
verify_checksums() {
    local dir="$1"
    local sums_file="${dir}/SHA256SUMS"

    if [ ! -f "$sums_file" ]; then
        # Try repo-root copy
        sums_file="${SCRIPT_DIR}/SHA256SUMS"
    fi

    if [ ! -f "$sums_file" ]; then
        warn "SHA256SUMS not found — skipping checksum verification"
        return 0
    fi

    if ! command -v sha256sum &>/dev/null; then
        warn "sha256sum not available — skipping checksum verification"
        return 0
    fi

    if (cd "$dir" && sha256sum -c --quiet "$sums_file" 2>/dev/null); then
        ok "Checksums verified (all files match SHA256SUMS)"
        return 0
    else
        fail "Checksum mismatch! Files may be corrupted."
        info "Re-run install to repair, or manually verify with:"
        info "  cd ${dir} && sha256sum -c SHA256SUMS"
        return 1
    fi
}

# ── Platform detection ─────────────────────────────────────────────

check_vim_lua() {
    command -v vim &>/dev/null || return 1

    local vim_ver
    vim_ver="$(vim --version 2>&1 | head -1 | grep -oP 'IMproved \K[\d]+\.[\d]+' || echo "unknown")"

    if ! vim --version 2>&1 | grep -q '+lua'; then
        warn "Vim ${vim_ver} found but WITHOUT Lua support (+lua missing)"
        info "Install vim-nox or compile Vim with --enable-luainterp"
        return 1
    fi

    # Check minimum version (8.2+)
    local major minor
    major="$(echo "$vim_ver" | cut -d. -f1)"
    minor="$(echo "$vim_ver" | cut -d. -f2)"
    if [ -n "$major" ] && [ -n "$minor" ] && [ "$major" -lt 8 ] || { [ "$major" -eq 8 ] && [ "$minor" -lt 2 ]; }; then
        warn "Vim ${vim_ver} is too old. NAM requires Vim 8.2+ with Lua support."
        return 1
    fi

    info "Found Vim ${vim_ver} with Lua support"
    return 0
}

check_nvim() {
    command -v nvim &>/dev/null || return 1
    local nvim_ver
    nvim_ver="$(nvim --version 2>&1 | head -1 | grep -oP 'v[\d]+\.[\d]+' || echo "unknown")"
    info "Found Neovim ${nvim_ver}"
    return 0
}

check_git() {
    if command -v git &>/dev/null; then
        return 0
    fi
    fail "git is required for installation (install git and try again)"
    return 1
}

# ── Install logic ──────────────────────────────────────────────────

# Install from a local source tree (when install.sh is run from the repo).
install_from_local() {
    local dir="$1"
    local label="$2"

    info "Installing from local source (${SCRIPT_DIR})..."

    mkdir -p "${dir}/lua" "${dir}/plugin"

    cp -r "${SCRIPT_DIR}/lua/nam" "${dir}/lua/"
    cp "${SCRIPT_DIR}/plugin/vproj.lua" "${dir}/plugin/"

    if [ -f "${SCRIPT_DIR}/SHA256SUMS" ]; then
        cp "${SCRIPT_DIR}/SHA256SUMS" "${dir}/"
    fi

    verify_files "$dir" "$label" || return 1
    verify_checksums "$dir" || return 1

    return 0
}

# Install (or update) by cloning from GitHub.
install_from_git() {
    local dir="$1"
    local label="$2"

    if [ -d "${dir}/.git" ]; then
        # ── Update existing installation ──
        info "Existing installation found at ${dir}, updating..."

        # Capture current HEAD so we can report what changed
        local old_head
        old_head="$(git -C "$dir" rev-parse --short HEAD 2>/dev/null || echo "unknown")"

        if ! git -C "$dir" pull --ff-only; then
            fail "Update failed. Try removing ${dir} and re-running."
            return 1
        fi

        local new_head
        new_head="$(git -C "$dir" rev-parse --short HEAD 2>/dev/null || echo "unknown")"

        if [ "$old_head" != "$new_head" ]; then
            info "Updated from ${old_head} to ${new_head}"
        else
            info "Already at the latest version (${old_head})"
        fi
    else
        # ── Fresh clone ──
        info "Cloning ${PLUGIN_REPO} ..."
        if ! git clone --depth 1 "$PLUGIN_REPO" "$dir"; then
            # Clean up partial clone on failure
            rm -rf "$dir" 2>/dev/null
            fail "Clone failed. Check your network connection and repo URL."
            return 1
        fi
        local head
        head="$(git -C "$dir" rev-parse --short HEAD 2>/dev/null || echo "unknown")"
        info "Cloned at commit ${head}"
    fi

    verify_files "$dir" "$label" || return 1
    verify_checksums "$dir" || return 1

    return 0
}

install_to() {
    local dir="$1"
    local label="$2"

    if is_repo_root; then
        install_from_local "$dir" "$label"
    else
        install_from_git "$dir" "$label"
    fi

    # Register for cleanup trap (removed on failure only)
    _INSTALLED_DIRS+=("$dir")
}

# ── Check mode (read-only) ─────────────────────────────────────────

do_check() {
    local exit_code=0

    header "NAM Installation Check"

    # ---- Vim ----
    if command -v vim &>/dev/null; then
        if vim --version 2>&1 | grep -q '+lua'; then
            ok "Vim with Lua support detected"
        else
            warn "Vim detected but without Lua support (+lua missing)"
        fi
        if [ -d "$VIM_PACK" ]; then
            if verify_files "$VIM_PACK" "Vim" 2>/dev/null; then
                ok "NAM installed for Vim at ${VIM_PACK}"
                local ver
                ver="$(git -C "$VIM_PACK" log --oneline -1 2>/dev/null || echo "(non-git install)")"
                info "  ${ver}"
            else
                warn "NAM installation for Vim is incomplete at ${VIM_PACK}"
                exit_code=1
            fi
        else
            info "NAM not installed for Vim (${VIM_PACK} does not exist)"
        fi
    else
        info "Vim not found on this system"
    fi

    # ---- Neovim ----
    if command -v nvim &>/dev/null; then
        ok "Neovim detected"
        if [ -d "$NVIM_PACK" ]; then
            if verify_files "$NVIM_PACK" "Neovim" 2>/dev/null; then
                ok "NAM installed for Neovim at ${NVIM_PACK}"
                local ver
                ver="$(git -C "$NVIM_PACK" log --oneline -1 2>/dev/null || echo "(non-git install)")"
                info "  ${ver}"
            else
                warn "NAM installation for Neovim is incomplete at ${NVIM_PACK}"
                exit_code=1
            fi
        else
            info "NAM not installed for Neovim (${NVIM_PACK} does not exist)"
        fi
    else
        info "Neovim not found on this system"
    fi

    # ---- Git ----
    if command -v git &>/dev/null; then
        ok "Git detected"
    else
        warn "Git not found (required for installation via git clone)"
    fi

    # ---- Checksums (if available) ----
    if [ -f "$VIM_PACK/SHA256SUMS" ]; then
        verify_checksums "$VIM_PACK" || exit_code=1
    fi
    if [ -f "$NVIM_PACK/SHA256SUMS" ]; then
        verify_checksums "$NVIM_PACK" || exit_code=1
    fi

    return $exit_code
}

# ── Uninstall mode ─────────────────────────────────────────────────

do_uninstall() {
    local any=0

    header "NAM Uninstall"

    if [ -d "$VIM_PACK" ]; then
        info "Removing Vim installation at ${VIM_PACK}..."
        rm -rf "$VIM_PACK"
        ok "Vim installation removed"
        any=1
    fi

    if [ -d "$NVIM_PACK" ]; then
        info "Removing Neovim installation at ${NVIM_PACK}..."
        rm -rf "$NVIM_PACK"
        ok "Neovim installation removed"
        any=1
    fi

    if [ "$any" -eq 0 ]; then
        info "No NAM installation found on this system."
    fi

    echo ""
    info "Workspace data may persist at:"
    info "  ~/.local/share/vproj/"
    info "Remove with:  rm -rf ~/.local/share/vproj/"
}

# ── Install entry points ───────────────────────────────────────────

do_install_vim() {
    check_git || return 1
    if ! check_vim_lua; then
        fail "Vim with Lua support (8.2+) is required for --vim install."
        return 1
    fi
    install_to "$VIM_PACK" "Vim"
}

do_install_nvim() {
    check_git || return 1
    if ! check_nvim; then
        fail "Neovim is required for --nvim install."
        return 1
    fi
    install_to "$NVIM_PACK" "Neovim"
}

do_install_both() {
    local ok=false

    check_git || return 1

    if check_vim_lua; then
        install_to "$VIM_PACK" "Vim" && ok=true
    else
        warn "Skipping Vim install (no Vim with +lua found)"
    fi

    if check_nvim; then
        install_to "$NVIM_PACK" "Neovim" && ok=true
    else
        warn "Skipping Neovim install (nvim not found)"
    fi

    if ! $ok; then
        fail "No supported editor found. Install Vim (with +lua) or Neovim first."
        return 1
    fi
}

# ── Post-install message ───────────────────────────────────────────

print_post_install() {
    cat <<'CONFIG'

  ── Setup ────────────────────────────────────────────────────
  Add this to your ~/.vimrc or ~/.config/nvim/init.lua:

      require("vproj").setup({ hotkey = "<F2>" })

  Then press F2 to open the sidebar. Press 'b' for buffers,
  'f' for files, 'g' for git status, 's' for symbols,
  'o' for outline. Press a label key (1, a, q, etc.) to
  jump to that item. Press 'q' to close.
  ─────────────────────────────────────────────────────────────
CONFIG
}

# ── Usage ──────────────────────────────────────────────────────────

print_usage() {
    # Extract the comment header (lines 2-30) for the usage summary
    sed -n '2,/^[^#]/p' "$0" 2>/dev/null | sed -n '/^#/p' | sed 's/^# \?//' | head -30
}

# ── Main ───────────────────────────────────────────────────────────

main() {
    case "${1:-}" in
        --help|-h)
            print_usage
            exit 0
            ;;
        --check|-c)
            do_check
            exit $?
            ;;
        --uninstall|-u)
            do_uninstall
            exit 0
            ;;
        --vim)
            do_install_vim
            print_post_install
            ;;
        --nvim)
            do_install_nvim
            print_post_install
            ;;
        --both|"")
            do_install_both
            print_post_install
            ;;
        *)
            echo "Usage: $(basename "$0") [--vim | --nvim | --both | --check | --uninstall | --help]"
            exit 1
            ;;
    esac
}

main "$@"
