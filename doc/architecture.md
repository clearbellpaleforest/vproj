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

These subsystems should be kept logically separate where practical. The core
lives in one autoload file (`autoload/vproj.vim`), organized internally by
subsystem, with `plugin/vproj.vim` as the public surface. Two add-ons are
separate files loaded on demand: `autoload/vproj/ai.vim` (AI provider chat and
prompt) and `autoload/vproj/agent.vim` (external coding-agent CLI in a
terminal split). The add-ons call back into core only through its exported
functions; plugin calls autoload, never the reverse.

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
- current mode (file, buf, code, qfix)
- current project (.vproj name and root)
- current root directory
- selected line and item index
- current page and items per page
- pane width (per-mode configurable)
- display options (info column, dotfiles, tree view, git filter)
- navigation indicator offset
- filter pattern
- preview state (active, file path)
- session persistence (last mode, directory, width, info column, git filter; written only when `g:vproj_save_session = 1`, read whenever a file exists)

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

`EditTargetWindow()` is the central helper for all file and buffer opens from
the pane. It returns the window the user came from if it is still an edit window,
else the first edit window in the tab, else creates one with `botright vnew`
(a vertical split to the right of the pane). `OpenFile`, `OpenBuffer` and
`OpenQfixEntry` use it; `ShowScratchSplit` (diff and blame) uses it and opens a
read-only vertical split beside it; `OpenPreview` creates its own split. The pane stays visible on the left. After a successful
open, `FinishOpen()` closes the pane in temporary mode and returns focus to it in
permanent mode.

This is a deliberate simplification. The three principles above describe the
logical structure that the code should be organized around, even when the
implementation uses direct function calls rather than formal event dispatch.
