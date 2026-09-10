# Security Model

This document describes how Library File Manager enforces Salesforce access control, and — just as importantly — the parts of the access model that **can't** be enforced by the app's own metadata and are the installing admin's responsibility. Everything below was verified against a real restricted user, not assumed; see the "How this was verified" section for the method, and [CHANGELOG.md](../CHANGELOG.md) for the specific gaps that verification found and fixed.

## Three independent layers of access control

A user needs **all three** of the following before they can use a given library through this app. Missing any one produces a different failure mode, and only the first is something the app's own permission set can grant.

### 1. Object and field permissions — the `LibraryFileManager` permission set

Grants CRUD on the Salesforce Content objects the app touches, scoped to what each operation actually needs — not blanket access:

| Object                | Read | Create | Edit | Delete |
| --------------------- | ---- | ------ | ---- | ------ |
| `ContentWorkspace`    | ✅   |        |      |        |
| `ContentFolder`       | ✅   | ✅     | ✅   |        |
| `ContentFolderMember` | ✅   | ✅     | ✅   | ✅     |
| `ContentDocument`     | ✅   | ✅     | ✅   | ✅     |
| `ContentVersion`      | ✅   | ✅     | ✅   |        |
| `ContentDocumentLink` | ✅   | ✅     | ✅   | ✅     |

Assigning this permission set is **necessary but not sufficient** — see layers 2 and 3 below. A user with only this permission set assigned and no library membership sees an empty library list with no error at all.

### 2. Library membership — `ContentWorkspaceMember`

Salesforce Library (`ContentWorkspace`) visibility is governed entirely by explicit membership records, independent of object CRUD. A user with full `ContentWorkspace` read access who isn't a member of a specific library still can't see it — the query simply returns zero rows, no exception.

This is **data, not metadata**: `ContentWorkspaceMember` records reference specific library IDs that don't exist until the org creates its own libraries, so it can never be part of a deployable permission set. It's the installing admin's responsibility, per library, per user — see [INSTALLATION.md](../INSTALLATION.md) step 4.

### 3. Library permission level — `ContentWorkspacePermission`

Library membership itself is assigned _at a permission level_ (`Viewer`, `Author`, `Library Administrator`, or a custom level an admin creates), and that level determines what the member can actually do within the library — independent of both layers above.

**Confirmed by querying `ContentWorkspacePermission` directly against a real org:** none of the three standard seeded levels have `PermissionsDeleteContent` or `PermissionsOrganizeFileAndFolder` checked. Concretely:

- `Viewer` — browse only.
- `Author` — browse and add files. **Cannot** delete files, create folders, or move files between folders.
- `Library Administrator` — manages workspace settings. Also, perhaps surprisingly, does **not** include Delete Content or Organize Content and Folders by default.

To grant a user the app's full functionality, the admin must create a custom library permission level with `Delete Content` and `Organize Content and Folders` checked, and assign that instead of the defaults. Like layer 2, this is data (a `ContentWorkspacePermission` record and its `ContentWorkspaceMember` assignment), not something the permission set can express.

## What the Apex layer enforces

`LibraryFileManagerController` is `public with sharing` and runs every operation under the actual permissions described above, not as the deploying admin:

- **Reads** use `WITH USER_MODE` on every SOQL query, so a query silently returns nothing (or the controller's normal "not found" error path) rather than exposing data the running user can't see.
- **Writes** use `insert as user` / `update as user` / `delete as user`, or `Database.insert/update/delete(records, allOrNone, AccessLevel.USER_MODE)` for the two calls that need per-row partial-success handling. A write that violates the running user's CRUD/FLS fails for that operation — it does not silently fall back to system-mode access.

Two specific hardening decisions worth knowing about if you're extending this controller:

- **No client-reachable bypass of library validation.** `getFilesInFolder` used to accept an `isTestRootFolder` flag directly from the client, which skipped library-existence validation. That parameter was removed from the public `@AuraEnabled` signature; the equivalent test-only path is a separate `@TestVisible` method that no LWC or external caller can reach.
- **Destination consistency is validated, not assumed.** `moveFilesToFolder` rejects the request outright — before any DML — if the destination folder doesn't actually belong to the destination library, instead of silently leaving `ContentDocument.ParentId` and `ContentFolderMember.ParentContentFolderId` pointing at different libraries.

## A real gotcha if you add new queries

`WITH USER_MODE` validates FLS on _every field present on the in-memory record_, not just the fields you're about to change. `moveFilesToFolder` originally selected `ContentFolderMember.ChildRecordId` alongside `ParentContentFolderId` even though nothing read `ChildRecordId` — and because that field isn't editable under `WITH USER_MODE`, the later `Database.update` failed on every row with "fields being inaccessible," even though only `ParentContentFolderId` was ever being written. If you add a query ahead of a `WITH USER_MODE` write, select only the fields the write actually needs.

## How this was verified

Every claim above was checked against a real restricted user, not inferred from documentation:

1. Create a `User` on Salesforce's most restrictive real profile, `Minimum Access - Salesforce`.
2. Assign **only** the `LibraryFileManager` permission set — no admin or Standard User baseline.
3. Wrap the actual controller calls in `System.runAs(restrictedUser) { ... }` inside a real `@isTest` method — this is the only valid way to simulate a non-admin user in Apex; anonymous Apex always executes as the CLI-authenticated user regardless of what you write.
4. Add library membership (and, where the operation needs it, a custom delete/organize-capable permission level) incrementally, re-running until the operation succeeds for the right reason.

This is what caught every gap described above — none of them were visible from a System Administrator test run, since an admin's blanket access papers over exactly these failure modes. If you add a new controller method, add a corresponding restricted-user test alongside it rather than only testing as the deploying admin. See `LibraryFileManagerTestHelper.createRestrictedUser()` / `grantLibraryMembership()` / `grantCustomLibraryMembership()` for the reusable helpers, and any test named `*_RestrictedUser` or `*_AuthorCannotDelete` across the test classes for worked examples.

## Known gaps / not yet done

- **DML failure paths under `AccessLevel.USER_MODE` are covered for the happy path, not exhaustively for every partial-failure combination.** The restricted-user tests confirm each operation succeeds when properly permissioned and fails cleanly when it isn't, but don't enumerate every possible partial-success/partial-failure permission combination across bulk operations.
- **No automated CI enforcement of any of this yet.** These are real, passing Apex tests, but nothing currently blocks a PR from removing `WITH USER_MODE`/`as user` or reintroducing a client-reachable bypass without a human noticing in review.
- **The controller is one class.** A future split into Controller/QueryService/MoveService/FolderService (tracked separately, intentionally deferred as higher-risk) would make the security-sensitive surface area smaller and easier to audit per class.

## Reporting a vulnerability

See [SECURITY.md](../SECURITY.md) at the repo root for how to report a security issue privately.
