# VPROJ — Design Specification

Vim project manager for software development.

## Folder Structure

```
~/dev/vproj
├── README.md
├── LICENSE
├── install.sh
├── design.md
├── doc_manual.txt
├── CLAUDE.md
├── .gitignore
├── .github
│   └── workflows
│       └── test.yml
├── docs
│   ├── architecture.md
│   ├── CONCEPT.MD
│   ├── constraints.md
│   ├── decisions.md
│   ├── design.md
│   ├── implementation-plan.md
│   ├── test-cases.md
│   ├── test-plan.md
│   └── superpowers
│       └── specs
│           └── 2026-06-20-streaming-integration-design.md
├── src
│   ├── autoload
│   │   └── vproj.vim
│   ├── doc
│   │   ├── tags
│   │   └── vproj.txt
│   └── plugin
│       └── vproj.vim
└── tests
    ├── coverage.vim
    ├── demo.vim
    ├── edge_test.vim
    ├── final.vim
    ├── gaps.vim
    ├── hand_test.md
    ├── keybindings.vim
    ├── regression.vim
    ├── smoke.vim
    ├── test_helpers.vim
    ├── integration
    │   ├── test_buf_mode.vim
    │   ├── test_git_full.vim
    │   ├── test_git_mode_full.vim
    │   ├── test_paging.vim
    │   ├── test_qfix_mode.vim
    │   └── test_special_chars.vim
    └── unit
        └── test_first_selectable.vim
```

## Purpose

VPROJ is a project and workspace manager for Vim. Browse files, manage buffers, and organize projects from a keyboard-driven sidebar pane.

## Architecture

A single autoload file (`src/autoload/vproj.vim`) holds all logic — rendering, mode switching, git integration, navigation, and pane lifecycle. The plugin file (`src/plugin/vproj.vim`) registers commands and default key mappings.

## Pane Lifecycle

The pane is a vertical split scratch buffer (`buftype=nofile`) on the left side, 40 columns wide by default.

Two toggle modes:

- **Temporary mode (Tab)** — pane auto-closes after opening a file, pressing Esc, or pressing Tab again
- **Permanent mode (Shift-Tab)** — pane stays open until Q, Shift-Tab again, or `:bdelete`

Commands: `:VprojToggle`, `:VprojOpen`, `:VprojClose`, `:VprojRefresh`, `:VprojDiag`

Default mappings:
| Mapping | Action |
|---------|--------|
| `<Tab>` | Toggle pane (temporary) |
| `<S-Tab>` | Toggle pane (permanent) |
| `<F1>` / `<Help>` | Toggle info column |

## Modes

Four modes, switched via Shift-F/B/C or `q` (or Enter on menu line to cycle):

| Key | Mode | Color | Shows |
|-----|------|-------|-------|
| `Shift-F` | File | Yellow | Directory browsing with file sizes |
| `Shift-B` | Buf | Green | Open buffers with flags and line counts |
| `Shift-C` | Code | Blue | Project tree from .vproj (excluded items in parentheses) |
| `q` | Qfix | Blue | Quickfix list entries (temp mode); closes pane (perm mode) |

Log mode was removed. `<Esc>` closes the pane
in temporary mode and is a no-op in permanent mode.

## Keybindings

All buffer-local mappings are set up in `SetupPaneMappings()` within the autoload file.

### Navigation
| Key | Action |
|-----|--------|
| `j` / `k`, `<Down>` / `<Up>` | Move selection |
| `Enter` | Open file / enter directory / cycle mode (on menu line) |
| `h` / `.` / `Ctrl-K` | Parent directory |
| `Ctrl-J` | Enter first subdirectory |
| `Ctrl-T` / `Ctrl-B` | Jump to first / last item |

### Actions
| Key | Action |
|-----|--------|
| `r` | Refresh listing |
| `T` | Toggle tree view (file mode) |
| `p` | Toggle file preview split (file and buf modes) |
| `F1` | Toggle info column |
| `/` | Filter by name pattern |
| `*` | Grep project (git grep -i) and populate quickfix |
| `x` | Close buffer (buf mode) |
| `+` / `-` | Include / exclude item (code mode) |
| `q` | Switch to Qfix (temp mode) / close pane (perm mode) |
| `Q` | Close pane |
| `Esc` | Close pane (temporary mode); no-op (permanent mode) |
| `>` / `<` | Shift nav indicators forward / backward |
| `<Left>` / `<Right>` | Shrink / grow pane width |
| `Ctrl-N` / `Ctrl-P` | Next / previous page |

### Git Actions (file and code mode)

All git actions use `\` prefix. Single-letter keys are freed for nav character jumping.

| Key | Action |
|-----|--------|
| `\s` | Stage / unstage file |
| `\d` | Open diff preview |
| `\D` | Discard changes (handles untracked, added, modified, deleted) |
| `\c` | Commit |
| `\p` | Push |
| `\u` | Pull --ff-only |
| `\b` | Switch branch |
| `\z` | Stash push |
| `\Z` | Stash pop |
| `\a` | Blame |
| `Ctrl-G` | Toggle git-changed-only filter |

### Nav Indicators

A curated set of 37 characters (avoiding mode keys and action keys) displayed in orange (`#FFAF00`). Press a character to jump directly to that item.

## Project Files (.vproj)

Line-oriented plain text at the project root. Sections: Project Name, Project Root, Included/Excluded Directories, Included/Excluded Files. Lines starting with `#` are comments. Use `+` and `-` in Git mode to edit interactively.

## Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `g:vproj_show_dotfiles` | 0 | Show hidden files when set to 1 |
| `g:vproj_pane_width_default` | 40 | Default pane width (20-80) |
| `g:vproj_pane_width_file` | 0 | Pane width for File mode (0 = use default) |
| `g:vproj_pane_width_buf` | 0 | Pane width for Buf mode |
| `g:vproj_pane_width_code` | 0 | Pane width for Code mode |
| `g:vproj_pane_width_qfix` | 0 | Pane width for Qfix mode |
