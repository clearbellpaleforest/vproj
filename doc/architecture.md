# Architecture

## Subsystems

The project manager consists of four major subsystems:

1. **Workspace Management** — owns runtime state, the authoritative source of
   truth. All other subsystems read from workspace. Only commands write to it.

2. **Project Management** — .vproj file I/O, project creation, loading,
   saving, modification. Operates on filesystem. Called by commands, never
   calls display directly.

3. **Navigation Management** — selection, paging, root changes, parent
   navigation, mode changes. Translates user input into state changes.

4. **Display Management** — generates pane contents from workspace state. Reads
   state. Never modifies it.

These subsystems should be kept logically separate where practical. The source
code may initially be contained in a single Vimscript file but should be
organized internally so that future separation into multiple source files is
straightforward.

## Architectural Principles

VPROJ follows three principles. These are not heavy frameworks. They are
disciplines applied consistently throughout the codebase.

### Workspace Domain Model

The workspace is not a variable bag. It is the central domain object.

The workspace owns all runtime state and is the authoritative source of truth.
Nothing outside the workspace may hold a copy of state that diverges from it.

Display output shall be generated from the workspace. Display output shall not
be treated as state.

The workspace contains:
- current mode (file, buf, code, qfix, log)
- current project (.vproj name and root)
- current root directory
- selected line and item index
- current page and items per page
- pane width (per-mode configurable)
- display options (info column, dotfiles, tree view, git filter)
- navigation indicator offset
- filter pattern
- preview state (active, file path)
- session persistence (last mode and directory)

### Command/Query Separation

All operations on the workspace shall be classified as either a Command or a
Query.

Commands change state. Queries never change state. This is a hard rule.

No function may both read state for display purposes and modify state at the
same time. This eliminates an entire class of bugs and makes the system
predictable.

**Commands** (change workspace state):
- IncludeFile
- ExcludeFile
- OpenBuffer
- RenameProject
- ChangeRoot
- ChangeMode
- SetPaneWidth
- SelectItem
- ChangePage
- ShiftNavOffset

**Queries** (only read workspace state):
- GetVisibleItems
- GetProjectTree
- GetOpenBuffers
- GetIncludedFiles
- GetCurrentPath
- GetPageInfo
- GetNavIndicators

Pattern: `ExecuteCommand('OPEN_BUFFER', item)` then `QueryVisibleItems()` to
rebuild the display. The display is always rebuilt from a query, never from
side effects of a command.

### Event Naming

A defined set of named events describes what happens in the system.

Events are not a full publish/subscribe bus — they are named, documented
moments in the lifecycle that functions hook into consistently.

When AI integration, history, or source control arrives, those features wire
into these named points rather than hunting through the code.

Events:
- ProjectLoaded
- ProjectCreated
- ProjectSaved
- RootChanged
- ModeChanged
- ItemSelected
- FileOpened
- BufferSwitched
- ItemIncluded
- ItemExcluded
- ProjectRenamed
- PaneToggled
- PageChanged

Every command shall emit exactly one event on completion. The display shall
rebuild in response to events, not in response to direct function calls. This
keeps the renderer decoupled from the command layer.

## Implementation Architecture (Current)

The current implementation uses explicit imperative flow rather than a formal
event bus. Commands change state then call `Render()` directly. The display is
a pure function of current state — call Render at any time and you get an
accurate picture of the workspace. No event bus, no CQS objects, no domain
model classes. Plain functions operating on script-local variables.

### Window Management

`OpenInRightPanel()` is the central helper for all content that appears to the
right of the pane. It finds an existing non-pane window (reusing it) or creates
a new `botright vnew` if only the pane exists. Callers (`OpenFile`, `GitBlame`,
`OpenDiffPreview`, `OpenPreview`) use it to get a consistent two-panel layout
without duplicating window-finding logic. The pane stays visible on the left;
content appears on the right.

This is a deliberate simplification. The three principles above describe the
logical structure that the code should be organized around, even when the
implementation uses direct function calls rather than formal event dispatch.
