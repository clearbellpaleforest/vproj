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
├── bin
│   └── vproj-ai-chat
├── doc
│   ├── architecture.md
│   ├── concept.md
│   ├── constraints.md
│   ├── decisions.md
│   ├── design.md
│   ├── implementation-plan.md
│   ├── test-cases.md
│   ├── test-plan.md
│   └── phase-2
│       └── specs
│           └── 2026-06-20-streaming-integration-design.md
│   (plus index, manual, key-bindings, install, docs-pipeline, revisions/)
├── src
│   ├── autoload
│   │   ├── vproj.vim
│   │   └── vproj
│   │       ├── ai.vim
│   │       └── agent.vim
│   ├── doc
│   │   ├── tags
│   │   └── vproj.txt
│   └── plugin
│       └── vproj.vim
└── tests
    ├── run_all.sh
    ├── (top-level scripts: smoke, coverage, regression, final, ...)
    ├── integration
    │   └── test_*.vim   (buf mode, git, paging, pane lifecycle, qfix, file ops, ...)
    └── unit
        └── test_first_selectable.vim, test_ai.vim, test_agent.vim, test_ai_credentials.vim
```

## Purpose

VPROJ is a project and workspace manager for Vim. Browse files, manage buffers, and organize projects from a keyboard-driven sidebar pane.

## Architecture

Two source files plus two add-ons. `src/autoload/vproj.vim` holds all core logic and state — rendering, mode switching, git integration, file operations, navigation, opt-in session saving, and pane lifecycle. `src/plugin/vproj.vim` registers commands, `<Plug>` mappings and the default Tab/Shift-Tab/F1 mappings. Two add-ons load on demand through their own autoload namespaces: `src/autoload/vproj/ai.vim` (`vproj#ai#`, AI provider chat and prompt) and `src/autoload/vproj/agent.vim` (`vproj#agent#`, an external coding-agent CLI in a terminal split). Plugin calls autoload, never the reverse.

## Pane Lifecycle

The pane is a vertical split scratch buffer (`buftype=nofile`) on the left side, 40 columns wide by default.

Two toggle modes:

- **Temporary mode (Tab)** — pane auto-closes after opening a file, pressing Esc, or pressing Tab again
- **Permanent mode (Shift-Tab)** — pane stays open until Q, Shift-Tab again, or `:bdelete`

Commands: `:VprojToggle`, `:VprojOpen`, `:VprojClose`, `:VprojRefresh`, `:VprojDiag`,
`:VprojAiPrompt`, `:VprojAgent`; on the file selected in the pane (file mode):
`:VprojCopy`, `:VprojDelete`, `:VprojRename`, `:VprojMove`

Default mappings:
| Mapping | Action |
|---------|--------|
| `<Tab>` | Toggle pane (temporary) |
| `<S-Tab>` | Toggle pane (permanent) |
| `<F1>` / `<Help>` | Toggle info column when the pane is focused, otherwise `:help` |

`<Plug>VprojToggle`, `<Plug>VprojTogglePermanent`, `<Plug>VprojF1`, `<Plug>VprojAiPrompt` and `<Plug>VprojAgent` are the remappable indirections. `<Plug>VprojAgent` and `<Plug>VprojAiPrompt` have no default key. The short aliases `:Copy` `:Delete` `:Rename` `:Move` are defined only when no other plugin owns those names.

## Modes

Four modes, switched via Shift-F/B/C or Shift-Q (or Enter on the menu line to cycle):

| Key | Mode | Color | Shows |
|-----|------|-------|-------|
| `Shift-F` | File | Yellow | Directory browsing with file sizes |
| `Shift-B` | Buf | Green | Open buffers with flags and line counts |
| `Shift-C` | Code | Blue | Project tree from .vproj (excluded items in parentheses) |
| `Q` | Qfix | Blue | Quickfix list entries (temp mode); closes pane (perm mode) |

Log mode was removed. `<Esc>` closes the pane
in temporary mode and is a no-op in permanent mode.

## Keybindings

All buffer-local mappings are set up in `SetupPaneMappings()` within the autoload file. Lowercase `a`-`z` are nav characters (they open files and enter directories); every action is a Shift, Ctrl, `\` or punctuation key.

### Navigation
| Key | Action |
|-----|--------|
| `<Down>` / `<Up>` | Move selection |
| `Enter` | Open file / enter directory / cycle mode (on menu line) / rename or create project (on code-mode status line). Opening a file closes a temporary pane and keeps a permanent one |
| `.` / `Ctrl-K` | Parent directory (file and code mode) |
| `Ctrl-J` | Enter first subdirectory |
| `Ctrl-T` / `Ctrl-B` | Jump to first / last item |

### Actions
| Key | Action |
|-----|--------|
| `R` | Refresh listing |
| `T` | Toggle tree view (file mode) |
| `P` | Toggle file preview split (file and buf modes) |
| `F1` | Toggle info column |
| `A` | AI chat terminal (all modes) |
| `Delete` | Delete the selected file (file mode, confirms) |
| `?` | Show a key reference in a help window (`q` closes it) |
| `/` | Filter by name pattern |
| `*` | Grep project (git grep -i) and populate quickfix |
| `X` | Close buffer (buf mode) |
| `+` / `-` | Include / exclude item (code mode) |
| `Q` | Switch to Qfix (temp mode) / close pane (perm mode) |
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

### File Operations (file mode)

`:VprojCopy`, `:VprojDelete`, `:VprojRename`, `:VprojMove` (aliases `:Copy` `:Delete` `:Rename` `:Move`) act on the selected file only, not directories. Copy makes `name_1.ext`, `name_2.ext`, ... in the same directory; Delete confirms (default No); Rename keeps the directory; Move prompts for a destination directory. Delete, Rename and Move refuse while the file has unsaved changes; Rename and Move retarget windows showing the file.

### Nav Indicators

Lowercase `a`-`z` (26 characters), shown in blue (`VprojNavIndicator`, `#569CD6`). Press a character to jump directly to that item; in file and code mode that opens the file or enters the directory, in buf and qfix mode it only moves the cursor. The parent entry is `.`. With more than 26 items, `>` / `<` shift the lettering by a block of 26.

### Session

Session saving is opt-in. Only when `g:vproj_save_session = 1` (default 0: never write) does closing the pane save mode, directory, width, info-column and git-filter state to `$XDG_CACHE_HOME/vproj/session` (`~/.cache/vproj/session` when unset; previous file kept as `session.bak`). If a session file exists it is read on the next open whether or not saving is on. `DirChanged` (global, tabpage, window) refreshes the file-mode listing; code mode ignores it.

## Project Files (.vproj)

Line-oriented plain text at the project root. Sections: Project Name, Project Root, Included/Excluded Directories, Included/Excluded Files. Lines starting with `#` are comments. Use `+` and `-` in Code mode to edit interactively.

## Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `g:vproj_show_dotfiles` | 0 | Show hidden files when set to 1 |
| `g:vproj_pane_width_default` | 40 | Default pane width (20-80) |
| `g:vproj_pane_width_file` | 0 | Pane width for File mode (0 = use default) |
| `g:vproj_pane_width_buf` | 0 | Pane width for Buf mode |
| `g:vproj_pane_width_code` | 0 | Pane width for Code mode |
| `g:vproj_pane_width_qfix` | 0 | Pane width for Qfix mode |
| `g:vproj_ai_api_key` / `g:vproj_ai_api_url` / `g:vproj_ai_model` | (env / DeepSeek) | AI add-on provider settings (key also from `$DEEPSEEK_API_KEY`, `$OPENAI_API_KEY`) |
| `g:vproj_agent_cmd` | first of `claude`, `codex` on PATH | Program (string) or program + args (list) run by `:VprojAgent` |
