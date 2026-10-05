# MintFiles

A standalone Swift/AppKit file manager for macOS, inspired by Linux Mint's Nemo. This is an initial working version, not an exact Nemo clone.

## Run

Open `dist/MintFiles.app`. To rebuild with Apple's Command Line Tools:

```sh
./scripts/build-app.sh
open dist/MintFiles.app
```

The script builds for the current Mac architecture, targets macOS 13+, and signs the app locally. It needs no packages or network access. The app is not sandboxed or notarized. It does not replace Finder or change system defaults.

## Included

- Places sidebar, editable folder paths, back/forward/up/home navigation.
- Multiple tabs, grid/list switching, and persistent view/size preferences.
- Resizable grid with Mint-style folder icons, wrapped filenames, and file sizes.
- Details list with sortable name, size, type, and modification columns; folders sort first.
- Multiple selection, double-click or Return to open, local filename filtering, hidden-file toggle.
- Copy, cut/move, paste, rename, new folders, and recoverable macOS Trash.
- Drag files out to other apps or copy files into the current pane/a folder row.
- Open the current folder in Terminal.
- Background folder loading and file transfers; visible operation status.
- Refresh every four seconds, without rebuilding an unchanged list.

Use the top-right buttons to switch between grid and list. Hold Control and scroll the mouse wheel to resize items, or use the bottom-right slider. In grid view, Right continues onto the first item of the next row, and Left continues onto the last item of the previous row. Hold Shift with the arrow keys to extend a contiguous selection from the starting item across rows; reversing direction shrinks it. Shift-click extends from the same starting item. Navigation stops at the first and last items. The size and view are saved between launches. Right-click a file or blank space for file commands, including New Folder. Dragging copies; use Cut/Paste to move.

## Shortcuts

| Action | Shortcut |
| --- | --- |
| New / close tab | Command-T / Command-W |
| Location | Command-L |
| Copy / cut / paste | Command-C / Command-X / Command-V |
| Select all | Command-A |
| New folder | Command-Shift-N |
| Rename | Command-R |
| Open selection | Return or Command-O |
| Move to Trash | Command-Delete |
| Back / forward | Command-[ / Command-] |
| Up | Command-Up |
| Home | Command-Shift-H |
| Hidden files | Command-H |
| Grid / list | Command-1 / Command-2 |
| Larger / smaller items | Command-= / Command-- |
| Resize with mouse | Control + mouse wheel |
| Refresh | F5 |

On some keyboards, function keys require Fn.

## File-operation behavior

Existing destinations are refused; no overwrite option is implemented. Self-copy and copying a directory into itself are refused. Batch operations stop on the first error, and previously completed items remain completed. Transfers cannot yet be cancelled or undone through this app. Trash restoration uses macOS Trash. Files are opened with their default macOS application. Protected folders remain subject to macOS permission prompts.

## Verification

```sh
dist/MintFiles.app/Contents/MacOS/MintFiles --self-test
```

The self-test creates and cleans up its own temporary directory. It checks visible/hidden listings, copied file contents, filename validation, conflicts, self-copy, and recursive-copy protection.

The running app was also tested with disposable files for navigation, tabs, copy, cut/move, rename, new-folder creation, and filtering. The grid/list update was checked in the running app for view switching, retained selection, resizing with the slider, and the grid context menu. Shift-arrow selection was verified across row boundaries in both directions, including shrinking and reversing past the anchor, and with vertical movement. Control-wheel is implemented in the scroll view but still needs a physical mouse check. Drag/drop, Trash restoration, large transfers, cloud files, network drives, and protected-folder access still need wider testing.

## Next work

Closer Nemo theming and breadcrumb navigation; persistent tabs; undo; transfer progress and cancellation; conflict choices; better drive and cloud integration. The app currently uses familiar macOS Command shortcuts rather than Linux Control shortcuts.
