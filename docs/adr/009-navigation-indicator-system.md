# ADR 009: Navigation Indicator System

- **Status**: Accepted
- **Date**: 2026-06-14
- **Author**: Aldous Thoreau
- **Supersedes**: [002-dsn-navigation.md](002-dsn-navigation.md)

## Context

The previous DSN (Direct Selection Navigation) used 4 fixed tiers of labels
(`1234567890`, `asdfghjkl`, `qwertyuiop`, `zxcvbnm`) with double-character
overflow. This was rigid — the label assignment was fixed and couldn't shift
when more items existed than keys.

## Decision

Use a **navigation indicator system** with dynamic assignment and TAB-based
relabeling via a `nav_offset` workspace field.

### Indicator Keys

```
a b c d e f g h i j k l m n o p q r s t u v w x y z  (26 lowercase)
A B C D E F G H I J K L M N O P Q R S T U V W X Y Z  (23 uppercase, excluding mode keys)
1 2 3 4 5 6 7 8 9                                     (9 digits)
─────────────────────────────────────────────────────
Total: 58 navigation indicators
```

### Reserved Keys

| Key | Purpose |
|-----|---------|
| `*` | Select the project name (rename on Enter) |
| `.` | Navigate to parent directory |
| `Shift-F` | File Mode |
| `Shift-D` | Document Mode |
| `Shift-C` | Code Mode |
| `Tab` | Cycle nav indicators forward (relabel) |
| `Shift-Tab` | Cycle nav indicators backward (relabel) |

### Indicator Assignment

- Each visible item (directory, file, buffer) gets a nav indicator like `a`
  displayed in cyan, one space to the left of the item name.
- Items beyond the 58-indicator limit have a blank indicator slot.
- **TAB** cycles the indicator range forward: `nav_offset` increments, and the
  displayed indicators relabel starting from the next unlabeled item. Wraps around.
- **Shift-TAB** cycles backward.
- The `nav_offset` is maintained as internal workspace state from the beginning.

### General Navigation Hotkeys

| Key | Action |
|-----|--------|
| Up/Down | Move selection up/down, wrapping at top/bottom |
| Left/Right | Decrease/increase pane width by 1 column |
| Enter | Perform default action on selected item |
| F1 | Toggle file information column on/off |
| Ctrl-N | Next page |
| Ctrl-P | Previous page |
| Ctrl-T | Go to first item |
| Ctrl-B | Go to last item |

### Paging vs. TAB Relabeling

Paging and TAB relabeling are **independent features solving different problems**:
- **Paging** (Ctrl-N/Ctrl-P): Too many items to display in the pane at once —
  show a subset.
- **TAB relabeling**: More items than nav indicators (58+) — shift which items
  get indicator labels.

Both shall be implemented in the Pane Infrastructure stage.

## Options Considered

### Option A: Dynamic Relabeling with nav_offset (Chosen)
- **Pros**: Scales beyond 58 items, simple mental model
- **Cons**: TAB cycling can feel slow with hundreds of items

### Option B: Fixed Tiers with Double-Character Overflow (Previous)
- **Pros**: No cycling needed, every item always has a label
- **Cons**: Double-char labels (`aa`, `ab`) are less readable, limited to
  ~1300 items before triple-char

### Option C: Fuzzy Filter Typing (fzf-style)
- **Pros**: Fast for known targets
- **Cons**: Hides available options, external dependency

## Consequences

- **Positive**: 58 single-character indicators — more than the previous 36.
- **Positive**: TAB relabeling handles projects of any size.
- **Negative**: Users must learn the TAB cycling mechanism.
- **Negative**: nav_offset must be maintained correctly in all display states.

## References

- [010-mode-architecture](010-mode-architecture.md)
- [011-display-management](011-display-management.md)
