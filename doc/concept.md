VPROJ_AI
Vim project manager with AI assistance. An add-on for VPROJ that adds
language model integration directly into the editing workflow.

Status (2026-06-23)
Currently: terminal-based chat via `:terminal` + bash SSE streaming script.
`A` key opens a 15-line `botright new` terminal running `bin/vproj-ai-chat`.
Streaming SSE responses, multi-turn conversation, curl-based API calls.
No job_start, no conversation buffer, no Vimscript-side SSE parsing.

AI Integration
The AI feature is accessed through a single key: A in the vproj pane. There
are no AI sub-modes, no separate commands for different AI actions. The user
presses A, describes what they want in natural language, and the system
handles the rest.

Pressing A opens a `:terminal` buffer running `bin/vproj-ai-chat`, a bash
script that:
- Receives context (file, filetype, mode) from Vim via $VPROJ_AI_TMPFILE env var
- Reads user prompts in a read loop
- Calls the OpenAI-compatible API (DeepSeek by default) with SSE streaming
- Renders token-by-token responses inline
- Maintains conversation history for multi-turn interaction
- Exits on /exit or Ctrl-D

Context is automatic and mode-aware. When A is pressed, the system gathers:
- File mode: absolute path under cursor + file ±100 lines
- Code mode: absolute path under cursor + file ±100 lines
- Log mode: commit hash under cursor + `git log --stat <hash>` output
- Qfix mode: filename:lnum + entry text from quickfix item
- Buf mode: target buffer's full text (capped)

The context is written to a temp file as JSON. The bash script reads it
and includes it in the system prompt sent to the API.

The AI backend is provider-agnostic (OpenAI-compatible API). Configured via
g:vproj_ai_api_key and g:vproj_ai_api_url. No external dependencies beyond curl.

VPROJ
Vim project manager for software development. (Base project — vproj_ai is a fork.)

Folder Structure:
~/dev/vproj
├── vproj.vproj
├── doc
│   ├── design.md
│   ├── feedback
│   ├── README.txt
│   └── revisions
└── src
    ├── autoload
    │   └── vproj.vim
    └── plugin
        └── vproj.vim

Purpose:
VPROJ is a project and workspace manager for Vim.

The purpose of VPROJ is to allow the user to navigate files, documents, and projects quickly using the keyboard. The project manager shall be suitable for software development projects containing large numbers of files and directories.
VPROJ should behave more like a lightweight IDE project manager than a traditional file browser.
The user should be able to perform most common navigation tasks without typing commands on the command line.
The user should be able to perform most common navigation tasks without using a mouse.

Overall Design
The project manager shall consist of four major subsystems:

    Workspace Management
    Project Management
    Navigation Management
    Display Management

These subsystems should be kept logically separate where practical.
The source code may initially be contained in a single Vimscript file but should be organized internally so that future separation into multiple source files is straightforward.

The internal architecture shall follow three principles:
    Workspace Domain Model
    Command/Query Separation
    Event Naming

These are described in detail in the Architecture section below.

Workspace Management
The workspace represents the current state of operation.
The workspace shall contain information such as:

    current mode
    current project
    current root directory
    selected item
    current page
    pane width
    display options

The workspace shall be the authoritative source of information regarding the current state of operation.
The display shall be generated from the workspace state.

The project manager will have a hotkey that toggles it visible or invisible.
This hotkey should be user settable, but can default to F4.
    When the hotkey is pressed then the plugin will determine the current directory and look for a .vproj file in that directory, which it will open and use to instantiate the display if it is found. If no .vproj file is found, then it will traverse upwards in the directory structure, looking for a .vproj file. If it finds one in a parent directory, then the project in that parent directory will be opened but the current root will be set to the current working directory.
    If no .vproj file is found and the system has navigated to the /home directory or to the /root directory, then on the ex command line the user will be invited to create a new project in the current working directory, with the default name being the name of that directory, but the user will be able to edit it.
    So, in the case that no .vproj file is found then the following happens:
        On the ex command line the user is prompted "No .vproj found, create one?"
        If the user presses y or Y then proceed to the next step, otherwise cancel
        On the ex command line the user is prompted "Create project: DIRNAME"
        where the user can edit DIRNAME (the name of the current directory)
        if the user presses Enter then the project file is created, if Esc then cancel
        If a new project is created then the project file is generated and the project opened normally.

Project Management
    A project is a collection of files and directories.
    Projects shall be stored in .vproj files.
    A project shall contain:

        project name
        project root
        included directories
        included files
        excluded directories
        excluded files

The project manager shall support:

    project creation
    project loading
    project saving
    project modification

The project manager shall not require external dependencies.

Project Definition Storage
    The information about what files and directories are in the project will be stored in the root directory of the project and named name.vproj where "name" is the name of the project.
    The .vproj file will contain the following information:
    a line "Project Name: [name]" listing the name of the project
    a line "Project Root: [path]" listing the full path of the project
    a line "Included Directories:" followed by a list of the paths of all the directories that are included in the project.
    a line "Included Files:" followed by a list of all the paths of all of the files specifically included in the project.
    a line "Excluded Directories:" followed by a list of all of the directories specifically excluded from the project.
    a line "Excluded Files:" followed by a list of all of the files specifically excluded from the project.

Navigation Management
    Navigation shall be keyboard oriented.
    Every visible item should be reachable without requiring cursor movement through the entire list.
    Navigation indicators shall be used for rapid selection.
    Navigation indicators shall be dynamically assigned.
    The navigation system shall support:

    direct item selection
    paging
    root changes
    parent navigation
    mode changes

Navigation operations should be independent of display operations where practical.

Navigation Indicators:
    To navigate, each line having a directory or a file or a buffer should have a letter like 'a' next to it in cyan. There should be a one-space separation between the nav indicator and the rest of the line. If the user presses that   letter then that file will become the action selection and will be highlighted.
    The nav keys should be "a b c d e f g h i j k l m n o p q r s t u v w x y z A B C D E F G ..." etc
    If we use the number keys too at the end it gives us 26 + 23 + 9 = 58 (approximately) nav indicators.
    The nav keys should not include keys used to select mode (Shift-F/Shift-B/Shift-C/q), navigation keys
    (h/j/k/l), action keys (r/x), or lowercase passthrough keys currently in use.
    The nav indicator of the project name should be the asterisk, '*'.
    The parent directory line should have no nav indicator. If the user presses '.' they go up a directory.
    Only about 58 files/directories will have a nav indicator. If there are more than that then the place where the nav indicator would go will be blank. If the user presses [TAB] then the nav indicator labeling should shift and relabel the files/directories starting with the next blank one. Likewise, pressing Tab cycles through the list and relabels the lines below. To summarize navigation:
    * project name
    . parent directory
    a-z, A-Z, 1-9 files/directories
    TAB re-label files below and cycles forward (wraps around if necessary)
    Shift-TAB relabel files above

General navigation hotkeys (all modes):
    Up/Down arrows    move selection up and down, wrapping at top and bottom
    Left/Right arrows decrease or increase pane width by one column
    Enter             perform the default action on the selected item
    F1                toggle the file information column on or off
    Ctrl-N            next page
    Ctrl-P            previous page
    Ctrl-T            go to first item
    Ctrl-B            go to last item

Mode selection hotkeys:
    Shift-F   File Mode
    Shift-B   Buffer Mode
    Shift-C   Code Mode
    q   Quickfix Mode

Actions on the Selection:
    When the project name is selected, then pressing Enter will allow the user to rename the project on the ex command line.
    When a directory is selected, then the display root will change to that directory.
    When a file is selected, then either the file is (1) opened as a new buffer, or (2) made the active buffer in the parent pane if the file is already in an existing buffer. Then the project window should close.
    If an unincluded file or directory is selected and the user presses Shift+I then that file will be included in the project.
    If a project file or directory is selected and the user presses Shift+X then that file or directory will be specifically excluded from the project.
    If a binary file is selected and the user presses Enter then a Vim status message should appear announcing that it is a binary file.

Display Management
    The display manager shall generate the contents of the project pane.
    The display manager shall not modify workspace state.
    The display manager shall determine:

item layout
truncation
colors
page indicators
information columns

Display behavior should be controlled by configuration variables where practical.

Project Window Layout (all modes):
    The project pane should be at most 40 columns wide (to start with).
    The right and left arrow keys should increase or decrease the pane width by one character.
    The up and down arrows should navigate up and down the file list as usual and should wrap around top to bottom.
    The F1 key should toggle on or off the file information column (on the right).
    The mode option display (menu) should be the first line (by default).
    Each mode has a distinct color on the menu line (yellow=File, green=Buf, blue=Code, blue=Qfix) so the user can identify the current mode at a glance.
    The nav key indicators should be cyan text in color and should be at the left separated from the rest of the line by one space.
    The file information column should be located on the right and be in bright green.
    The file information column size should depend on the content.
    The file name column should adjust so that the total width of the project pane is the specified width.
    If there are more files than can be displayed in the pane, then a page navigation row should be shown as the last row.
    The page navigation row should display the page situation and remind of the hotkeys to navigate pages. For example:
    " >>> Page 4/8 CTRL-N CTRL-P <<< "
Normally the mode option display should be separated from the file list by a line composed of dashes.
The mode option display should be at the top of the project pane by default but there should be a user-configurable way to put it at the bottom instead.

Modes
    The project manager shall support multiple operating modes.
    Additional modes may be added in future versions.
    Initially the following modes shall be supported.
        (Shift-F) File Mode
        Purpose:
        General file browsing and selection.
        The display shall show:

            directories
            files
            file size information

The display shall be based on the current directory.
The parent directory shall be represented by "..".

    The status label at the top of the screen should show the current path.
    If the current path will not fit in the allotted space for the pane, then the status label should be right aligned.
    The file information column should have the file size like this " 324K" or "  45M".
    The file information column should be exactly 5 characters and be right-aligned padded with spaces.
    The parent directory should be indicated with a .. as usual.
    Pressing ENTER on the parent directory entry should navigate up a directory.
    Pressing CTRL-K should navigate up a directory.
    Pressing CTRL-J should navigate down into the first listed directory (if there are any subdirectories).
    If the current folder has no subdirectories and CTRL-J is pressed then nothing happens.
In a future version we may support hierarchical file display, but for now just show the current directory.

(Shift-B) Buffer Mode
    Purpose:
    Management of open Vim buffers.
    The display shall show:

        buffer names
        modification status
        active buffer status

    The display shall allow rapid switching between buffers.

The buffer mode should display in a way similar to the vim buffer list, it shows the open buffers.
The information column (on the right) should operate similar to Vim's buffer flags.
It would be interesting if the Vim buffer list informational symbols were queryable somehow rather than writing code to determine them from scratch.
    Note- getbufinfo() returns buffer state directly.
In other respects the Buffer Mode should operate similar to the File Mode.
    Note-getbufinfo() returns buffer state directly, including modified status, listed status, hidden status, active window information, and line count. Buffer flags and line count shall both be derived from getbufinfo() rather than reimplemented from scratch. **Note that linecount is only valid when the buffer is loaded.

(Shift-C) Code Mode
    Purpose:
    Management of project structure.
    The display shall show:

        project name
        current root
        project tree

    The display shall be based on project information rather than filesystem information.
    Included and excluded items shall be visible.

In code mode, the name of the project should be the second line with the base directory as a label.
Next should be a line named ".. [dir name]" allowing user to navigate to a parent directory.
The project tree should be shown next.
The project tree shall be shown relative to a current root directory which the user can change.
    So, in other words, let's say the project root is ~/dev/vproj then that is the label.
    However, if the user navigates to ~/dev/vproj/src then that becomes the current root.
    Only the subtree of the current root is shown.
    The user knows the current root because it is shown in the ".." line.
Below the project tree should be files/directories in the base directory which are not included.
    The files/directories not included should be listed with parentheses around them.

(q) Quickfix Mode
    Purpose:
    Iteration through the Vim quickfix list.
    The display shall show:

        filename
        line number
        entry text

    The display shall be based on the current quickfix list (getqflist()).
    Entries shall be selectable by nav indicator.
    Pressing ENTER on an entry shall jump to that file:line and close the pane.
    The quickfix list is populated externally — by :make, :grep, :vimgrep,
    setqflist(), or AI-driven analysis. VPROJ displays it; it does not
    populate it.

Display Philosophy
    The display should emphasize useful information while minimizing visual clutter.
    The project pane should remain narrow.
    The default pane width shall be forty columns.
    The display should remain readable on terminals of varying size.
    Colors should only be used when color support is available.
    The display should remain usable in monochrome terminals.

Configuration Variables:
    The user should be able to control certain parameters of operation by configuration variables in their .vimrc file. For example:
    VPROJ_pane-width_default=40
    VPROJ_pane-width_code=40
    VPROJ_pane-width_file=40
    VPROJ_pane-width_buf=40
    VPROJ_pane-width_qfix=40
    VPROJ_mode-display-location=TOP
A natural way to implement the mode display location option is by an environmental variable such as VPROJ_mode-display-location which the user could set to "TOP" or "BOTTOM" and place in his vimrc file. Obviously option values like this should not be case sensitive and should allow initial letter prefixes like "t" or "B" just the same way "y" or "N" is allowed for Yes/No options. This is handled natively by Vim's tolower() and strpart() functions. No external library is needed.

Architecture
VPROJ shall follow three architectural principles: Workspace Domain Model, Command/Query Separation, and Event Naming. These are not heavy frameworks. They are disciplines applied consistently throughout the codebase.

    Workspace Domain Model
    The workspace is not a variable bag. It is the central domain object.
    The workspace owns all runtime state and is the authoritative source of truth.
    Nothing outside the workspace may hold a copy of state that diverges from it.
    Display output shall be generated from the workspace. Display output shall not be treated as state.
    This rule should be followed consistently throughout development.

    The workspace contains:

        current mode
        current project
        current root directory
        selected item
        current page
        pane width
        display options
        navigation indicator offset


Command/Query Separation
    All operations on the workspace shall be classified as either a Command or a Query.
    Commands change state. Queries never change state. This is a hard rule.
    No function may both read state for display purposes and modify state at the same time.
    This eliminates an entire class of bugs and makes the system predictable.

Commands (these change workspace state):

    IncludeFile
    ExcludeFile
    OpenBuffer
    RenameProject
    ChangeRoot
    ChangeMode
    SetPaneWidth
    SelectItem
    ChangePage
    ShiftNavOffset


Queries (these only read workspace state):

GetVisibleItems
GetProjectTree
GetOpenBuffers
GetIncludedFiles
GetCurrentPath
GetPageInfo
GetNavIndicators


Instead of a monolithic function like OpenFile() that does everything, the pattern is:
    ExecuteCommand('OPEN_BUFFER', item)
    then QueryVisibleItems() to rebuild the display
The display is always rebuilt from a query, never from side effects of a command.

Event Naming
    A defined set of named events describes what happens in the system.
    Events are not a full publish/subscribe bus — they are named, documented moments in the lifecycle that functions hook into consistently.
    When AI integration, history, or source control arrives, those features wire into these named points rather than hunting through the code.

Events:

    ProjectLoaded
    ProjectCreated
    ProjectSaved
    RootChanged
    ModeChanged
    ItemSelected
    FileOpened
    BufferSwitched
    ItemIncluded
    ItemExcluded
    ProjectRenamed
    PaneToggled
    PageChanged
    

Every command shall emit exactly one event on completion.
The display shall rebuild in response to events, not in response to direct function calls.
This keeps the renderer decoupled from the command layer.

Future Development
Future versions may include:

    source control integration
    semantic search
    project metrics
    code analysis
    workspace history

Such features should be added in a manner consistent with the existing architecture.
The primary objective shall remain fast keyboard-based project navigation.
Features which compromise simplicity or responsiveness should be avoided.

## Conversation Model

### Lifecycle

A conversation begins when the user presses `A` in the vproj pane and
types a prompt. The first response opens in a `botright vnew` split.
The buffer becomes a conversation view:

- Each exchange is labeled `User:` / `AI:`
- A `> ` prompt line at the bottom accepts follow-up input
- Press Enter on the `> ` line to send a follow-up
- `q` closes the conversation

Only one conversation exists at a time. Pressing `A` while a conversation
is open wipes the old buffer and starts fresh.

### Buffer Format

```
===============================================================================
 AI Assistant                                                     q to close
───────────────────────────────────────────────────────────────────────────────

User: <first prompt>

AI: <response>

User: <follow-up>

AI: <response>

> _
```

### History Management

The last 5 exchanges ({prompt, response} pairs) are stored in `ai_history`
and sent with each API request. The API sees the full conversation context.
The buffer displays all exchanges regardless of the history cap — the cap
only affects what is sent to the API.

### Context Freezing

The context dict from GatherContext() is frozen when the conversation
starts (stored in `ai_conversation_ctx`). All follow-up turns reuse this
frozen context — the AI always knows which file, mode, and cursor position
the conversation started from.

## Code Application Model

When the AI responds with code fences (```), the user can apply that code
directly to the original file. Press `a` anywhere inside or near a code
block to trigger the apply flow.

### Insertion Strategy

1. **Visual selection was active** — code replaces the original selection
2. **Cursor position known** — code is inserted after the cursor line
3. **No context available** — user is asked where to append

### Safety

- Code is inserted into the Vim buffer, NOT written to disk. User must
  `:w` to persist. This prevents accidental file corruption.
- Confirmation prompt shows the language tag and target filename:
  `Apply (python) code block to utils.py? (y/N): `
- All operations are undoable with standard Vim `u`.

Development Strategy
Development should proceed incrementally.
Recommended order:

Pane Infrastructure
File Mode
Buffer Mode
Project Storage
Code Mode
Quickfix Mode
Configuration
Documentation
Advanced Features

Each stage should result in a usable system.
At no point should the project require a complete rewrite to continue development.
TAB indicator relabeling is a version 1 feature, not optional. The nav_offset shall be
maintained as internal workspace state from the beginning. Paging and TAB relabeling are
independent features solving different problems and both shall be implemented in the
Pane Infrastructure stage.
