VPROJ USER MANUAL
=================

vproj is a project manager sidebar for Vim. Browse files, switch buffers,
manage git, and navigate project structure — all from a narrow vertical
pane.  No mouse. No file-explorer popups.  Keyboard from end to end.

This manual covers vproj 1.x.  For the latest version, see the repository
at https://github.com/clearbellpaleforest/vproj.


TABLE OF CONTENTS
-----------------

<ol>
  <li><a href="#1-installation">Installation</a></li>
  <li><a href="#2-quick-start">Quick Start</a></li>
  <li><a href="#3-the-pane">The Pane</a></li>
  <li><a href="#4-modes">Modes</a>
    <ul>
      <li><a href="#41-file-mode-press-shift-f">4.1 File Mode</a></li>
      <li><a href="#42-buffer-mode-press-shift-b">4.2 Buffer Mode</a></li>
      <li><a href="#43-code-mode-press-shift-c">4.3 Code Mode</a></li>
      <li><a href="#44-quickfix-mode-cycle-to-it-via-enter-on-menu-line">4.4 Quickfix Mode</a></li>
      <li><a href="#45-log-mode-press-shift-l">4.5 Log Mode</a></li>
    </ul>
  </li>
  <li><a href="#5-key-reference">Key Reference</a>
    <ul>
      <li><a href="#51-navigation">5.1 Navigation</a></li>
      <li><a href="#52-mode-switching">5.2 Mode Switching</a></li>
      <li><a href="#53-git-actions-file-and-code-mode">5.3 Git Actions</a></li>
      <li><a href="#54-pane-controls">5.4 Pane Controls</a></li>
      <li><a href="#55-paging">5.5 Paging</a></li>
      <li><a href="#56-quick-nav-nav-indicators">5.6 Quick Nav</a></li>
    </ul>
  </li>
  <li><a href="#6-configuration">Configuration</a></li>
  <li><a href="#7-the-vproj-file">The .vproj File</a></li>
  <li><a href="#8-git-integration">Git Integration</a></li>
  <li><a href="#9-troubleshooting">Troubleshooting</a></li>
  <li><a href="#10-quick-reference-card">Quick Reference Card</a></li>
</ol>


1. INSTALLATION
===============

Clone the repository and run the install script:

    git clone https://github.com/clearbellpaleforest/vproj.git
    cd vproj
    sh install.sh

Or install manually by creating symlinks to ~/.vim/pack/bundle/start/vproj/:

    mkdir -p ~/.vim/pack/bundle/start/vproj/{plugin,autoload,doc}
    ln -s $PWD/src/plugin/vproj.vim ~/.vim/pack/bundle/start/vproj/plugin/
    ln -s $PWD/src/autoload/vproj.vim ~/.vim/pack/bundle/start/vproj/autoload/

Then generate the help tags from within Vim:

    :helptags ~/.vim/pack/bundle/start/vproj/doc/

Restart Vim.  The plugin loads automatically.  No configuration required.


2. QUICK START
==============

Press Tab to open the project pane.  You will see a file listing for the
current directory.  Use j/k to move up and down.  Press Enter on a file
to open it.  Press Enter on a directory to navigate into it.

Press Tab to toggle the pane open and closed. For extended sessions,
press Shift-Tab for permanent mode where the pane stays open until you
explicitly close it.

    Tab        — Toggle pane open/closed
    Shift-Tab  — Open pane (permanent mode; stays open until you close it)

    Inside the pane:
    j / Down   — Move selection down
    k / Up     — Move selection up
    Enter      — Open selected file or enter selected directory
    h          — Go to parent directory
    Q          — Close pane
    Shift-F    — File mode (browse filesystem)
    Shift-B    — Buffer mode (switch between open buffers)
    Shift-C    — Code mode (manage project structure and source control)


3. THE PANE
===========

The pane is a vertical split on the left side of your Vim window.  It is
40 columns wide by default (adjustable from 20 to 80 columns with the
Left/Right arrow keys while the pane is focused).

The top line shows the current mode and path.  The bottom line shows
paging information when there are more items than fit in one screen.

The pane has two toggle behaviors:

    TEMPORARY MODE (Tab)
    --------------------
    The pane can be toggled open and closed with Tab. Press Esc while
    the pane has focus to close it, or press Tab again.

    This is for quick file/buffer access — no extra keystroke to dismiss.

    PERMANENT MODE (Shift-Tab)
    --------------------------
    The pane stays open until you:
      - Press Shift-Tab again
      - Press Q (while the pane has focus)
      - Close the pane buffer via :bdelete

    This is for extended project management sessions.

Pressing the alternate toggle key while the pane is open transitions
between modes without closing the pane.  For example, if the pane is
open in temporary mode and you press Shift-Tab, it switches to permanent
mode and stays open.


4. MODES
========

vproj has five modes.  Press the mode key (Shift-F, Shift-B, Shift-C, q, or Shift-L) to switch,
or press Enter on the mode menu line at the top of the pane to cycle
through modes in order.  Note: in permanent mode, `q` closes the pane
instead of switching to Qfix mode — use Enter on the menu line to cycle
to Qfix in permanent mode.

Each mode has a distinct color on the menu line:
    File  — Yellow
    Buf   — Green
    Code  — Blue
    Qfix  — Blue
    Log   — Cyan


4.1 FILE MODE  (press Shift-F)
------------------------

File mode browses the filesystem.  Directories are listed first, then
files.  File sizes (to the nearest K or M) are shown in an info column
on the right.

    Enter      — Open file or enter directory
    h / .      — Go to parent directory
    Ctrl-K     — Go to parent directory
    Ctrl-J     — Enter first subdirectory (if any)
    T          — Toggle tree view (indented directory tree)
    p          — Toggle file preview split (updates as cursor moves; also works in buf mode)
    /          — Filter by name pattern
    *          — Grep the project (git grep -i) and auto-switch to quickfix list
    Ctrl-G     — Toggle showing only git-changed files

Tree view shows directories as an indented tree with expand/collapse.
Press Enter on a collapsed directory to expand it; Enter on an expanded
directory to collapse it.

File preview opens a split showing the file contents.  As you move the
cursor in the pane, the preview updates.  Press p again to close it.

Filter (/) prompts for a pattern and narrows the listing to matching
names.  Press Enter on a blank filter to clear it and show all items.

Grep (*) runs `git grep -n -i` from the git root and populates the
quickfix list, then auto-switches to Qfix mode to browse results.


4.2 BUFFER MODE  (press Shift-B)
----------------------------

Buffer mode shows all open Vim buffers.  Modified buffers are marked
with +, the current buffer with %.  Line counts are shown in the info
column.

    Enter  — Switch to selected buffer
    x      — Close selected buffer
    r      — Refresh buffer list

This is faster than `:ls` and `:b` for switching between many buffers.


4.3 CODE MODE  (press Shift-C)
-------------------------

Code mode shows a project-aware file tree based on a .vproj file.
Included items are shown normally; excluded items appear in parentheses.

If no .vproj file is found, all items are shown in parentheses and the
status line shows "* (no project found)".  Press Enter on the status
line to create or rename a project.

    Enter on status line  — Rename or create project
    + / -                 — Include / exclude item from project
    Enter on file         — Open file
    Enter on directory    — Navigate into directory

And git actions (see Section 8):
    c — Commit             P — Push
    U — Pull --ff-only     b — Branch switch
                           z — Stash push
                           Z — Stash pop
    Ctrl-G                — Toggle git-changed-only filter


4.4 QUICKFIX MODE  (cycle to it via Enter on menu line)
------------------------------

Quickfix mode displays the Vim quickfix list — grep results, compiler
errors, or AI analysis output.  Each entry shows filename, line number,
and text.

    Enter  — Jump to selected entry (opens file at line)

Populate the quickfix list with `:grep`, `:make`, `:vimgrep`, or press
* (grep) from File mode.  The pane auto-switches to Qfix mode after grep
results are populated.  You can also cycle to Qfix mode by pressing Enter
on the mode menu line.


4.5 LOG MODE  (press Shift-L)
-------------------------

Log mode shows git commit history (`git log --oneline` output).  Nav
characters let you jump to any commit.

    Enter  — Open detailed diff for selected commit in a split

Use this to review recent changes and inspect individual commits while
staying in the editor.


5. KEY REFERENCE
================

All keys listed below are active when the vproj pane has focus.
They do not affect other Vim buffers.


5.1 NAVIGATION
--------------

    j / Down         Move selection down (wraps)
    k / Up           Move selection up (wraps)
    h / .            Go to parent directory
    Enter            Open file or enter directory
    Ctrl-T           Jump to first item
    Ctrl-B           Jump to last item
    Ctrl-K           Go to parent directory (same as h)
    Ctrl-J           Enter first subdirectory


5.2 MODE SWITCHING
------------------

    Shift-F          File mode
    Shift-B          Buffer mode
    Shift-C          Code mode
    q                Quickfix mode (temp mode only; closes pane in permanent mode)
    Shift-L          Log mode
    Enter on menu    Cycle to next mode


5.3 GIT ACTIONS  (file and code mode)
----------------------------

    s                Stage / unstage file under cursor
    d                Open diff preview in vertical split
    D                Discard file changes (with confirmation)
    c                Commit with message prompt
    P                Push to remote
    U                Pull --ff-only from remote
    b                Switch branch (prompts for branch name)
    z                Stash changes (optional message)
    Z                Pop a stash (shows list, prompts for index)
    a                Blame file under cursor (git annotate in split)
    Ctrl-G           Toggle showing only git-changed files (file and code mode)


5.4 PANE CONTROLS
-----------------

    r                Refresh listing
    x                Close selected buffer (buf mode only)
    + / -            Include / exclude item (code mode only)
    T                Toggle tree view (file mode only)
    p                Toggle file preview split
    /                Filter files by name pattern (file mode)
    *                Grep project and populate quickfix (file mode)
    Left / Right     Shrink / grow pane width by 1 column
    F1               Toggle info column (file sizes, line counts)
    Q / Tab          Close pane
    ESC              Close pane (temporary mode only)


5.5 PAGING
----------

When there are more items than fit in the pane, a paging row appears at
the bottom:

    Ctrl-N           Next page
    Ctrl-P           Previous page


5.6 QUICK NAV  (Nav Indicators)
--------------------------------

Each file, directory, or buffer gets a nav indicator — a single character
displayed in orange (#FFAF00) on the left side of the pane.  Press that
character to jump directly to the item.

Nav indicators use a curated set of characters to avoid conflicts with
mode-switching and action keys (37 slots).

    selected chars    Jump to item by nav character
    >                 Shift nav indicators forward (relabel next block)
    <                 Shift nav indicators backward (relabel previous block)
    .                 Parent directory (no nav indicator)

If there are more items than nav indicator slots, press > to shift the
indicators forward through the list.  Press < to shift backward.
The indicators wrap around at the ends.


6. CONFIGURATION
================

Set these variables in your .vimrc before the plugin loads, or reload
the plugin after setting them.

    g:vproj_show_dotfiles
        Set to 1 to show hidden files (dotfiles).  Default: 0 (hidden).

    g:vproj_pane_width_default
        Initial pane width in columns (20-80).  Default: 40.

    g:vproj_pane_width_file
        Pane width for File mode (20-80).  0 = use default.  Default: 0.

    g:vproj_pane_width_buf
        Pane width for Buf mode (20-80).   Default: 0.

    g:vproj_pane_width_code
        Pane width for Code mode (20-80).  Default: 0.

    g:vproj_pane_width_qfix
        Pane width for Qfix mode (20-80).  Default: 0.

    g:vproj_pane_width_log
        Pane width for Log mode (20-80).   Default: 0.

Example .vimrc:

    " Show hidden files
    let g:vproj_show_dotfiles = 1

    " Use F2 for temporary toggle instead of Tab
    nmap <F2> <Plug>VprojToggle
    nunmap <Tab>

    " Use F3 for permanent toggle instead of Shift-Tab
    nmap <F3> <Plug>VprojTogglePermanent
    nunmap <S-Tab>


7. THE .vproj FILE
==================

A .vproj file defines a project for Code Mode.  It lives at the project
root and specifies which files and directories belong to the project.

When you press Tab to open the pane, vproj searches for a .vproj file
starting in the current directory and walking upward.  If none is found,
you are prompted to create one.

Format:

    Project Name: my-project
    Project Root: /home/user/dev/my-project
    Included Directories:
    src
    tests
    Included Files:
    README.md
    CHANGELOG.md
    Excluded Directories:
    .git
    node_modules
    build
    Excluded Files:
    .env

Lines starting with # are comments.

You never need to edit the .vproj file by hand.  Use + / - in Code mode
to include or exclude items interactively.  The file is saved
automatically after each change.


8. GIT INTEGRATION
==================

vproj provides git actions accessible from File and Code mode.
No plugins required.  Operations use the git command-line tool.

### Stage / Unstage (`s`) — file and code mode

Toggles the staged state of the file under cursor.

    git add <file>
    git reset HEAD <file>

### Diff Preview (`d`) — file and code mode

Opens a vertical split with git diff for the file under cursor. Press `q` to close.

### Discard (`D`) — file and code mode

Prompts for confirmation, then discards changes. Handles four cases:

| Status | Action |
|--------|--------|
| Untracked (`?`) | Deletes the file |
| Added (`A`) | `git reset HEAD -- <file>` |
| Modified (`M`/`R`) | `git checkout -- <file>` |
| Deleted (`D`) | `git checkout HEAD -- <file>` |

### Commit (`c`)

Prompts for a commit message on the command line.

    git commit -m "<message>"

### Push (`P`)

Pushes to the configured remote.

    git push

### Pull (`U`)

Pulls with `--ff-only` to prevent merge commits.

    git pull --ff-only

### Branch Switch (`B`)

Prompts for a branch name. Switches with `git checkout`. Refreshes the pane after switching.

### Stash Push (`z`)

Stashes current changes. Prompts for an optional message.

    git stash push -m "<message>"

### Stash Pop (`Z`)

Shows a numbered list of all stashes. Prompts for which to pop. Defaults to `stash@{0}`.

    git stash pop stash@{<N>}

### Blame (`a`)

Opens a vertical split with `git annotate` for the file under cursor. File must be tracked by git. Press `q` to close. Available in File and Code mode.

### Git-Changed Filter (`Ctrl-G`)

Toggles a filter that shows only files with git changes (modified, added, or untracked). Press again to show all files.


9. TROUBLESHOOTING
==================

E36 "Not enough room" on split
------------------------------
If you see E36 when opening files, blame windows, or diffs from the
pane, your command-line height may be set too high:

    :set cmdheight?

If the value is above 2, lower it:

    :set cmdheight=1

Or set it permanently in your .vimrc:

    set cmdheight=1

vproj temporarily lowers cmdheight, winminwidth, and winminheight during
split operations, but persistent high values can still cause issues.

Run :VprojDiag to see current window dimensions and option values.

Pane doesn't open
-----------------
Check that the plugin loaded:
    :echo exists('g:loaded_vproj')

If it returns 0, check your runtimepath:
    :echo &rtp

Ensure ~/.vim/pack/bundle/start/vproj is in the runtime path and that
both plugin/vproj.vim and autoload/vproj.vim are present.

Tab key doesn't work
--------------------
Some terminal configurations swallow Tab.  Remap to a different key:

    nmap <F4> <Plug>VprojToggle

No .vproj found
---------------
If vproj cannot find a .vproj file in or above the current directory,
it will prompt you to create one.  Press y at the prompt, then enter a
project name (defaults to the current directory name).  The .vproj file
is created automatically and Code mode becomes active.


10. QUICK REFERENCE CARD
========================

    OPEN / CLOSE
    ------------
    Tab                 Open pane (temporary — auto-closes on file-open)
    Shift-Tab           Open pane (permanent — stays until you close it)
    Q / Tab             Close pane
    ESC                 Close pane (temporary mode only)

    MOVE
    ----
    j / Down            Next item
    k / Up              Previous item
    h / .               Parent directory
    Enter               Open file / enter directory
    Ctrl-T / Ctrl-B     Jump to top / bottom
    Ctrl-J              Enter first subdirectory

    MODE
    ----
    Shift-F             File mode (filesystem browser)
    Shift-B             Buffer mode (open buffers)
    Shift-C             Code mode (project tree + source control)
    q                   Quickfix mode (temp mode; closes pane in permanent)
    Shift-L             Log mode (git commit history)

    GIT
    ---
    s                   Stage / unstage file
    d                   Diff preview
    D                   Discard changes
    c                   Commit
    P                   Push
    U                   Pull --ff-only
    b                   Branch switch
    z                   Stash push
    Z                   Stash pop
    a                   Blame (annotate)
    Ctrl-G              Toggle git-changed-only filter

    OTHER
    -----
    r                   Refresh
    x                   Close buffer (buf mode)
    + / -               Include / exclude (code mode)
    T                   Tree view toggle (file mode)
    p                   File preview toggle
    /                   Filter by name
    *                   Grep project
    F1                  Toggle info column
    Left / Right        Shrink / grow pane width
    Ctrl-N / Ctrl-P     Next / previous page
    > / <               Shift nav indicators forward / back

    COMMANDS
    --------
    :VprojToggle        Toggle pane (temporary)
    :VprojOpen          Open pane
    :VprojClose         Close pane
    :VprojRefresh       Refresh pane contents
    :VprojDiag          Diagnostic info


---

vproj 1.x — Vim project manager
License: MIT
