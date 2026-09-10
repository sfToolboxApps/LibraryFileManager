@isTest
private class LibraryFileManagerMoveTest {
  @isTest
  static void testMoveFilesToLibrary_Success() {
    Map<String, Object> data = LibraryFileManagerTestHelper.createTestLibraries();
    ContentWorkspace lib = (ContentWorkspace) data.get('library');

    Test.startTest();
    List<String> fileIds = LibraryFileManagerTestHelper.createTestFiles(lib.Id);

    LibraryFileManagerController.OperationResult result = LibraryFileManagerController.moveFilesToLibrary(
      fileIds,
      lib.Id
    );
    Test.stopTest();

    System.assert(result.success, 'Should succeed');
  }

  @isTest
  static void testMoveFilesToLibrary_CrossLibrary() {
    Map<String, Object> data = LibraryFileManagerTestHelper.createTestLibraries();
    ContentWorkspace lib = (ContentWorkspace) data.get('library');
    ContentWorkspace lib2 = (ContentWorkspace) data.get('secondaryLibrary');

    Test.startTest();
    List<String> fileIds = LibraryFileManagerTestHelper.createTestFiles(lib.Id);

    LibraryFileManagerController.OperationResult result = LibraryFileManagerController.moveFilesToLibrary(
      fileIds,
      lib2.Id
    );
    Test.stopTest();

    System.assert(result.success, 'Should succeed');
  }

  @isTest
  static void testMoveFilesToFolder() {
    Map<String, Object> data = LibraryFileManagerTestHelper.createTestLibraries();
    ContentWorkspace lib = (ContentWorkspace) data.get('library');
    ContentFolder folder = (ContentFolder) data.get('subFolder');

    if (folder != null) {
      Test.startTest();
      List<String> fileIds = LibraryFileManagerTestHelper.createTestFiles(
        lib.Id
      );

      LibraryFileManagerController.OperationResult result = LibraryFileManagerController.moveFilesToFolder(
        fileIds,
        folder.Id,
        lib.Id
      );
      Test.stopTest();

      System.assertNotEquals(null, result, 'Should return result');
    }
  }

  @isTest
  static void testMoveFilesToFolder_NoMembers() {
    Map<String, Object> data = LibraryFileManagerTestHelper.createTestLibraries();
    ContentWorkspace lib = (ContentWorkspace) data.get('library');
    ContentFolder folder = (ContentFolder) data.get('subFolder');

    if (folder != null) {
      Test.startTest();
      List<String> fileIds = LibraryFileManagerTestHelper.createTestFiles(
        lib.Id
      );

      LibraryFileManagerController.OperationResult result = LibraryFileManagerController.moveFilesToFolder(
        fileIds,
        folder.Id,
        lib.Id
      );
      Test.stopTest();

      System.assertNotEquals(null, result, 'Should handle missing members');
    }
  }

  // Reproduces a real shape found in a customer org: a file can carry a
  // ContentFolderMember row pointing at a folder with no ContentWorkspace at
  // all - e.g. a private/unfiled membership Salesforce creates when a file
  // is first uploaded directly to a record, before ever being filed into a
  // Library, which is never cleaned up once the file is later filed into a
  // real Library. A same-library folder move must skip that row rather than
  // blindly reparenting it and tripping Salesforce's "different root"
  // validation.
  @isTest
  static void testMoveFilesToFolder_SkipsOrphanFolderMembership() {
    Map<String, Object> data = LibraryFileManagerTestHelper.createTestLibraries();
    ContentWorkspace lib = (ContentWorkspace) data.get('library');
    ContentFolder folder = (ContentFolder) data.get('subFolder');

    if (folder != null) {
      List<String> fileIds = LibraryFileManagerTestHelper.createTestFiles(
        lib.Id
      );
      String fileId = fileIds[0];

      ContentFolder orphanRoot;
      User currentUser = [SELECT Id FROM User WHERE Id = :UserInfo.getUserId()];
      System.runAs(currentUser) {
        orphanRoot = new ContentFolder(
          Name = 'OrphanRoot' + System.currentTimeMillis()
        );
        insert orphanRoot;
      }
      insert new ContentFolderMember(
        ParentContentFolderId = orphanRoot.Id,
        ChildRecordId = fileId
      );

      Test.startTest();
      LibraryFileManagerController.OperationResult result = LibraryFileManagerController.moveFilesToFolder(
        fileIds,
        folder.Id,
        lib.Id
      );
      Test.stopTest();

      System.assert(
        result.success,
        'Move should succeed even when the file carries an unrelated orphan folder membership: ' +
        result.errors
      );
      System.assert(
        result.errors.isEmpty(),
        'Should not surface a cross-root error for the orphan row: ' +
        result.errors
      );

      List<ContentFolderMember> membersAfter = [
        SELECT ParentContentFolderId
        FROM ContentFolderMember
        WHERE ChildRecordId = :fileId
      ];
      Set<Id> parentsAfter = new Set<Id>();
      for (ContentFolderMember member : membersAfter) {
        parentsAfter.add(member.ParentContentFolderId);
      }

      System.assertEquals(
        2,
        membersAfter.size(),
        'Both the real and orphan rows should still exist'
      );
      System.assert(
        parentsAfter.contains(orphanRoot.Id),
        'Orphan row must be left untouched, not reparented into the library'
      );
      System.assert(
        parentsAfter.contains(folder.Id),
        'Real library row must have moved to the destination folder'
      );
    }
  }

  // Same hazard as above, exercised through moveFilesToLibrary's root-
  // relocation step (the other place that reparents ContentFolderMember
  // rows without originally scoping to the target library).
  @isTest
  static void testMoveFilesToLibrary_SkipsOrphanFolderMembership() {
    Map<String, Object> data = LibraryFileManagerTestHelper.createTestLibraries();
    ContentWorkspace lib = (ContentWorkspace) data.get('library');

    List<String> fileIds = LibraryFileManagerTestHelper.createTestFiles(lib.Id);
    String fileId = fileIds[0];

    ContentFolder orphanRoot;
    User currentUser = [SELECT Id FROM User WHERE Id = :UserInfo.getUserId()];
    System.runAs(currentUser) {
      orphanRoot = new ContentFolder(
        Name = 'OrphanRoot' + System.currentTimeMillis()
      );
      insert orphanRoot;
    }
    insert new ContentFolderMember(
      ParentContentFolderId = orphanRoot.Id,
      ChildRecordId = fileId
    );

    Test.startTest();
    LibraryFileManagerController.OperationResult result = LibraryFileManagerController.moveFilesToLibrary(
      fileIds,
      lib.Id
    );
    Test.stopTest();

    System.assert(
      result.success,
      'Move should succeed even when the file carries an unrelated orphan folder membership: ' +
      result.errors
    );
    System.assert(
      result.errors.isEmpty(),
      'Should not surface a cross-root error for the orphan row: ' +
      result.errors
    );

    List<ContentFolderMember> membersAfter = [
      SELECT ParentContentFolderId
      FROM ContentFolderMember
      WHERE ChildRecordId = :fileId
    ];
    Set<Id> parentsAfter = new Set<Id>();
    for (ContentFolderMember member : membersAfter) {
      parentsAfter.add(member.ParentContentFolderId);
    }

    System.assert(
      parentsAfter.contains(orphanRoot.Id),
      'Orphan row must be left untouched, not reparented into the library'
    );
  }

  @isTest
  static void testSmartMoveFiles_ToLibrary() {
    Map<String, Object> data = LibraryFileManagerTestHelper.createTestLibraries();
    ContentWorkspace lib = (ContentWorkspace) data.get('library');

    Test.startTest();
    List<String> fileIds = LibraryFileManagerTestHelper.createTestFiles(lib.Id);

    LibraryFileManagerController.OperationResult result = LibraryFileManagerController.smartMoveFiles(
      fileIds,
      lib.Id,
      'library'
    );
    Test.stopTest();

    System.assert(result.success, 'Should succeed');
  }

  @isTest
  static void testSmartMoveFiles_ToFolder() {
    Map<String, Object> data = LibraryFileManagerTestHelper.createTestLibraries();
    ContentWorkspace lib = (ContentWorkspace) data.get('library');
    ContentFolder folder = (ContentFolder) data.get('subFolder');

    if (folder != null) {
      Test.startTest();
      List<String> fileIds = LibraryFileManagerTestHelper.createTestFiles(
        lib.Id
      );

      LibraryFileManagerController.OperationResult result = LibraryFileManagerController.smartMoveFiles(
        fileIds,
        folder.Id,
        'folder'
      );
      Test.stopTest();

      System.assertNotEquals(null, result, 'Should return result');
    }
  }

  @isTest
  static void testExecuteAutomaticCrossLibraryMove_Direct() {
    Map<String, Object> data = LibraryFileManagerTestHelper.createTestLibraries();
    ContentWorkspace lib = (ContentWorkspace) data.get('library');
    ContentWorkspace lib2 = (ContentWorkspace) data.get('secondaryLibrary');
    ContentFolder folder = (ContentFolder) data.get('subFolder');

    if (folder != null) {
      Test.startTest();
      List<String> fileIds = LibraryFileManagerTestHelper.createTestFiles(
        lib.Id
      );

      LibraryFileManagerController.OperationResult result = LibraryFileManagerController.executeAutomaticCrossLibraryMove(
        fileIds,
        lib2.Id,
        folder.Id
      );
      Test.stopTest();

      System.assertNotEquals(null, result, 'Should return result');
    }
  }

  @isTest
  static void testMoveFilesToLibrary_InvalidFileIds() {
    Map<String, Object> data = LibraryFileManagerTestHelper.createTestLibraries();
    ContentWorkspace lib = (ContentWorkspace) data.get('library');

    Test.startTest();
    LibraryFileManagerController.OperationResult result = LibraryFileManagerController.moveFilesToLibrary(
      new List<String>{ '069000000000000' },
      lib.Id
    );
    Test.stopTest();

    System.assert(
      !result.success || result.errors.size() > 0,
      'Should handle invalid files'
    );
  }

  @isTest
  static void testMoveFilesToLibrary_EmptyList() {
    Map<String, Object> data = LibraryFileManagerTestHelper.createTestLibraries();
    ContentWorkspace lib = (ContentWorkspace) data.get('library');

    Test.startTest();
    LibraryFileManagerController.OperationResult result = LibraryFileManagerController.moveFilesToLibrary(
      new List<String>(),
      lib.Id
    );
    Test.stopTest();

    System.assertNotEquals(null, result, 'Should handle empty list');
  }

  @isTest
  static void testMoveFilesToFolder_LibraryMoveFails() {
    Map<String, Object> data = LibraryFileManagerTestHelper.createTestLibraries();
    ContentWorkspace lib = (ContentWorkspace) data.get('library');
    ContentFolder folder = (ContentFolder) data.get('subFolder');
    System.assertNotEquals(
      null,
      folder,
      'Test setup should always create subFolder'
    );

    Test.startTest();
    // A fake ContentDocument Id is not in any library, so moveFilesToFolder's
    // internal moveFilesToLibrary call fails outright, and moveFilesToFolder
    // must return early without ever querying ContentFolderMember.
    LibraryFileManagerController.OperationResult result = LibraryFileManagerController.moveFilesToFolder(
      new List<String>{ '069000000000000' },
      folder.Id,
      lib.Id
    );
    Test.stopTest();

    System.assert(
      !result.success,
      'Should fail when the underlying library move fails'
    );
    System.assert(
      !result.errors.isEmpty(),
      'Should surface the library-move error'
    );
  }

  @isTest
  static void testMoveFilesToFolder_InvalidFolder() {
    Map<String, Object> data = LibraryFileManagerTestHelper.createTestLibraries();
    ContentWorkspace lib = (ContentWorkspace) data.get('library');

    Test.startTest();
    List<String> fileIds = LibraryFileManagerTestHelper.createTestFiles(lib.Id);

    LibraryFileManagerController.OperationResult result = LibraryFileManagerController.moveFilesToFolder(
      fileIds,
      '00l000000000000',
      lib.Id
    );
    Test.stopTest();

    System.assertNotEquals(null, result, 'Should handle invalid folder');
  }

  @isTest
  static void testSmartMoveFiles_InvalidDestination() {
    Map<String, Object> data = LibraryFileManagerTestHelper.createTestLibraries();
    ContentWorkspace lib = (ContentWorkspace) data.get('library');

    Test.startTest();
    List<String> fileIds = LibraryFileManagerTestHelper.createTestFiles(lib.Id);

    LibraryFileManagerController.OperationResult result = LibraryFileManagerController.smartMoveFiles(
      fileIds,
      '00l000000000000',
      'folder'
    );
    Test.stopTest();

    System.assertNotEquals(null, result, 'Should handle invalid destination');
  }

  @isTest
  static void testSmartMoveFiles_InvalidFileIds() {
    Map<String, Object> data = LibraryFileManagerTestHelper.createTestLibraries();
    ContentWorkspace lib = (ContentWorkspace) data.get('library');

    Test.startTest();
    LibraryFileManagerController.OperationResult result = LibraryFileManagerController.smartMoveFiles(
      new List<String>{ '069000000000000' },
      lib.Id,
      'library'
    );
    Test.stopTest();

    System.assert(!result.success, 'Should fail for invalid file IDs');
  }

  @isTest
  static void testExecuteAutomaticCrossLibraryMove_InvalidFiles() {
    Map<String, Object> data = LibraryFileManagerTestHelper.createTestLibraries();
    ContentWorkspace lib = (ContentWorkspace) data.get('library');
    ContentFolder folder = (ContentFolder) data.get('subFolder');

    if (folder != null) {
      Test.startTest();
      LibraryFileManagerController.OperationResult result = LibraryFileManagerController.executeAutomaticCrossLibraryMove(
        new List<String>{ '069000000000000' },
        lib.Id,
        folder.Id
      );
      Test.stopTest();

      System.assert(!result.success, 'Should fail for invalid files');
    }
  }

  @isTest
  static void testMoveFilesToLibrary_AlreadyInTarget() {
    Map<String, Object> data = LibraryFileManagerTestHelper.createTestLibraries();
    ContentWorkspace lib = (ContentWorkspace) data.get('library');

    Test.startTest();
    List<String> fileIds = LibraryFileManagerTestHelper.createTestFiles(lib.Id);

    // Move to same library (already there)
    LibraryFileManagerController.OperationResult result = LibraryFileManagerController.moveFilesToLibrary(
      fileIds,
      lib.Id
    );
    Test.stopTest();

    System.assert(result.success, 'Should succeed when already in library');
    System.assertEquals(3, result.successCount, 'Should count files');
  }

  // Regression test for a real user-reported bug: moving a file from a
  // subfolder to its OWN library's root reported success but never actually
  // moved the file. Root cause: moveFilesToLibrary only updates
  // ContentDocument.ParentId and ContentDocumentLink - it never touched
  // ContentFolderMember. Cross-library moves accidentally masked this
  // because re-parenting to a genuinely different library makes Salesforce
  // auto-create the folder membership there as a side effect; that side
  // effect never fires when the target library is already the current one,
  // since ParentId doesn't actually change.

  @isTest
  static void testMoveFilesToLibrary_FromSubfolderToSameLibraryRoot() {
    Map<String, Object> data = LibraryFileManagerTestHelper.createTestLibraries();
    ContentWorkspace lib = (ContentWorkspace) data.get('library');
    ContentFolder folder = (ContentFolder) data.get('subFolder');
    System.assertNotEquals(
      null,
      folder,
      'Test setup should always create subFolder'
    );

    List<String> fileIds = LibraryFileManagerTestHelper.createTestFiles(lib.Id);

    // Move the files into the subfolder first, to start from the exact
    // scenario that was silently broken.
    List<ContentFolderMember> members = [
      SELECT Id, ChildRecordId, ParentContentFolderId
      FROM ContentFolderMember
      WHERE ChildRecordId IN :fileIds
    ];
    for (ContentFolderMember member : members) {
      member.ParentContentFolderId = folder.Id;
    }
    update members;

    Test.startTest();
    // "Move" to the SAME library (its root) - the exact case that used to
    // be a silent no-op for folder membership.
    LibraryFileManagerController.OperationResult result = LibraryFileManagerController.moveFilesToLibrary(
      fileIds,
      lib.Id
    );
    Test.stopTest();

    System.assert(result.success, 'Should report success');

    List<ContentWorkspace> refreshedLib = [
      SELECT RootContentFolderId
      FROM ContentWorkspace
      WHERE Id = :lib.Id
    ];
    String rootFolderId = refreshedLib[0].RootContentFolderId;

    List<ContentFolderMember> updatedMembers = [
      SELECT ParentContentFolderId
      FROM ContentFolderMember
      WHERE ChildRecordId IN :fileIds
    ];
    System.assertEquals(
      fileIds.size(),
      updatedMembers.size(),
      'All moved files should still have exactly one folder membership'
    );
    for (ContentFolderMember member : updatedMembers) {
      System.assertEquals(
        rootFolderId,
        member.ParentContentFolderId,
        'File "moved" to the library should actually land in the library root, not stay in its old subfolder'
      );
    }
  }

  @isTest
  static void testBulkFileOperations_CrossLibrarySharing() {
    Map<String, Object> data = LibraryFileManagerTestHelper.createTestLibraries();
    ContentWorkspace lib = (ContentWorkspace) data.get('library');
    ContentWorkspace lib2 = (ContentWorkspace) data.get('secondaryLibrary');

    Test.startTest();
    List<String> fileIds = LibraryFileManagerTestHelper.createTestFiles(lib.Id);

    // Test bulk move to same library - should recognize files are already there
    LibraryFileManagerController.OperationResult moveResult = LibraryFileManagerController.moveFilesToLibrary(
      fileIds,
      lib.Id
    );

    System.assert(
      moveResult.success,
      'Bulk move should succeed (files already in library)'
    );
    System.assertEquals(
      3,
      moveResult.successCount,
      'Should count all 3 files as successful'
    );

    // Move to second library - this should add files to second library (sharing)
    LibraryFileManagerController.OperationResult shareResult = LibraryFileManagerController.moveFilesToLibrary(
      fileIds,
      lib2.Id
    );

    System.assert(
      shareResult.success,
      'Share to second library should succeed'
    );
    System.assertEquals(
      3,
      shareResult.successCount,
      'Should add all 3 files to second library'
    );

    // Files should now be accessible from both libraries (sharing model)
    List<ContentDocumentLink> allShares = [
      SELECT ContentDocumentId, LinkedEntityId
      FROM ContentDocumentLink
      WHERE
        ContentDocumentId IN :fileIds
        AND LinkedEntityId IN (SELECT Id FROM ContentWorkspace)
    ];

    System.assert(
      allShares.size() >= 3,
      'Files should be shared across libraries'
    );
    Test.stopTest();
  }

  @isTest
  static void testFileMovement_ContentFolderMemberUpdate() {
    Map<String, Object> data = LibraryFileManagerTestHelper.createTestLibraries();
    ContentWorkspace lib = (ContentWorkspace) data.get('library');
    ContentFolder folder = (ContentFolder) data.get('subFolder');

    if (folder != null) {
      Test.startTest();
      List<String> fileIds = LibraryFileManagerTestHelper.createTestFiles(
        lib.Id
      );

      // Query existing ContentFolderMember records created by ContentDocumentLink
      List<ContentFolderMember> existingMembers = [
        SELECT Id, ChildRecordId, ParentContentFolderId
        FROM ContentFolderMember
        WHERE ChildRecordId IN :fileIds
      ];

      if (!existingMembers.isEmpty()) {
        // UPDATE existing ContentFolderMember records
        for (ContentFolderMember member : existingMembers) {
          member.ParentContentFolderId = folder.Id;
        }
        update existingMembers;

        // Verify the update worked
        List<ContentFolderMember> updatedMembers = [
          SELECT ParentContentFolderId
          FROM ContentFolderMember
          WHERE Id IN :existingMembers
        ];
        System.assertEquals(
          folder.Id,
          updatedMembers[0].ParentContentFolderId,
          'ContentFolderMember should be updated to new folder'
        );
      } else {
        // Test that controller handles missing ContentFolderMember gracefully
        LibraryFileManagerController.OperationResult result = LibraryFileManagerController.smartMoveFiles(
          fileIds,
          folder.Id,
          'folder'
        );

        System.assert(
          result.success || !result.errors.isEmpty(),
          'Should handle missing ContentFolderMember gracefully'
        );
      }
      Test.stopTest();
    }
  }

  @isTest
  static void testMoveFilesToLibrary_FileNotFound() {
    Map<String, Object> data = LibraryFileManagerTestHelper.createTestLibraries();
    ContentWorkspace lib = (ContentWorkspace) data.get('library');

    Test.startTest();
    // Use a properly formatted but non-existent ContentDocument Id.
    LibraryFileManagerController.OperationResult result = LibraryFileManagerController.moveFilesToLibrary(
      new List<String>{ '069000000000000' },
      lib.Id
    );
    Test.stopTest();

    System.assert(
      !result.success || result.errors.size() > 0,
      'Should have error for missing file'
    );
  }

  @isTest
  static void testMoveFilesToFolder_FolderNotInTargetLibrary() {
    Map<String, Object> data = LibraryFileManagerTestHelper.createTestLibraries();
    ContentWorkspace lib = (ContentWorkspace) data.get('library');
    ContentWorkspace lib2 = (ContentWorkspace) data.get('secondaryLibrary');
    ContentFolder folder = (ContentFolder) data.get('subFolder');
    System.assertNotEquals(
      null,
      folder,
      'Test setup should always create subFolder'
    );

    Test.startTest();
    List<String> fileIds = LibraryFileManagerTestHelper.createTestFiles(lib.Id);

    // folder belongs to lib, not lib2 - moveFilesToFolder must reject this
    // combination outright rather than leaving ContentDocument.ParentId and
    // ContentFolderMember.ParentContentFolderId pointing at different libraries.
    LibraryFileManagerController.OperationResult result = LibraryFileManagerController.moveFilesToFolder(
      fileIds,
      folder.Id,
      lib2.Id
    );
    Test.stopTest();

    System.assert(
      !result.success,
      'Should reject a folder that does not belong to the target library'
    );
    System.assert(
      !result.errors.isEmpty(),
      'Should explain why the move was rejected'
    );

    List<ContentDocument> docs = [
      SELECT ParentId
      FROM ContentDocument
      WHERE Id IN :fileIds
    ];
    for (ContentDocument doc : docs) {
      System.assertNotEquals(
        lib2.Id,
        doc.ParentId,
        'Rejected move should not have changed file ownership'
      );
    }
  }

  @isTest
  static void testSmartMoveFiles_FindLibraryForFolder() {
    Map<String, Object> data = LibraryFileManagerTestHelper.createTestLibraries();
    ContentWorkspace lib = (ContentWorkspace) data.get('library');
    ContentFolder folder = (ContentFolder) data.get('subFolder');

    if (folder != null) {
      Test.startTest();
      List<String> fileIds = LibraryFileManagerTestHelper.createTestFiles(
        lib.Id
      );

      // smartMoveFiles must resolve the owning library from the folder Id alone.
      LibraryFileManagerController.OperationResult result = LibraryFileManagerController.smartMoveFiles(
        fileIds,
        folder.Id,
        'folder'
      );
      Test.stopTest();

      System.assertNotEquals(null, result, 'Should complete smart move');
    }
  }

  @isTest
  static void testSmartMoveFiles_DetectCrossLibrary() {
    Map<String, Object> data = LibraryFileManagerTestHelper.createTestLibraries();
    ContentWorkspace lib = (ContentWorkspace) data.get('library');
    ContentWorkspace lib2 = (ContentWorkspace) data.get('secondaryLibrary');

    // Create folder in secondary library
    ContentFolder folder2 = null;
    if (lib2.RootContentFolderId != null) {
      folder2 = new ContentFolder(
        Name = 'SecondaryFolder',
        ParentContentFolderId = lib2.RootContentFolderId
      );
      insert folder2;
    }

    if (folder2 != null) {
      Test.startTest();
      List<String> fileIds = LibraryFileManagerTestHelper.createTestFiles(
        lib.Id
      );

      // Destination folder lives in a different library than the files.
      LibraryFileManagerController.OperationResult result = LibraryFileManagerController.smartMoveFiles(
        fileIds,
        folder2.Id,
        'folder'
      );
      Test.stopTest();

      System.assertNotEquals(
        null,
        result,
        'Should handle cross-library scenario'
      );
    }
  }

  @isTest
  static void testMoveFilesToFolder_RestrictedUser() {
    Map<String, Object> data = LibraryFileManagerTestHelper.createTestLibraries();
    ContentWorkspace lib = (ContentWorkspace) data.get('library');
    ContentFolder folder = (ContentFolder) data.get('subFolder');
    System.assertNotEquals(
      null,
      folder,
      'Test setup should always create subFolder'
    );
    List<String> fileIds = LibraryFileManagerTestHelper.createTestFiles(lib.Id);

    User restrictedUser = LibraryFileManagerTestHelper.createRestrictedUser();
    LibraryFileManagerTestHelper.grantCustomLibraryMembership(
      restrictedUser.Id,
      lib.Id,
      true,
      false,
      true
    );

    Test.startTest();
    LibraryFileManagerController.OperationResult result;
    System.runAs(restrictedUser) {
      result = LibraryFileManagerController.moveFilesToFolder(
        fileIds,
        folder.Id,
        lib.Id
      );
    }
    Test.stopTest();

    System.assert(
      result.success,
      'Restricted user with organize-capable library membership should be able to move files into a folder. Errors: ' +
      String.join(result.errors, ' | ')
    );
  }

  @isTest
  static void testMoveFilesToLibrary_RestrictedUser() {
    Map<String, Object> data = LibraryFileManagerTestHelper.createTestLibraries();
    ContentWorkspace lib = (ContentWorkspace) data.get('library');
    ContentWorkspace lib2 = (ContentWorkspace) data.get('secondaryLibrary');
    List<String> fileIds = LibraryFileManagerTestHelper.createTestFiles(lib.Id);

    User restrictedUser = LibraryFileManagerTestHelper.createRestrictedUser();
    // Cross-library move needs membership in BOTH the source and destination
    // library - the file must be readable/writable in its current library
    // and the destination library must accept the new link.
    LibraryFileManagerTestHelper.grantLibraryMembership(
      restrictedUser.Id,
      lib.Id,
      'Author'
    );
    LibraryFileManagerTestHelper.grantLibraryMembership(
      restrictedUser.Id,
      lib2.Id,
      'Author'
    );

    Test.startTest();
    LibraryFileManagerController.OperationResult result;
    System.runAs(restrictedUser) {
      result = LibraryFileManagerController.moveFilesToLibrary(
        fileIds,
        lib2.Id
      );
    }
    Test.stopTest();

    System.assert(
      result.success,
      'Restricted user with Author membership in both libraries should be able to move files across libraries'
    );
  }
}
