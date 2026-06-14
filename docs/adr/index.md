# Architecture Decision Records

Architecture Decision Records (ADRs) document the significant decisions
made in the Vproj project. Each record describes a decision, its context,
the options considered, and the consequences.

## Active Records (VPROJ Redesign)

| # | Title | Status | Date |
|---|-------|--------|------|
| [005](005-workspace-domain-model.md) | Workspace Domain Model | Accepted | 2026-06-14 |
| [006](006-command-query-separation.md) | Command/Query Separation (CQS) | Accepted | 2026-06-14 |
| [007](007-event-naming.md) | Event Naming Protocol | Accepted | 2026-06-14 |
| [008](008-vproj-project-file-format.md) | .vproj Project File Format | Accepted | 2026-06-14 |
| [009](009-navigation-indicator-system.md) | Navigation Indicator System | Accepted | 2026-06-14 |
| [010](010-mode-architecture.md) | Mode Architecture (File/Doc/Code) | Accepted | 2026-06-14 |
| [011](011-display-management.md) | Display Management & Pane Layout | Accepted | 2026-06-14 |
| [012](012-pane-infrastructure.md) | Pane Infrastructure & Implementation Order | Accepted | 2026-06-14 |

## Superseded Records (DSN Architecture)

These records document the original DSN-based design. They are preserved for
historical context but have been superseded by ADRs 005-012.

| # | Title | Status | Date |
|---|-------|--------|------|
| [001](001-vim9script-rewrite.md) | Vim9Script Rewrite from Lua | Superseded | 2026-06-13 |
| [002](002-dsn-navigation.md) | Direct Selection Navigation | Superseded | 2026-06-13 |
| [003](003-session-persistence.md) | JSON Session Persistence | Superseded | 2026-06-13 |
| [004](004-security-model.md) | Input Validation and Security Model | Superseded | 2026-06-14 |

## What is an ADR?

An Architecture Decision Record is a document that captures an important
architectural decision along with its context and consequences. ADRs help
future contributors understand why the codebase looks the way it does.

They serve three purposes:
1. **Documentation** — Why was this decision made?
2. **Onboarding** — New contributors can read ADRs to understand the architecture.
3. **Re-evaluation** — When circumstances change, ADRs show what was considered
   and what tradeoffs were made.

## ADR Protocol

### Creating a New ADR

1. Copy `000-template.md` to `NNN-title-with-dashes.md` (use the next
   available number).
2. Fill in the sections: Status, Date, Author, Context, Decision, Options
   Considered, Consequences, References.
3. Add an entry to the table at the top of this file.
4. Submit a pull request. ADRs are reviewed like code.

### ADR Lifecycle

```
Proposed → Accepted → (Implemented) → Superseded
                         ↓
                      Deprecated
```

- **Proposed**: Under discussion, not yet approved.
- **Accepted**: Approved and awaiting implementation (or already implemented).
- **Superseded**: Replaced by a newer ADR. Still provides historical context.
- **Deprecated**: The decision is no longer relevant (feature removed, approach
  abandoned entirely).

### When to Write an ADR

Write an ADR when:
- Making an architectural decision that affects multiple subsystems.
- Choosing between competing approaches with non-obvious tradeoffs.
- Establishing a pattern or convention that other code should follow.
- Changing a decision that was previously documented in an ADR.

Don't write an ADR for:
- Routine implementation details (function signatures, variable names).
- Fixing bugs (unless the fix requires an architectural change).
- Adding features that follow existing patterns.

### Linking ADRs

Use the `References` section at the bottom of each ADR to link to related
records. Use relative Markdown links: `[005-title](005-title.md)`.

### Template

See [000-template.md](000-template.md) for the ADR template.
