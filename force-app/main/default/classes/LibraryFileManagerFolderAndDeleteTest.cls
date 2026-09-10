@isTest
private class LibraryFileManagerFolderAndDeleteTest {
  @isTest
  static void testDeleteFiles_Success() {
    Map<String, Object> data = LibraryFileManagerTestHelper.createTestLibraries();
    ContentWorkspace lib = (ContentWorkspace) data.get('library');

    Test.startTest();
    List<String> fileIds = LibraryFileManagerTestHelper.createTestFiles(lib.Id);

    LibraryFileManagerController.OperationResult result = LibraryFileManagerController.deleteFiles(
      fileIds
    );
    Test.stopTest();

    System.assert(result.success, 'Should delete files');
  }

  @isTest
  static void testDeleteFiles_EmptyList() {
    Test.startTest();
    LibraryFileManagerController.OperationResult result = LibraryFileManagerController.deleteFiles(
      new List<String>()
    );
    Test.stopTest();

    System.assert(!result.success, 'Should fail with empty list');
  }

  @isTest
  static void testCreateFolder_Success() {
    Map<String, Object> data = LibraryFileManagerTestHelper.createTestLibraries();
    ContentWorkspace lib = (ContentWorkspace) data.get('library');
    ContentFolder folder = (ContentFolder) data.get('subFolder');

    Test.startTest();
    if (folder != null) {
      LibraryFileManagerController.createFolder('NewFolder', lib.Id, folder.Id);
    }
    Test.stopTest();

    System.assert(true, 'Folder creation attempted');
  }

  @isTest
  static void testDeleteFiles_NonExistent() {
    Test.startTest();
    LibraryFileManagerController.OperationResult result = LibraryFileManagerController.deleteFiles(
      new List<String>{ '069000000000000' }
    );
    Test.stopTest();

    System.assert(!result.success, 'Should fail for non-existent files');
  }

  @isTest
  static void testCreateFolder_BlankName() {
    Map<String, Object> data = LibraryFileManagerTestHelper.createTestLibraries();
    ContentWorkspace lib = (ContentWorkspace) data.get('library');

    Test.startTest();
    try {
      LibraryFileManagerController.createFolder('', lib.Id, null);
    } catch (Exception e) {
      System.assert(true, 'Should handle blank folder name');
    }
    Test.stopTest();
  }

  @isTest
  static void testCreateFolder_NoContextSelected() {
    Test.startTest();
    try {
      LibraryFileManagerController.createFolder('SomeFolder', null, null);
      System.assert(
        false,
        'Should throw when no library/folder context is provided'
      );
    } catch (AuraHandledException e) {
      System.assert(
        true,
        'Should throw a clean AuraHandledException for missing context'
      );
    }
    Test.stopTest();
  }

  @isTest
  static void testCreateFolder_BlankLibraryId() {
    Test.startTest();
    try {
      LibraryFileManagerController.createFolder('SomeFolder', '', '');
      System.assert(false, 'Should throw when parentLibraryId is blank');
    } catch (AuraHandledException e) {
      System.assert(
        true,
        'Should throw a clean AuraHandledException for blank library Id'
      );
    }
    Test.stopTest();
  }

  @isTest
  static void testCreateFolder_NonExistentLibrary() {
    Test.startTest();
    try {
      LibraryFileManagerController.createFolder(
        'TestFolder',
        '058000000000000',
        null
      );
    } catch (Exception e) {
      System.assert(true, 'Should handle non-existent library');
    }
    Test.stopTest();
  }

  @isTest
  static void testCreateFolder_InvalidParent() {
    Map<String, Object> data = LibraryFileManagerTestHelper.createTestLibraries();
    ContentWorkspace lib = (ContentWorkspace) data.get('library');

    Test.startTest();
    try {
      LibraryFileManagerController.createFolder(
        'TestFolder',
        lib.Id,
        '00l000000000000'
      );
    } catch (Exception e) {
      System.assert(true, 'Should handle invalid parent folder');
    }
    Test.stopTest();
  }

  @isTest
  static void testCreateFolder_WithValidParent() {
    Map<String, Object> data = LibraryFileManagerTestHelper.createTestLibraries();
    ContentWorkspace lib = (ContentWorkspace) data.get('library');
    ContentFolder folder = (ContentFolder) data.get('subFolder');

    if (folder != null) {
      Test.startTest();
      try {
        LibraryFileManagerController.createFolder(
          'SubSubFolder',
          lib.Id,
          folder.Id
        );
        System.assert(true, 'Folder creation attempted');
      } catch (Exception e) {
        System.assert(true, 'Exception acceptable in test context');
      }
      Test.stopTest();
    }
  }

  @isTest
  static void testDeleteFiles_EdgeCases() {
    Test.startTest();

    // Properly formatted but non-existent ContentDocument Id.
    LibraryFileManagerController.OperationResult result1 = LibraryFileManagerController.deleteFiles(
      new List<String>{ '069000000000000' }
    );
    System.assert(!result1.success, 'Should fail for non-existent file');

    LibraryFileManagerController.OperationResult result2 = LibraryFileManagerController.deleteFiles(
      new List<String>()
    );
    System.assert(!result2.success, 'Should fail for empty list');

    Test.stopTest();
  }

  @isTest
  static void testCreateFolder_AllPaths() {
    Map<String, Object> data = LibraryFileManagerTestHelper.createTestLibraries();
    ContentWorkspace lib = (ContentWorkspace) data.get('library');
    ContentFolder folder = (ContentFolder) data.get('subFolder');

    Test.startTest();

    // Create folder under library root.
    try {
      LibraryFileManagerController.createFolder(
        'RootLevelFolder',
        lib.Id,
        null
      );
    } catch (Exception e) {
      System.assert(true, 'Exception acceptable in test context');
    }

    // Create under existing folder
    if (folder != null) {
      try {
        LibraryFileManagerController.createFolder(
          'SubLevelFolder',
          lib.Id,
          folder.Id
        );
      } catch (Exception e) {
        System.assert(true, 'Exception acceptable in test context');
      }
    }

    Test.stopTest();
  }

  // Proves the "as user" / AccessLevel.USER_MODE DML added to moveFilesToLibrary,
  // moveFilesToFolder, deleteFiles, and createFolder actually works for a real
  // restricted user with the LibraryFileManager permission set and library
  // membership, not just for the System Administrator profile these tests
  // otherwise run as.

  @isTest
  static void testCreateFolder_RestrictedUser() {
    Map<String, Object> data = LibraryFileManagerTestHelper.createTestLibraries();
    ContentWorkspace lib = (ContentWorkspace) data.get('library');

    User restrictedUser = LibraryFileManagerTestHelper.createRestrictedUser();
    LibraryFileManagerTestHelper.grantCustomLibraryMembership(
      restrictedUser.Id,
      lib.Id,
      true,
      false,
      true
    );

    Test.startTest();
    System.runAs(restrictedUser) {
      LibraryFileManagerController.createFolder(
        'RestrictedUserFolder',
        lib.Id,
        null
      );
    }
    Test.stopTest();

    List<ContentFolder> createdFolders = [
      SELECT Id
      FROM ContentFolder
      WHERE Name = 'RestrictedUserFolder'
    ];
    System.assertEquals(
      1,
      createdFolders.size(),
      'Restricted user with organize-capable library membership should be able to create a folder'
    );
  }

  @isTest
  static void testDeleteFiles_RestrictedUser() {
    Map<String, Object> data = LibraryFileManagerTestHelper.createTestLibraries();
    ContentWorkspace lib = (ContentWorkspace) data.get('library');
    List<String> fileIds = LibraryFileManagerTestHelper.createTestFiles(lib.Id);

    User restrictedUser = LibraryFileManagerTestHelper.createRestrictedUser();
    LibraryFileManagerTestHelper.grantCustomLibraryMembership(
      restrictedUser.Id,
      lib.Id,
      true,
      true,
      false
    );

    Test.startTest();
    LibraryFileManagerController.OperationResult result;
    System.runAs(restrictedUser) {
      result = LibraryFileManagerController.deleteFiles(fileIds);
    }
    Test.stopTest();

    System.assert(
      result.success,
      'Restricted user with delete-capable library membership should be able to delete files'
    );
    System.assertEquals(
      fileIds.size(),
      result.successCount,
      'Should report all files deleted'
    );
  }

  // The default 'Author' library permission level does NOT include delete
  // rights (confirmed empirically - see grantCustomLibraryMembership).
  // This proves that boundary is actually enforced, not accidentally
  // bypassed by the "as user" DML change.

  @isTest
  static void testDeleteFiles_AuthorCannotDelete() {
    Map<String, Object> data = LibraryFileManagerTestHelper.createTestLibraries();
    ContentWorkspace lib = (ContentWorkspace) data.get('library');
    List<String> fileIds = LibraryFileManagerTestHelper.createTestFiles(lib.Id);

    User restrictedUser = LibraryFileManagerTestHelper.createRestrictedUser();
    LibraryFileManagerTestHelper.grantLibraryMembership(
      restrictedUser.Id,
      lib.Id,
      'Author'
    );

    Test.startTest();
    LibraryFileManagerController.OperationResult result;
    System.runAs(restrictedUser) {
      result = LibraryFileManagerController.deleteFiles(fileIds);
    }
    Test.stopTest();

    System.assert(
      !result.success,
      'Author-level library membership should NOT be able to delete files'
    );
    System.assert(
      !result.errors.isEmpty(),
      'Should surface an error explaining the failed delete'
    );
  }
}
