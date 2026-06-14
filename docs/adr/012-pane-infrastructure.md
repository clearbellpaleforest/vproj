# ADR 012: Pane Infrastructure & Implementation Order

- **Status**: Accepted
- **Date**: 2026-06-14
- **Author**: Aldous Thoreau

## Context

The design specifies four major subsystems (Workspace, Project, Navigation,
Display) that must be built incrementally. Each stage should result in a
usable system — at no point should the project require a complete rewrite
to continue development.

## Decision

Development shall proceed in this order:

### Stage 1: Pane Infrastructure
- Create/open/close the project pane (scratch buffer in vertical split)
- Toggle visibility via user-configurable hotkey (default: `F4`)
- Pane width management (default 40, Left/Right arrows adjust)
- Basic mode menu display (3 modes, separators)
- Up/Down arrow selection wrapping

### Stage 2: File Mode
- Directory listing (dirs first, then files)
- Parent directory navigation (`..` and Ctrl-K/Ctrl-J)
- File info column (5-char right-aligned sizes, F1 toggle)
- Status label (current path, right-aligned on overflow)
- File opening on Enter

### Stage 3: Document Mode
- Buffer list from `getbufinfo()`
- Buffer flags in info column
- Modification status display
- Buffer switching on Enter

### Stage 4: Project Storage
- `.vproj` file parser
- Project discovery (traverse up from cwd)
- Project creation on Enter (status line → set name → write file)
- Include/Exclude commands (`+`/`-` keys)

### Stage 5: Code Mode
- Project tree display relative to current root
- Included/excluded item visualization
- Non-included items in parentheses
- Root changes via directory navigation

### Stage 6: Navigation Indicators
- a-z, A-Z, 1-9 indicator assignment
- TAB relabeling (nav_offset) — this is a v1 feature, not optional
- Page navigation (Ctrl-N/Ctrl-P, page nav row)
- Paging and TAB relabeling are independent features; both implemented now

### Stage 7: Configuration
- Environment variables (`VPROJ_pane-width_*`, `VPROJ_mode-display-location`)
- `.vimrc` configuration
- Mode display position (TOP/BOTTOM)

### Stage 8: Documentation
- Help file
- README
- Quick reference

### Rules

- **Each stage results in a usable system.** No "scaffolding only" stages.
- **No complete rewrites.** Each stage builds on the previous one.
- **TAB relabeling is a v1 feature.** Implement it in Pane Infrastructure,
  not deferred to a later stage.

## Source Layout

```
src/
├── autoload/
│   └── vproj.vim          # All autoloaded functions (single file initially)
└── plugin/
    └── vproj.vim           # Entry point, commands, hotkey mapping
```

Internal organization should allow future separation into multiple source files
(`workspace.vim`, `navigation.vim`, `display.vim`, `project.vim`) without
restructuring.

## Options Considered

### Option A: Incremental Stages (Chosen)
- **Pros**: Always usable, no big-bang rewrites, each stage is testable
- **Cons**: Some early stages will be feature-incomplete

### Option B: All-at-Once Implementation
- **Pros**: Everything works together from day one
- **Cons**: Long period of non-functionality, hard to test incrementally

## Consequences

- **Positive**: The plugin is functional after Stage 1 (basic file browsing).
- **Positive**: Each stage can be tested and released independently.
- **Negative**: Total development time is longer than a single implementation sprint.
- **Negative**: Interface design decisions made in later stages may require
  minor refactoring of earlier stages.

## References

- [005-workspace-domain-model](005-workspace-domain-model.md)
- [010-mode-architecture](010-mode-architecture.md)
- [011-display-management](011-display-management.md)
