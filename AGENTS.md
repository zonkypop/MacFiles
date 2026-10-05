# MintFiles interaction reference

The user wants Linux Mint Nemo's behavior, not macOS Finder/AppKit defaults. Use Nemo as the reference for selection, keyboard navigation, mouse gestures, file operations, and layout. Inspect Nemo's source when a behavior is uncertain. Do not assume native AppKit behavior matches Nemo, or claim exact parity without verifying it.

Grid Left/Right must wrap across row boundaries with and without Shift. Shift selection uses a fixed anchor and moving endpoint; reversing direction shrinks the range and can extend past the anchor. Preserve this when changing selection, layout, refresh, or sizing code.

No split-pane functionality and no New Folder toolbar button. Keep New Folder in the context menu. Grid/list switching and Control–mousewheel item sizing are required.

Before implementing or revising a file-manager interaction, inspect the corresponding upstream Nemo source and menu resources proactively. Record relevant behavior and any remaining parity gaps; do not wait for the user to enumerate standard Nemo features.
