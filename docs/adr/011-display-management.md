# ADR 011: Display Management & Pane Layout

- **Status**: Accepted
- **Date**: 2026-06-14
- **Author**: Aldous Thoreau

## Context

The previous codebase used a renderer module (`renderer.vim`) that wrote
directly to sidebar buffers. Pane layout was loosely defined with a header,
separator, body, and footer structure that varied between modes.

## Decision

The display manager shall generate the contents of the project pane from
workspace queries. It shall not modify workspace state. A consistent pane
layout applies across all modes.

### Pane Layout (top to bottom)

```
┌──────────────────────────────────────┐
│ [F]ile  [D]oc  [C]ode               │  ← Mode menu (top by default)
│ ──────────────────────────────────── │  ← Separator (dashes)
│ a  src/                              │
│ b  doc/                              │  ← Item list (nav indicator + name)
│ c  README.md              1.2K       │     Info column on right
│ d  LICENSE                  45       │
│ >>> Page 1/4  CTRL-N CTRL-P <<<     │  ← Page nav row (last line)
└──────────────────────────────────────┘
```

### Layout Rules

1. **Mode menu** is the first line. User-configurable to bottom via
   `VPROJ_mode-display-location=TOP` or `BOTTOM`. Case-insensitive,
   accepts prefixes (`t`, `T`, `b`, `B`).
2. **Separator** is a line of dashes between menu and item list.
3. **Item list**: Each line has a nav indicator (cyan), one space, then
   the item name.
4. **Info column**: Right side, bright green, content-dependent width.
   File name column adjusts so total width equals pane width.
5. **Page nav row**: Shown as last line when items exceed pane height.
   Format: ` >>> Page 4/8 CTRL-N CTRL-P <<<`

### Pane Dimensions

- **Default width**: 40 columns
- **Per-mode override**: `VPROJ_pane-width_file`, `VPROJ_pane-width_doc`,
  `VPROJ_pane-width_code` — each defaults to 40 if unset.
- **Left/Right arrows** increase/decrease pane width by 1 column.
- **File info column** (F1 toggle): when visible, file sizes shown in
  exactly 5 characters, right-aligned, space-padded. When hidden, file
  names expand to fill the space.

### Color Scheme

- **Nav indicators**: Cyan
- **Info column**: Bright green
- Colors only applied when `&t_Co > 1` (color support available).
- All content must remain readable in monochrome terminals.

### Display Philosophy

- Emphasize useful information while minimizing visual clutter.
- The project pane should remain narrow.
- Default pane width: 40 columns.
- The display should remain readable on terminals of varying size.
- Colors should only be used when color support is available.
- The display should remain usable in monochrome terminals.

## Options Considered

### Option A: Query-Generated Display (Chosen)
- **Pros**: Display always reflects current workspace state
- **Cons**: Requires full redraw on every event (acceptable at <100 items)

### Option B: Incremental Updates (Previous)
- **Pros**: Faster for large lists
- **Cons**: State can drift from display, harder to debug

## Consequences

- **Positive**: Display is always consistent with workspace state.
- **Positive**: Adding a mode only requires implementing its display logic —
  the pane layout is shared.
- **Negative**: Full redraws may flicker on very slow connections.
- **Negative**: 40-column width may truncate long filenames.

## References

- [005-workspace-domain-model](005-workspace-domain-model.md)
- [009-navigation-indicator-system](009-navigation-indicator-system.md)
- [010-mode-architecture](010-mode-architecture.md)
