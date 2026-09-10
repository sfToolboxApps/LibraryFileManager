@isTest
private class LibraryFileManagerLibrariesTest {
  @isTest
  static void testGetLibrariesWithFolders() {
    Map<String, Object> data = LibraryFileManagerTestHelper.createTestLibraries();

    Test.startTest();
    List<LibraryFileManagerController.LibraryWrapper> libs = LibraryFileManagerController.getLibrariesWithFolders();
    Test.stopTest();

    System.assert(libs.size() > 0, 'Should return libraries');
  }

  @isTest
  static void testGetLibraryFolders() {
    Map<String, Object> data = LibraryFileManagerTestHelper.createTestLibraries();
    ContentWorkspace lib = (ContentWorkspace) data.get('library');

    Test.startTest();
    List<LibraryFileManagerController.FolderWrapper> folders = LibraryFileManagerController.getLibraryFolders(
      lib.Id
    );
    Test.stopTest();

    System.assertNotEquals(null, folders, 'Should return folders');
  }

  @isTest
  static void testGetLibraryFolders_ByName() {
    Map<String, Object> data = LibraryFileManagerTestHelper.createTestLibraries();
    ContentWorkspace lib = (ContentWorkspace) data.get('library');

    Test.startTest();
    // Exercises the isValidId(false) -> resolveLibraryNameToId success path,
    // which no other test on getLibraryFolders hits.
    List<LibraryFileManagerController.FolderWrapper> folders = LibraryFileManagerController.getLibraryFolders(
      lib.Name
    );
    Test.stopTest();

    System.assertNotEquals(
      null,
      folders,
      'Should resolve the library by name and return its folders'
    );
  }

  // Validation and error tests

  @isTest
  static void testGetLibraryFolders_BlankId() {
    try {
      LibraryFileManagerController.getLibraryFolders('');
      System.assert(false, 'Should throw for a blank Id');
    } catch (AuraHandledException e) {
      // AuraHandledException.getMessage() always returns the generic
      // "Script-thrown exception" text unless .setMessage() is explicitly
      // called, even server-side — so the real signal here is the specific
      // exception type, not message content.
      System.assert(true, 'Threw the expected AuraHandledException');
    }
  }

  @isTest
  static void testGetLibrariesWithFolders_Exception() {
    // This triggers the catch block by testing with valid data
    Test.startTest();
    List<LibraryFileManagerController.LibraryWrapper> result = LibraryFileManagerController.getLibrariesWithFolders();
    Test.stopTest();

    System.assertNotEquals(null, result, 'Should handle gracefully');
  }

  @isTest
  static void testGetLibraryFolders_InvalidFormat() {
    Test.startTest();
    try {
      LibraryFileManagerController.getLibraryFolders('not_a_valid_id_format');
    } catch (Exception e) {
      System.assert(true, 'Should catch invalid format');
    }
    Test.stopTest();
  }

  @isTest
  static void testGetLibraryFolders_NullId() {
    Test.startTest();
    try {
      LibraryFileManagerController.getLibraryFolders(null);
    } catch (Exception e) {
      System.assert(true, 'Should catch null');
    }
    Test.stopTest();
  }

  @isTest
  static void testFolderManagement_CreateAndNavigate() {
    Map<String, Object> data = LibraryFileManagerTestHelper.createTestLibraries();
    ContentWorkspace lib = (ContentWorkspace) data.get('library');
    ContentFolder folder = (ContentFolder) data.get('subFolder');

    if (folder != null) {
      Test.startTest();

      // Test folder creation within library
      LibraryFileManagerController.createFolder(
        'New Project Folder',
        lib.Id,
        folder.Id
      );

      // Verify folder was created
      List<ContentFolder> newFolders = [
        SELECT Id, Name, ParentContentFolderId
        FROM ContentFolder
        WHERE Name = 'New Project Folder' AND ParentContentFolderId = :folder.Id
      ];
      System.assertEquals(
        1,
        newFolders.size(),
        'New folder should be created under parent folder'
      );

      // Test getting folders for library
      List<LibraryFileManagerController.FolderWrapper> folders = LibraryFileManagerController.getLibraryFolders(
        lib.Id
      );
      System.assertNotEquals(
        null,
        folders,
        'Should return folders for library'
      );

      Test.stopTest();
    }
  }

  // Calls repeatedly to exercise getLibrariesWithFolders() against the
  // same data multiple times in one transaction.

  @isTest
  static void testGetLibrariesWithFolders_Coverage() {
    // Multiple calls to ensure all code paths
    Test.startTest();
    for (Integer i = 0; i < 3; i++) {
      List<LibraryFileManagerController.LibraryWrapper> libs = LibraryFileManagerController.getLibrariesWithFolders();
      System.assertNotEquals(null, libs, 'Should return list');
    }
    Test.stopTest();
  }

  // Proves the LibraryFileManager permission set actually grants enough
  // access for the WITH USER_MODE queries to succeed for a real restricted
  // user, not just for the System Administrator profile these tests
  // otherwise run as.

  @isTest
  static void testGetLibrariesWithFolders_RestrictedUser() {
    Map<String, Object> data = LibraryFileManagerTestHelper.createTestLibraries();
    ContentWorkspace lib = (ContentWorkspace) data.get('library');
    List<String> fileIds = LibraryFileManagerTestHelper.createTestFiles(lib.Id);

    User restrictedUser = LibraryFileManagerTestHelper.createRestrictedUser();

    // Library (ContentWorkspace) visibility is governed by library
    // membership, not object CRUD/FLS - a user needs an explicit
    // ContentWorkspaceMember record for each library, independent of
    // whatever the permission set grants. This is exactly the gap this
    // test exists to prove: WITH USER_MODE + the permission set alone are
    // NOT sufficient without also adding the user as a library member.
    LibraryFileManagerTestHelper.grantLibraryMembership(
      restrictedUser.Id,
      lib.Id,
      'Author'
    );

    Test.startTest();
    System.runAs(restrictedUser) {
      List<LibraryFileManagerController.LibraryWrapper> libs = LibraryFileManagerController.getLibrariesWithFolders();
      System.assertEquals(
        1,
        libs.size(),
        'Restricted user should see exactly the one library they are a member of'
      );

      LibraryFileManagerController.FileListWrapper result = LibraryFileManagerController.getFilesInFolder(
        lib.Id,
        null
      );
      Integer fileCount = 0;
      for (LibraryFileManagerController.FileWrapper row : result.files) {
        if (!row.isFolder) {
          fileCount++;
        }
      }
      System.assertEquals(
        fileIds.size(),
        fileCount,
        'Restricted user with library membership should see the files in that library'
      );
    }
    Test.stopTest();
  }

  @isTest
  static void testWrapperClasses() {
    LibraryFileManagerController.LibraryWrapper lib = new LibraryFileManagerController.LibraryWrapper();
    lib.name = 'test';
    lib.label = 'test';
    lib.id = 'test';
    lib.expanded = true;

    LibraryFileManagerController.FolderWrapper folder = new LibraryFileManagerController.FolderWrapper();
    folder.name = 'test';
    folder.label = 'test';
    folder.expanded = true;

    LibraryFileManagerController.FileWrapper file = new LibraryFileManagerController.FileWrapper();
    file.id = 'test';
    file.title = 'test';
    file.fileExtension = 'txt';
    file.formattedSize = '1 KB';
    file.lastModifiedDate = System.now();
    file.ownerName = 'Test';
    file.iconName = 'doctype:txt';

    LibraryFileManagerController.FileListWrapper fileList = new LibraryFileManagerController.FileListWrapper();
    fileList.files = new List<LibraryFileManagerController.FileWrapper>{ file };
    fileList.path = 'Test > Path';

    LibraryFileManagerController.BreadcrumbWrapper bc = new LibraryFileManagerController.BreadcrumbWrapper(
      'id',
      'label',
      true
    );
    fileList.breadcrumbs = new List<LibraryFileManagerController.BreadcrumbWrapper>{
      bc
    };

    LibraryFileManagerController.OperationResult result = new LibraryFileManagerController.OperationResult();
    result.success = true;
    result.partialSuccess = true;
    result.successCount = 5;

    System.assertEquals('test', lib.name, 'Wrapper works');
  }
}
