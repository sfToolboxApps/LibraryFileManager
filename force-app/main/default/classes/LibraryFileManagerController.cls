/**
 * @description Apex controller backing the libraryFileManager LWC. Lists Salesforce
 * Libraries (ContentWorkspace) and their folders, browses files within them, moves
 * files within and across libraries, creates folders, and deletes files.
 *
 * Runs entirely under the calling user's actual permissions - WITH USER_MODE on reads,
 * "as user" / AccessLevel.USER_MODE on writes - rather than as the deploying admin. See
 * docs/security.md for the full access-control model (a permission set alone is not
 * sufficient; Library membership and Library permission level are separate, data-only
 * requirements no permission set can grant) and docs/architecture.md for how the public
 * methods below relate to each other, in particular the smartMoveFiles routing logic.
 *
 * @license MIT - see LICENSE
 */
public with sharing class LibraryFileManagerController {
  // Library folders are eagerly built for the tree UI only this many levels
  // deep, as a UI/performance cap - not a Salesforce platform limit. Folders
  // nested deeper simply won't appear in the tree, but remain fully reachable
  // by direct navigation (their breadcrumbs/path use FOLDER_PATH_SAFETY_LIMIT
  // below, not this).
  private static final Integer FOLDER_TREE_BUILD_MAX_DEPTH = 5;

  // Safety valve (not a real expected depth) for the folder-to-root walks
  // used by breadcrumbs/path/library-lookup, guarding against an
  // unexpectedly deep or cyclic ParentContentFolderId chain running away.
  // Deliberately higher than FOLDER_TREE_BUILD_MAX_DEPTH since these walks
  // must reach the true root for any folder, not just the ones shown in the
  // eagerly-built tree.
  private static final Integer FOLDER_PATH_SAFETY_LIMIT = 10;

  /**
   * @description Lists every Library the running user can see, with each Library's
   * full folder tree and per-folder file counts, loaded eagerly in one call - there is
   * no separate lazy per-folder fetch (see docs/architecture.md for why). The org's
   * built-in system Asset Library is excluded (matched by WorkspaceType, not by name).
   * @return One LibraryWrapper per visible Library. Empty list if the user has no
   * visible Libraries (not an error - see docs/security.md on Library membership
   * being required separately from object permissions).
   * @throws AuraHandledException if the underlying query fails.
   */
  @AuraEnabled(cacheable=false)
  public static List<LibraryWrapper> getLibrariesWithFolders() {
    try {
      // WorkspaceType 'B' is the org's single built-in Asset Library - a system
      // workspace, not a regular user-created one ('R'). Filtering on this type
      // code (rather than the display Name, which any user library could also
      // be named) is what actually distinguishes it reliably.
      List<ContentWorkspace> workspaces = [
        SELECT Id, Name, Description, RootContentFolderId
        FROM ContentWorkspace
        WHERE WorkspaceType != 'B'
        WITH USER_MODE
        ORDER BY Name
      ];

      if (workspaces.isEmpty()) {
        return new List<LibraryWrapper>();
      }

      // Collect root folder IDs per workspace in bulk (no per-workspace SOQL)
      Map<String, String> workspaceToRootFolder = new Map<String, String>();
      Set<Id> workspacesWithoutRoot = new Set<Id>();
      Set<String> allRootFolderIds = new Set<String>();

      for (ContentWorkspace ws : workspaces) {
        if (ws.RootContentFolderId != null) {
          workspaceToRootFolder.put(ws.Id, ws.RootContentFolderId);
          allRootFolderIds.add(ws.RootContentFolderId);
        } else {
          workspacesWithoutRoot.add(ws.Id);
        }
      }

      if (!workspacesWithoutRoot.isEmpty()) {
        for (ContentFolderLink link : [
          SELECT ContentFolderId, ParentEntityId
          FROM ContentFolderLink
          WHERE ParentEntityId IN :workspacesWithoutRoot
          WITH USER_MODE
        ]) {
          workspaceToRootFolder.put(link.ParentEntityId, link.ContentFolderId);
          allRootFolderIds.add(link.ContentFolderId);
        }
      }

      // Load full folder hierarchy (plus per-folder file counts) for ALL
      // libraries in bulk - shared with getFoldersForLibrary below so both
      // build the tree the exact same way.
      Map<String, ContentFolder> allFoldersMap = new Map<String, ContentFolder>();
      Map<String, Integer> folderFileCounts = new Map<String, Integer>();
      loadFolderHierarchyWithCounts(
        allRootFolderIds,
        allFoldersMap,
        folderFileCounts
      );

      // Build wrappers from in-memory maps — no more SOQL per library
      List<LibraryWrapper> libraries = new List<LibraryWrapper>();
      for (ContentWorkspace workspace : workspaces) {
        LibraryWrapper library = new LibraryWrapper();
        library.id = workspace.Id;
        library.name = workspace.Id;
        library.label = workspace.Name;
        library.expanded = false;

        String rootFolderId = workspaceToRootFolder.get(workspace.Id);
        if (rootFolderId != null) {
          Integer rootFileCount = folderFileCounts.get(rootFolderId);
          library.fileCount = rootFileCount != null ? rootFileCount : 0;
        }

        if (rootFolderId != null && allFoldersMap.containsKey(rootFolderId)) {
          ContentFolder rootFolder = allFoldersMap.get(rootFolderId);
          if (rootFolder.Name == workspace.Id) {
            library.items = getSubFoldersFromMap(
              rootFolderId,
              allFoldersMap,
              folderFileCounts
            );
          } else {
            FolderWrapper fw = new FolderWrapper();
            fw.name = rootFolder.Id;
            Integer fc = folderFileCounts.get(rootFolder.Id);
            fw.label = formatFolderLabel(rootFolder.Name, fc != null ? fc : 0);
            fw.expanded = false;
            fw.items = getSubFoldersFromMap(
              rootFolder.Id,
              allFoldersMap,
              folderFileCounts
            );
            library.items = new List<FolderWrapper>{ fw };
          }
        } else {
          library.items = new List<FolderWrapper>();
        }
        libraries.add(library);
      }

      return libraries;
    } catch (Exception e) {
      throw new AuraHandledException(
        'Error loading libraries: ' + e.getMessage()
      );
    }
  }

  /**
   * @description Returns the folder tree for a single Library. Used less often than
   * getLibrariesWithFolders (which returns every Library's tree in one bulk call); kept
   * for callers that only need one Library's folders.
   * @param libraryId Either the Library's Id or its Name - resolved server-side.
   * @return The Library's top-level folders, each with its own nested subfolders.
   * @throws AuraHandledException if libraryId is blank or doesn't resolve to a Library
   * the running user can see.
   */
  @AuraEnabled
  public static List<FolderWrapper> getLibraryFolders(String libraryId) {
    // Input validation
    if (String.isBlank(libraryId)) {
      throw new AuraHandledException('Library ID cannot be blank');
    }

    try {
      // Accept either Id or Name for libraryId
      String resolvedLibraryId = libraryId;
      if (!isValidId(libraryId)) {
        String tryId = resolveLibraryNameToId(libraryId);
        if (tryId == null) {
          throw new AuraHandledException(
            'Library not found for Id or Name: ' + libraryId
          );
        }
        resolvedLibraryId = tryId;
      }

      // Validate library exists
      List<ContentWorkspace> libraries = [
        SELECT Id
        FROM ContentWorkspace
        WHERE Id = :resolvedLibraryId
        WITH USER_MODE
        LIMIT 1
      ];
      if (libraries.isEmpty()) {
        throw new AuraHandledException(
          'Library not found for Id: ' + resolvedLibraryId
        );
      }

      return getFoldersForLibrary(resolvedLibraryId);
    } catch (QueryException e) {
      throw new AuraHandledException(
        'Library not found for Id or Name: ' + libraryId
      );
    } catch (AuraHandledException e) {
      throw e;
    } catch (Exception e) {
      throw new AuraHandledException(
        'Library not found for Id or Name: ' + libraryId
      );
    }
  }

  /**
   * @description Lists the files (and subfolder rows, so the file table can show
   * folders inline) at a given location.
   * @param libraryId Either the Library's Id or its Name - resolved server-side.
   * @param folderId Either a ContentFolder's Id or Name, a Library Id (treated as that
   * Library's root), or blank (the given libraryId's root). Resolved server-side.
   * @return Files/subfolders at that location, plus the resolved path and breadcrumbs.
   * @throws AuraHandledException if libraryId is blank, or either Id/Name doesn't
   * resolve to something the running user can see.
   */
  @AuraEnabled
  public static FileListWrapper getFilesInFolder(
    String libraryId,
    String folderId
  ) {
    return getFilesInFolderCore(libraryId, folderId, false);
  }

  // Test-only entry point for exercising the isTestRootFolder branch below.
  // Not @AuraEnabled - client code can never reach this, only Apex tests can
  // (via @TestVisible), so it can't be used to bypass library validation.
  @TestVisible
  private static FileListWrapper getFilesInFolderTestHook(
    String libraryId,
    String folderId
  ) {
    return getFilesInFolderCore(libraryId, folderId, true);
  }

  private static FileListWrapper getFilesInFolderCore(
    String libraryId,
    String folderId,
    Boolean isTestRootFolder
  ) {
    try {
      FileListWrapper result = new FileListWrapper();

      // Null safety checks
      if (String.isBlank(libraryId)) {
        throw new AuraHandledException('Library ID cannot be null or empty');
      }

      // Validate and resolve IDs
      if (!isValidId(libraryId)) {
        String resolvedId = resolveLibraryNameToId(libraryId);
        if (resolvedId == null) {
          throw new AuraHandledException(
            'No library found for name: ' + libraryId
          );
        }
        libraryId = resolvedId;
      }

      if (!String.isBlank(folderId) && !isValidId(folderId)) {
        String resolvedFolderId = resolveFolderNameToId(folderId, libraryId);
        if (resolvedFolderId == null) {
          throw new AuraHandledException(
            'No folder found for name: ' +
              folderId +
              ' in library: ' +
              libraryId
          );
        }
        folderId = resolvedFolderId;
      }

      if (isTestRootFolder && !String.isBlank(folderId)) {
        // Test hook: treat folderId as the root folder
        List<ContentFolder> folders = [
          SELECT Id, Name
          FROM ContentFolder
          WHERE Id = :folderId
          WITH USER_MODE
          LIMIT 1
        ];
        if (folders.isEmpty()) {
          result.files = new List<FileWrapper>();
          result.path = '';
          result.breadcrumbs = new List<BreadcrumbWrapper>();
          return result;
        }

        try {
          List<FileWrapper> hookRows = getSubfolderRows(folderId);
          hookRows.addAll(getFilesInContentFolder(folderId));
          result.files = hookRows;
        } catch (Exception e) {
          result.files = new List<FileWrapper>();
        }

        try {
          result.path = getFolderPath(folderId);
        } catch (Exception e) {
          result.path = '';
        }

        try {
          result.breadcrumbs = buildBreadcrumbs(folderId);
        } catch (Exception e) {
          result.breadcrumbs = new List<BreadcrumbWrapper>();
        }

        return result;
      }

      // Check library exists
      List<ContentWorkspace> libraries = [
        SELECT Id, Name
        FROM ContentWorkspace
        WHERE Id = :libraryId
        WITH USER_MODE
        LIMIT 1
      ];
      if (libraries.isEmpty()) {
        throw new AuraHandledException(
          'ContentWorkspace (library) not found for Id: ' + libraryId
        );
      }

      if (String.isBlank(folderId)) {
        // Library root
        List<FileWrapper> rootRows = getSubfolderRows(
          getRootFolderId(libraryId)
        );
        rootRows.addAll(getFilesInLibraryRoot(libraryId));
        result.files = rootRows;
        result.path = getLibraryName(libraryId);
        result.breadcrumbs = new List<BreadcrumbWrapper>{
          new BreadcrumbWrapper(libraryId, getLibraryName(libraryId), true)
        };
      } else {
        // Check if folderId is actually a library Id
        List<ContentWorkspace> libs = [
          SELECT Id
          FROM ContentWorkspace
          WHERE Id = :folderId
          WITH USER_MODE
          LIMIT 1
        ];
        if (!libs.isEmpty()) {
          List<FileWrapper> libRootRows = getSubfolderRows(
            getRootFolderId(folderId)
          );
          libRootRows.addAll(getFilesInLibraryRoot(folderId));
          result.files = libRootRows;
          result.path = getLibraryName(folderId);
          result.breadcrumbs = new List<BreadcrumbWrapper>{
            new BreadcrumbWrapper(folderId, getLibraryName(folderId), true)
          };
        } else {
          // ContentFolder
          List<FileWrapper> folderRows = getSubfolderRows(folderId);
          folderRows.addAll(getFilesInContentFolder(folderId));
          result.files = folderRows;
          result.path = getFolderPath(folderId);
          result.breadcrumbs = buildBreadcrumbs(folderId);
        }
      }

      return result;
    } catch (Exception e) {
      throw new AuraHandledException('Error loading files: ' + e.getMessage());
    }
  }

  /**
   * @description Moves files into a Library - adding them if they aren't already
   * linked there, transferring ownership (ContentDocument.ParentId), removing links to
   * any other Libraries, and explicitly relocating each file's folder membership to the
   * target Library's root folder (even when the file is already in that Library - see
   * the "moving a file to its own library's root silently failed" entry in
   * CHANGELOG.md for why this step is explicit rather than left to a Salesforce
   * side-effect). Prefer smartMoveFiles from client code; this method doesn't know
   * about destination folders.
   * @param fileIds ContentDocument Ids to move.
   * @param targetLibraryId The destination Library's Id.
   * @return success true if at least one file ended up in the target Library.
   * Per-file failures (e.g. a non-existent ContentDocument Id) are reported in errors
   * without failing the whole batch.
   */
  @AuraEnabled
  public static OperationResult moveFilesToLibrary(
    List<String> fileIds,
    String targetLibraryId
  ) {
    OperationResult result = new OperationResult();
    result.errors = new List<String>();

    try {
      // Get current library associations
      Map<String, List<ContentDocumentLink>> fileToLinksMap = new Map<String, List<ContentDocumentLink>>();
      // Get workspace IDs first
      Set<Id> workspaceIds = new Set<Id>();
      for (ContentWorkspace ws : [
        SELECT Id
        FROM ContentWorkspace
        WITH USER_MODE
      ]) {
        workspaceIds.add(ws.Id);
      }

      // Scoped to library (ContentWorkspace) links only - a file can also be
      // linked to non-library records (e.g. a Case or Account), and those
      // links must be left untouched by a library move.
      List<ContentDocumentLink> allCurrentLinks = [
        SELECT Id, ContentDocumentId, LinkedEntityId
        FROM ContentDocumentLink
        WHERE ContentDocumentId IN :fileIds AND LinkedEntityId IN :workspaceIds
        WITH USER_MODE
      ];

      for (ContentDocumentLink link : allCurrentLinks) {
        if (!fileToLinksMap.containsKey(link.ContentDocumentId)) {
          fileToLinksMap.put(
            link.ContentDocumentId,
            new List<ContentDocumentLink>()
          );
        }
        fileToLinksMap.get(link.ContentDocumentId).add(link);
      }

      // Process each file - TRUE MOVE LOGIC
      List<ContentDocumentLink> linksToAdd = new List<ContentDocumentLink>();
      List<ContentDocumentLink> linksToRemove = new List<ContentDocumentLink>();
      List<ContentDocument> documentsToUpdate = new List<ContentDocument>();
      Integer alreadyInTargetCount = 0;
      Integer trueMovesCount = 0;

      for (String fileId : fileIds) {
        // Validate ContentDocument exists
        List<ContentDocument> docs = [
          SELECT Id, ParentId
          FROM ContentDocument
          WHERE Id = :fileId
          WITH USER_MODE
        ];
        if (docs.isEmpty()) {
          result.errors.add('ContentDocument not found for Id: ' + fileId);
          continue;
        }

        ContentDocument doc = docs[0];
        List<ContentDocumentLink> fileLinks = fileToLinksMap.get(fileId);
        Boolean alreadyInTarget = false;

        if (fileLinks != null) {
          for (ContentDocumentLink link : fileLinks) {
            if (link.LinkedEntityId == targetLibraryId) {
              alreadyInTarget = true;
              alreadyInTargetCount++;
              break;
            }
          }
        }

        if (!alreadyInTarget) {
          // Add to target library
          linksToAdd.add(
            new ContentDocumentLink(
              ContentDocumentId = fileId,
              LinkedEntityId = targetLibraryId,
              ShareType = 'I'
            )
          );
        }

        // Always update ParentId to transfer ownership
        documentsToUpdate.add(
          new ContentDocument(Id = fileId, ParentId = targetLibraryId)
        );

        // Collect links to remove from other libraries
        if (fileLinks != null) {
          for (ContentDocumentLink link : fileLinks) {
            if (link.LinkedEntityId != targetLibraryId) {
              linksToRemove.add(link);
              trueMovesCount++;
            }
          }
        }
      }

      // Order matters here for partial-failure safety: link the file into the
      // new library and transfer ownership *before* removing the old library
      // link, so a failure partway through leaves the file still accessible
      // in its original library rather than orphaned with no library link at all.

      // 1. Add to new library first
      if (!linksToAdd.isEmpty()) {
        insert as user linksToAdd;
        result.successCount += linksToAdd.size();
      }

      // 2. Transfer ownership
      if (!documentsToUpdate.isEmpty()) {
        update as user documentsToUpdate;
      }

      // 3. Now safely remove from old libraries
      if (!linksToRemove.isEmpty()) {
        Database.DeleteResult[] deleteResults = Database.delete(
          linksToRemove,
          false,
          AccessLevel.USER_MODE
        );

        for (Integer i = 0; i < deleteResults.size(); i++) {
          if (!deleteResults[i].isSuccess()) {
            result.errors.add(
              'Failed to remove file from library: ' +
              deleteResults[i].getErrors()[0].getMessage()
            );
          }
        }
      }

      // Explicitly land every file in the target library's root folder.
      // Re-parenting ContentDocument to a genuinely different library makes
      // Salesforce auto-create the folder membership there as a side effect,
      // which is what made this look like it worked in the cross-library
      // case - but that's undocumented platform behavior, not something this
      // method actually did, and it never fires at all when the file is
      // already in the target library (moving from a subfolder up to that
      // same library's root): ParentId doesn't change, so nothing moves the
      // file's ContentFolderMember out of whatever subfolder it was already
      // in, even though the move reports success.
      String targetRootFolderId = getRootFolderId(targetLibraryId);
      if (!String.isBlank(targetRootFolderId)) {
        List<ContentFolderMember> membersToRelocate = [
          SELECT Id, ParentContentFolderId
          FROM ContentFolderMember
          WHERE ChildRecordId IN :fileIds
          WITH USER_MODE
        ];
        List<ContentFolderMember> membersToUpdate = new List<ContentFolderMember>();
        for (ContentFolderMember member : membersToRelocate) {
          if (member.ParentContentFolderId != targetRootFolderId) {
            member.ParentContentFolderId = targetRootFolderId;
            membersToUpdate.add(member);
          }
        }
        if (!membersToUpdate.isEmpty()) {
          Database.update(membersToUpdate, false, AccessLevel.USER_MODE);
        }
      }

      result.successCount += alreadyInTargetCount;
      result.success = result.successCount > 0;

      if (trueMovesCount > 0) {
        result.warnings.add(
          trueMovesCount + ' files moved completely to target library.'
        );
      }

      return result;
    } catch (Exception e) {
      result.success = false;
      result.errors.add('Error moving files to library: ' + e.getMessage());
      return result;
    }
  }

  /**
   * @description Moves files into a specific folder. Rejects the request outright,
   * before any DML, if targetFolderId doesn't actually belong to targetLibraryId - see
   * the "Destination consistency is validated, not assumed" note in
   * docs/security.md. If the files aren't already in targetLibraryId, calls
   * moveFilesToLibrary first. Prefer smartMoveFiles from client code, which resolves
   * targetLibraryId from targetFolderId automatically and detects cross-library moves.
   * @param fileIds ContentDocument Ids to move.
   * @param targetFolderId The destination ContentFolder's Id.
   * @param targetLibraryId The Id of the Library targetFolderId must belong to.
   * @return success true if at least one file's folder membership was updated.
   * partialSuccess true if some but not all files succeeded.
   */
  @AuraEnabled
  public static OperationResult moveFilesToFolder(
    List<String> fileIds,
    String targetFolderId,
    String targetLibraryId
  ) {
    OperationResult result = new OperationResult();
    result.errors = new List<String>();

    try {
      // Reject before any DML if the destination folder doesn't actually
      // belong to the destination library. Without this check, the two
      // parameters could disagree (e.g. a stale client-side selection) and
      // leave ContentDocument.ParentId pointing at one library while
      // ContentFolderMember.ParentContentFolderId points at a folder in
      // another.
      String actualLibraryForFolder = findLibraryForFolder(targetFolderId);
      if (
        actualLibraryForFolder == null ||
        actualLibraryForFolder != targetLibraryId
      ) {
        result.success = false;
        result.errors.add(
          'Target folder does not belong to the target library.'
        );
        return result;
      }

      // Ensure files are in target library first
      List<String> filesToMoveLibrary = new List<String>();
      Map<String, String> fileToLibraryMap = getCurrentLibrariesForFiles(
        fileIds
      );

      for (String fileId : fileIds) {
        String currentLibrary = fileToLibraryMap.get(fileId);
        if (currentLibrary != targetLibraryId) {
          filesToMoveLibrary.add(fileId);
        }
      }

      if (!filesToMoveLibrary.isEmpty()) {
        OperationResult libraryMoveResult = moveFilesToLibrary(
          filesToMoveLibrary,
          targetLibraryId
        );
        if (!libraryMoveResult.success) {
          result.errors.addAll(libraryMoveResult.errors);
          result.success = false;
          return result;
        }
      }

      // Move to folder using ContentFolderMember UPDATE pattern. Only select
      // the fields actually read/written below - ChildRecordId isn't
      // editable under WITH USER_MODE, and including it here (even though
      // its value is never changed) makes the later Database.update fail
      // with "fields being inaccessible" for every row.
      List<ContentFolderMember> existingMembers = [
        SELECT Id, ParentContentFolderId
        FROM ContentFolderMember
        WHERE ChildRecordId IN :fileIds
        WITH USER_MODE
      ];

      if (!existingMembers.isEmpty()) {
        for (ContentFolderMember member : existingMembers) {
          member.ParentContentFolderId = targetFolderId;
        }

        Database.SaveResult[] updateResults = Database.update(
          existingMembers,
          false,
          AccessLevel.USER_MODE
        );
        Integer successCount = 0;

        for (Integer i = 0; i < updateResults.size(); i++) {
          if (updateResults[i].isSuccess()) {
            successCount++;
          } else {
            result.errors.add(
              'Failed to move file to folder: ' +
              updateResults[i].getErrors()[0].getMessage()
            );
          }
        }

        result.successCount = successCount;
        result.success = successCount > 0;

        if (successCount < existingMembers.size()) {
          result.partialSuccess = true;
          result.warnings.add(
            successCount +
              ' of ' +
              existingMembers.size() +
              ' files moved to folder successfully.'
          );
        }
      } else {
        result.success = false;
        result.errors.add(
          'No folder associations found for files. Files may need time to process in the library before folder organization.'
        );
        result.warnings.add(
          'Try refreshing and moving to folder again in a few moments.'
        );
      }

      return result;
    } catch (Exception e) {
      result.success = false;
      result.errors.add('Error moving files to folder: ' + e.getMessage());
      return result;
    }
  }

  /**
   * @description The single move entry point the LWC actually calls - client code
   * never decides directly between moveFilesToLibrary/moveFilesToFolder/
   * executeAutomaticCrossLibraryMove. Routes to the right one based on destinationType
   * and, for a folder destination, whether the files currently live in a different
   * Library than the target folder (in which case it runs the cross-library sequence
   * automatically). See docs/architecture.md for the full decision tree.
   * @param fileIds ContentDocument Ids to move.
   * @param destinationId A Library Id (when destinationType is "library") or a
   * ContentFolder Id (when "folder").
   * @param destinationType "library" or "folder".
   * @return The OperationResult from whichever underlying move method actually ran -
   * same shape regardless of which one it was.
   */
  @AuraEnabled
  public static OperationResult smartMoveFiles(
    List<String> fileIds,
    String destinationId,
    String destinationType
  ) {
    OperationResult result = new OperationResult();

    try {
      if (destinationType == 'library') {
        result = moveFilesToLibrary(fileIds, destinationId);
      } else if (destinationType == 'folder') {
        // Validate files exist
        for (String fileId : fileIds) {
          List<ContentDocument> docs = [
            SELECT Id
            FROM ContentDocument
            WHERE Id = :fileId
            WITH USER_MODE
          ];
          if (docs.isEmpty()) {
            result.errors.add('ContentDocument not found for Id: ' + fileId);
            result.success = false;
            return result;
          }
        }

        // Find target library for folder
        String targetLibraryId = findLibraryForFolder(destinationId);
        if (targetLibraryId == null) {
          result.success = false;
          result.errors.add('Unable to determine target library for folder.');
          return result;
        }

        // Check if cross-library move needed
        Map<String, String> fileCurrentLibraries = getCurrentLibrariesForFiles(
          fileIds
        );
        Boolean needsCrossLibraryMove = false;

        for (String currentLibrary : fileCurrentLibraries.values()) {
          if (currentLibrary != null && currentLibrary != targetLibraryId) {
            needsCrossLibraryMove = true;
            break;
          }
        }

        if (needsCrossLibraryMove) {
          result = executeAutomaticCrossLibraryMove(
            fileIds,
            targetLibraryId,
            destinationId
          );
        } else {
          result = moveFilesToFolder(fileIds, destinationId, targetLibraryId);
        }
      }

      return result;
    } catch (Exception e) {
      result.success = false;
      result.errors.add('Error in smart move: ' + e.getMessage());
      return result;
    }
  }

  /**
   * @description Runs a cross-library move as one operation: moveFilesToLibrary, then
   * moveFilesToFolder, reported as a single OperationResult. If moving to the folder
   * fails after the library move already succeeded, that's reported as a
   * partialSuccess (the files are in the right Library, just not organized into the
   * requested folder) rather than an overall failure - the files are never left
   * stranded. Reached via smartMoveFiles when a folder destination requires a Library
   * change; not normally called directly from client code.
   * @param fileIds ContentDocument Ids to move.
   * @param targetLibraryId The destination Library's Id.
   * @param targetFolderId The destination ContentFolder's Id, within that Library.
   * @return success true once the Library move succeeds, regardless of whether the
   * folder step also succeeds - see partialSuccess/warnings for that detail.
   */
  @AuraEnabled
  public static OperationResult executeAutomaticCrossLibraryMove(
    List<String> fileIds,
    String targetLibraryId,
    String targetFolderId
  ) {
    OperationResult result = new OperationResult();
    result.errors = new List<String>();

    try {
      // Step 1: Move to target library
      OperationResult libraryMoveResult = moveFilesToLibrary(
        fileIds,
        targetLibraryId
      );

      if (!libraryMoveResult.success) {
        result.success = false;
        result.errors.add(
          'Step 1 Failed - Could not move files to target library: ' +
          String.join(libraryMoveResult.errors, '; ')
        );
        return result;
      }

      // Step 2: Move to folder
      OperationResult folderMoveResult = moveFilesToFolder(
        fileIds,
        targetFolderId,
        targetLibraryId
      );

      if (folderMoveResult.success) {
        result.success = true;
        result.successCount = libraryMoveResult.successCount;
        result.warnings.add(
          'Cross-library move completed successfully. Files moved to target library and organized into folder.'
        );

        if (libraryMoveResult.partialSuccess) {
          result.partialSuccess = true;
          result.warnings.add(
            'Note: Some files may remain accessible in original libraries due to Salesforce ownership rules.'
          );
        }
      } else {
        result.success = true;
        result.partialSuccess = true;
        result.successCount = libraryMoveResult.successCount;
        result.warnings.add(
          'Files successfully moved to target library, but folder organization encountered issues: ' +
          String.join(folderMoveResult.errors, '; ')
        );
        result.warnings.add(
          'Files should appear in the target library root and may automatically organize into the folder after a few moments.'
        );
      }

      return result;
    } catch (Exception e) {
      result.success = false;
      result.errors.add(
        'Error in automatic cross-library move: ' + e.getMessage()
      );
      return result;
    }
  }

  /**
   * @description Permanently deletes the given files' underlying ContentDocument
   * records - not just their association with the current Library. If a file is
   * shared across multiple Libraries or linked to other records, this removes it
   * everywhere (subject to the org's recycle bin retention). There is no "remove
   * from this Library only" option; see the README's Delete Files warning.
   * @param fileIds ContentDocument Ids to delete.
   * @return success true if at least one document was found and deleted.
   */
  @AuraEnabled
  public static OperationResult deleteFiles(List<String> fileIds) {
    OperationResult result = new OperationResult();
    result.errors = new List<String>();

    try {
      List<ContentDocument> documentsToDelete = [
        SELECT Id
        FROM ContentDocument
        WHERE Id IN :fileIds
        WITH USER_MODE
      ];

      if (!documentsToDelete.isEmpty()) {
        delete as user documentsToDelete;
        result.success = true;
        result.successCount = documentsToDelete.size();
      } else {
        result.errors.add('No files found to delete.');
        result.success = false;
      }

      return result;
    } catch (Exception e) {
      result.success = false;
      result.errors.add('Error deleting files: ' + e.getMessage());
      return result;
    }
  }

  /**
   * @description Creates a folder at a Library's root (parentFolderId blank) or nested
   * under another folder. Requires a Library permission level with "Organize Content
   * and Folders" checked - the standard Viewer/Author/Library Administrator defaults do
   * not include it; see docs/security.md.
   * @param folderName The new folder's name.
   * @param parentLibraryId The Library to create the folder in. Required even when
   * parentFolderId is set, as a defense-in-depth guard against being called with no
   * context (the LWC's Create Folder button is disabled until one is selected, but this
   * checks again server-side).
   * @param parentFolderId The folder to nest the new folder under, or blank to create
   * it at the Library root.
   * @throws AuraHandledException if parentLibraryId is blank, the Library doesn't
   * exist, or the folder can't be created (including a clearer message for the
   * MIXED_DML_OPERATION case when this runs in the same transaction as a Library-level
   * operation).
   */
  @AuraEnabled
  public static void createFolder(
    String folderName,
    String parentLibraryId,
    String parentFolderId
  ) {
    // Defense in depth: the LWC button that calls this is disabled until a library
    // or folder is selected, but guard here too in case this is ever invoked from
    // somewhere else with no context.
    if (String.isBlank(parentLibraryId)) {
      throw new AuraHandledException(
        'Please select a library or folder before creating a folder.'
      );
    }

    try {
      ContentFolder newFolder = new ContentFolder();
      newFolder.Name = folderName;

      if (String.isBlank(parentFolderId)) {
        // Creating folder under library root
        List<ContentWorkspace> workspaces = [
          SELECT Id, RootContentFolderId
          FROM ContentWorkspace
          WHERE Id = :parentLibraryId
          WITH USER_MODE
          LIMIT 1
        ];

        if (workspaces.isEmpty()) {
          throw new AuraHandledException(
            'Library not found for Id: ' + parentLibraryId
          );
        }

        ContentWorkspace workspace = workspaces[0];

        if (workspace.RootContentFolderId != null) {
          newFolder.ParentContentFolderId = workspace.RootContentFolderId;
        } else {
          // Query for auto-created root folder
          List<ContentFolder> rootFolders = [
            SELECT Id
            FROM ContentFolder
            WHERE Name = :parentLibraryId
            WITH USER_MODE
            LIMIT 1
          ];

          if (!rootFolders.isEmpty()) {
            newFolder.ParentContentFolderId = rootFolders[0].Id;
          } else {
            newFolder.ParentContentFolderId = null;
          }
        }
      } else {
        // Creating subfolder
        newFolder.ParentContentFolderId = parentFolderId;
      }

      insert as user newFolder;
    } catch (Exception e) {
      if (e.getMessage().contains('MIXED_DML_OPERATION')) {
        throw new AuraHandledException(
          'Cannot create folder in same transaction as library operations. Please try again.'
        );
      } else {
        throw new AuraHandledException(
          'Error creating folder: ' + e.getMessage()
        );
      }
    }
  }

  // Helper Methods

  private static List<FolderWrapper> getFoldersForLibrary(String libraryId) {
    List<FolderWrapper> folders = new List<FolderWrapper>();

    try {
      Set<String> rootFolderIds = new Set<String>();

      // Get root folders via ContentWorkspace
      ContentWorkspace workspace = [
        SELECT Id, RootContentFolderId
        FROM ContentWorkspace
        WHERE Id = :libraryId
        WITH USER_MODE
        LIMIT 1
      ];

      if (workspace.RootContentFolderId != null) {
        rootFolderIds.add(workspace.RootContentFolderId);
      }

      // Fallback via ContentFolderLink
      if (rootFolderIds.isEmpty()) {
        for (ContentFolderLink link : [
          SELECT ContentFolderId
          FROM ContentFolderLink
          WHERE ParentEntityId = :libraryId
          WITH USER_MODE
        ]) {
          rootFolderIds.add(link.ContentFolderId);
        }
      }

      // Get folder hierarchy (plus per-folder file counts) - shared with
      // getLibrariesWithFolders above so both build the tree the same way.
      if (!rootFolderIds.isEmpty()) {
        Map<String, ContentFolder> allFoldersMap = new Map<String, ContentFolder>();
        Map<String, Integer> folderFileCounts = new Map<String, Integer>();
        loadFolderHierarchyWithCounts(
          rootFolderIds,
          allFoldersMap,
          folderFileCounts
        );

        // Build folder tree
        for (String rootFolderId : rootFolderIds) {
          if (allFoldersMap.containsKey(rootFolderId)) {
            ContentFolder rootFolder = allFoldersMap.get(rootFolderId);

            if (rootFolder.Name == libraryId) {
              // Skip root folder, show children
              List<FolderWrapper> subFolders = getSubFoldersFromMap(
                rootFolder.Id,
                allFoldersMap,
                folderFileCounts
              );
              folders.addAll(subFolders);
            } else {
              FolderWrapper folderWrapper = new FolderWrapper();
              folderWrapper.name = rootFolder.Id;
              Integer fileCount = folderFileCounts.get(rootFolder.Id);
              if (fileCount == null)
                fileCount = 0;
              folderWrapper.label = formatFolderLabel(
                rootFolder.Name,
                fileCount
              );
              folderWrapper.expanded = false;
              folderWrapper.items = getSubFoldersFromMap(
                rootFolder.Id,
                allFoldersMap,
                folderFileCounts
              );
              folders.add(folderWrapper);
            }
          }
        }
      }
    } catch (Exception e) {
      // Return empty list on error
    }

    return folders;
  }

  // Loads the folder hierarchy (up to FOLDER_TREE_BUILD_MAX_DEPTH levels)
  // rooted at rootFolderIds, plus per-folder file counts, into the two output
  // maps (Apex passes collections by reference, so mutating them here mutates
  // the caller's maps). Shared by getLibrariesWithFolders (bulk, all
  // libraries at once) and getFoldersForLibrary (single library) so both
  // build the tree exactly the same way instead of maintaining two copies of
  // this logic.
  private static void loadFolderHierarchyWithCounts(
    Set<String> rootFolderIds,
    Map<String, ContentFolder> allFoldersMap,
    Map<String, Integer> folderFileCounts
  ) {
    Set<String> foldersToQuery = new Set<String>(rootFolderIds);
    Set<String> processedFolders = new Set<String>();

    for (
      Integer level = 0;
      level < FOLDER_TREE_BUILD_MAX_DEPTH && !foldersToQuery.isEmpty();
      level++
    ) {
      List<ContentFolder> batch = [
        SELECT Id, Name, ParentContentFolderId
        FROM ContentFolder
        WHERE Id IN :foldersToQuery OR ParentContentFolderId IN :foldersToQuery
        WITH USER_MODE
        ORDER BY Name
      ];
      Set<String> nextLevel = new Set<String>();
      for (ContentFolder f : batch) {
        allFoldersMap.put(f.Id, f);
        if (!processedFolders.contains(f.Id)) {
          nextLevel.add(f.Id);
        }
      }
      processedFolders.addAll(foldersToQuery);
      foldersToQuery = nextLevel;
      foldersToQuery.removeAll(processedFolders);
    }

    if (!allFoldersMap.isEmpty()) {
      try {
        for (AggregateResult ar : [
          SELECT ParentContentFolderId, COUNT(Id) fileCount
          FROM ContentFolderMember
          WHERE ParentContentFolderId IN :allFoldersMap.keySet()
          WITH USER_MODE
          GROUP BY ParentContentFolderId
        ]) {
          folderFileCounts.put(
            (String) ar.get('ParentContentFolderId'),
            (Integer) ar.get('fileCount')
          );
        }
      } catch (Exception e) {
        // Continue without file counts
      }
    }
  }

  private static List<FolderWrapper> getSubFoldersFromMap(
    String parentFolderId,
    Map<String, ContentFolder> allFoldersMap,
    Map<String, Integer> folderFileCounts
  ) {
    List<FolderWrapper> subFolders = new List<FolderWrapper>();

    for (ContentFolder folder : allFoldersMap.values()) {
      if (folder.ParentContentFolderId == parentFolderId) {
        FolderWrapper folderWrapper = new FolderWrapper();
        folderWrapper.name = folder.Id;

        Integer fileCount = folderFileCounts.get(folder.Id);
        if (fileCount == null)
          fileCount = 0;

        folderWrapper.label = formatFolderLabel(folder.Name, fileCount);
        folderWrapper.expanded = false;
        folderWrapper.items = getSubFoldersFromMap(
          folder.Id,
          allFoldersMap,
          folderFileCounts
        );
        subFolders.add(folderWrapper);
      }
    }

    return subFolders;
  }

  private static String formatFolderLabel(
    String folderName,
    Integer fileCount
  ) {
    return folderName +
      ' (' +
      fileCount +
      ' file' +
      (fileCount == 1 ? '' : 's') +
      ')';
  }

  private static Map<String, String> getCurrentLibrariesForFiles(
    List<String> fileIds
  ) {
    Map<String, String> fileToLibraryMap = new Map<String, String>();

    try {
      // Get workspace IDs first
      Set<Id> workspaceIds = new Set<Id>();
      for (ContentWorkspace ws : [
        SELECT Id
        FROM ContentWorkspace
        WITH USER_MODE
      ]) {
        workspaceIds.add(ws.Id);
      }

      // Same library-only scoping as moveFilesToLibrary - links to non-library
      // records are irrelevant to "which library is this file currently in".
      for (ContentDocumentLink link : [
        SELECT ContentDocumentId, LinkedEntityId
        FROM ContentDocumentLink
        WHERE ContentDocumentId IN :fileIds AND LinkedEntityId IN :workspaceIds
        WITH USER_MODE
      ]) {
        fileToLibraryMap.put(link.ContentDocumentId, link.LinkedEntityId);
      }
    } catch (Exception e) {
      // Return empty map
    }

    return fileToLibraryMap;
  }

  private static String findLibraryForFolder(String folderId) {
    try {
      // Check if folderId is actually a library
      List<ContentWorkspace> libs = [
        SELECT Id
        FROM ContentWorkspace
        WHERE Id = :folderId
        WITH USER_MODE
        LIMIT 1
      ];
      if (!libs.isEmpty()) {
        return folderId;
      }

      // Traverse folder hierarchy to root
      String currentFolderId = folderId;
      String rootFolderId = null;
      Integer safety = 0;

      while (currentFolderId != null && safety++ < FOLDER_PATH_SAFETY_LIMIT) {
        List<ContentFolder> folders = [
          SELECT Id, ParentContentFolderId
          FROM ContentFolder
          WHERE Id = :currentFolderId
          WITH USER_MODE
          LIMIT 1
        ];

        if (folders.isEmpty()) {
          break;
        }

        ContentFolder folder = folders[0];
        if (folder.ParentContentFolderId == null) {
          rootFolderId = folder.Id;
          break;
        }
        currentFolderId = folder.ParentContentFolderId;
      }

      if (rootFolderId != null) {
        // Find via ContentFolderLink
        List<ContentFolderLink> links = [
          SELECT ParentEntityId
          FROM ContentFolderLink
          WHERE ContentFolderId = :rootFolderId
          WITH USER_MODE
          LIMIT 1
        ];
        if (!links.isEmpty()) {
          return links[0].ParentEntityId;
        }

        // Fallback via RootContentFolderId
        List<ContentWorkspace> workspaces = [
          SELECT Id
          FROM ContentWorkspace
          WHERE RootContentFolderId = :rootFolderId
          WITH USER_MODE
          LIMIT 1
        ];
        if (!workspaces.isEmpty()) {
          return workspaces[0].Id;
        }
      }
    } catch (Exception e) {
      // Return null
    }

    return null;
  }

  private static List<FileWrapper> getFilesInLibraryRoot(String libraryId) {
    List<FileWrapper> files = new List<FileWrapper>();

    try {
      String rootFolderId = getRootFolderId(libraryId);
      if (String.isBlank(rootFolderId)) {
        return files;
      }

      // Folder-scoped: only files whose ContentFolderMember points at the library's root folder
      Set<String> documentIds = new Set<String>();
      for (ContentFolderMember member : [
        SELECT ChildRecordId
        FROM ContentFolderMember
        WHERE ParentContentFolderId = :rootFolderId
        WITH USER_MODE
      ]) {
        documentIds.add(member.ChildRecordId);
      }

      if (documentIds.isEmpty()) {
        return files;
      }

      List<ContentVersion> versions = [
        SELECT
          ContentDocumentId,
          Title,
          FileExtension,
          ContentSize,
          LastModifiedDate,
          Owner.Name
        FROM ContentVersion
        WHERE ContentDocumentId IN :documentIds AND IsLatest = TRUE
        WITH USER_MODE
        ORDER BY Title
      ];

      for (ContentVersion version : versions) {
        FileWrapper file = new FileWrapper();
        file.id = version.ContentDocumentId;
        file.title = version.Title;
        file.fileExtension = version.FileExtension != null
          ? version.FileExtension
          : '';
        file.formattedSize = formatFileSize(version.ContentSize);
        file.contentSize = version.ContentSize;
        file.lastModifiedDate = version.LastModifiedDate;
        file.ownerName = version.Owner.Name;
        file.iconName = getFileIcon(version.FileExtension);
        files.add(file);
      }
    } catch (Exception e) {
      // Return empty list
    }

    return files;
  }

  private static String getRootFolderId(String libraryId) {
    try {
      List<ContentWorkspace> workspaces = [
        SELECT RootContentFolderId
        FROM ContentWorkspace
        WHERE Id = :libraryId
        WITH USER_MODE
        LIMIT 1
      ];
      if (!workspaces.isEmpty()) {
        return workspaces[0].RootContentFolderId;
      }
    } catch (Exception e) {
      // Return null
    }
    return null;
  }

  private static List<FileWrapper> getSubfolderRows(String parentFolderId) {
    List<FileWrapper> rows = new List<FileWrapper>();
    if (String.isBlank(parentFolderId)) {
      return rows;
    }
    try {
      for (ContentFolder folder : [
        SELECT Id, Name
        FROM ContentFolder
        WHERE ParentContentFolderId = :parentFolderId
        WITH USER_MODE
        ORDER BY Name
      ]) {
        FileWrapper row = new FileWrapper();
        row.id = folder.Id;
        row.title = folder.Name;
        row.isFolder = true;
        row.fileExtension = '';
        row.formattedSize = '';
        row.iconName = 'standard:folder';
        rows.add(row);
      }
    } catch (Exception e) {
      // Return whatever we have
    }
    return rows;
  }

  private static List<FileWrapper> getFilesInContentFolder(String folderId) {
    try {
      List<ContentFolder> folders = [
        SELECT Id, Name
        FROM ContentFolder
        WHERE Id = :folderId
        WITH USER_MODE
        LIMIT 1
      ];
      if (folders.isEmpty()) {
        return new List<FileWrapper>();
      }

      List<FileWrapper> files = new List<FileWrapper>();
      List<ContentFolderMember> members = [
        SELECT ChildRecordId
        FROM ContentFolderMember
        WHERE ParentContentFolderId = :folderId
        WITH USER_MODE
      ];

      if (members.isEmpty()) {
        return files;
      }

      Set<String> documentIds = new Set<String>();
      for (ContentFolderMember member : members) {
        documentIds.add(member.ChildRecordId);
      }

      if (documentIds.isEmpty()) {
        return files;
      }

      List<ContentVersion> versions = [
        SELECT
          ContentDocumentId,
          Title,
          FileExtension,
          ContentSize,
          LastModifiedDate,
          Owner.Name
        FROM ContentVersion
        WHERE ContentDocumentId IN :documentIds AND IsLatest = TRUE
        WITH USER_MODE
        ORDER BY Title
      ];

      for (ContentVersion version : versions) {
        FileWrapper file = new FileWrapper();
        file.id = version.ContentDocumentId;
        file.title = version.Title;
        file.fileExtension = version.FileExtension != null
          ? version.FileExtension
          : '';
        file.formattedSize = formatFileSize(version.ContentSize);
        file.contentSize = version.ContentSize;
        file.lastModifiedDate = version.LastModifiedDate;
        file.ownerName = version.Owner.Name;
        file.iconName = getFileIcon(version.FileExtension);
        files.add(file);
      }

      return files;
    } catch (Exception e) {
      return new List<FileWrapper>();
    }
  }

  private static String getLibraryName(String libraryId) {
    try {
      ContentWorkspace workspace = [
        SELECT Name
        FROM ContentWorkspace
        WHERE Id = :libraryId
        WITH USER_MODE
        LIMIT 1
      ];
      return workspace.Name;
    } catch (Exception e) {
      return 'Unknown Library';
    }
  }

  private static String getFolderPath(String folderId) {
    try {
      List<String> pathParts = new List<String>();
      String currentFolderId = folderId;
      Integer safety = 0;

      while (currentFolderId != null && safety++ < FOLDER_PATH_SAFETY_LIMIT) {
        List<ContentFolder> folders = [
          SELECT Name, ParentContentFolderId
          FROM ContentFolder
          WHERE Id = :currentFolderId
          WITH USER_MODE
          LIMIT 1
        ];

        if (folders.isEmpty()) {
          break;
        }

        ContentFolder folder = folders[0];
        pathParts.add(0, folder.Name);

        if (folder.ParentContentFolderId == null) {
          break;
        }
        currentFolderId = folder.ParentContentFolderId;
      }

      String libraryId = findLibraryForFolder(folderId);
      if (libraryId != null) {
        String libraryName = getLibraryName(libraryId);
        if (libraryName != 'Unknown Library') {
          pathParts.add(0, libraryName);
        }
      }

      return String.join(pathParts, ' > ');
    } catch (Exception e) {
      return 'Unknown Path';
    }
  }

  private static List<BreadcrumbWrapper> buildBreadcrumbs(String folderId) {
    List<BreadcrumbWrapper> breadcrumbs = new List<BreadcrumbWrapper>();

    try {
      String currentFolderId = folderId;
      Integer safety = 0;

      while (currentFolderId != null && safety++ < FOLDER_PATH_SAFETY_LIMIT) {
        List<ContentFolder> folders = [
          SELECT Name, ParentContentFolderId
          FROM ContentFolder
          WHERE Id = :currentFolderId
          WITH USER_MODE
          LIMIT 1
        ];

        if (folders.isEmpty()) {
          return breadcrumbs;
        }

        ContentFolder folder = folders[0];
        breadcrumbs.add(
          0,
          new BreadcrumbWrapper(currentFolderId, folder.Name, false)
        );

        if (folder.ParentContentFolderId == null) {
          break;
        }
        currentFolderId = folder.ParentContentFolderId;
      }

      String libraryId = findLibraryForFolder(folderId);
      if (libraryId != null) {
        String libraryName = getLibraryName(libraryId);
        if (libraryName != 'Unknown Library') {
          breadcrumbs.add(
            0,
            new BreadcrumbWrapper(libraryId, libraryName, false)
          );
        }
      }

      if (!breadcrumbs.isEmpty()) {
        breadcrumbs[breadcrumbs.size() - 1].isLast = true;
      }
    } catch (Exception e) {
      // Return what we have
    }

    return breadcrumbs;
  }

  private static String formatFileSize(Integer bytes) {
    if (bytes == null)
      return '0 B';

    if (bytes < 1024)
      return bytes + ' B';
    if (bytes < 1024 * 1024)
      return String.valueOf(bytes / 1024) + ' KB';
    if (bytes < 1024 * 1024 * 1024)
      return String.valueOf(bytes / (1024 * 1024)) + ' MB';
    return String.valueOf(bytes / (1024 * 1024 * 1024)) + ' GB';
  }

  private static String getFileIcon(String fileExtension) {
    if (String.isBlank(fileExtension))
      return 'doctype:unknown';

    String ext = fileExtension.toLowerCase();
    if (ext == 'pdf')
      return 'doctype:pdf';
    if (ext == 'doc' || ext == 'docx')
      return 'doctype:word';
    if (ext == 'xls' || ext == 'xlsx')
      return 'doctype:excel';
    if (ext == 'ppt' || ext == 'pptx')
      return 'doctype:ppt';
    if (ext == 'jpg' || ext == 'jpeg' || ext == 'png' || ext == 'gif')
      return 'doctype:image';
    if (ext == 'txt')
      return 'doctype:txt';
    if (ext == 'zip' || ext == 'rar')
      return 'doctype:zip';
    return 'doctype:unknown';
  }

  // Helper: Validate Salesforce ID format
  private static Boolean isValidId(String s) {
    if (String.isBlank(s))
      return false;
    if (s.length() != 15 && s.length() != 18)
      return false;
    String pattern = '^[a-zA-Z0-9]{15,18}$';
    System.Pattern p = System.Pattern.compile(pattern);
    System.Matcher m = p.matcher(s);
    return m.matches();
  }

  // Helper: Resolve library name to ID
  private static String resolveLibraryNameToId(String name) {
    if (String.isBlank(name))
      return null;
    List<ContentWorkspace> libs = [
      SELECT Id
      FROM ContentWorkspace
      WHERE Name = :name
      WITH USER_MODE
      LIMIT 1
    ];
    if (!libs.isEmpty())
      return libs[0].Id;
    return null;
  }

  // Helper: Resolve folder name to ID
  private static String resolveFolderNameToId(
    String folderName,
    String libraryId
  ) {
    if (String.isBlank(folderName) || String.isBlank(libraryId))
      return null;

    List<ContentWorkspace> libs = [
      SELECT RootContentFolderId
      FROM ContentWorkspace
      WHERE Id = :libraryId
      WITH USER_MODE
      LIMIT 1
    ];
    if (!libs.isEmpty()) {
      String rootFolderId = libs[0].RootContentFolderId;
      if (rootFolderId != null) {
        List<ContentFolder> folders = [
          SELECT Id
          FROM ContentFolder
          WHERE Name = :folderName AND ParentContentFolderId = :rootFolderId
          WITH USER_MODE
          LIMIT 1
        ];
        if (!folders.isEmpty())
          return folders[0].Id;
      }
    }

    List<ContentFolder> allFolders = [
      SELECT Id
      FROM ContentFolder
      WHERE
        Name = :folderName
        AND Id IN (
          SELECT ContentFolderId
          FROM ContentFolderLink
          WHERE ParentEntityId = :libraryId
        )
      WITH USER_MODE
      LIMIT 1
    ];
    if (!allFolders.isEmpty())
      return allFolders[0].Id;

    List<ContentFolder> anyFolders = [
      SELECT Id
      FROM ContentFolder
      WHERE Name = :folderName
      WITH USER_MODE
      LIMIT 1
    ];
    if (!anyFolders.isEmpty())
      return anyFolders[0].Id;

    return null;
  }

  // Wrapper Classes - ALL PUBLIC

  /** @description A single Library (ContentWorkspace) node in the tree, with its folder subtree already attached. */
  public class LibraryWrapper {
    @AuraEnabled
    public String name;
    @AuraEnabled
    public String label;
    @AuraEnabled
    public String id;
    @AuraEnabled
    public Boolean expanded;
    @AuraEnabled
    public List<FolderWrapper> items;
    @AuraEnabled
    public Integer fileCount;

    public LibraryWrapper() {
      this.items = new List<FolderWrapper>();
      this.fileCount = 0;
    }
  }

  /** @description A single folder (ContentFolder) node in the tree, recursively nesting its own subfolders. */
  public class FolderWrapper {
    @AuraEnabled
    public String name;
    @AuraEnabled
    public String label;
    @AuraEnabled
    public Boolean expanded;
    @AuraEnabled
    public List<FolderWrapper> items;

    public FolderWrapper() {
      this.items = new List<FolderWrapper>();
    }
  }

  /** @description A single row in the file table - either a real file (a ContentVersion's latest metadata) or, when isFolder is true, a subfolder shown inline. */
  public class FileWrapper {
    @AuraEnabled
    public String id;
    @AuraEnabled
    public String title;
    @AuraEnabled
    public String fileExtension;
    @AuraEnabled
    public String formattedSize;
    @AuraEnabled
    public Integer contentSize;
    @AuraEnabled
    public DateTime lastModifiedDate;
    @AuraEnabled
    public String ownerName;
    @AuraEnabled
    public String iconName;
    @AuraEnabled
    public Boolean isFolder = false;
  }

  /** @description The result of getFilesInFolder - a location's files/subfolders plus its resolved display path and breadcrumb trail. */
  public class FileListWrapper {
    @AuraEnabled
    public List<FileWrapper> files;
    @AuraEnabled
    public String path;
    @AuraEnabled
    public List<BreadcrumbWrapper> breadcrumbs;

    public FileListWrapper() {
      this.files = new List<FileWrapper>();
      this.breadcrumbs = new List<BreadcrumbWrapper>();
    }
  }

  /** @description A single crumb in a location's breadcrumb trail, root-to-leaf order; isLast marks the final (current) crumb. */
  public class BreadcrumbWrapper {
    @AuraEnabled
    public String id;
    @AuraEnabled
    public String label;
    @AuraEnabled
    public Boolean isLast;

    public BreadcrumbWrapper(String id, String label, Boolean isLast) {
      this.id = id;
      this.label = label;
      this.isLast = isLast;
    }
  }

  /** @description The common result shape for every move/delete operation, so client code has one result-handling path regardless of which method actually ran (see the smartMoveFiles decision tree in docs/architecture.md). partialSuccess means some but not all files succeeded; check errors/warnings for detail either way. */
  public class OperationResult {
    @AuraEnabled
    public Boolean success;
    @AuraEnabled
    public Boolean partialSuccess;
    @AuraEnabled
    public Integer successCount;
    @AuraEnabled
    public List<String> errors;
    @AuraEnabled
    public List<String> warnings;

    public OperationResult() {
      this.success = false;
      this.partialSuccess = false;
      this.successCount = 0;
      this.errors = new List<String>();
      this.warnings = new List<String>();
    }
  }
}
