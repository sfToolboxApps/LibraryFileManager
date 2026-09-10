# Installation Guide

This guide walks through deploying Library File Manager to a Salesforce org, assigning access, and troubleshooting the most common setup issues.

## 1. Prerequisites

- **Salesforce CRM Content must be enabled.** Go to **Setup → Salesforce CRM Content Settings** and enable it. Libraries (`ContentWorkspace`) do not function without this — the app will deploy fine but will be unusable (empty library list, errors creating libraries/folders) if this step is skipped.
- Salesforce CLI (`sf`) installed and authenticated to your target org.
- Deploy access (System Administrator or equivalent) to the target org.

## 2. Deploy the metadata

Clone the repo and deploy with the Salesforce CLI:

```bash
git clone https://github.com/sfToolboxApps/LibraryFileManager.git
cd LibraryFileManager
sf org login web --alias your-org-alias --instance-url https://login.salesforce.com
sf project deploy start --source-dir force-app --target-org your-org-alias
```

This deploys:

- Apex: `LibraryFileManagerController`, plus its tests — `LibraryFileManagerTestHelper`, `LibraryFileManagerLibrariesTest`, `LibraryFileManagerFilesTest`, `LibraryFileManagerMoveTest`, `LibraryFileManagerFolderAndDeleteTest`
- LWC: `libraryFileManager`, `gettingStarted`
- The `LibraryFileManager` custom application, with `Getting_Started` and `LibraryFileManager` tabs
- The `LibraryFileManager` FlexiPages and permission set

If you only want the app's own components (skipping unrelated metadata that may exist elsewhere in the org), scope the deploy to the specific files instead of the whole `force-app` directory — see the file list above.

## 3. Assign the permission set

Every user who needs access must be assigned the **Library File Manager** permission set:

```bash
sf org assign permset --name LibraryFileManager --target-org your-org-alias
```

Or in Setup UI: **Permission Sets → Library File Manager → Manage Assignments → Add Assignment**.

**The permission set alone is not enough — see step 4.** It grants object-level access (create/read/edit/delete on the underlying Content objects), but Salesforce Library _visibility_ is a separate, per-library membership concept that no permission set can grant.

## 4. Add each user as a member of every Library they need access to

This step is **required** and easy to miss, because the app will deploy and the permission set will assign cleanly with no errors — the failure only shows up as an empty library list (or "Library not found" errors) for anyone who isn't a Library member yet, even a System Administrator's own non-admin test users.

Salesforce Libraries (`ContentWorkspace`) restrict visibility to explicit members, tracked as `ContentWorkspaceMember` records — independent of object permissions, profiles, or permission sets. A user with full CRUD on `ContentWorkspace` who isn't a member of a specific library still can't see it.

For each library a user needs to work with:

**Setup UI:** Open the Library in **Salesforce CRM Content Libraries** (or via the standard Files/Libraries UI) → **Library Members** → **Add Member** → select the user and a role.

**Important:** in a stock org, none of the three default library permission levels (**Viewer**, **Author**, **Library Administrator**) have **Delete Content** or **Organize Content and Folders** checked — confirmed by inspecting `ContentWorkspacePermission` directly. That means, out of the box:

- **Viewer** can browse only.
- **Author** can browse and add files, but **cannot** delete files, create folders, or move files between folders using this app.
- **Library Administrator** can manage workspace settings, but — perhaps surprisingly — also doesn't include Delete Content or Organize Content and Folders by default.

To let a user actually delete files, create folders, or move files between folders (the full functionality this app offers), create a **custom** library permission level with **Delete Content** and **Organize Content and Folders** checked (Setup → Salesforce CRM Content Libraries → your library → Permissions, or org-wide under Content Library Permissions), and assign users that level instead of the defaults.

**Or via Apex/Data Loader**, insert a `ContentWorkspaceMember` referencing whichever `ContentWorkspacePermission` you've set up:

```apex
insert new ContentWorkspaceMember(
    ContentWorkspaceId = '<libraryId>',
    MemberId = '<userId>',
    ContentWorkspacePermissionId = '<ContentWorkspacePermission Id>'
);
```

## 5. Add the app to a user's App Launcher

The deploy already creates the standalone **Library File Manager** app (with `Getting_Started` as its default landing tab). Assigned users will find it in the App Launcher immediately. If you'd rather surface the `LibraryFileManager` tab inside an _existing_ custom app instead of using the standalone app, add the tab to that app's tab set via **Setup → App Manager → [Your App] → Edit → Navigation Items**.

## 6. Verify

Open the App Launcher, search for **Library File Manager**, and open it. You should land on the **Getting Started** tab, with the **Library File Manager** tab available in the app's navigation.

---

## Troubleshooting

### The app is empty / "No libraries found" / errors creating a folder

**Cause:** Salesforce CRM Content is not enabled. This is the single most common setup issue.

**Fix:** Setup → Salesforce CRM Content Settings → enable it. This cannot be done via metadata deploy; it's an org setting that must be turned on manually (or via the appropriate Metadata API `Settings` type if you're automating org setup).

### A user has the permission set assigned but sees no libraries (or "Library not found" errors)

**Cause:** the user isn't a member of any Library yet. The permission set grants object-level access, not library visibility — see step 4 above. This is the most common post-deploy surprise, because it produces no error at deploy time or permission-set-assignment time; the app just looks empty for that user.

**Fix:** add the user as a Library member (Viewer or Author) for each library they need — see step 4.

### A user can browse and add files, but Delete Files / Create Folder / Move Files fails

**Cause:** the user's library permission level doesn't include **Delete Content** or **Organize Content and Folders**. None of the three default levels (Viewer, Author, Library Administrator) include either by default — see step 4.

**Fix:** create a custom library permission level with those boxes checked and assign it to the user for that library.

### A user has the permission set assigned but can't see the tab(s)

**Cause:** a permission set's `tabSettings` entry can be set to `Available` instead of `Visible`. `Available` only makes the tab show up in "add tab" pickers — it does **not** put the tab in the user's visible navigation, and does not affect whether a custom application's `defaultLandingTab` is actually reachable for that user. This is easy to miss because the deploy succeeds cleanly either way; the only symptom is the tab silently not appearing for assigned users.

**Fix:** confirm the permission set's `tabSettings` for both `Getting_Started` and `LibraryFileManager` are set to `Visible`, not `Available`:

```xml
<tabSettings>
    <tab>Getting_Started</tab>
    <visibility>Visible</visibility>
</tabSettings>
<tabSettings>
    <tab>LibraryFileManager</tab>
    <visibility>Visible</visibility>
</tabSettings>
```

Redeploy the permission set after fixing.

### Deploy succeeds but Apex tests fail

Run the test classes directly with coverage to see the actual failure:

```bash
sf apex run test --class-names LibraryFileManagerLibrariesTest,LibraryFileManagerFilesTest,LibraryFileManagerMoveTest,LibraryFileManagerFolderAndDeleteTest --code-coverage --target-org your-org-alias --result-format human
```

Most test failures trace back to the CRM Content prerequisite above — several tests create `ContentWorkspace` records, which fail if the feature isn't enabled in the target org.

### Tests fail with "ContentPublication Limit exceeded"

**Cause:** Salesforce enforces an org-wide daily limit on file-publish operations (each `ContentVersion` insert counts against it). This test suite creates several files per run, and repeated runs in the same day — especially alongside demo data seeding — can exhaust it, particularly in Developer Edition/trial orgs.

**Fix:** this isn't a code or config problem; wait for the daily limit to reset (typically 24 hours from first use that day) and re-run. It's unrelated to any other test failure pattern in this guide.

### "MIXED_DML_OPERATION" errors when seeding data via anonymous Apex

`ContentWorkspace` is a Salesforce "setup object." Creating a library and creating folders/files in the _same_ transaction throws `MIXED_DML_OPERATION`. If you're scripting data setup, create libraries in one Apex execution and folders/files in a separate one.
