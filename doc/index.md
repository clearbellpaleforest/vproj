# Design Decisions

This directory contains the design decisions for the vproj project. The
decision log is `decisions.md`; the AI add-on decisions are recorded further
down this page (the "Base vproj Decisions" section below is a second copy of
the `decisions.md` entries with in-line **Current** notes). Entries are dated
records: the original text is kept and a status note under each heading says
whether it still matches the code. Status values: Current, Superseded, Partly
superseded, Removed.

An earlier version of this table listed one entry, "ADR-001 One Trigger Key
(A)". No record with that name exists in this repository; the one-key AI
trigger is discussed under AI-03 below. The table replaces it.

### Core decisions (`decisions.md`)

| # | Decision | Status | Record |
|---|----------|--------|--------|
| D-01 | Vim9Script Over Legacy Vimscript | Current | [decisions.md](decisions.md#vim9script-over-legacy-vimscript) |
| D-02 | Explicit Render Over Event Bus | Current | [decisions.md](decisions.md#explicit-render-over-event-bus) |
| D-03 | Script-Local State Over Object Model | Current | [decisions.md](decisions.md#script-local-state-over-object-model) |
| D-04 | Two Source Files | Partly superseded | [decisions.md](decisions.md#two-source-files) |
| D-05 | No External Dependencies | Current | [decisions.md](decisions.md#no-external-dependencies) |
| D-06 | Pane Width: 40 Columns Default, 20-80 Range | Current | [decisions.md](decisions.md#pane-width-40-columns-default-20-80-range) |
| D-07 | ASCII-Only Separators | Partly superseded | [decisions.md](decisions.md#ascii-only-separators) |
| D-08 | `<Cmd>` Mappings | Current | [decisions.md](decisions.md#cmd-mappings) |
| D-09 | Nav Indicators: Dynamic Assignment Over Fixed | Partly superseded | [decisions.md](decisions.md#nav-indicators-dynamic-assignment-over-fixed) |
| D-10 | Paging vs. Tab Relabeling | Partly superseded | [decisions.md](decisions.md#paging-vs-tab-relabeling) |
| D-11 | getftype() Filtering | Current | [decisions.md](decisions.md#getftype-filtering) |
| D-12 | Info Column: File Sizes Over Modification Times | Current | [decisions.md](decisions.md#info-column-file-sizes-over-modification-times) |
| D-13 | Shift Mode Keys | Partly superseded | [decisions.md](decisions.md#shift-mode-keys) |
| D-14 | Qfix Mode | Partly superseded | [decisions.md](decisions.md#qfix-mode) |
| D-15 | constraints.md Over requirements.md | Partly superseded | [decisions.md](decisions.md#constraintsmd-over-requirementsmd) |
| D-16 | DirChanged Autocommand for `:cd` Tracking | Partly superseded | [decisions.md](decisions.md#dirchanged-autocommand-for-cd-tracking) |
| D-17 | Color-Coded Mode Indicators | Current | [decisions.md](decisions.md#color-coded-mode-indicators) |
| D-18 | Shift Mode Keys Eliminate `<nowait>` | Partly superseded | [decisions.md](decisions.md#shift-mode-keys-eliminate-nowait) |
| D-19 | Shortmess S Flag Save/Restore | Partly superseded | [decisions.md](decisions.md#shortmess-s-flag-saverestore) |
| D-20 | Global F1/Help Mapping (HandleF1) | Current | [decisions.md](decisions.md#global-f1help-mapping-handlef1) |
| D-21 | matchadd() ID Auto-Assignment | Current | [decisions.md](decisions.md#matchadd-id-auto-assignment) |
| D-22 | Log Mode (L key, 5th Pane Mode) | Removed | [decisions.md](decisions.md#log-mode-l-key-5th-pane-mode) |
| D-23 | Git Actions in Pane (s, d, D, C, P, U, B) | Partly superseded | [decisions.md](decisions.md#git-actions-in-pane-s-d-d-c-p-u-b) |
| D-24 | Tree View Toggle (T key) | Partly superseded | [decisions.md](decisions.md#tree-view-toggle-t-key) |
| D-25 | File Preview (p key) | Partly superseded | [decisions.md](decisions.md#file-preview-p-key) |
| D-26 | Filter by Name (/ key) and Grep (* key) | Partly superseded | [decisions.md](decisions.md#filter-by-name-key-and-grep-key) |
| D-27 | cmdheight Lowering Before Splits (E36 Guard) | Partly superseded | [decisions.md](decisions.md#cmdheight-lowering-before-splits-e36-guard) |
| D-28 | OpenInRightPanel: Centralized Right-Panel Window Management | Superseded | [decisions.md](decisions.md#openinrightpanel-centralized-right-panel-window-management) |
| D-29 | Two-Panel Layout: Pane Stays Open After Opening Files | Partly superseded | [decisions.md](decisions.md#two-panel-layout-pane-stays-open-after-opening-files) |
| D-30 | Defensive Dict Access: get() Over Dot Notation | Partly superseded | [decisions.md](decisions.md#defensive-dict-access-get-over-dot-notation) |
| D-31 | Git Stash Keys (z/Z) | Partly superseded | [decisions.md](decisions.md#git-stash-keys-zz) |
| D-32 | Git Blame Key (a) | Partly superseded | [decisions.md](decisions.md#git-blame-key-a) |
| D-33 | Tab/Shift-Tab: Temporary vs. Permanent Pane Mode | Current | [decisions.md](decisions.md#tabshift-tab-temporary-vs-permanent-pane-mode) |
| D-34 | Pane Events | Partly superseded | [decisions.md](decisions.md#pane-events) |
| D-35 | `<Cmd>` Override: When `:call` Is Required | Current | [decisions.md](decisions.md#cmd-override-when-call-is-required) |
| D-36 | `<Cmd>` and Insert Mode in Secondary Buffers | Superseded | [decisions.md](decisions.md#cmd-and-insert-mode-in-secondary-buffers) |
| D-37 | Edge Test: PaneGrow/PaneShrink in While Loops | Current | [decisions.md](decisions.md#edge-test-panegrowpaneshrink-in-while-loops) |
| D-38 | setwinvar for Window-Local Options | Current | [decisions.md](decisions.md#setwinvar-for-window-local-options) |

### AI add-on decisions (this page)

| # | Decision | Status | Record |
|---|----------|--------|--------|
| AI-01 | Context-Aware by Default | Partly superseded | [below](#context-aware-by-default) |
| AI-02 | Response Style Picked by the System | Partly superseded | [below](#response-style-picked-by-the-system) |
| AI-03 | Two Activation Contexts | Partly superseded | [below](#two-activation-contexts) |
| AI-04 | Provider-Agnostic API Layer | Current | [below](#provider-agnostic-api-layer) |
| AI-05 | No External Dependencies (Maintained) | Current | [below](#no-external-dependencies-maintained) |
| AI-06 | Streaming: Removed, Then Re-Introduced (2026-06-20) | Current | [below](#streaming-removed-then-re-introduced-2026-06-20) |
| AI-07 | Insert Mode Bug: `<Cmd>` in nnoremap (2026-06-19) | Superseded | [below](#insert-mode-bug-cmd-in-nnoremap-2026-06-19) |
| AI-08 | Side-Car Response Buffer (not implemented) | Superseded | [below](#side-car-response-buffer-not-implemented) |
| AI-09 | Mode-Aware Context Extraction (not implemented) | Partly superseded | [below](#mode-aware-context-extraction-not-implemented) |
| AI-10 | No New Source Files (Maintained) | Current | [below](#no-new-source-files-maintained) |
| AI-11 | Input() in Mapping Context — Critical Pitfall (2026-06-22) | Partly superseded | [below](#input-in-mapping-context-critical-pitfall-2026-06-22) |

---

Rationale for key design choices and documented divergences from the original
concept.

## AI Integration (`vproj#ai#` add-on)

### Context-Aware by Default

The AI prompt automatically includes relevant context: current file path,
cursor position, visual selection if any, project structure, current mode.
The user does not manually provide context. **Current:** context is the file in the window the pane came from (+/-100 lines around the cursor), the cwd and the pane mode; project structure and visual selection are not sent.

**Rationale:** Manual context-gathering is friction. Most questions are about
"this" — this file, this function, this selection. Providing context
automatically makes the common case zero-effort. The user can always ask about
something else explicitly.

### Response Style Picked by the System

The plugin routes the AI response to the appropriate Vim surface based on
content type, not user choice:

| Response type | Surface | Example |
|--------------|---------|---------|
| Short text (1-2 lines) | cmdline (`echo`) | "This function validates session tokens" |
| Code change | diff split | Refactored function shown as unified diff |
| Long explanation | preview split | Architecture explanation, code walkthrough |
| List of locations | quickfix list | "All callers of parseArgs()" |

**Current:** the router is simpler. Code mode inserts the first fenced code
block of the response into the file below the cursor, only after a confirm
prompt; question mode (and a response with no fenced block) shows a popup. The
cmdline, diff-split, preview-split and quickfix surfaces above are not
implemented. The chat itself runs in a terminal split.

**Rationale:** The user should not think about *where* the answer goes. They
ask a question; the system puts the answer in the right place. This reuses
vproj's existing display surfaces (diff split via `d` key pattern, preview
split via `p` key pattern, quickfix list via qfix mode) rather than inventing
new ones.

### Two Activation Contexts

`A` works in two places with different default context:

- **In the vproj pane:** context is the file open in the edit window the pane was opened from
- **In an editing buffer:** `:VprojAiPrompt` (bind `<Plug>VprojAiPrompt` yourself; there is no default key)

**Current:** only `A` inside the pane is mapped by default. Context is the file in the origin window (path, filetype, cursor, +/-100 lines), plus the current pane mode and cwd. Selected-item and visual-selection context are not implemented.

**Rationale:** The pane is for project-level thinking ("what calls this
function?"). The editing buffer is for code-level thinking ("refactor this
loop"). Same key, different context. The user doesn't switch modes — context
follows where they press `A`.

### Provider-Agnostic API Layer

The AI backend is an OpenAI-compatible HTTP API. Provider is configured via
`g:vproj_ai_api_url` and `g:vproj_ai_api_key`. DeepSeek today, any
OpenAI-compatible provider tomorrow.

**Rationale:** Hardcoding a provider creates vendor lock-in on a feature that
should outlast any single AI service. OpenAI-compatible is the de facto
standard. The plugin cares about the interface, not the implementation.

### No External Dependencies (Maintained)

AI integration uses `system()` with `curl` for synchronous calls, with a
`job_start` + `mode: 'raw'` for async streaming (`AiCallStream`). The `A` key itself opens a terminal running `bin/vproj-ai-chat`, which needs `bash` and `curl`.
No Python, Node, or plugin dependencies.

**Rationale:** The original vproj constraint holds: a project manager must load
instantly. AI features add latency from network calls but must not add startup
cost. If `curl` is not available, the feature degrades gracefully with a clear
error message.

### Streaming: Removed, Then Re-Introduced (2026-06-20)

> **Status (2026-11-10): Current.** Streaming is `AiCallStream()` (`job_start`, `mode: 'raw'`).

**First attempt (Tasks #95-99):** A streaming implementation was built using
`job_start` but failed — callbacks didn't fire, or buffers weren't updated.
The root cause was three-fold:

1. **`function('Callback')` in Vim9 `def` context:** `job_start` callbacks
   passed as string references couldn't resolve `def` functions from the
   autoload namespace. Vim9 `def` functions aren't placed in the legacy
   global function dictionary.
2. **`mode: 'nl'` or `mode: 'json'`:** If either mode was used, newline
   characters inside JSON payloads split frames mid-object, causing
   `json_decode()` to throw silently and terminate the callback.
3. **Missing `redraw`:** Without explicit `redraw` in the append cycle, Vim
   batched all screen updates until job completion — tokens accumulated
   invisibly and appeared all at once, same user experience as blocking.

The streaming code was removed (Task #100) and replaced with a simplification
that used only `system()` (Task #108).

**Second attempt (2026-06-20):** A minimal working example proved the pattern
works with three fixes: lambda wrapper `(chan, msg) => ProcessChunk(...)`
for callback binding, `mode: 'raw'` exclusively, and `redraw` after every
`setbufline`/`appendbufline`. MWE at `tests/stream_mwe.vim` passes with
token-by-token rendering verified. Design spec at
`doc/phase-2/specs/2026-06-20-streaming-integration-design.md`.

**Additional finding:** `getbufline` after `setbufline` returns stale data in
headless Vim. The MWE works around this by tracking line state in script-local
variables (`stream_cur_line`, `stream_cur_text`) instead of reading back from
the buffer.

### Insert Mode Bug: `<Cmd>` in nnoremap (2026-06-19)

> **Status (2026-11-10): Superseded.** The `vproj_ai` mappings, `RenderConversation`, `HandleConvBufWipeout` and the conversation buffer are gone; `A` is mapped by the core and opens a terminal chat (`vproj#ai#AiTerminalChat()`) — see `src/autoload/vproj/ai.vim`.

The vproj pane was ending up in insert mode after the AI conversation flow
completed. Root cause: `<Cmd>` in nnoremap skips the command-line mode
transition where Vim saves and restores buffer mode. When `botright new`
creates a window inside a `<Cmd>` mapping, Vim loses track of what mode the
originating buffer should be in.

**Fix:** All 6 nnoremap mappings changed from `<Cmd>call ...<CR>` to
`:call ...<CR>`. Defensive `stopinsert` calls added in `RenderConversation`
and the `AiPrompt` exit path. The `HandleConvBufWipeout` signature changed
to accept `wiped_bufnr: number` via `str2nr(expand('<abuf>'))`.

### Side-Car Response Buffer (not implemented)

> **Status (2026-11-10): Superseded.** Never built; the chat runs in a terminal split and short answers use a popup — see `src/autoload/vproj/ai.vim`.

The current response buffer is a full-width horizontal split (`botright new`).
The streaming redesign uses a 50-column `botright vsplit` side buffer
(`__AI_Response__`) so the user's code remains visible and the response streams
in a narrow right panel. Focus bounces back to the pane immediately after
buffer creation — the user never leaves their working window.

### Mode-Aware Context Extraction (not implemented)

`GatherContext` currently reads the alternate buffer's file regardless of pane
mode. The redesign checks `vproj#GetCurrentMode()` and captures mode-specific
context (entry text in Qfix mode, target buffer content in Buf mode). Log mode
no longer exists. **Current:** the mode name is sent; the context is always
the origin window's file.

### No New Source Files (Maintained)

**Current:** vproj is two source files (`plugin/vproj.vim`,
`autoload/vproj.vim`) plus two approved add-ons, each loaded on demand:
`autoload/vproj/ai.vim` (`vproj#ai#`, AI provider API) and
`autoload/vproj/agent.vim` (`vproj#agent#`, external agent CLI in a terminal
split). Any further file needs approval.

**Rationale:** Same as vproj. Two files is the minimal split. AI features add
functions, not architectural complexity.

### Input() in Mapping Context — Critical Pitfall (2026-06-22)

> **Status (2026-11-10): Partly superseded.** The pitfall is real and `:VprojAiPrompt <prompt>` still takes the prompt as `<q-args>`, but `A` now opens a terminal chat and `SendFollowup()` / `AiApplyCode()` no longer exist (code is applied by `ApplyCode()` after `confirm()`) — see `src/autoload/vproj/ai.vim`.

`input()` called inside a `:call` mapping RHS consumes phantom typeahead
(per `:help input()`). The interaction of `input()` + `botright new`
window split during mapping execution destabilizes Vim's mode state,
landing in insert mode despite no `startinsert` anywhere in the code.

**Fix:** The initial prompt path uses Vim's native command-line
(`:VprojAiPrompt<Space>`). The user types on the command line; the prompt
arrives as `<q-args>` to `AiPrompt(prompt_from_cmdline)`. No `input()` in
the mapping path. `input()` remains only in `SendFollowup()` and
`AiApplyCode()` where it's called from within the conversation buffer,
not from a mapping RHS.

## Base vproj Decisions (inherited from fork)

## Vim9Script Over Legacy Vimscript

Vim9Script provides type checking, `def` functions with strict semantics, and
better performance. The trade-off: `def` functions have stricter rules (lambda
vars must start with capital, `readdir()` requires explicit filter arguments).

## Explicit Render Over Event Bus

CONCEPT.MD specifies event-driven display: commands emit events, display
rebuilds in response. The current implementation uses direct `Render()` calls
after every state change.

**Rationale:** With a single-threaded Vim runtime and a single consumer
(the pane buffer), an event bus adds indirection without benefit. The
"explicit imperative flow" pattern — where every command ends with a Render
call — is simpler to trace, debug, and test. Events will be introduced when
multiple consumers exist (e.g., source control integration, history log).

## Script-Local State Over Object Model

CONCEPT.MD specifies a Workspace Domain Model. The current implementation
uses flat script-local variables.

**Rationale:** Vim9Script has no class construct. A flat list of script-local
variables with clear naming conventions achieves the same goal (single source
of truth, no divergent copies) without building an object system in a language
that doesn't support one. The variables are listed at the top of the file,
serving as a visible schema.

## Two Source Files

`plugin/vproj.vim` and `autoload/vproj.vim`, plus the two add-ons
`autoload/vproj/ai.vim` and `autoload/vproj/agent.vim`. No other files.

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

> **Status (2026-11-10): Partly superseded.** The rule now covers all text vproj
> prints, not only separators -- see constraints.md "ASCII-Only Output".

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
visible items in the current page, starting from `nav_offset`. The nav characters are lowercase `a-z` (26 per block).

**Rationale:** Fixed assignments would require permanent tracking of which
letter maps to which file across directory changes. Dynamic assignment is
simpler: label what's visible, shift with `>` / `<` (Tab now toggles the pane). The user learns the position,
not the letter.

## Paging vs. Tab Relabeling

Paging (Ctrl-N/Ctrl-P) changes which items are visible. Relabeling (`>` / `<`)
changes which visible items get nav indicators. They are independent features
solving different problems: paging handles too many items to display;
relabeling handles too many items to label with the 26 available indicators.

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

**Current:** Modes are selected with `Shift-F` (file), `Shift-B` (buf) and
`Shift-C` (code); `Q` switches to qfix in a temporary pane and closes a
permanent pane. Enter on the mode menu line cycles through the four modes.
(The original design used lowercase `f`/`b`/`g`/`q`; those were given up so
that all of lowercase `a-z` can be nav characters.)

**Rationale:** Every lowercase letter is a nav character, so actions and mode
switches live on Shift, Ctrl and `\` keys.

## Qfix Mode

A fourth mode displays the Vim quickfix list. `getqflist()` provides entries;
Enter jumps to file:line (and closes a temporary pane).

**Rationale:** The quickfix list is Vim's standard mechanism for iterating
through search results, compile errors, or any filterable content. By reading
it rather than writing it, qfix mode composes with `:make`, `:grep`,
`:vimgrep`, and AI-driven `setqflist()` calls without any vproj-specific API.
Standard Vim tooling populates the list; vproj displays it.

## constraints.md Over requirements.md

Hard constraints (cross-platform, no dependencies, two source files,
ASCII-only) live in a separate `constraints.md` file. Features live in
CONCEPT.MD.

**Rationale:** Constraints are walls you can't move; features are things you
might add. Keeping them separate prevents desirable features from being
confused with non-negotiable boundaries. When a new feature is proposed, you
check it against constraints.md, not a merged wishlist.

## DirChanged Autocommand for `:cd` Tracking

Vim's `DirChanged` event triggers an automatic refresh of the file pane when
the user changes directories with `:cd`, `:lcd`, or `:tcd`. The `global`, `tabpage` and
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
`VprojModeFile`, `VprojModeBuf`, `VprojModeCode`, `VprojModeQfix`. **Current:**
they are linked to the Title, Directory, Special and Question groups, so they
follow the colorscheme.

The active mode's group is selected dynamically in `ApplyStaticHighlights()`
based on `toupper(current_mode[0]) .. current_mode[1 : ]`.

Color coding provides at-a-glance mode identification without reading the
label text. The user learns the color mapping quickly and can confirm mode
with peripheral vision. Four distinct colors are used rather than reusing a
single color to avoid ambiguity.

## `<nowait>` on Pane Keys

**Current:** Nav characters (`a-z`), `.`, `A`, `T`, `+`, `-`, `>`, `<`, `?`,
`/` and `*` use `<nowait>` in their buffer-local mappings so Vim does not
wait `timeoutlen` for a longer key sequence (for example the `\` git
prefix or Vim's own `g`/`f`/`q` commands). (The original design applied
`<nowait>` to the lowercase mode keys `f`, `g` and `q`, which no longer
exist.)

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
with `Q` or `Esc`.

## Global F1/Help Mapping (HandleF1)

F1 and Help are Vim built-in keys that cannot be overridden by buffer-local
mappings. A global `:call vproj#HandleF1()<CR>` mapping (`<Plug>VprojF1`, mapped to `<F1>` and `<Help>` unless you map it yourself) checks the context:
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

## Log Mode (removed)

A fifth pane mode once displayed `git log --oneline`. **Current:** it no longer
exists; there are four modes (File, Buf, Code, Qfix). An old session file that
names `log` loads as file mode.

## Git Actions in Pane (`\` prefix)

**Current:** git operations are `\s \d \D \c \p \u \b \z \Z \a` (stage, diff,
discard, commit, push, pull, branch switch, stash, stash pop, blame) plus
`Ctrl-G` for the git filter. The original single-key design (`s d D C P U B`)
was dropped so lowercase letters could be nav characters. Operations work in
file and code modes. No need to drop to a terminal or use Vim's
`:!git` commands.

**Rationale:** Project management includes version control. The most common git
operations should be single keystrokes. These keys are only mapped in the pane
buffer and do not affect other Vim buffers. Operations that modify the working
tree (discard, commit, push) use confirmation prompts or `input()`.

## Tree View Toggle (Shift-T)

Flat file listing can be toggled to an indented directory tree with T.
Individual directories can be expanded/collapsed. Tree state is preserved
within file mode across mode switches.

**Rationale:** A flat listing is fast to scan; a tree view reveals project
structure. The user toggles between them depending on the task. `T` is Shift-T so
lowercase `t` stays a nav character.

## File Preview (Shift-P)

Pressing `P` opens a split showing the contents of the file under cursor.
The preview updates on cursor movement. Pressing `P` again closes it.

**Rationale:** Quick file preview without opening. Particularly useful when
scanning a directory — you can see file contents without committing to opening
the file. `botright vnew` creates the preview window below and to the right
of the pane.

## Filter by Name (/ key) and Grep (* key)

`/` prompts for a name filter and reduces the listing to matching items.
Clearing the filter restores the full listing. `*` prompts for a grep pattern,
runs `git grep` (case-insensitive) in the repository, or in the pane's directory outside a repository, and populates the quickfix list.

**Rationale:** Standard Vim users reach for `/` to search and `*` to find
occurrences. These mappings in the pane buffer adapt both keys to project-level
operations. `/` filters the current listing; `*` populates quickfix for qfix
mode navigation.

## cmdheight Lowering Before Splits (E36 Guard)

Before any `:split`, `:vnew`, or `:vsplit` operation, the code temporarily
lowers `cmdheight` to 1 (if above 2) and `winminwidth`/`winminheight` to 1,
then restores the original values. This is done in OpenFile, OpenPreview,
OpenDiffPreview, OpenBuffer, OpenQfixEntry and the other split-creating
functions.

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

## Opening Files: EditTargetWindow and Pane Stay/Close

**Current:** A file, buffer or quickfix entry opens in the window the user
came from if it is still an edit window, else the first edit window in the
tab, else a new `botright vnew` split to the right of the pane
(`EditTargetWindow()`). Enter on a file then **closes a temporary pane** (Tab)
and **keeps a permanent pane** (Shift-Tab) open with focus on the pane. The
right-side window is reused rather than stacking more splits.

**Rationale:** Temporary mode is for quick access (no extra key to dismiss);
permanent mode treats the pane as a persistent sidebar, like an IDE file
tree. (Earlier text here described a single `OpenInRightPanel()` helper that
no longer exists, and an always-stay-open layout.)

## Defensive Dict Access: get() Over Dot Notation

All dict key access on items from external sources (user input, filesystem
listings, git output, quickfix entries) uses `get(dict, 'key', default)`
rather than `dict.key` dot notation. Dot notation throws E716 "Key not
present in Dictionary" when the key is missing, even when the code has an
empty-dict sentinel check.

**Rationale:** Items flow through multiple transformations (listing, filtering,
paging) before reaching display or action functions. An item from ReadDir has
different keys than one from QfixItems. Even within a single code
path, a `GetSelectedItem()` caller may receive an empty `{}` or a partial
dict on edge cases. `get()` with a sensible default returns safely; dot
notation crashes. The extra typing is negligible compared to the debugging
cost of an E716 that only triggers when the user has an empty quickfix list
or browses a directory with unusual entries.

A comprehensive audit (2026-06-18) replaced all unguarded dot accesses across
the entire 3286-line codebase: `item.name`, `item.path`, `item.is_dir`,
`item.size`, `project.root`, `project.name`, `item.col`, `item.lnum`,
`item.filename`.

## Git Stash Keys (`\z` / `\Z`)

`\z` pushes a stash with an optional message via `git stash push`. `\Z` pops a
stash after listing all stashes and prompting for which to pop (default: top).

**Rationale:** The `\z`/`\Z` pair follows the lowercase/uppercase convention
established by `\d`/`\D` (diff/discard).
Showing the stash list before popping prevents accidental pop of the wrong
stash — the user sees what's there before choosing. The alternative of a
single toggle key was rejected because push and pop are distinct operations
with different confirmation requirements.

## Git Blame Key (`\a`)

`\a` opens a split showing `git annotate` output for the file under cursor.
In file and code modes, only for regular tracked files.

**Rationale:** `annotate` is the canonical alias for `git annotate` (git's cleaner
interface to blame). Using `git annotate` rather than `git blame` gives the
same output with a cleaner interface name. The blame window is a scratch
buffer (buftype=nofile, readonly, nomodifiable) following the same pattern
as diff preview — `q` closes it. E36 guards follow the established pattern
for all split operations. Untracked files are rejected because `git annotate`
fails on them — the `git ls-files` guard prevents a confusing error.

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

## Documents

<!-- DOCS:START -->
| Document | Path |
|----------|------|
| [Architecture](architecture.md) | `architecture.md` |
| [Concept](concept.md) | `concept.md` |
| [Constraints](constraints.md) | `constraints.md` |
| [Design Decisions](decisions.md) | `decisions.md` |
| [Design](design.md) | `design.md` |
| [Implementation Plan](implementation-plan.md) | `implementation-plan.md` |
| [Implementation Plan](implementation.md) | `implementation.md` |
| [Manual](manual.md) | `manual.md` |
| [vproj_ai Streaming Integration — Design Spec](phase-2/specs/2026-06-20-streaming-integration-design.md) | `phase-2/specs/2026-06-20-streaming-integration-design.md` |
| [Test Cases](test-cases.md) | `test-cases.md` |
| [Test Plan](test-plan.md) | `test-plan.md` |
<!-- DOCS:END -->

## How This Site Updates

When you push to the git repository, the site rebuilds automatically:

1. A post-receive hook extracts `doc/` from the repo
2. Changed `.md` files sync into this site's `docs/` folder
3. The document index above is regenerated from all `.md` files found
4. `mkdocs build --strict` rebuilds the static site

**Do not edit the document table above by hand.** Add, remove, or rename
`.md` files in the repo's `doc/` directory and push — the table regenerates
on the next build.
