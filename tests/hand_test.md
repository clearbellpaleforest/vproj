# Hand Test — Manual Verification Checklist

Launch from vproj project root:

```
vim -N -u NONE --cmd 'set rtp+=src' --cmd 'runtime! plugin/vproj.vim'
```

Press `Tab` to open the pane, then work through each section.

## 1. Pane Open/Close

- [ ] `Tab` — opens pane (temporary mode)
- [ ] Inside pane, press `Tab` — closes pane (temporary mode)
- [ ] Outside pane, `Tab` — re-opens pane
- [ ] `Shift-Tab` — opens pane (permanent mode, Esc won't close it)
- [ ] `Esc` in pane — closes only in temporary mode; no-op in permanent
- [ ] `Q` in pane — always closes pane
- [ ] `:call vproj#PaneClose()` — close via function

## 2. Navigation

- [ ] `j` / `k` — move cursor down / up
- [ ] `<Down>` / `<Up>` — same as j / k
- [ ] `h` — go to parent directory
- [ ] `l` — enter directory or open file
- [ ] `.` — same as h (parent directory)
- [ ] `<CR>` (Enter) on a file — open file in right split
- [ ] `<CR>` on a directory — navigate into it
- [ ] `<CR>` on the mode menu line (line 1) — cycles to next mode
- [ ] `<C-T>` — jump to first item
- [ ] `<C-B>` — jump to last item
- [ ] `<C-K>` — go to parent directory (same as h)
- [ ] `<C-J>` — enter first subdirectory

## 3. Mode Switching (Shift keys)

Pressing these while pane is focused:

- [ ] `<S-F>` (Shift-F) — File mode (browse filesystem)
- [ ] `<S-B>` (Shift-B) — Buf mode (open buffers)
- [ ] `<S-C>` (Shift-C) — Code mode (project tree from .vproj)
- [ ] `<S-L>` (Shift-L) — Log mode (git commit history)

Verify each mode label appears on line 1 with colored background.
Mode menu: `[F]ile  [B]uf  [C]ode  [Q]fix  [L]og`

## 4. Width

- [ ] `<Right>` — grow pane by 1 column (max 80)
- [ ] `<Left>` — shrink pane by 1 column (min 20)
- [ ] `:call vproj#SetPaneWidth(50)` — set exact width (20-80)

## 5. Actions

- [ ] `r` — refresh pane contents (preserves mode)
- [ ] `x` — close selected buffer (buf mode only; shows message in other modes)
- [ ] `+` / `-` — include / exclude item (code mode only, on project items)
- [ ] `<F1>` — toggle info column (file sizes / line counts)
- [ ] `T` — toggle tree view (file mode only, indented with expand/collapse)
- [ ] `p` — toggle file preview split (updates on cursor move; file mode)
- [ ] `/` — filter files by name pattern (prompt appears)
- [ ] `*` — grep project, populate quickfix list

## 6. Paging

Navigate to a directory with many items:

- [ ] `<C-N>` — next page
- [ ] `<C-P>` — previous page

## 7. Quick Nav (nav indicators)

Nav chars are the single chars at start of each line.

- [ ] `>` — shift nav indicators forward (next batch)
- [ ] `<` — shift nav indicators backward (previous batch)

Jump to item by pressing the nav char directly. Try several uppercase, lowercase, and digit chars from the current page. If a char is not on the current page, nothing happens (no crash).

Chars NOT available for nav (already mapped): h, j, k, l, ., r, x, +, -, T, p

## 8. Git Actions

Navigate to a git-tracked file (file or code mode):

- [ ] `s` — stage/unstage file under cursor (`git add` / `git reset HEAD`)
- [ ] `d` — open diff preview in vertical split (`q` to close)
- [ ] `D` — discard file changes (confirmation prompt)
- [ ] `C` — commit with message prompt
- [ ] `P` — push to remote
- [ ] `U` — pull --ff-only from remote
- [ ] `B` — switch branch (prompt for branch name)
- [ ] `z` — stash changes (optional message prompt)
- [ ] `Z` — pop a stash (shows list, select by index)
- [ ] `a` — blame file under cursor (split with `git annotate`, `q` to close)
- [ ] `<C-G>` — toggle showing only git-changed files

Git actions should show error messages when no repo is present (not crash).

## 9. Log Mode

From a git repo directory:

- [ ] `<S-L>` — switch to log mode
- [ ] `j` / `k` — navigate commits
- [ ] `<CR>` on a commit — open commit detail in split
- [ ] `q` in commit detail — close split
- [ ] The commit hash is shown in the status bar after opening

## 10. Qfix Mode

- [ ] Run `:vimgrep /TODO/j **/*.vim` to populate quickfix
- [ ] `<S-C>` then `<S-F>` to enter qfix mode (or press Enter on [Q]fix in menu)
- [ ] `j` / `k` — navigate entries
- [ ] `<CR>` on entry — open file at line/column
- [ ] Empty qfix list shows "(no quickfix items)"

## 11. Buf Mode

- [ ] `<S-B>` — switch to buf mode
- [ ] Open buffers listed with `%` (current) and `+` (modified) markers
- [ ] `j` / `k` — navigate buffers
- [ ] `<CR>` — switch to selected buffer
- [ ] `x` on a buffer — close it (modified buffers prompt to save)
- [ ] Navigation wraps: `k` at top goes to bottom, `j` at bottom goes to top

## 12. Code Mode (.vproj project)

- [ ] `<S-C>` — switch to code mode
- [ ] Status line shows project name, root directory, git branch
- [ ] `<CR>` on status line — prompts to create or rename project
- [ ] Included items listed normally; excluded items in parentheses
- [ ] `+` on excluded item — include it
- [ ] `-` on included item — exclude it
- [ ] Changes are saved to .vproj file immediately

## 13. Tree View (file mode)

- [ ] `T` in file mode — toggles tree view
- [ ] Indented directories with `▶` / `▼` expand/collapse indicators
- [ ] `<CR>` on collapsed dir — expands
- [ ] `<CR>` on expanded dir — collapses
- [ ] `T` again — returns to flat view

## 14. File Preview

- [ ] `p` in file mode — opens preview split
- [ ] Moving cursor updates preview content
- [ ] `p` again — closes preview
- [ ] Preview shows file contents in a split to the right

## 15. Session Persistence

- [ ] Open pane, set width to 55, switch to buf mode
- [ ] Close vim and reopen with same command
- [ ] Press `Tab` — pane opens at width 55 in buf mode

## 16. Passthrough — Standard Vim Keys

These Vim keys should NOT be remapped and should work as usual:

- [ ] `t<char>` — find until character
- [ ] `w` — word forward
- [ ] `e` — end of word
- [ ] `0` / `$` — line start / line end
- [ ] `G` — go to buffer bottom
- [ ] `H` / `M` / `L` — screen top / middle / bottom
- [ ] `%` — jump to matching `( ) { } [ ]`
- [ ] `{` / `}` — paragraph back / forward
- [ ] `y` — yank (copies text from pane buffer)
- [ ] `<C-F>` / `<C-B>` — page down / up
- [ ] `<C-D>` / `<C-U>` — half-page down / up
- [ ] `<C-W>` keys — window management
- [ ] `zz` / `zt` / `zb` — scroll cursor to center / top / bottom

## 17. Error Handling

- [ ] Press `x` in file mode — shows "x closes buffers in buf mode only"
- [ ] Press `+`/`-` in file mode — shows "No project -- Enter on status line to create one"
- [ ] Press `d`/`D`/`s` outside a git repo — shows message, does not crash
- [ ] Press `<CR>` on a directory — navigates in, does not crash
- [ ] `h` at filesystem root — stays at root, does not crash
