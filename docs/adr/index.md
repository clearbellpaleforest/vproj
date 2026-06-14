# Architecture Decision Records

Architecture Decision Records (ADRs) document the significant decisions
made in the Vproj project. Each record describes a decision, its context,
the options considered, and the consequences.

## Records

| # | Title | Status | Date |
|---|-------|--------|------|
| [001](001-vim9script-rewrite.md) | Vim9Script Rewrite from Lua | Accepted | 2026-06-13 |
| [002](002-dsn-navigation.md) | Direct Selection Navigation | Accepted | 2026-06-13 |
| [003](003-session-persistence.md) | JSON Session Persistence | Accepted | 2026-06-13 |
| [004](004-security-model.md) | Input Validation and Security Model | Accepted | 2026-06-14 |

## What is an ADR?

An Architecture Decision Record is a document that captures an important
architectural decision along with its context and consequences. ADRs help
future contributors understand why the codebase looks the way it does.

## Creating a New ADR

1. Copy `000-template.md` to `NNN-title-with-dashes.md`
2. Fill in the sections
3. Add an entry to the table above
4. Submit a pull request

## Template

See [000-template.md](000-template.md) for the ADR template.
