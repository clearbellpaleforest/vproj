---
name: vproj
description: Vproj Vim plugin development and testing. Use when working in the vproj repo, modifying autoload/vproj.vim or plugin/vproj.vim, adding features to the project pane, debugging Vim9script, running vproj tests, or understanding vproj's architecture. Always invoke before touching vproj code.
---

# Vproj — Development & Testing

## Quick Commands

```bash
# Smoke test (always start here)
vim -N -u NONE -S tests/smoke.vim -c 'qall!' 2>&1 | grep -E 'PASS|FAIL'

# Integration tests
vim -N -u NONE -S tests/integration/test_buf_mode.vim -c 'qall!'
vim -N -u NONE -S tests/integration/test_git_full.vim -c 'qall!'
vim -N -u NONE -S tests/integration/test_qfix_mode.vim -c 'qall!'

# Keybinding test
vim -N -u NONE -S tests/keybindings.vim -c 'qall!'

# Full suite (run these in order)
vim -N -u NONE -S tests/smoke.vim -c 'qall!'
vim -N -u NONE -S tests/keybindings.vim -c 'qall!'
vim -N -u NONE -S tests/regression.vim -c 'qall!'
vim -N -u NONE -S tests/integration/test_buf_mode.vim -c 'qall!'
vim -N -u NONE -S tests/integration/test_git_full.vim -c 'qall!'
vim -N -u NONE -S tests/integration/test_qfix_mode.vim -c 'qall!'
```

## Architecture

```
src/
├── plugin/vproj.vim         # Entry point — commands, default Tab mapping, load guard
├── autoload/vproj.vim        # All logic — ~3,700 lines Vim9Script
│   ├── State (script-local vars at top)
│   ├── Pane lifecycle (PaneOpen, PaneClose, Render)
│   ├── Mode dispatch (VprojKey → FileModeKey/BufModeKey/CodeModeKey/QfixModeKey)
│   ├── Navigation (SelectByNavChar, NavigateUp, paging)
│   ├── Git (ToggleGitFilter, stage, diff, blame, commit, push, stash)
│   └── AI dispatch (VprojKey("A") → vproj#ai#AiTerminalChat)
├── autoload/vproj/ai.vim     # AI subsystem — streaming, chat, code extraction
└── doc/vproj.txt              # Help file
bin/
└── vproj-ai-chat             # Terminal chat bash script
```

## Exported API (every command you can call from outside)

### Pane
| Function | What it does |
|----------|-------------|
| `vproj#PaneToggle()` | Toggle open/closed (temporary mode → close; closed → temp) |
| `vproj#PaneOpen()` | Open pane, decide temp vs permanent |
| `vproj#PaneClose()` | Close pane unconditionally |
| `vproj#Refresh()` | Re-render from disk |
| `vproj#PaneGrow()` / `PaneShrink()` | Width +/- 1 |
| `vproj#SetPaneWidth(n)` | Exact width 20-80 |
| `vproj#IsPaneVisible()` | Boolean — is pane open |
| `vproj#GetPaneBufnr()` | Buffer number (add-ons use this to detect pane) |
| `vproj#GetPaneWidth()` / `GetCurrentMode()` | Query state |
| `vproj#PaneTogglePermanent()` | Toggle permanent mode |

### Navigation
| Function | What it does |
|----------|-------------|
| `vproj#SelectNext()` / `SelectPrev()` | Move cursor |
| `vproj#SelectCurrent()` | Open file/dir or execute action on selected line |
| `vproj#SelectByNavChar(ch)` | Jump to item by nav character |
| `vproj#VprojKey(key)` | Master dispatcher — routes to mode-specific or AI |
| `vproj#NavigateUp()` | Parent directory |
| `vproj#NavigateIntoFirstDir()` | First subdirectory |
| `vproj#SelectFirst()` / `SelectLast()` | Jump to top/bottom |
| `vproj#NextPage()` / `PrevPage()` | Page through long listings |
| `vproj#HandleEsc()` / `HandlePaneQ()` | Esc/q key handlers |
| `vproj#HandleF1()` | Toggle info column (pane) or open help (elsewhere) |

### Modes
| Function | What it does |
|----------|-------------|
| `vproj#SwitchMode(key)` | Switch to file (F), buf (B), code (C) |

### Git
| Function | What it does |
|----------|-------------|
| `vproj#ToggleGitFilter()` | Show only git-changed files |
| `vproj#GitStageToggle()` | Stage/unstage file under cursor (\s) |
| `vproj#OpenDiffPreview()` | Diff preview in vertical split (\d) |
| `vproj#DiscardChanges()` | Discard file changes with confirmation (\D) |
| `vproj#GitCommit()` | Commit with message prompt (\c) |
| `vproj#GitPush()` / `GitPull()` | Push/pull |
| `vproj#GitBranchSwitch()` | Switch branch with prompt (\b) |
| `vproj#GitStashPush()` / `GitStashPop()` | Stash |
| `vproj#GitBlame()` | Blame split (\a) |

### Filter & Search
| Function | What it does |
|----------|-------------|
| `vproj#PromptFilter()` | Filter by pattern (/) |
| `vproj#GrepSearch()` | Grep project → quickfix (*) |
| `vproj#ToggleInfoColumn()` | Show/hide info column |

### Tree & Preview
| Function | What it does |
|----------|-------------|
| `vproj#ToggleTreeView()` | Toggle tree view (T) |
| `vproj#TogglePreview()` | Toggle file preview split (P) |

### Code Mode
| Function | What it does |
|----------|-------------|
| `vproj#ToggleInclude()` | Include/exclude item (+/-) |
| `vproj#IncludeItem()` / `ExcludeItem()` | Explicit include/exclude |
| `vproj#RenameProject()` | Rename/create project |

### AI (vproj#ai# namespace)
| Function | What it does |
|----------|-------------|
| `vproj#ai#AiTerminalChat()` | Open terminal chat (A key) |
| `vproj#ai#AiPrompt(text)` | One-shot prompt — code or question |
| `vproj#ai#AiPromptFromKey()` | Interactive prompt via input() |
| `vproj#ai#AiCall(prompt, ctx)` | Sync POST to API (fallback) |
| `vproj#ai#StreamCancelCmd()` | Cancel streaming |

## Modes

| Mode | How to enter | What it shows |
|------|-------------|---------------|
| File | Shift-F (default) | Directory tree, file sizes, nav chars |
| Buf | Shift-B | Open buffers with flags + line counts |
| Code | Shift-C | Project tree from .vproj config |
| Qfix | Enter on `[Q]fix` in mode menu | Quickfix list entries |

Mode switching is via Shift-F/B/C keys OR pressing Enter on the mode menu line.
The mode menu line shows `[F]ile [B]uf [C]ode [Q]fix`.

## Key System

### VprojKey dispatcher
The single dispatcher function. All buffer-local key mappings route here.
Mode changes are instantaneous because *mappings never change* — the
dispatcher checks `current_mode` and routes to the right handler.

```vim
export def VprojKey(key: string): void
  if key == 'A'
    vproj#ai#AiTerminalChat()     # AI — mode-independent
    return
  endif
  if current_mode == 'file'
    FileModeKey(key)
  elseif current_mode == 'buf'
    BufModeKey(key)
  elseif current_mode == 'code'
    CodeModeKey(key)
  elseif current_mode == 'qfix'
    QfixModeKey(key)
  else
    Error('unknown mode')
```

### Nav chars
Lowercase a-z are mapped to open the file at that nav indicator.
Nav indicators are computed from sorted filenames, one char per visible item.
SHIFT keys are mode switches (F/B/C/R/P/X/Q/T).

### MapKeys function
All buffer-local mappings in one function. Sorted by key for readability.
Use `<Cmd>` for input()-safe mappings (processes before cmdline mode).
Use `<nowait>` for char mappings to prevent prefix-key timeout.

## Testing Rules

1. **Always run smoke test first** — verifies basic load/open/close/mode switch
2. **Run before every commit** — `vim -N -u NONE -S tests/smoke.vim -c 'qall!'`
3. **Test each mode independently** — don't combine file/buf/code tests
4. **Test edge cases**: empty directory, missing .vproj, deleted buffer, Ctrl-C
5. **AI tests** can only verify function existence (no curl in headless Vim)
6. **Assertion pattern**: `Assert(cond, 'description')` with failure counter

## Common Mistakes

- **Adding a key without adding it to VprojKey**: every new mapping must route through the dispatcher
- **Forgetting MapKeys**: the new key needs `nnoremap` in MapKeys()
- **Mode confusion**: Use `current_mode`, not `mode` — the latter is a Vim builtin
- **v:null in getenv**: `getenv('VAR')` returns `v:null`, not `''`
- **tempname() leak**: Always cleanup in `finally` block
- **string() adds quotes**: `string('hello')` → `"'hello'"` — never use on strings
