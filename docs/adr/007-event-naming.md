# ADR 007: Event Naming Protocol

- **Status**: Accepted
- **Date**: 2026-06-14
- **Author**: Aldous Thoreau

## Context

The previous DSN-based codebase used an event bus (`events.vim`) with
string-based event names like `'mode_changed'` and `'mode_rerender'`.
These were loosely defined and inconsistently emitted.

## Decision

A defined set of **named events** describes what happens in the system. Events
are not a full publish/subscribe bus — they are named, documented moments in
the lifecycle that functions hook into consistently.

### Event Catalog

| Event | Emitted When | Payload |
|-------|-------------|---------|
| `ProjectLoaded` | A `.vproj` file is loaded | `{project_name, project_root}` |
| `ProjectCreated` | A new `.vproj` file is created | `{project_name, project_root}` |
| `ProjectSaved` | Project changes are written to disk | `{project_name}` |
| `RootChanged` | Current root directory changes | `{old_root, new_root}` |
| `ModeChanged` | Active mode switches | `{old_mode, new_mode}` |
| `ItemSelected` | An item is selected (highlighted) | `{item, index}` |
| `FileOpened` | A file is opened in Vim | `{filepath, buffer_number}` |
| `BufferSwitched` | Active Vim buffer changes | `{old_buffer, new_buffer}` |
| `ItemIncluded` | A file/directory is included in project | `{item}` |
| `ItemExcluded` | A file/directory is excluded from project | `{item}` |
| `ProjectRenamed` | The project name changes | `{old_name, new_name}` |
| `PaneToggled` | The project pane opens or closes | `{visible}` |
| `PageChanged` | The current page changes | `{old_page, new_page, total_pages}` |

### Rules

1. **Every command shall emit exactly one event on completion.**
2. **The display shall rebuild in response to events**, not in response to
   direct function calls.
3. **Event handlers are registered once** during initialization and remain
   stable throughout the session.

This keeps the renderer decoupled from the command layer. When AI integration,
history, or source control arrives, those features wire into these named points
rather than hunting through the code.

## Options Considered

### Option A: Named Event Protocol (Chosen)
- **Pros**: Explicit contract, discoverable, extensible
- **Cons**: Slightly more code than direct function calls

### Option B: Ad-Hoc String Events (Previous)
- **Pros**: Flexible
- **Cons**: Inconsistent, easy to misspell, no documented contract

### Option C: Full Pub/Sub Bus
- **Pros**: Maximum flexibility
- **Cons**: Overengineered for 13 events, adds complexity

## Consequences

- **Positive**: Renderer, history, and future features only need to know event names.
- **Positive**: Pane display can be rebuilt by listening to events rather than
  being called imperatively from command functions.
- **Negative**: 13 events to maintain and document.
- **Negative**: Event payload shapes must remain backward-compatible.

## References

- [005-workspace-domain-model](005-workspace-domain-model.md)
- [006-command-query-separation](006-command-query-separation.md)
- [011-display-management](011-display-management.md)
