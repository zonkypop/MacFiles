# Files

A standalone Swift/AppKit file manager for macOS, inspired by Linux Mint's Nemo. This is an initial working version, not an exact Nemo clone.

## Run

Open `dist/Files.app`. To rebuild with Apple's Command Line Tools:

```sh
./scripts/build-app.sh
open dist/Files.app
```

The script builds for the current Mac architecture, targets macOS 13+, and signs the app locally. It needs no packages or network access. The app is not sandboxed or notarized. It does not replace Finder or change system defaults.

## Included

- Places sidebar, editable folder paths, back/forward/up/home navigation.
- Multiple tabs, grid/list switching, and persistent view/size preferences.
- Resizable grid with Mint-style folder icons, wrapped filenames, file sizes, and cached image thumbnails (including PNG, WebP, and AVIF on supported macOS versions).
- Details list with sortable name, size, type, and modification columns; folders sort first.
- Multiple selection, double-click or Return to open, local filename filtering, hidden-file toggle.
- Copy, cut/move, paste, rename, new folders, and recoverable macOS Trash.
- Drag files out to other apps or copy files into the current pane/a folder row.
- Open the current folder in Terminal.
- Background folder loading and file transfers; visible operation status.
- Refresh every four seconds, without rebuilding an unchanged list.

Use the top-right buttons to switch between grid and list. Hold Control and scroll the mouse wheel to resize items, or use the bottom-right slider. In grid view, Right continues onto the first item of the next row, and Left continues onto the last item of the previous row. Hold Shift with the arrow keys to extend a contiguous selection from the starting item across rows; reversing direction shrinks it. Shift-click extends from the same starting item. Navigation stops at the first and last items. The size and view are saved between launches. Right-click a file or blank space for file commands, including New Folder. Dragging copies; use Cut/Paste to move.

## Image thumbnails

Grid and list thumbnails share the same cache and are requested for displayed items. List name cells are reused, and requests are cancelled when rows leave view. ImageIO downsamples originals to a maximum of 320 pixels (enough for the largest grid size on a Retina display), preserves orientation/transparency, and keeps decoding off the main thread. Quick Look is a fallback for image formats the decoder cannot handle. Failed previews retain their normal file icon.

Two workers limit concurrent decoding. Requests share in-flight work, cancel when items leave the viewport, and reject stale results when a tile is reused. The memory cache has a 64 MB cost limit. A persistent PNG cache lives in `~/Library/Caches/local.mintfiles.app/Thumbnails-v1/`, with hashed filenames derived from the original path, size, and modification time. It is pruned to 256 MB at startup and periodically while writing. Cache data stays outside the repository. Cloud-only iCloud originals are skipped rather than downloaded for a preview.

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
dist/Files.app/Contents/MacOS/Files --self-test
dist/Files.app/Contents/MacOS/Files --thumbnail-self-test
```

The self-test creates and cleans up its own temporary directory. It checks visible/hidden listings, copied file contents, filename validation, conflicts, self-copy, and recursive-copy protection.

The running app was also tested with disposable files for navigation, tabs, copy, cut/move, rename, new-folder creation, and filtering. The grid/list update was checked in the running app for view switching, retained selection, resizing with the slider, and the grid context menu. Shift-arrow selection was verified across row boundaries in both directions, including shrinking and reversing past the anchor, and with vertical movement. Control-wheel is implemented in the scroll view but still needs a physical mouse check. Drag/drop, Trash restoration, large transfers, cloud files, network drives, and protected-folder access still need wider testing.

Thumbnail tests cover downsampling/aspect ratio, memory reuse, disk reuse, source invalidation, shared requests, cancellation, and WebP/AVIF decoding. PNG, WebP, and AVIF previews were visually checked in the app, along with fast scrolling through 100 images and fallback for a broken image.

## Next work

Closer Nemo theming and breadcrumb navigation; persistent tabs; undo; transfer progress and cancellation; conflict choices; better drive and cloud integration. The app currently uses familiar macOS Command shortcuts rather than Linux Control shortcuts.

Image preview: select an image in grid or list view and press **Space**. Use **arrow keys** to move the file selection and update the open preview (including grid row wrapping). Press **Space**, **Escape**, or **Q** to close and return to the selection; **F** or **F11** toggles full screen. Previews decode asynchronously at display resolution (capped at 4096 pixels), rather than stretching the small thumbnail or loading an unbounded full-resolution bitmap.

The layout follows the Nemo references: fixed-pitch grid columns, bottom-aligned icons and larger image thumbnails, up to three filename lines, row heights based on captions, and cached folder item counts. Grid and list sizes are saved separately. The top bar has clickable breadcrumbs (⌘L to edit the path), ancestor navigation, a search toggle, and in-window menus. The full-width bottom bar shows folder/selection counts and available disk space, with the size slider on the right.
