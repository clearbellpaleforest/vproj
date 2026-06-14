# ADR 004: Input Validation and Security Model

- **Status**: Accepted
- **Date**: 2026-06-14
- **Author**: Aldous Thoreau

## Context

Vproj handles data from multiple untrusted sources:
1. **Environment variables**: `$XDG_CACHE_HOME`
2. **User configuration**: `Setup()` dict with hotkeys, labels, paths
3. **Session files**: JSON from disk (could be corrupted or malicious)
4. **External processes**: `ctags` output, `git status` output
5. **Filesystem**: Directory listings via `readdir()`

Without comprehensive input validation, these sources could cause
crashes, data corruption, or command injection.

## Decision

Apply defense-in-depth validation at every trust boundary:

### Validation Layers

| Boundary | Validation | Location |
|----------|-----------|----------|
| `$XDG_CACHE_HOME` | Path traversal rejection (`..`, `.`, glob chars) | `persistence.vim:41-55` |
| Hotkey string | Reject newlines, pipes, quotes, control chars | `init.vim:81` |
| Label tier chars | Reject `"`, `\|`, `<`, `>`, control chars | `navigation.vim:45` |
| Session JSON | try/catch `json_decode`, type check dict, field validation | `persistence.vim:232-243` |
| Window layout | Regex validate `^(resize\|vertical resize)\s+\d+$` | `persistence.vim:287-292` |
| Buffer paths | `^[/~]` prefix + `fnameescape()` | `persistence.vim:254` |
| Shell commands | `shellescape()` for all arguments | `git.vim`, `symbols_mode.vim` |
| Workspace paths | Path traversal + glob char rejection | `workspace.vim:176-185` |
| Workspace names | `[^a-zA-Z0-9_-]` sanitization | `workspace.vim:187-189` |

### Design Principles

1. **Validate at boundaries**: Check data as soon as it enters the system.
2. **Fail closed**: Reject invalid input, don't attempt to fix it.
3. **Defense in depth**: Multiple validation layers catch what single checks miss.
4. **No silent corruption**: Return `false` or error values, don't silently
   accept invalid data.

## Options Considered

### Option A: Comprehensive Validation (Chosen)
- **Pros**: Prevents crashes, RCE, data corruption
- **Cons**: More code, slight performance cost on I/O paths

### Option B: Trusted Input Only
- **Pros**: Simpler code
- **Cons**: Vulnerable to corrupted session files, config injection

### Option C: Schema Validation (e.g., JSON Schema)
- **Pros**: Declarative, standardized
- **Cons**: No Vim-native JSON Schema validator exists

## Consequences

- **Positive**: All known injection vectors are blocked.
- **Positive**: Corrupted session files fail gracefully (return false, no crash).
- **Negative**: Validation code is duplicated across modules (e.g., path
  traversal checks in both `persistence.vim` and `workspace.vim`).
- **Negative**: Adding new data sources requires adding validation code.

## Audit History

| Date | Audit Type | Findings | Status |
|------|-----------|----------|--------|
| 2026-06-13 | Initial security review | 8 issues found | Resolved |
| 2026-06-14 | PhD-level 10-agent audit | 4 critical, 4 high, 4 moderate | In progress |

## References

- `autoload/vproj/persistence.vim` — Most heavily validated module
- `autoload/vproj/init.vim:81` — Hotkey validation regex
