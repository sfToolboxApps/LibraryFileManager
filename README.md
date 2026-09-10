# Salesforce Library File Manager

Salesforce Library File Manager is a custom Lightning Web Component that dramatically simplifies file organization in Salesforce. Move files between libraries, organize them into folders, and manage your content library structure—all from an intuitive, modern interface.

## Give Back to the Trailblazer Community

Enjoying this tool? Give back by attending, donating, or sponsoring Biggest Little Dreamin', a Salesforce community conference in Reno, NV (Jan 28-29, 2027). Can't make it? A personal donation, or getting your company to donate if your team's using this tool, helps the community a ton.

[Support Biggest Little Dreamin' →](https://biggestlittledreamin.com)

**What makes this special?** Salesforce's native file management requires moving files one at a time and doesn't support moving files between folders in different libraries. This component eliminates those limitations.

## 📋 Table of Contents

- [Overview](#overview)
- [The Problem](#the-problem)
- [The Solution](#the-solution)
- [Features](#features)
- [Testing](#testing)
- [Installation](#installation)
- [Usage](#usage)
- [Architecture](#architecture)
- [Key Technical Decisions](#key-technical-decisions)
- [Documentation](#documentation)
- [Contributing](#contributing)
- [License](#license)
- [Known Limitations](#known-limitations)
- [Roadmap](#roadmap)
- [Acknowledgments](#acknowledgments)

## 🎯 Overview

Salesforce Library File Manager gives you an explorer-style view of every Library you have access to — a folder tree on one side, a file table on the other — and lets you move, organize, and delete files across that whole structure without leaving the page.

## 🔥 The Problem

Standard Salesforce file management has real limitations:

- ❌ **One file at a time** — the native UI moves files individually; there's no native bulk-move action.
- ❌ **No cross-library folder moves** — Salesforce doesn't support moving a file directly from a folder in one library to a folder in another. Natively, you'd have to share it to the new library, then re-file it, by hand.
- ❌ **No unified explorer view** — no single, native place to browse every library's folder tree alongside its files.
- ❌ **No in-app search across the tree** — finding a specific file or folder means clicking through the hierarchy manually.

## ✨ The Solution

This component provides:

- ✅ **True cross-library bulk moves** — select any number of files, in any library or folder, and move them across libraries and into a specific destination folder in a single action.
- ✅ **Explorer-style browsing** — a library/folder tree alongside a file table, with folders shown inline.
- ✅ **In-app search** — a live, client-side filter across the current view; no server round-trip.
- ✅ **Automatic handling of Salesforce's cross-library move mechanics** — the two-step "join the library, then file into the folder" sequence Salesforce requires under the hood happens as one action from your perspective.

## 🚀 Features

- **True cross-library moves** — select any number of files, in any library or folder, and move them across libraries and into a specific destination folder in a single bulk action
- **Explorer-style browsing** — a library/folder tree alongside a file table, with folders shown inline (folder icon, click-to-navigate) next to files
- **In-app search** — a live, client-side search box above the file table filters both files and folders in the current view as you type; no server round-trip, and selections are preserved when the filter is applied or cleared
- **Folder creation** — create folders at a library root or nested under another folder
- **Bulk delete** — remove multiple files in one action. This permanently deletes the underlying `ContentDocument` (subject to the org's recycle bin), not just its association with the current library — the file disappears everywhere it was shared, not only from the library you're viewing
- **Live file/folder counts** — libraries and folders show accurate, correctly-pluralized file counts in the tree
- **Expand All / Collapse All** — quickly open or close the entire library tree
- **Getting Started landing page** — a dedicated tab introducing the app when it opens
- **Asset Library excluded automatically** — the org's built-in system Asset Library is filtered out of the library list (matched by its `WorkspaceType`, not by name), so only real user-created libraries appear

## 🧪 Testing

`LibraryFileManagerController.cls` has **81% code coverage** (652 of 807 lines), with all 71 Apex test methods passing (100% pass rate) in a clean full run. The tests live across 5 focused classes — `LibraryFileManagerLibrariesTest`, `LibraryFileManagerFilesTest`, `LibraryFileManagerMoveTest`, `LibraryFileManagerFolderAndDeleteTest`, plus a shared `LibraryFileManagerTestHelper` with no test methods of its own — rather than one large file. Coverage numbers reflect the actual last test run against a live org — re-run `sf apex run test --class-names LibraryFileManagerLibrariesTest,LibraryFileManagerFilesTest,LibraryFileManagerMoveTest,LibraryFileManagerFolderAndDeleteTest --code-coverage` to verify current numbers before relying on them, as they will drift as the code changes.

## 📦 Installation

### Prerequisites

- **Salesforce CRM Content must be enabled** in your org (Setup → Salesforce CRM Content Settings → Enable Salesforce CRM Content). Without this, Libraries (`ContentWorkspace`) won't function and the app will not be usable.
- Salesforce CLI (`sf`) installed for deployment
- System Administrator or equivalent deploy access to the target org

### Option 1: Deploy via Salesforce CLI (SFDX)

```bash
git clone https://github.com/sfToolboxApps/LibraryFileManager.git
cd LibraryFileManager
sf org login web --alias your-org-alias
sf project deploy start --source-dir force-app --target-org your-org-alias
```

### Option 2: Deploy as an unmanaged package

Retrieve the source and deploy it into your org as an unmanaged package using the same `sf project deploy start` command above, targeting your org.

After deploying, assign the **Library File Manager** permission set to any user who needs access, **and** add them as a member of each Library they need to work with (Library membership is separate from the permission set — Salesforce Libraries are only visible to their explicit members) — see [INSTALLATION.md](INSTALLATION.md) for the full step-by-step, including this and a permission-set gotcha that will silently hide the app's tabs if missed.

## 💡 Usage

### Getting oriented

Open the **Getting Started** tab — it's the app's default landing tab, and gives a quick orientation before you get into the Library File Manager tab itself.

### Moving files within the same library

1. Open the **Library File Manager** tab.
2. Select a library from the tree on the left.
3. Select one or more files using the checkboxes in the file table.
4. Click **Move Files**, choose a destination folder within the same library, and confirm.

### Moving files across libraries

1. Select files from any library or folder, the same way as above.
2. Click **Move Files** and pick a destination in a _different_ library (or a folder within it).
3. Confirm — the app handles the cross-library move as a single action, including files that need to be added to the destination library and organized into a specific folder. This is the capability native Salesforce doesn't offer.

### Creating folders and deleting files

Use **Create Folder** to add a new folder under the currently selected library or folder, and **Delete Files** to remove selected files. Both buttons are disabled until you've selected the necessary context (a library, or files) — see [QUICK_START.md](QUICK_START.md) for a plain-language walkthrough.

**Delete Files permanently deletes the file itself**, not just its presence in the library you're currently viewing. If a file is shared across multiple libraries or linked to other records, deleting it here removes it everywhere (subject to your org's recycle bin retention). There is no "remove from this library only" option.

## 🏗 Architecture

### Component structure

```
force-app/main/default/
├── applications/
│   └── LibraryFileManager.app-meta.xml
├── classes/
│   ├── LibraryFileManagerController.cls          # single Apex controller — all server logic
│   ├── LibraryFileManagerTestHelper.cls           # shared test setup, no test methods itself
│   ├── LibraryFileManagerLibrariesTest.cls        # tests: library/folder listing
│   ├── LibraryFileManagerFilesTest.cls            # tests: file browsing, icons, sizes
│   ├── LibraryFileManagerMoveTest.cls             # tests: all move/smart-move variants
│   └── LibraryFileManagerFolderAndDeleteTest.cls  # tests: create folder, delete files
├── lwc/
│   ├── libraryFileManager/                        # main app UI — tree + file table + move panel
│   └── gettingStarted/                            # default landing tab, pure presentation
├── permissionsets/
│   └── LibraryFileManager.permissionset-meta.xml
└── tabs/
    ├── Getting_Started.tab-meta.xml
    └── LibraryFileManager.tab-meta.xml
```

Both tabs point directly at their LWC (`lwcComponent`), not at a FlexiPage — there's no page layout indirection between the tab and the component.

### Salesforce object model

| Object                | Purpose                                        |
| --------------------- | ---------------------------------------------- |
| `ContentWorkspace`    | A Library                                      |
| `ContentFolder`       | A folder within a library                      |
| `ContentFolderMember` | Links a file to the folder it's filed in       |
| `ContentDocument`     | The file itself                                |
| `ContentVersion`      | File content and version data                  |
| `ContentDocumentLink` | Links a file to the libraries it's shared into |

## Key Technical Decisions

1. **`smartMoveFiles` is the single move entry point.** The LWC never decides client-side whether a move is same-library, cross-library, or into a folder — that routing lives entirely server-side. See [docs/architecture.md](docs/architecture.md) for the full decision tree.
2. **Cross-library folder moves are two Salesforce operations wrapped in one.** Salesforce requires a file to join the destination library before it can be organized into a folder there; `executeAutomaticCrossLibraryMove` runs both steps as a single server-side action, with partial-success reporting if the second step fails after the first already succeeded.
3. **Everything loads eagerly; nothing is lazy.** `getLibrariesWithFolders()` returns every library, folder, and file count in one call on load. There's no per-folder fetch triggered by expanding a node.
4. **The library tree's expand/collapse state is never touched by application code on a click.** An earlier version tried to force nodes open or closed in response to selection and produced a hard-to-reproduce bug class — nodes silently collapsing, or reopening, on unrelated state changes. The current code does pure navigation on selection only.
5. **Access control is three independent layers, and only one is deployable metadata.** The permission set grants object/field CRUD; Library membership and the Library permission level's Delete/Organize flags are org data an admin must configure per user, per library — see [docs/security.md](docs/security.md).

## Documentation

- [QUICK_START.md](QUICK_START.md) — short, end-user walkthrough
- [INSTALLATION.md](INSTALLATION.md) — detailed admin deployment guide and troubleshooting
- [docs/architecture.md](docs/architecture.md) — class/component responsibilities, the move decision tree, and key LWC design decisions
- [docs/security.md](docs/security.md) — access control model (permission set, library membership, library permission levels) and how it's verified
- [SECURITY.md](SECURITY.md) — how to report a security vulnerability
- [CONTRIBUTING.md](CONTRIBUTING.md) — how to report bugs, suggest features, and contribute code
- [CHANGELOG.md](CHANGELOG.md) — release history
- [LICENSE](LICENSE) — MIT License

## 🤝 Contributing

Bug reports, feature suggestions, and pull requests are welcome — see [CONTRIBUTING.md](CONTRIBUTING.md).

## 📄 License

This project is licensed under the **MIT License** — see the [LICENSE](LICENSE) file for details.

### What this license means

- ✅ Free to use for personal and commercial projects
- ✅ Free to modify and distribute
- ✅ No warranty provided
- ℹ️ Must include the copyright notice and license text

## ⚠️ Known Limitations

- **No folder renaming or folder deletion yet** — only folder creation is supported today.
- **No drag-and-drop** — all moves go through the Move panel.
- **No automated CI enforcement yet** of the security-sensitive patterns (`WITH USER_MODE`, `as user`) described in [docs/security.md](docs/security.md) — these are real, passing Apex tests, but nothing currently blocks a PR from regressing them without a human catching it in review.
- **Library membership and the Library permission level's Delete/Organize flags must be configured manually**, per user, per library, by an admin — see [docs/security.md](docs/security.md). The permission set alone is not sufficient for a user to see or fully use a library.
- **Visual/CSS verification has mostly been done via retrieve-and-diff** against a deployed org and Jest DOM assertions, not a browser screenshot tool.

## 🗺 Roadmap

Future work under consideration:

- [ ] Split `LibraryFileManagerController` into focused service classes (query/move/folder) — planned, intentionally deferred until after the security and correctness hardening work landed (see [docs/architecture.md](docs/architecture.md))
- [ ] Automated CI enforcement of the security tests and patterns described in [docs/security.md](docs/security.md)
- [ ] Folder renaming
- [ ] Folder deletion (with file-handling)
- [ ] Move an entire folder, including its subfolders, in one action
- [ ] Drag-and-drop interface

## 🎉 Acknowledgments

- Built with the [Salesforce Lightning Design System](https://www.lightningdesignsystem.com/).
- Thanks to the Trailblazer community — see [Give Back to the Trailblazer Community](#give-back-to-the-trailblazer-community) above if this tool has saved you time.

---

_If Library File Manager saves you time, consider starring the repository — and see the Give Back section above._
