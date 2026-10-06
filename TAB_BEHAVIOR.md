# Tabs

Reference: Linux Mint Nemo's `src/nemo-notebook.c` and `src/nemo-places-sidebar.c`:
https://github.com/linuxmint/nemo/blob/master/src/nemo-notebook.c
https://github.com/linuxmint/nemo/blob/master/src/nemo-places-sidebar.c

- The tab bar appears with two or more tabs, below the navigation toolbar.
- Each tab has a folder title, full-path tooltip, close button, and separate pane state (location, navigation history, selection, scrolling, filter, view mode and item size).
- Folder context menus in grid/list and sidebar locations offer Open in New Tab. New tabs appear beside the active tab and become active.
- Command+T or Control+T duplicates the current location; Command+W or Control+W closes the active tab. Closing the final tab closes the window.
- Control+Tab / Control+Shift+Tab switch tabs with wraparound. Shift+Return opens selected folders in tabs.
- Middle-click a folder/sidebar location to open it in a tab; middle-click a tab to close it. Drag a tab horizontally to reorder it. Overflow tabs scroll horizontally.

Remaining Nemo parity differences: tabs cannot detach into a separate window, and there is no tab loading spinner or tab context menu. Tab widths are fixed rather than expanding to fill the window.

Verification: app builds successfully; checked new-tab creation, grid folder Open in New Tab, sidebar menu presence, and Control+Tab switching between separate locations in the running application.
