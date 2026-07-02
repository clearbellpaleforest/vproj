# Hand Test — Manual Verification Checklist

Launch from vproj project root:

```
vim -N -u NONE --cmd 'set rtp+=src' --cmd 'runtime! plugin/vproj.vim'
```

Press `Tab` to open the pane, then work through each section.

## 1. Pane Open/Close

- [ ] `Tab` — opens pane (temporary mode, closes on file open)
- [ ] `Tab` again — closes pane
- [ ] `Shift-Tab` — opens pane (permanent mode, stays open)
- [ ] `Shift-Q` — closes pane in both temp and permanent mode
- [ ] `Esc` in pane — closes only in temporary mode; no-op in permanent
- [ ] `:call vproj#PaneClose()` — close via function

## 2. Navigation

- [ ] `<Down>` / `<Up>` — move cursor down / up
- [ ] `<C-T>` — jump to first item
- [ ] `<C-B>` — jump to last item
- [ ] `<C-K>` — go to parent directory
- [ ] `<C-J>` — enter first subdirectory

## 3. Parent Directory

- [ ] `.` — navigate to parent directory (the nav indicator dot)

## 4. Mode Switching (Shift keys)

- [ ] `B` (Shift-B) — Buf mode
- [ ] `C` (Shift-C) — Code mode
- [ ] `F` (Shift-F) — File mode
Mode menu shows: `[F]ile  [B]uf  [C]ode  [Q]fix`

## 5. Width

- [ ] `<Right>` — grow pane by 1 column (max 80)
- [ ] `<Left>` — shrink pane by 1 column (min 20)
- [ ] `:call vproj#SetPaneWidth(50)` — set exact width (20-80)

## 6. Actions (Shift keys)

- [ ] `R` (Shift-R) — refresh pane contents
- [ ] `X` (Shift-X) — close selected buffer (buf mode only; shows message in other modes)
- [ ] `+` / `-` — include / exclude item (code mode only)
- [ ] `T` — toggle tree view (file mode only)
- [ ] `P` (Shift-P) — toggle file preview split
- [ ] `/` — filter files by name pattern
- [ ] `*` — grep project, populate quickfix list

## 7. Nav Indicators (Quick File Open)

Every file/directory gets a single-letter nav indicator in blue (`VprojNavIndicator` highlight).

- [ ] Indicators start at `a` and go up to `z` with no gaps
- [ ] The first file gets `a`, second gets `b`, etc.
- [ ] `.` is reserved for parent directory (not assigned to first file)
- [ ] Press a letter to open its file (temporary mode: pane closes; permanent mode: pane stays)
- [ ] `>` — shift indicators forward (next batch)
- [ ] `<` — shift indicators backward (previous batch)
- [ ] If a letter has no file on this page, nothing happens (no crash)
- [ ] All 26 letters a-z are nav chars. No letters are stolen for cursor movement or actions.

## 8. Paging

- [ ] `<C-N>` — next page
- [ ] `<C-P>` — previous page

## 9. Enter

- [ ] `<CR>` on a file — opens file
- [ ] `<CR>` on a directory — navigates into it
- [ ] `<CR>` on mode menu line (line 1) — cycles to next mode

## 10. Git Actions (`\` prefix)

All git actions use `\` prefix to keep a-z free for nav chars.

- [ ] `\s` — stage/unstage file under cursor
- [ ] `\d` — open diff preview
- [ ] `\D` — discard file changes (confirmation prompt)
- [ ] `\c` — commit with message prompt
- [ ] `\p` — push to remote
- [ ] `\u` — pull --ff-only from remote
- [ ] `\b` — switch branch
- [ ] `\z` — stash changes
- [ ] `\Z` — pop a stash
- [ ] `\a` — blame file under cursor
- [ ] `<C-G>` — toggle showing only git-changed files

## 11. Qfix Mode

- [ ] Run `:vimgrep /TODO/j **/*.vim` to populate quickfix
- [ ] Press Enter on `[Q]fix` in mode menu to enter qfix mode
- [ ] `<Down>` / `<Up>` — navigate entries
- [ ] `<CR>` on entry — open file at line/column
- [ ] Empty qfix list shows "(no quickfix items)"

## 12. Buf Mode

- [ ] `B` (Shift-B) — switch to buf mode
- [ ] Open buffers listed with `%` (current) and `+` (modified) markers
- [ ] `<Down>` / `<Up>` — navigate buffers
- [ ] `<CR>` — switch to selected buffer
- [ ] `X` (Shift-X) on a buffer — close it (modified buffers prompt to save)

## 13. Code Mode (.vproj project)

- [ ] `C` (Shift-C) — switch to code mode
- [ ] Status line shows project name, root directory, git branch
- [ ] `<CR>` on status line — prompts to create or rename project
- [ ] `+` on excluded item — include it
- [ ] `-` on included item — exclude it

## 14. Tree View (file mode)

- [ ] `T` in file mode — toggles tree view
- [ ] `<CR>` on collapsed dir — expands
- [ ] `<CR>` on expanded dir — collapses
- [ ] `T` again — returns to flat view

## 15. File Preview

- [ ] `P` (Shift-P) in file mode — opens preview split
- [ ] Moving cursor updates preview content
- [ ] `P` again — closes preview

## 16. Passthrough — Standard Vim Keys

These standard Vim keys should NOT be remapped in the pane:

- [ ] `0` / `$` — line start / line end
- [ ] `%` — jump to matching `( ) { } [ ]`
- [ ] `{` / `}` — paragraph back / forward
- [ ] `<C-F>` — page down
- [ ] `<C-D>` / `<C-U>` — half-page down / up
- [ ] `<C-W>` keys — window management
- [ ] `zz` / `zt` / `zb` — scroll cursor to center / top / bottom

## 17. Error Handling

- [ ] Press `X` in file mode — shows "X closes buffers in buf mode only (press B for buf mode)"
- [ ] Press `+`/`-` in file mode — shows appropriate message
- [ ] Press `\d`/`\D`/`\s` outside a git repo — shows message, does not crash
- [ ] Press `<CR>` on a directory — navigates in, does not crash
- [ ] `.` at filesystem root — stays at root, does not crash
