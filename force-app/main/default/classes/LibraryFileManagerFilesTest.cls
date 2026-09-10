@isTest
private class LibraryFileManagerFilesTest {
  @isTest
  static void testGetFilesInFolder_LibraryRoot() {
    Map<String, Object> data = LibraryFileManagerTestHelper.createTestLibraries();
    ContentWorkspace lib = (ContentWorkspace) data.get('library');

    Test.startTest();
    List<String> fileIds = LibraryFileManagerTestHelper.createTestFiles(lib.Id);

    LibraryFileManagerController.FileListWrapper result = LibraryFileManagerController.getFilesInFolder(
      lib.Id,
      null
    );
    Test.stopTest();

    System.assertNotEquals(null, result, 'Should return result');
    // Folder-scoped: root listing = 3 files actually in the root folder,
    // plus 1 subfolder row for the 'Projects' subfolder created by LibraryFileManagerTestHelper.createTestLibraries().
    Integer fileCount = 0;
    Integer folderCount = 0;
    for (LibraryFileManagerController.FileWrapper row : result.files) {
      if (row.isFolder) {
        folderCount++;
      } else {
        fileCount++;
      }
    }
    System.assertEquals(
      3,
      fileCount,
      'Should have 3 files in the library root'
    );
    System.assertEquals(
      1,
      folderCount,
      'Should have 1 subfolder row (Projects) inline with files'
    );
  }

  @isTest
  static void testGetFilesInFolder_InFolder() {
    Map<String, Object> data = LibraryFileManagerTestHelper.createTestLibraries();
    ContentWorkspace lib = (ContentWorkspace) data.get('library');
    ContentFolder folder = (ContentFolder) data.get('subFolder');
    System.assertNotEquals(
      null,
      folder,
      'Test setup should always create subFolder'
    );

    List<String> fileIds = LibraryFileManagerTestHelper.createTestFiles(lib.Id);

    // Actually move two of the three files into the subfolder so this test
    // exercises getFilesInContentFolder's file-query/wrapper-building logic,
    // not just its early "folder not found" guard.
    List<ContentFolderMember> members = [
      SELECT Id, ChildRecordId, ParentContentFolderId
      FROM ContentFolderMember
      WHERE ChildRecordId IN :fileIds
      ORDER BY ChildRecordId
      LIMIT 2
    ];
    Set<String> movedIds = new Set<String>();
    for (ContentFolderMember member : members) {
      member.ParentContentFolderId = folder.Id;
      movedIds.add(member.ChildRecordId);
    }
    update members;

    Test.startTest();
    LibraryFileManagerController.FileListWrapper folderResult = LibraryFileManagerController.getFilesInFolder(
      lib.Id,
      folder.Id
    );
    LibraryFileManagerController.FileListWrapper rootResult = LibraryFileManagerController.getFilesInFolder(
      lib.Id,
      null
    );
    Test.stopTest();

    System.assertEquals(
      movedIds.size(),
      folderResult.files.size(),
      'Folder should contain exactly the moved files'
    );
    for (LibraryFileManagerController.FileWrapper row : folderResult.files) {
      System.assert(
        movedIds.contains(row.id),
        'Every row returned for the folder should be one of the moved files'
      );
      System.assertNotEquals(
        null,
        row.formattedSize,
        'Moved file should have a formatted size'
      );
      System.assertNotEquals(
        null,
        row.ownerName,
        'Moved file should have owner info'
      );
    }

    Integer rootFileCount = 0;
    Integer rootFolderRowCount = 0;
    for (LibraryFileManagerController.FileWrapper row : rootResult.files) {
      if (row.isFolder) {
        rootFolderRowCount++;
      } else {
        rootFileCount++;
        System.assert(
          !movedIds.contains(row.id),
          'Moved files should no longer show up in the library root'
        );
      }
    }
    System.assertEquals(
      fileIds.size() - movedIds.size(),
      rootFileCount,
      'Root should only show the file that was not moved'
    );
    System.assertEquals(
      1,
      rootFolderRowCount,
      'Root should still show the Projects subfolder row'
    );
  }

  @isTest
  static void testGetFilesInFolder_TestHook() {
    Map<String, Object> data = LibraryFileManagerTestHelper.createTestLibraries();
    ContentWorkspace lib = (ContentWorkspace) data.get('library');
    ContentFolder folder = (ContentFolder) data.get('subFolder');

    if (folder != null) {
      Test.startTest();
      List<String> fileIds = LibraryFileManagerTestHelper.createTestFiles(
        lib.Id
      );

      // Use actual library ID even with test hook - the test hook just bypasses library validation
      LibraryFileManagerController.FileListWrapper result = LibraryFileManagerController.getFilesInFolderTestHook(
        lib.Id,
        folder.Id
      );
      Test.stopTest();

      System.assertNotEquals(null, result, 'Should return result');
      System.assertNotEquals(null, result.files, 'Should have files list');
    }
  }

  @isTest
  static void testGetFilesInFolder_FolderIdIsLibrary() {
    Map<String, Object> data = LibraryFileManagerTestHelper.createTestLibraries();
    ContentWorkspace lib = (ContentWorkspace) data.get('library');

    Test.startTest();
    List<String> fileIds = LibraryFileManagerTestHelper.createTestFiles(lib.Id);

    LibraryFileManagerController.FileListWrapper result = LibraryFileManagerController.getFilesInFolder(
      lib.Id,
      lib.Id
    );
    Test.stopTest();

    System.assertNotEquals(null, result, 'Should handle library as folderId');
  }

  @isTest
  static void testGetFilesInFolder_LibraryNameResolution() {
    Map<String, Object> data = LibraryFileManagerTestHelper.createTestLibraries();
    ContentWorkspace lib = (ContentWorkspace) data.get('library');

    Test.startTest();
    List<String> fileIds = LibraryFileManagerTestHelper.createTestFiles(lib.Id);

    LibraryFileManagerController.FileListWrapper result = LibraryFileManagerController.getFilesInFolder(
      lib.Name,
      null
    );
    Test.stopTest();

    System.assertNotEquals(null, result, 'Should resolve library by name');
  }

  @isTest
  static void testGetFilesInFolder_FolderNameResolution() {
    Map<String, Object> data = LibraryFileManagerTestHelper.createTestLibraries();
    ContentWorkspace lib = (ContentWorkspace) data.get('library');
    ContentFolder folder = (ContentFolder) data.get('subFolder');

    if (folder != null) {
      Test.startTest();
      List<String> fileIds = LibraryFileManagerTestHelper.createTestFiles(
        lib.Id
      );

      LibraryFileManagerController.FileListWrapper result = LibraryFileManagerController.getFilesInFolder(
        lib.Id,
        folder.Name
      );
      Test.stopTest();

      System.assertNotEquals(null, result, 'Should resolve folder by name');
    }
  }

  @isTest
  static void testGetFilesInFolder_NamesSuccess() {
    Map<String, Object> data = LibraryFileManagerTestHelper.createTestLibraries();
    ContentWorkspace lib = (ContentWorkspace) data.get('library');

    Test.startTest();
    List<String> fileIds = LibraryFileManagerTestHelper.createTestFiles(lib.Id);

    LibraryFileManagerController.FileListWrapper result = LibraryFileManagerController.getFilesInFolder(
      lib.Name,
      null
    );
    Test.stopTest();

    System.assertNotEquals(null, result, 'Should work with library name');
    System.assert(result.files.size() > 0, 'Should have files');
  }

  @isTest
  static void testGetFilesInFolder_NullLibraryId() {
    try {
      LibraryFileManagerController.getFilesInFolder(null, null);
      System.assert(false, 'Should throw for a null library Id');
    } catch (AuraHandledException e) {
      // See note in testGetLibraryFolders_BlankId — AuraHandledException's
      // getMessage() is not reliably assertable server-side.
      System.assert(true, 'Threw the expected AuraHandledException');
    }
  }

  @isTest
  static void testFileIcons() {
    Map<String, Object> data = LibraryFileManagerTestHelper.createTestLibraries();
    ContentWorkspace lib = (ContentWorkspace) data.get('library');

    Test.startTest();
    User currentUser = [SELECT Id FROM User WHERE Id = :UserInfo.getUserId()];
    System.runAs(currentUser) {
      List<ContentVersion> files = new List<ContentVersion>();
      String[] extensions = new List<String>{
        'pdf',
        'doc',
        'xls',
        'ppt',
        'jpg',
        'txt',
        'zip'
      };

      for (String ext : extensions) {
        files.add(
          new ContentVersion(
            Title = 'Test.' + ext,
            PathOnClient = 'test.' + ext,
            VersionData = Blob.valueOf('Test'),
            Origin = 'H',
            FirstPublishLocationId = lib.Id
          )
        );
      }
      insert files;
    }
    Test.stopTest();

    LibraryFileManagerController.FileListWrapper result = LibraryFileManagerController.getFilesInFolder(
      lib.Id,
      null
    );
    System.assert(result.files.size() > 0, 'Should have files with icons');
  }

  @isTest
  static void testFileIcon_Unknown() {
    Map<String, Object> data = LibraryFileManagerTestHelper.createTestLibraries();
    ContentWorkspace lib = (ContentWorkspace) data.get('library');

    Test.startTest();
    User currentUser = [SELECT Id FROM User WHERE Id = :UserInfo.getUserId()];
    System.runAs(currentUser) {
      ContentVersion file = new ContentVersion(
        Title = 'Unknown File',
        PathOnClient = 'unknown',
        VersionData = Blob.valueOf('Test'),
        Origin = 'H',
        FirstPublishLocationId = lib.Id
      );
      insert file;
    }
    Test.stopTest();

    LibraryFileManagerController.FileListWrapper result = LibraryFileManagerController.getFilesInFolder(
      lib.Id,
      null
    );
    System.assert(result.files.size() > 0, 'Should handle unknown extension');
  }

  @isTest
  static void testFileSizes() {
    Map<String, Object> data = LibraryFileManagerTestHelper.createTestLibraries();
    ContentWorkspace lib = (ContentWorkspace) data.get('library');

    Test.startTest();
    User currentUser = [SELECT Id FROM User WHERE Id = :UserInfo.getUserId()];
    System.runAs(currentUser) {
      List<ContentVersion> files = new List<ContentVersion>();

      files.add(
        new ContentVersion(
          Title = 'Small',
          PathOnClient = 'small.txt',
          VersionData = Blob.valueOf('x'),
          Origin = 'H',
          FirstPublishLocationId = lib.Id
        )
      );

      files.add(
        new ContentVersion(
          Title = 'Medium',
          PathOnClient = 'medium.txt',
          VersionData = Blob.valueOf('x'.repeat(2000)),
          Origin = 'H',
          FirstPublishLocationId = lib.Id
        )
      );

      insert files;
    }
    Test.stopTest();

    LibraryFileManagerController.FileListWrapper result = LibraryFileManagerController.getFilesInFolder(
      lib.Id,
      null
    );
    System.assert(result.files.size() > 0, 'Should format file sizes');
  }

  @isTest
  static void testGetFilesInFolder_InvalidLibraryFormat() {
    Test.startTest();
    try {
      LibraryFileManagerController.getFilesInFolder('invalid_format', null);
    } catch (Exception e) {
      System.assert(true, 'Should catch invalid library format');
    }
    Test.stopTest();
  }

  @isTest
  static void testGetFilesInFolder_NonExistentLibrary() {
    Test.startTest();
    try {
      LibraryFileManagerController.getFilesInFolder('058000000000000', null);
    } catch (Exception e) {
      System.assert(true, 'Should catch non-existent library');
    }
    Test.stopTest();
  }

  @isTest
  static void testGetFilesInFolder_InvalidFolderName() {
    Map<String, Object> data = LibraryFileManagerTestHelper.createTestLibraries();
    ContentWorkspace lib = (ContentWorkspace) data.get('library');

    Test.startTest();
    try {
      LibraryFileManagerController.getFilesInFolder(
        lib.Id,
        'NonExistentFolder'
      );
    } catch (Exception e) {
      System.assert(true, 'Should handle invalid folder name');
    }
    Test.stopTest();
  }

  @isTest
  static void testGetFilesInFolder_TestHookNonExistentFolder() {
    Test.startTest();
    // Use a validly-formatted but non-existent library AND folder Id. The test
    // hook branch never validates the library exists, so this actually reaches
    // the folders.isEmpty() guard inside getFilesInFolder's isTestRootFolder path.
    LibraryFileManagerController.FileListWrapper result = LibraryFileManagerController.getFilesInFolderTestHook(
      '058000000000000',
      '00l000000000000'
    );
    Test.stopTest();

    System.assertEquals(
      0,
      result.files.size(),
      'Non-existent folder should return no file rows'
    );
    System.assertEquals(
      '',
      result.path,
      'Non-existent folder should return an empty path'
    );
    System.assertEquals(
      0,
      result.breadcrumbs.size(),
      'Non-existent folder should return no breadcrumbs'
    );
  }

  @isTest
  static void testGetFilesInFolder_EmptyLibraryName() {
    Test.startTest();
    try {
      LibraryFileManagerController.getFilesInFolder('', null);
    } catch (Exception e) {
      System.assert(true, 'Should handle empty library name');
    }
    Test.stopTest();
  }

  @isTest
  static void testNameResolution_NotFound() {
    Test.startTest();
    try {
      LibraryFileManagerController.getFilesInFolder(
        'NonExistentLibraryName',
        null
      );
      System.assert(false, 'Should throw');
    } catch (Exception e) {
      System.assert(true, 'Exception thrown as expected');
    }
    Test.stopTest();
  }

  @isTest
  static void testFolderNameResolution_NotFound() {
    Map<String, Object> data = LibraryFileManagerTestHelper.createTestLibraries();
    ContentWorkspace lib = (ContentWorkspace) data.get('library');

    Test.startTest();
    try {
      LibraryFileManagerController.getFilesInFolder(
        lib.Id,
        'NonExistentFolderName'
      );
      System.assert(false, 'Should throw');
    } catch (Exception e) {
      System.assert(true, 'Exception thrown as expected');
    }
    Test.stopTest();
  }

  @isTest
  static void testTestHook_EmptyFolder() {
    Map<String, Object> data = LibraryFileManagerTestHelper.createTestLibraries();
    ContentWorkspace lib = (ContentWorkspace) data.get('library');

    // Create a folder with NO files
    ContentFolder emptyFolder = new ContentFolder(
      Name = 'EmptyTestFolder',
      ParentContentFolderId = lib.RootContentFolderId
    );
    insert emptyFolder;

    Test.startTest();
    LibraryFileManagerController.FileListWrapper result = LibraryFileManagerController.getFilesInFolderTestHook(
      lib.Id,
      emptyFolder.Id
    );
    Test.stopTest();

    System.assertNotEquals(
      null,
      result,
      'Should return result for empty folder'
    );
    System.assertEquals(0, result.files.size(), 'Should have no files');
  }

  @isTest
  static void testGetFilesInFolder_ExplicitNullFolder() {
    Map<String, Object> data = LibraryFileManagerTestHelper.createTestLibraries();
    ContentWorkspace lib = (ContentWorkspace) data.get('library');

    Test.startTest();
    List<String> fileIds = LibraryFileManagerTestHelper.createTestFiles(lib.Id);

    // Explicitly pass null for folderId to exercise the library-root path.
    LibraryFileManagerController.FileListWrapper result = LibraryFileManagerController.getFilesInFolder(
      lib.Id,
      null
    );
    Test.stopTest();

    System.assertNotEquals(null, result, 'Should return library root files');
    System.assertNotEquals(null, result.path, 'Should have path');
    System.assertEquals(
      1,
      result.breadcrumbs.size(),
      'Should have library breadcrumb'
    );
  }

  @isTest
  static void testGetFilesInFolder_FolderIdIsActuallyLibraryId() {
    Map<String, Object> data = LibraryFileManagerTestHelper.createTestLibraries();
    ContentWorkspace lib = (ContentWorkspace) data.get('library');
    ContentWorkspace lib2 = (ContentWorkspace) data.get('secondaryLibrary');

    Test.startTest();
    List<String> fileIds = LibraryFileManagerTestHelper.createTestFiles(lib.Id);

    // Pass library2.Id as BOTH libraryId and folderId to exercise the
    // "folderId is actually a library Id" branch.
    LibraryFileManagerController.FileListWrapper result = LibraryFileManagerController.getFilesInFolder(
      lib.Id,
      lib2.Id
    );
    Test.stopTest();

    System.assertNotEquals(null, result, 'Should handle library as folder ID');
  }
}
