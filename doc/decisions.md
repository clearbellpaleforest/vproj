# Design Decisions

Rationale for key design choices and documented divergences from the original
concept.

## Vim9Script Over Legacy Vimscript

Vim9Script provides type checking, `def` functions with strict semantics, and
better performance. The trade-off: `def` functions have stricter rules (lambda
vars must start with capital, `readdir()` requires explicit filter arguments).

## Explicit Render Over Event Bus

concept.md specifies event-driven display: commands emit events, display
rebuilds in response. The current implementation uses direct `Render()` calls
after every state change.

**Rationale:** With a single-threaded Vim runtime and a single consumer
(the pane buffer), an event bus adds indirection without benefit. The
"explicit imperative flow" pattern — where every command ends with a Render
call — is simpler to trace, debug, and test. Events will be introduced when
multiple consumers exist (e.g., source control integration, history log).

## Script-Local State Over Object Model

concept.md specifies a Workspace Domain Model. The current implementation
uses flat script-local variables.

**Rationale:** Vim9Script has no class construct. A flat list of script-local
variables with clear naming conventions achieves the same goal (single source
of truth, no divergent copies) without building an object system in a language
that doesn't support one. The variables are listed at the top of the file,
serving as a visible schema.

## Two Source Files

`plugin/vproj.vim` and `autoload/vproj.vim`. No additional files.

**Rationale:** Vim's autoload mechanism provides lazy loading — functions in
`autoload/` are only loaded when first called. The plugin file is the table of
contents. Two files is the minimal split that preserves this separation. A
third file would need to justify itself against the complexity cost of another
boundary.

## No External Dependencies

**Rationale:** A project manager should load instantly. Dependencies add
startup cost, version compatibility risk, and installation friction. Vim's
built-in functions (`getbufinfo()`, `readdir()`, `readblob()`) provide
everything needed.

## Pane Width: 40 Columns Default, 20-80 Range

**Rationale:** 40 columns balances file path visibility against screen real
estate. The user's primary work happens in the editing window, not the project
pane. The 20-80 range prevents degenerate states while allowing user
preference.

## ASCII-Only Separators

**Rationale:** Unicode box-drawing characters render inconsistently across
terminals and fonts. ASCII dashes are unambiguous everywhere. The display
should never depend on a specific terminal emulator or font configuration.

## `<Cmd>` Mappings

All buffer-local mappings use `<Cmd>` instead of `:`.

**Rationale:** `<Cmd>` executes the command directly without entering
command-line mode, avoiding visual flicker and mode-change side effects.
Available in Vim 8.2+ and Neovim.

## Nav Indicators: Dynamic Assignment Over Fixed

Each item does not have a permanent nav letter. Indicators are assigned to
visible items in the current page, starting from `nav_offset`.

**Rationale:** Fixed assignments would require permanent tracking of which
letter maps to which file across directory changes. Dynamic assignment is
simpler: label what's visible, shift with Tab. The user learns the position,
not the letter.

## Paging vs. Tab Relabeling

Paging (Ctrl-N/Ctrl-P) changes which items are visible. Tab relabeling changes
which visible items get nav indicators. They are independent features solving
different problems: paging handles too many items to display; Tab handles too
many items to label with the available 58 indicators.

## getftype() Filtering

`getftype()` is used to exclude FIFOs, sockets, and devices from directory
listings and code mode.

**Rationale:** `readblob()` hangs on FIFOs. Filtering these at the listing
stage prevents the hang. This is a defensive measure — most directories will
not contain FIFOs, but when they do, the program must not freeze.

## Info Column: File Sizes Over Modification Times

File mode shows sizes, not modification dates.

**Rationale:** File size is the more actionable piece of information when
scanning a project — large files vs. small files is immediately useful. Dates
add visual noise for little navigation benefit.

## Shift Mode Keys

Modes are selected with Shift-modified keys: `Shift-F` (file), `Shift-B` (buf),
`Shift-C` (code). Quickfix uses `q` (unmodified, since it toggles close in
permanent mode). Close pane stays on `Q`.

**Rationale:** Moving mode keys to Shift frees lowercase `f`, `b`, `c`, and `g`
for use as nav indicators, nearly doubling the available indicator set. It also
eliminates Vim prefix-key timeout conflicts — `f<char>`, `gg`/`G`, and `q` (macro
record) no longer need `<nowait>` hacks because Shift-modified keys are not Vim
prefix keys. The trade-off: two-key chords for the most frequent action (mode
switching) versus more nav indicators and simpler key mapping. One-letter
mnemonics are preserved: Shift-F = File, Shift-B = Buffer, Shift-C = Code.

## Qfix Mode

A fourth mode displays the Vim quickfix list. `getqflist()` provides entries;
Enter jumps to file:line and closes the pane.

**Rationale:** The quickfix list is Vim's standard mechanism for iterating
through search results, compile errors, or any filterable content. By reading
it rather than writing it, qfix mode composes with `:make`, `:grep`,
`:vimgrep`, and AI-driven `setqflist()` calls without any VPROJ-specific API.
Standard Vim tooling populates the list; VPROJ displays it.

## constraints.md Over requirements.md

Hard constraints (cross-platform, no dependencies, two source files,
ASCII-only) live in a separate `constraints.md` file. Features live in
concept.md.

**Rationale:** Constraints are walls you can't move; features are things you
might add. Keeping them separate prevents desirable features from being
confused with non-negotiable boundaries. When a new feature is proposed, you
check it against constraints.md, not a merged wishlist.

## DirChanged Autocommand for `:cd` Tracking

Vim's `DirChanged` event triggers an automatic refresh of the file pane when
the user changes directories with `:cd`, `:lcd`, or `:tcd`. Both `global` and
`window` scopes are monitored.

On directory change:
- If the pane is not visible or code mode is active, no action is taken.
- Otherwise, `current_dir` is updated to the new CWD, selection resets to the
  first selectable item, and `nav_offset` and `current_page` reset to 0 before
  re-rendering.

**Rationale:** A project manager must stay in sync with Vim's working
directory. Without this, changing `:cd` would leave the pane showing stale
contents — a safety issue since the user could act on files from the wrong
directory. The autocommand is scoped to `global` and `window` to catch all
forms of directory change. Code mode is excluded because it operates on the
project root, not the CWD.

## Color-Coded Mode Indicators

Four mode-specific highlight groups replace a single generic group:
`VprojModeFile` (yellow), `VprojModeBuf` (green), `VprojModeCode` (blue),
`VprojModeQfix` (blue). Each uses `cterm=bold,underline` plus its distinct
color.

The active mode's group is selected dynamically in `ApplyStaticHighlights()`
based on `toupper(current_mode[0]) .. current_mode[1 : ]`.

Color coding provides at-a-glance mode identification without reading the
label text. The user learns the color mapping quickly and can confirm mode
with peripheral vision. Four distinct colors are used rather than reusing a
single color to avoid ambiguity.

## Shift Mode Keys Eliminate `<nowait>`

Mode-switch keys `Shift-F`, `Shift-B`, and `Shift-C` do not need `<nowait>`
because Shift-modified keys are not Vim prefix keys. The prefix-key timeout
conflict (`f<char>`, `gg`/`G`, `q` macro record) is eliminated entirely —
no `<nowait>` hack required.

**Rationale:** Moving mode keys to Shift was driven by two goals: freeing
lowercase letters for nav indicators and removing `<nowait>` complexity.
`<nowait>` was a workaround for the inherent conflict between Vim's prefix-key
conventions and buffer-local single-key mappings. Shift keys sidestep the
conflict instead of working around it.

## Shortmess S Flag Save/Restore

The pane temporarily adds the `S` flag to Vim's `shortmess` option to suppress
"search hit BOTTOM, continuing at TOP" messages that appear during matchadd
highlight application. The original `shortmess` value is saved to a
script-local variable and restored when the pane closes (`HandleBufWipeout`).

**Rationale:** `shortmess` is a global-only Vim option — it cannot be set
per-buffer or per-window. The S flag suppresses the passive search-wrap
messages that `matchadd()` can trigger when applying highlight patterns. The
save/restore pattern ensures other buffers are unaffected. Restore happens in
`HandleBufWipeout` as the last cleanup step, even if the user closes the pane
with `Q` or `F4`.

## Global F1/Help Mapping (HandleF1)

F1 and Help are Vim built-in keys that cannot be overridden by buffer-local
mappings. A global `:call vproj#HandleF1()<CR>` mapping checks the context:
inside the pane, it toggles the info column; outside, it calls `:help`.

**Rationale:** `<F1>` and `<Help>` are hardwired to `:help` in Vim. A
`nnoremap <buffer>` can't intercept them because the global handler fires
first. The standard Vim pattern for this: a global `:call` mapping that
checks context. Using `:call` (not `<Cmd>`) is essential because `<Cmd>`
forbids any command that changes window or buffer — the else branch calls
`:help`, which opens a new window, which `<Cmd>` would block with
"error not enough room".

## matchadd() ID Auto-Assignment

All `matchadd()` calls pass `-1` as the 4th argument for automatic match ID
assignment.

**Rationale:** The 4th argument to `matchadd()` is the match ID, not a window
ID. A previous bug passed `pane_wid` (a window ID like 1001) as the match ID,
causing both `matchadd()` calls to claim the same ID — the second call failed
with E801. Using `-1` lets Vim assign unique IDs automatically. Additionally,
`matchdelete(id, window)` takes a window ID as its 2nd argument, which is
separate from the match ID — conflating the two was the root cause.

## Log Mode (L key, 5th Pane Mode)

A fifth pane mode displays git commit history using `git log --oneline`.
Enter on a commit opens a detailed diff split.

**Rationale:** The pane already has git integration (file status indicators,
diff preview, staging). Seeing the commit log directly in the pane is the
natural next step — it turns the pane into a lightweight git history browser
without leaving Vim. The `Shift-L` key was chosen because it's unused in the pane.

## Git Actions in Pane (s, d, D, C, P, U, B)

Single-key git operations work directly from the pane: stage, diff, discard,
commit, push, pull, branch switch. No need to drop to a terminal or use Vim's
`:!git` commands.

**Rationale:** Project management includes version control. The most common git
operations should be single keystrokes. These keys are only mapped in the pane
buffer and do not affect other Vim buffers. Operations that modify the working
tree (discard, commit, push) use confirmation prompts or `input()`.

## Tree View Toggle (T key)

Flat file listing can be toggled to an indented directory tree with T.
Individual directories can be expanded/collapsed. Tree state is preserved
within file mode across mode switches.

**Rationale:** A flat listing is fast to scan; a tree view reveals project
structure. The user toggles between them depending on the task. T is unused
in the pane (upper-case, distinct from mode keys).

## File Preview (p key)

Pressing p opens a split showing the contents of the file under cursor.
The preview updates on cursor movement. Pressing p again closes it.

**Rationale:** Quick file preview without opening. Particularly useful when
scanning a directory — you can see file contents without committing to opening
the file. `botright vnew` creates the preview window below and to the right
of the pane.

## Filter by Name (/ key) and Grep (* key)

`/` prompts for a name filter and reduces the listing to matching items.
Clearing the filter restores the full listing. `*` prompts for a grep pattern,
runs `grep -rn` in the project root, and populates the quickfix list.

**Rationale:** Standard Vim users reach for `/` to search and `*` to find
occurrences. These mappings in the pane buffer adapt both keys to project-level
operations. `/` filters the current listing; `*` populates quickfix for qfix
mode navigation.

## cmdheight Lowering Before Splits (E36 Guard)

Before any `:split`, `:vnew`, or `:vsplit` operation, the code temporarily
lowers `cmdheight` to 1 (if above 2) and `winminwidth`/`winminheight` to 1,
then restores the original values. This is done in OpenFile, OpenPreview,
OpenDiffPreview, OpenBuffer, OpenQfixEntry, and OpenCommitDetail — every split
in the codebase.

**Rationale:** A user with `cmdheight=23` (24-line terminal) had only 1 line
available for windows, causing E36 "Not enough room" on every split. `cmdheight`
is a global option that can consume most of the screen. Lowering it before
splits prevents E36 without requiring the user to change their vimrc. The
`winminwidth`/`winminheight` lowering similarly prevents E36 when those are
set high.

The restore of `cmdheight`/`winminwidth`/`winminheight` lives in a `finally`
block so it executes even when the split throws an exception. A previous version
of this code duplicated the restore in both the catch block and after endtry;
the `finally` block eliminates the duplication. (Note: `return` from within
`finally` is legal in Vim9Script. If the catch block returns, `finally` still
executes before the return takes effect.)

## OpenInRightPanel: Centralized Right-Panel Window Management

`OpenInRightPanel()` finds or creates a window to the right of the VPROJ
pane. It iterates `getwininfo()` to find an existing non-pane window, reusing
it if found. If only the pane window exists, it creates a new vertical split
with `botright vnew`.

**Rationale:** Before this helper, `OpenFile`, `OpenDiffPreview`, `GitBlame`,
and `OpenPreview` each had their own (inconsistent) split logic. Three of them
used `rightbelow split` + `rightbelow vsplit` which created an awkward
horizontal+vertical layout instead of a clean left/right split. Only
`OpenPreview` had the correct `getwininfo()` + `botright vnew` pattern.
Extracting the correct pattern into one function eliminates the duplication
and ensures consistent window layout.

## Two-Panel Layout: Pane Stays Open After Opening Files

When the user presses Enter on a file, the file opens in a window to the
right of the pane. The pane stays visible on the left. The user can continue
browsing and open another file — the right-side window is reused, replacing
its content instead of stacking more splits.

**Rationale:** The old behavior (close the pane, take over the full screen)
turned the pane into a one-shot file browser. The two-panel layout treats the
pane as a persistent sidebar — like a file-manager tree view that stays open
while you edit files. This matches user expectation from IDEs and graphical
file managers. `OpenFile`, `GitBlame`, and `OpenDiffPreview` all use
`OpenInRightPanel()` for consistent window behavior.

## Defensive Dict Access: get() Over Dot Notation

All dict key access on items from external sources (user input, filesystem
listings, git output, quickfix entries) uses `get(dict, 'key', default)`
rather than `dict.key` dot notation. Dot notation throws E716 "Key not
present in Dictionary" when the key is missing, even when the code has an
empty-dict sentinel check.

**Rationale:** Items flow through multiple transformations (listing, filtering,
paging) before reaching display or action functions. An item from ReadDir has
different keys than one from QfixItems or LogItems. Even within a single code
path, a `GetSelectedItem()` caller may receive an empty `{}` or a partial
dict on edge cases. `get()` with a sensible default returns safely; dot
notation crashes. The extra typing is negligible compared to the debugging
cost of an E716 that only triggers when the user has an empty quickfix list
or browses a directory with unusual entries.

A comprehensive audit (2026-06-18) replaced all unguarded dot accesses across
the entire 3286-line codebase: `item.name`, `item.path`, `item.is_dir`,
`item.size`, `project.root`, `project.name`, `item.col`, `item.lnum`,
`item.filename`.

## Git Stash Keys (z/Z)

`z` pushes a stash with an optional message via `git stash push`. `Z` pops a
stash after listing all stashes and prompting for which to pop (default: top).

**Rationale:** The `z`/`Z` pair follows the lowercase/uppercase convention
established by `d`/`D` (diff/discard). `z` was chosen because it's mnemonic
for "stash" (phonetically) and was previously a nav indicator character.
Showing the stash list before popping prevents accidental pop of the wrong
stash — the user sees what's there before choosing. The alternative of a
single toggle key was rejected because push and pop are distinct operations
with different confirmation requirements.

## Git Blame Key (a)

`a` opens a split showing `git annotate` output for the file under cursor.
Only in file mode, only for regular tracked files.

**Rationale:** `a` is the canonical alias for `git annotate` (git's cleaner
interface to blame). Using `git annotate` rather than `git blame` gives the
same output with a cleaner interface name. The blame window is a scratch
buffer (buftype=nofile, readonly, nomodifiable) following the same pattern
as diff preview — `q` closes it. E36 guards follow the established pattern
for all split operations. Untracked files are rejected because `git annotate`
fails on them — the `git ls-files` guard prevents a confusing error.

## Tab/Shift-Tab: Temporary vs. Permanent Pane Mode

`Tab` opens the pane in temporary mode (auto-closes on file-open, ESC, or Tab).
`Shift-Tab` opens in permanent mode (stays until explicit close). Pressing the
alternate toggle while the pane is open transitions modes without closing.

Both are `<Plug>` indirections (`VprojToggle`, `VprojTogglePermanent`) so users
can remap them. The plugin tracks `pane_open_mode` ('temporary' or 'permanent').

**Rationale:** Two use cases, two keys. Temporary mode is for quick file access
— open, pick, dismiss. Permanent mode is for extended project management
sessions — keep the pane visible while editing. The previous single-toggle
(Tab only, permanent-only) served neither use case well: users who wanted quick
access had to manually close the pane each time; users who wanted persistence
had no way to signal intent. The dual-key design lets the user declare intent
at toggle time.

### Pane Events

The plugin fires `User VprojPaneOpenedTemporary`, `User VprojPaneOpenedPermanent`,
and `User VprojPaneClosed` events. Add-ons (e.g., vproj_ai) listen for
`VprojPaneReady` (which fires after both open events) to inject buffer-local
mappings when the pane is structurally sound.

**Rationale:** Add-ons need to know when the pane buffer is ready for key
injection. The `BufEnter` autocommand fires before split layout stabilizes;
`User VprojPaneReady` guarantees the pane window exists, is the correct width,
and is in normal mode.

## `<Cmd>` Override: When `:call` Is Required

The `<Cmd>` mapping modifier is preferred for its lack of mode-change side
effects, but it forbids any command that changes window or buffer — including
`:help`, `:split`, `:new`, `botright new`, and any function that calls them.
The global `HandleF1` mapping uses `:call` (not `<Cmd>`) because the else
branch opens a `:help` window.

**Rationale:** `<Cmd>` is a straightjacket, not a preference. It prevents
commands that create windows because Vim's command-line mode tracks the
originating buffer's state at command entry — `<Cmd>` bypasses that tracking.
Any mapping whose call chain creates a window or buffer must use `:call`.

### `<Cmd>` and Insert Mode in Secondary Buffers

When `<Cmd>` maps create a window inside their callback (e.g., `botright new`),
Vim can lose track of what mode the originating buffer should return to. The
pane buffer would end up in insert mode after the AI conversation flow
completed. Root cause: `<Cmd>` skips the command-line mode transition where Vim
saves and restores buffer mode.

**Fix:** All 6 nnoremap mappings in vproj_ai changed from `<Cmd>call ...<CR>`
to `:call ...<CR>`. Defensive `stopinsert` calls guard the conversation buffer
and pane buffer at exit points.

## Edge Test: PaneGrow/PaneShrink in While Loops

The edge test originally used while loops (`while w < 80 | PaneGrow() | endwhile`)
to test width clamping. These loops caused test hangs because `PaneGrow()` and
`PaneShrink()` each call `Render()`, and 50+ consecutive Render calls in
non-interactive Vim fill the message buffer, triggering hit-enter prompts that
block test execution.

**Fix:** Replaced while loops with direct `SetPaneWidth(80)` and `SetPaneWidth(20)`
calls, which set the width in one operation. The clamping assertions (PaneGrow
past max, PaneShrink past min) are tested with a single call each after setting
the boundary value.

## setwinvar for Window-Local Options

Options like `number`, `relativenumber`, `signcolumn`, `cursorline`,
`winfixwidth`, `foldenable`, and `wrap` are window-local in Vim.
`setbufvar()` silently does nothing for these — they must be set with
`setwinvar()` passing the window ID.

**Rationale:** Vim's option scoping is not obvious: `setbufvar()` succeeds
without error for window-local options but applies nothing. This caused the
pane to lack `winfixwidth=1` — the option was set via `setbufvar()` which
silently failed. All window-local options in the codebase now use
`setwinvar(wid, ...)` with the window ID captured immediately after window
creation (`win_getid()`).
