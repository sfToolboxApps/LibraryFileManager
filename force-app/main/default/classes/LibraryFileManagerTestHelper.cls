@isTest
public class LibraryFileManagerTestHelper {
  // Helper method: Create ALL setup objects in ONE System.runAs() block

  public static Map<String, Object> createTestLibraries() {
    ContentWorkspace library;
    ContentWorkspace secondaryLibrary;
    ContentFolder subFolder = null;

    // System.runAs avoids MIXED_DML_OPERATION errors from combining
    // ContentWorkspace/ContentFolder DML with other object DML in this
    // transaction (see the same check in createFolder()'s catch block).
    User currentUser = [SELECT Id FROM User WHERE Id = :UserInfo.getUserId()];
    System.runAs(currentUser) {
      library = new ContentWorkspace(
        Name = 'Primary Library ' + System.currentTimeMillis(),
        DeveloperName = 'Primary_Library_' +
          String.valueOf(System.currentTimeMillis()).substring(0, 10)
      );
      insert library;

      secondaryLibrary = new ContentWorkspace(
        Name = 'Secondary Library ' + System.currentTimeMillis(),
        DeveloperName = 'Secondary_Library_' +
          String.valueOf(System.currentTimeMillis()).substring(0, 10)
      );
      insert secondaryLibrary;

      // Refresh to get RootContentFolderId
      library = [
        SELECT Id, Name, RootContentFolderId
        FROM ContentWorkspace
        WHERE Id = :library.Id
      ];
      secondaryLibrary = [
        SELECT Id, Name, RootContentFolderId
        FROM ContentWorkspace
        WHERE Id = :secondaryLibrary.Id
      ];

      // Create folder IN THE SAME System.runAs() block
      if (library.RootContentFolderId != null) {
        subFolder = new ContentFolder(
          Name = 'Projects',
          ParentContentFolderId = library.RootContentFolderId
        );
        insert subFolder;
      }
    }

    Map<String, Object> data = new Map<String, Object>();
    data.put('library', library);
    data.put('secondaryLibrary', secondaryLibrary);
    data.put('subFolder', subFolder);

    return data;
  }

  // Helper method: Create files (non-setup) using System.runAs() to avoid MIXED_DML

  public static List<String> createTestFiles(String libraryId) {
    List<ContentVersion> testFiles = new List<ContentVersion>();

    // Same MIXED_DML_OPERATION avoidance as createTestLibraries() above.
    User currentUser = [SELECT Id FROM User WHERE Id = :UserInfo.getUserId()];
    System.runAs(currentUser) {
      for (Integer i = 1; i <= 3; i++) {
        testFiles.add(
          new ContentVersion(
            Title = 'Test File ' + i,
            PathOnClient = 'test' + i + '.txt',
            VersionData = Blob.valueOf('Test file content ' + i),
            Origin = 'H',
            FirstPublishLocationId = libraryId
          )
        );
      }
      insert testFiles;
    }

    // Get ContentDocument IDs
    List<String> fileIds = new List<String>();
    for (ContentVersion cv : [
      SELECT ContentDocumentId
      FROM ContentVersion
      WHERE Id IN :testFiles
    ]) {
      fileIds.add(cv.ContentDocumentId);
    }

    return fileIds;
  }

  // Creates a user on the most restrictive real profile ("Minimum Access -
  // Salesforce") with ONLY the LibraryFileManager permission set assigned -
  // no admin/Standard User baseline access. Used to prove (not assume) that
  // WITH USER_MODE queries actually work under the permission set this repo
  // ships, not just under the System Administrator profile tests run as.

  public static User createRestrictedUser() {
    Profile minimumAccessProfile = [
      SELECT Id
      FROM Profile
      WHERE Name = 'Minimum Access - Salesforce'
      LIMIT 1
    ];

    String uniqueSuffix = String.valueOf(System.currentTimeMillis());
    User restrictedUser = new User(
      FirstName = 'Restricted',
      LastName = 'TestUser' + uniqueSuffix,
      Alias = 'ru' + uniqueSuffix.right(6),
      Email = 'restricted.user.' + uniqueSuffix + '@example.com.invalid',
      Username = 'restricted.user.' + uniqueSuffix + '@example.com.invalid',
      ProfileId = minimumAccessProfile.Id,
      TimeZoneSidKey = 'America/Los_Angeles',
      LocaleSidKey = 'en_US',
      EmailEncodingKey = 'UTF-8',
      LanguageLocaleKey = 'en_US'
    );
    insert restrictedUser;

    PermissionSet libraryFileManagerPermSet = [
      SELECT Id
      FROM PermissionSet
      WHERE Name = 'LibraryFileManager'
      LIMIT 1
    ];
    insert new PermissionSetAssignment(
      AssigneeId = restrictedUser.Id,
      PermissionSetId = libraryFileManagerPermSet.Id
    );

    return restrictedUser;
  }

  // Library (ContentWorkspace) visibility and content operations are gated
  // by library membership, independent of object CRUD/FLS - see
  // testGetLibrariesWithFolders_RestrictedUser below for how that was
  // discovered. permissionName is one of 'Viewer', 'Author', or
  // 'Library Administrator' (standard, org-wide ContentWorkspacePermission
  // records that already exist in every org).

  public static void grantLibraryMembership(
    Id userId,
    Id libraryId,
    String permissionName
  ) {
    ContentWorkspacePermission permission = [
      SELECT Id
      FROM ContentWorkspacePermission
      WHERE Name = :permissionName
      LIMIT 1
    ];
    insert new ContentWorkspaceMember(
      ContentWorkspaceId = libraryId,
      MemberId = userId,
      ContentWorkspacePermissionId = permission.Id
    );
  }

  // None of this org's three default library permission levels (Viewer,
  // Author, Library Administrator) have PermissionsDeleteContent or
  // PermissionsOrganizeFileAndFolder checked - confirmed by querying
  // ContentWorkspacePermission directly. Deleting files and creating/moving
  // folders are gated by library-permission-level configuration, not by the
  // LibraryFileManager permission set (which can't grant either - they're
  // Library-specific settings, same category of gap as library membership
  // itself). This creates a custom permission level with the requested
  // rights so tests can prove the "as user" DML paths work correctly when
  // an admin DOES grant the right access, without relying on org-specific
  // seeded data that may not exist in every org.

  public static void grantCustomLibraryMembership(
    Id userId,
    Id libraryId,
    Boolean addContent,
    Boolean deleteContent,
    Boolean organizeFileAndFolder
  ) {
    ContentWorkspacePermission customPermission = new ContentWorkspacePermission(
      Name = 'TestCustom' + String.valueOf(System.currentTimeMillis()),
      PermissionsAddContent = addContent,
      PermissionsDeleteContent = deleteContent,
      PermissionsOrganizeFileAndFolder = organizeFileAndFolder
    );
    User currentUser = [SELECT Id FROM User WHERE Id = :UserInfo.getUserId()];
    System.runAs(currentUser) {
      insert customPermission;
    }
    insert new ContentWorkspaceMember(
      ContentWorkspaceId = libraryId,
      MemberId = userId,
      ContentWorkspacePermissionId = customPermission.Id
    );
  }
}
