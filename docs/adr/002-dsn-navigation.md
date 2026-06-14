# ADR 002: Direct Selection Navigation (DSN)

- **Status**: Accepted
- **Date**: 2026-06-13
- **Author**: Aldous Thoreau

## Context

Traditional IDE file trees require cursor movement to navigate:
expand/collapse directories, scroll through long file lists, and position
the cursor on a target. This is O(n) traversal with cognitive overhead.

Vproj needs a navigation model that:
1. Works with keyboard-only input
2. Scales to hundreds of items
3. Has zero cursor-movement cost

## Decision

Use **Direct Selection Navigation (DSN)**: every displayed item gets a
unique keyboard label (1-3 characters). Pressing the label selects the
item directly — no cursor movement required.

### Label Architecture

- **4 tiers of labels** for 36 single-key items:
  - Tier 1: `1234567890` (10 keys)
  - Tier 2: `asdfghjkl` (9 keys)
  - Tier 3: `qwertyuiop` (10 keys)
  - Tier 4: `zxcvbnm` (7 keys)
- **Double-character overflow**: Items 37+ get labels like `aa`, `ab`, `ac`
- **Mode hotkeys** occupy reserved single characters: `b` (Buffers), `f` (Files), `g` (Git), `s` (Symbols), `o` (Outline)

### Dispatch Model

Each label key is mapped to a buffer-local `nnoremap` that calls the
handler bridge. The handler:
1. Tries the current mode's `Select(label)` — if consumed, done.
2. Falls back to mode hotkey dispatch — if `label` matches a mode key, switch.
3. Otherwise, no-op.

## Options Considered

### Option A: DSN with Label Map (Chosen)
- **Pros**: O(1) selection, no cursor movement, flat display
- **Cons**: Label generation is O(n²) in worst case (hash collisions)

### Option B: Tree Navigation (like NERDTree)
- **Pros**: Familiar mental model
- **Cons**: O(depth) navigation, cursor movement, slow for large trees

### Option C: Fuzzy Search (like fzf/Telescope)
- **Pros**: Fast for known targets
- **Cons**: Requires typing, hides available options, external dependency

## Consequences

- **Positive**: Selection cost is O(1) regardless of list size.
- **Positive**: No cursor movement — keyboard stays on home row.
- **Negative**: Users must learn the label system.
- **Negative**: Limited to 36 single-key items before double-char overflow.
- **Negative**: Mode hotkeys reduce available label keys (5 reserved).

## References

- `autoload/vproj/labels.vim` — Label generation engine
- `autoload/vproj/navigation.vim` — Key mapping and dispatch
