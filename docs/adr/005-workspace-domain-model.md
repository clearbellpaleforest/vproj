# ADR 005: Workspace Domain Model

- **Status**: Accepted
- **Date**: 2026-06-14
- **Author**: Aldous Thoreau
- **Supersedes**: [002-dsn-navigation.md](002-dsn-navigation.md)

## Context

The previous DSN (Direct Selection Navigation) architecture used module-level
variables scattered across multiple files (`autoload/vproj/*.vim`) as runtime
state. This made it difficult to reason about state transitions, test
individual operations, and maintain consistency.

## Decision

Adopt a **Workspace Domain Model** — the workspace is the central domain object
that owns all runtime state and is the authoritative source of truth.

### Workspace State

The workspace contains:
- `current_mode` — active mode key (File, Document, Code)
- `current_project` — loaded project name and metadata
- `current_root` — active directory within the project tree
- `selected_item` — currently highlighted item
- `current_page` — page number within the current view
- `nav_offset` — navigation indicator offset (for TAB relabeling)
- `pane_width` — width of the project pane in columns
- `display_options` — info column visibility, mode menu position

### Rules

1. **Nothing outside the workspace may hold a copy of state that diverges from it.**
2. **Display output shall be generated from the workspace.** Display output shall
   not be treated as state.
3. **The workspace is the single source of truth** for all runtime state.

## Options Considered

### Option A: Workspace Domain Model (Chosen)
- **Pros**: Predictable state, testable, clear ownership
- **Cons**: More ceremony than module-level variables

### Option B: Module-Level State (Previous)
- **Pros**: Simple, direct access
- **Cons**: State scattered across files, hard to test, easy to corrupt

### Option C: Event-Sourced State
- **Pros**: Full audit trail, replayable
- **Cons**: Heavy for a Vim plugin, overengineered for this scope

## Consequences

- **Positive**: All state changes flow through defined Command functions.
- **Positive**: Display is always regenerated from workspace queries, never from side effects.
- **Negative**: Requires discipline to maintain — no direct state mutation from display code.

## References

- `src/autoload/vproj.vim` — Workspace implementation
- [006-command-query-separation](006-command-query-separation.md)
- [007-event-naming](007-event-naming.md)
