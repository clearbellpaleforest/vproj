# ADR 006: Command/Query Separation (CQS)

- **Status**: Accepted
- **Date**: 2026-06-14
- **Author**: Aldous Thoreau
- **Supersedes**: [002-dsn-navigation.md](002-dsn-navigation.md)

## Context

In the previous DSN-based codebase, mode functions like `Select()` both modified
state (opening files, switching windows) and returned results used for display
decisions. This interleaving of reads and writes made the system unpredictable
and difficult to test.

## Decision

All operations on the workspace shall be classified as either a **Command** or
a **Query**. Commands change state. Queries never change state. This is a
**hard rule** — no function may both read state for display and modify state
at the same time.

### Commands (change workspace state)

| Command | Effect |
|---------|--------|
| `IncludeFile` | Add file to project |
| `ExcludeFile` | Remove file from project |
| `OpenBuffer` | Open file in Vim buffer |
| `RenameProject` | Change project name |
| `ChangeRoot` | Navigate to different directory |
| `ChangeMode` | Switch active mode |
| `SetPaneWidth` | Adjust pane width |
| `SelectItem` | Set selected item |
| `ChangePage` | Switch to different page |
| `ShiftNavOffset` | Shift navigation indicator range |

### Queries (only read workspace state)

| Query | Returns |
|-------|---------|
| `GetVisibleItems` | Items visible on current page |
| `GetProjectTree` | Project structure relative to root |
| `GetOpenBuffers` | List of open Vim buffers |
| `GetIncludedFiles` | Files included in project |
| `GetCurrentPath` | Current root directory path |
| `GetPageInfo` | Page count, current page |
| `GetNavIndicators` | Current navigation indicator labels |

### Pattern

Instead of a monolithic function like `OpenFile()` that does everything:
1. `ExecuteCommand('OPEN_BUFFER', item)` — changes state
2. `QueryVisibleItems()` — reads state to rebuild the display

The display is always rebuilt from a query, never from side effects of a command.

## Options Considered

### Option A: Command/Query Separation (Chosen)
- **Pros**: Eliminates read/write interleaving bugs, makes system predictable
- **Cons**: Requires two calls where one might suffice

### Option B: Mixed Read/Write Functions (Previous)
- **Pros**: Fewer function calls
- **Cons**: Hard to test, state changes hidden in display code

## Consequences

- **Positive**: Every state change is explicit and traceable.
- **Positive**: Queries are pure and can be called freely without side effects.
- **Negative**: Performance-sensitive paths require two function calls instead of one.
- **Negative**: Requires team discipline — CQS violations must be caught in review.

## References

- [005-workspace-domain-model](005-workspace-domain-model.md)
- [007-event-naming](007-event-naming.md)
