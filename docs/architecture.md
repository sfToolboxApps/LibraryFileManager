# Architecture

This document describes how the pieces of Library File Manager fit together today. For the access-control model specifically, see [security.md](security.md).

## Components at a glance

```
force-app/main/default/
├── classes/
│   ├── LibraryFileManagerController.cls        ← single Apex controller (all server logic)
│   ├── LibraryFileManagerTestHelper.cls         ← shared test setup, no test methods itself
│   ├── LibraryFileManagerLibrariesTest.cls      ← tests: library/folder listing
│   ├── LibraryFileManagerFilesTest.cls          ← tests: file browsing, icons, sizes
│   ├── LibraryFileManagerMoveTest.cls           ← tests: all move/smart-move variants
│   └── LibraryFileManagerFolderAndDeleteTest.cls← tests: create folder, delete files
├── lwc/
│   ├── libraryFileManager/                      ← the main app UI (tree + file table + move panel)
│   └── gettingStarted/                          ← default landing tab, pure presentation
├── applications/LibraryFileManager.app-meta.xml
├── tabs/Getting_Started.tab-meta.xml, LibraryFileManager.tab-meta.xml
└── permissionsets/LibraryFileManager.permissionset-meta.xml
```

Both tabs point directly at their LWC (`lwcComponent`), not at a FlexiPage — there's no page layout indirection between the tab and the component.

## Apex: one controller, grouped by concern

`LibraryFileManagerController` is intentionally a single class today, not yet split into separate services (see "Planned evolution" below). Its public `@AuraEnabled` surface:

| Method                                                                       | Purpose                                                                                                                                                                                                                                                                             |
| ---------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `getLibrariesWithFolders()`                                                  | Loads every library the user can see, with its full folder tree and file counts, eagerly, in one call. This is the only library/tree load the LWC does — there's no lazy per-folder fetch.                                                                                          |
| `getLibraryFolders(libraryId)`                                               | Folder tree for a single library (used less often than the bulk call above; kept for the case where only one library's folders are needed).                                                                                                                                         |
| `getFilesInFolder(libraryId, folderId)`                                      | Files (and subfolder rows) for a given location. `folderId` blank means the library root. Accepts either an Id or a Name for both parameters (resolved server-side).                                                                                                                |
| `moveFilesToLibrary(fileIds, targetLibraryId)`                               | Moves files into a library — including relocating them to that library's root folder even if the source and target library are the same (see the CHANGELOG entry on the same-library-root bug for why that step exists explicitly rather than relying on a Salesforce side effect). |
| `moveFilesToFolder(fileIds, targetFolderId, targetLibraryId)`                | Moves files into a specific folder. Validates the folder actually belongs to the target library before doing anything. Internally calls `moveFilesToLibrary` first if the files aren't already in that library.                                                                     |
| `smartMoveFiles(fileIds, destinationId, destinationType)`                    | **The single entry point the LWC actually calls for every move.** Routes to the two methods above, or to `executeAutomaticCrossLibraryMove` when the files need to change library _and_ land in a specific folder in one action.                                                    |
| `executeAutomaticCrossLibraryMove(fileIds, targetLibraryId, targetFolderId)` | The two-step cross-library sequence (move to library, then move to folder) run automatically as one operation, with partial-success reporting if step 2 fails after step 1 already succeeded.                                                                                       |
| `deleteFiles(fileIds)`                                                       | Permanently deletes `ContentDocument` records (not just a library association — see the README's Delete Files warning).                                                                                                                                                             |
| `createFolder(folderName, parentLibraryId, parentFolderId)`                  | Creates a folder at a library root (`parentFolderId` blank) or nested under another folder.                                                                                                                                                                                         |

The private helpers below these fall into three groups: folder-hierarchy building (`loadFolderHierarchyWithCounts`, `getSubFoldersFromMap`, shared by the two listing entry points), file-row building (`getFilesInLibraryRoot`, `getFilesInContentFolder`, `getSubfolderRows`), and path/breadcrumb resolution (`getFolderPath`, `buildBreadcrumbs`, `findLibraryForFolder`) — the last group intentionally uses a higher iteration safety limit than the tree builders, since it must reach the true root for any folder, not just ones inside the eagerly-built tree (see the `FOLDER_TREE_BUILD_MAX_DEPTH` / `FOLDER_PATH_SAFETY_LIMIT` comments in the class itself).

### The move decision tree

`smartMoveFiles` is the only move-related method the LWC calls directly. Server-side, it decides which of the three real move operations to run:

```
smartMoveFiles(fileIds, destinationId, destinationType)
│
├── destinationType == "library"
│   └── moveFilesToLibrary(fileIds, destinationId)
│
└── destinationType == "folder"
    ├── find the folder's owning library
    ├── are any files currently in a DIFFERENT library than that?
    │   ├── yes → executeAutomaticCrossLibraryMove(fileIds, targetLibraryId, destinationId)
    │   │           = moveFilesToLibrary(...) then moveFilesToFolder(...), one result
    │   └── no  → moveFilesToFolder(fileIds, destinationId, targetLibraryId)
```

All three concrete operations return the same `OperationResult` shape (`success`, `partialSuccess`, `successCount`, `errors`, `warnings`), so the LWC has one result-handling code path regardless of which one actually ran.

## LWC: `libraryFileManager`

The bulk of the client logic lives in one component. A few architectural decisions are worth knowing before changing it:

- **Everything is eager-loaded, nothing is lazy.** `getLibrariesWithFolders()` returns the full tree (all libraries, all folders, all file counts) in one call on load. There is no per-folder fetch triggered by expanding a node. This was a deliberate simplification — see the next point for why.
- **The tree never has its expand/collapse state touched by application code on a click.** `lightning-tree` only fires a JS event (`onselect`) for label clicks, never for chevron clicks, and there is no supported way to distinguish "user expanded this via the chevron" from "the data changed" once you start mutating the `items` array in response to selection. Earlier attempts to force the clicked node open (or its ancestors open) on selection caused a real, hard-to-reproduce bug class: nodes silently collapsing on unrelated state changes, or previously-opened nodes all reopening at once later in the session. The current code (`handleTreeSelect`) does pure navigation only — it never touches `expanded` on any node. Two narrow programmatic cases (jumping to a destination after a move, re-selecting after a refresh) do need to force a specific path open; those use `expandPathToTarget`, which always collapses everything first and then forces only the target path — never builds on top of possibly-stale state. If you're tempted to make chevron-clicks and label-clicks behave more consistently by having code react to selection, read this section again first.
- **File search is entirely client-side.** The search box filters the already-loaded `currentFiles` array in memory (`updateDisplayedFiles`); it does not re-query Apex. Selections are explicitly preserved across a filter being applied or cleared (`handleFileSelection` merges hidden-but-still-selected rows back in rather than trusting `lightning-datatable`'s `selectedRows`, which only reflects currently-visible rows).
- **Move panel and cross-library moves are one action from the user's perspective.** The LWC always calls `smartMoveFiles`; it does not decide client-side whether a move is "same library," "cross library," or "to a folder" — that logic lives entirely server-side (see the decision tree above), so the client only needs one success/failure handling path.

`gettingStarted` is intentionally simple by comparison — a static landing page with one navigation action (`NavigationMixin` to jump to the `LibraryFileManager` tab) and no Apex calls at all.

## Tests

Split into 5 files (see [CHANGELOG.md](../CHANGELOG.md) for why) mirroring the controller's own grouping: libraries/folders, file browsing, moves, and folder-create/delete, plus a shared `LibraryFileManagerTestHelper` with no test methods of its own. See [security.md](security.md) for the restricted-user testing pattern used throughout.

## Planned evolution (not yet done)

The controller is currently one class covering four distinct concerns: listing/browsing, moving, folder management, and shared query/path helpers. A future split into separate service classes (query service, move service, folder service, thin controller) is planned but intentionally deferred — it's the highest-risk, lowest-urgency item on the open-source hardening roadmap, saved for after the security and correctness work landed and was tested (see `docs/security.md` and the CHANGELOG's Security/Fixed sections for what that work found). Splitting a working, recently-stabilized class carries real regression risk and shouldn't be bundled with safer, more urgent fixes.
