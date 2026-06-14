# ADR 003: JSON Session Persistence

- **Status**: Accepted
- **Date**: 2026-06-13
- **Author**: Aldous Thoreau

## Context

Vproj needs to persist workspace state across Vim sessions:
- Open buffers and cursor positions
- Active mode and sidebar visibility
- Window layout (split sizes)
- Pinned buffers, bookmarks, and recent symbols

## Decision

Use per-project JSON session files stored at
`$XDG_CACHE_HOME/vproj/session_<hash>.json` with atomic writes.

### Key Design Decisions

1. **Atomic writes**: Uses a temp-then-rename pattern (`writefile` to `.tmp.*`,
   then `rename()` to target) to prevent file corruption on crash.
2. **djb2 project hashing**: Session files are keyed by a djb2 hash of the
   project root path, ensuring different projects get different session files.
3. **Buffer cap**: `MAX_RESTORE_BUFFERS = 50` prevents a corrupted session
   file from attempting to open an unbounded number of buffers.
4. **Window layout sanitization**: The `window_layout` field is validated
   against a strict regex (`^(resize|vertical resize)\s+\d+$`) before `execute`
   to prevent command injection.
5. **Path validation**: All buffer paths must match `^[/~]` and are passed
   through `fnameescape()` before use in `execute 'badd'`.

## Options Considered

### Option A: JSON + Atomic Write (Chosen)
- **Pros**: Human-readable, debuggable, no format migration needed
- **Cons**: Slightly slower than binary formats

### Option B: Vim native `:mksession`
- **Pros**: Built-in, handles all Vim state
- **Cons**: Restores ALL Vim state (noise), Vimscript in session files (RCE risk)

### Option C: SQLite
- **Pros**: Queryable, atomic by design
- **Cons**: Requires `+sqlite` compile flag, not universally available

## Consequences

- **Positive**: Session files are human-readable JSON for debugging.
- **Positive**: Atomic writes prevent corruption on crash.
- **Negative**: JSON serialization adds slight overhead on save/restore.
- **Negative**: Version migration logic needed for format changes.

## Security Considerations

- Window layout commands are regex-validated before `execute` to prevent RCE.
- Buffer paths require `^[/~]` prefix and `fnameescape()` escaping.
- `json_decode` is wrapped in try/catch to handle corrupted files.
- `XDG_CACHE_HOME` is validated against path traversal (`..`, `.`, glob chars).

## References

- `autoload/vproj/persistence.vim` — Session persistence implementation
