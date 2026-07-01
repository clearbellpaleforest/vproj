# Test Cases

Concrete test vectors. Each has an ID, description, setup, action, and expected
result.

## TC001: Pane Toggle Open

- Setup: Vim with no vproj_ai pane open
- Action: `call vproj_ai#PaneToggle()`
- Expect: Pane opens on the right, file mode, showing CWD contents. Width 40.

## TC002: Pane Toggle Close

- Setup: Vim with vproj_ai pane open
- Action: `call vproj_ai#PaneToggle()`
- Expect: Pane closes. Original window layout restored.

## TC003: Select Next

- Setup: Pane open, file mode, selected_line at first selectable item
- Action: `call vproj_ai#SelectNext()`
- Expect: selected_line advances by 1. Highlight moves down.

## TC004: Select Next Wraps at Bottom

- Setup: Pane open, selected_line at last selectable item
- Action: `call vproj_ai#SelectNext()`
- Expect: selected_line wraps to first selectable item.

## TC005: Select Prev Wraps at Top

- Setup: Pane open, selected_line at first selectable item
- Action: `call vproj_ai#SelectPrev()`
- Expect: selected_line wraps to last selectable item.

## TC006: Open File

- Setup: Pane open, file mode, select a regular text file
- Action: `call vproj_ai#SelectCurrent()`
- Expect: File opens as buffer in previous window. Pane closes.

## TC007: Navigate Into Directory

- Setup: Pane open, file mode, select a subdirectory
- Action: `call vproj_ai#SelectCurrent()`
- Expect: current_dir changes to subdirectory. Display refreshes with new
  contents. selected_line at first selectable item.

## TC008: Navigate to Parent

- Setup: Pane open, file mode, current_dir is a subdirectory of CWD
- Action: Select ".." and press Enter, or press ".", or press Ctrl-K
- Expect: current_dir changes to parent. Display refreshes.

## TC009: Pane Width Grow

- Setup: Pane open, pane_width = 40
- Action: `call vproj_ai#PaneGrow()`
- Expect: pane_width = 41. Window resized.

## TC010: Pane Width Shrink

- Setup: Pane open, pane_width = 40
- Action: `call vproj_ai#PaneShrink()`
- Expect: pane_width = 39. Window resized.

## TC011: Pane Width Minimum

- Setup: Pane open, pane_width = 20
- Action: `call vproj_ai#PaneShrink()`
- Expect: pane_width = 20. No change below minimum.

## TC012: Pane Width Maximum

- Setup: Pane open, pane_width = 80
- Action: `call vproj_ai#PaneGrow()`
- Expect: pane_width = 80. No change above maximum.

## TC013: Switch to Buf Mode

- Setup: Pane open in file mode
- Action: `call vproj_ai#SwitchMode('buf')`
- Expect: current_mode = 'buf'. Display shows buffer list.

## TC014: Switch to Code Mode

- Setup: Pane open in file mode, .vproj_ai exists in CWD
- Action: `call vproj_ai#SwitchMode('git')`
- Expect: current_mode = 'git'. Display shows project tree.

## TC015: Cycle Mode via Enter on Menu

- Setup: Pane open in file mode
- Action: Move selection to mode menu line, press Enter
- Expect: current_mode cycles to 'buf'. Press Enter again, cycles to 'git'.
  Press again, cycles to 'qfix'. Press again, cycles to 'file'.

## TC016: Close Buffer (Buf Mode)

- Setup: Pane open, buf mode, multiple buffers open
- Action: Select a buffer, press 'x'
- Expect: Buffer is bdeleted. Display refreshes. Selection adjusts if needed.

## TC017: Binary File Detection

- Setup: Pane open, file mode, select a binary file (e.g. a PNG)
- Action: `call vproj_ai#SelectCurrent()`
- Expect: Status message "binary file". File does not open.

## TC018: Empty Directory

- Setup: Pane open, file mode, current_dir is empty
- Action: Render
- Expect: Shows mode menu, separator, status, "..", and "(empty)". No crash.

## TC019: Nav Indicator Jump

- Setup: Pane open, file mode, items have nav indicators
- Action: Press the letter corresponding to item 3
- Expect: selected_line moves to item 3. Item highlighted.

## TC020: Tab Shift Nav Forward

- Setup: Pane open, >58 items listed, nav_offset = 0
- Action: Press Tab
- Expect: nav_offset increases by visible indicator count. Indicators relabel
  starting from the next unlabeled block.

## TC021: Shift-Tab Shift Nav Backward

- Setup: Pane open, nav_offset > 0
- Action: Press Shift-Tab
- Expect: nav_offset decreases. Indicators relabel backward.

## TC022: Next Page

- Setup: Pane open, items exceed one page
- Action: Press Ctrl-N
- Expect: current_page increments. Display shows next page of items.

## TC023: Prev Page

- Setup: Pane open, current_page > 0
- Action: Press Ctrl-P
- Expect: current_page decrements. Display shows previous page.

## TC024: Toggle Info Column

- Setup: Pane open, show_info_column = 1
- Action: Press F1
- Expect: show_info_column = 0. Info column hidden. Item names expand.

## TC025: Select First

- Setup: Pane open, selected_line at position 5
- Action: Press Ctrl-T
- Expect: selected_line moves to first selectable item.

## TC026: Select Last

- Setup: Pane open, selected_line at position 3
- Action: Press Ctrl-B
- Expect: selected_line moves to last selectable item.

## TC027: Include Item (Code Mode)

- Setup: Pane open, code mode, non-included item selected
- Action: Press '+'
- Expect: Item added to .vproj_ai Included Files/Directories. File rewritten.
  Display refreshes. Item no longer in parentheses.

## TC028: Exclude Item (Code Mode)

- Setup: Pane open, code mode, included item selected
- Action: Press '-'
- Expect: Item added to .vproj_ai Excluded Files/Directories. File rewritten.
  Display refreshes. Item shown in parentheses.

## TC029: Rename Project (Code Mode)

- Setup: Pane open, code mode, project name line selected
- Action: Press Enter
- Expect: input() prompt for new project name. On Enter: .vproj_ai updated.
  Display refreshes with new name.
