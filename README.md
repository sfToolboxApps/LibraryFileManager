# Salesforce Library File Manager

Salesforce Library File Manager is a custom Lightning Web Component that dramatically simplifies file organization in Salesforce. Move files between libraries, organize them into folders, and manage your content library structure—all from an intuitive, modern interface.

## Give Back to the Trailblazer Community

Enjoying this tool? Give back by attending, donating, or sponsoring Biggest Little Dreamin', a Salesforce community conference in Reno, NV (Jan 28-29, 2027). Can't make it? A personal donation, or getting your company to donate if your team's using this tool, helps the community a ton.

[Support Biggest Little Dreamin' →](https://biggestlittledreamin.com)

**What makes this special?** Salesforce's native file management requires moving files one at a time and doesn't support moving files between folders in different libraries. This component eliminates those limitations.

## Features

- **True cross-library moves** — select any number of files, in any library or folder, and move them across libraries and into a specific destination folder in a single bulk action
- **Explorer-style browsing** — a library/folder tree alongside a file table, with folders shown inline (folder icon, click-to-navigate) next to files
- **In-app search** — a live, client-side search box above the file table filters both files and folders in the current view as you type; no server round-trip, and selections are preserved when the filter is applied or cleared
- **Folder creation** — create folders at a library root or nested under another folder
- **Bulk delete** — remove multiple files in one action. This permanently deletes the underlying `ContentDocument` (subject to the org's recycle bin), not just its association with the current library — the file disappears everywhere it was shared, not only from the library you're viewing
- **Live file/folder counts** — libraries and folders show accurate, correctly-pluralized file counts in the tree
- **Expand All / Collapse All** — quickly open or close the entire library tree
- **Getting Started landing page** — a dedicated tab introducing the app when it opens
- **Asset Library excluded automatically** — the org's built-in system Asset Library is filtered out of the library list (matched by its `WorkspaceType`, not by name), so only real user-created libraries appear

## Test Coverage

`LibraryFileManagerController.cls` has **81% code coverage** (652 of 807 lines), with all 71 Apex test methods passing (100% pass rate) in a clean full run. The tests live across 5 focused classes — `LibraryFileManagerLibrariesTest`, `LibraryFileManagerFilesTest`, `LibraryFileManagerMoveTest`, `LibraryFileManagerFolderAndDeleteTest`, plus a shared `LibraryFileManagerTestHelper` with no test methods of its own — rather than one large file. Coverage numbers reflect the actual last test run against a live org — re-run `sf apex run test --class-names LibraryFileManagerLibrariesTest,LibraryFileManagerFilesTest,LibraryFileManagerMoveTest,LibraryFileManagerFolderAndDeleteTest --code-coverage` to verify current numbers before relying on them, as they will drift as the code changes.

## Prerequisites

- **Salesforce CRM Content must be enabled** in your org (Setup → Salesforce CRM Content Settings → Enable Salesforce CRM Content). Without this, Libraries (`ContentWorkspace`) won't function and the app will not be usable.
- Salesforce CLI (`sf`) installed for deployment
- System Administrator or equivalent deploy access to the target org

## Installation

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

## Usage

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

## Documentation

- [QUICK_START.md](QUICK_START.md) — short, end-user walkthrough
- [INSTALLATION.md](INSTALLATION.md) — detailed admin deployment guide and troubleshooting
- [docs/architecture.md](docs/architecture.md) — class/component responsibilities, the move decision tree, and key LWC design decisions
- [docs/security.md](docs/security.md) — access control model (permission set, library membership, library permission levels) and how it's verified
- [SECURITY.md](SECURITY.md) — how to report a security vulnerability
- [CONTRIBUTING.md](CONTRIBUTING.md) — how to report bugs, suggest features, and contribute code
- [CHANGELOG.md](CHANGELOG.md) — release history
- [LICENSE](LICENSE) — MIT License

## Contributing

Bug reports, feature suggestions, and pull requests are welcome — see [CONTRIBUTING.md](CONTRIBUTING.md).

## License

MIT — see [LICENSE](LICENSE).
