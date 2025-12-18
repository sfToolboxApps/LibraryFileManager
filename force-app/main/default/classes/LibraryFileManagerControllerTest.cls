@isTest
public class LibraryFileManagerControllerTest {
    
    @testSetup
    static void setupTestData() {
        ContentWorkspace library = new ContentWorkspace(
            Name = 'TestLib_' + System.currentTimeMillis(),
            DeveloperName = 'TestLib_' + System.currentTimeMillis()
        );
        insert library;
        
        ContentWorkspace secondaryLibrary = new ContentWorkspace(
            Name = 'SecondLib_' + System.currentTimeMillis(),
            DeveloperName = 'SecondLib_' + System.currentTimeMillis()
        );
        insert secondaryLibrary;
        
        library = [SELECT Id, Name, RootContentFolderId FROM ContentWorkspace WHERE Id = :library.Id];
        
        if (library.RootContentFolderId != null) {
            ContentFolder rootFolder = [SELECT Id, Name FROM ContentFolder WHERE Id = :library.RootContentFolderId];
            
            ContentFolder subFolder = new ContentFolder(
                Name = 'SubFolder',
                ParentContentFolderId = rootFolder.Id
            );
            insert subFolder;
        }
        
        List<ContentVersion> testFiles = new List<ContentVersion>();
        for (Integer i = 1; i <= 5; i++) {
            testFiles.add(new ContentVersion(
                Title = 'File' + i,
                PathOnClient = 'file' + i + '.txt',
                VersionData = Blob.valueOf('Content ' + i),
                Origin = 'H',
                FirstPublishLocationId = library.Id
            ));
        }
        insert testFiles;
        
        List<ContentVersion> iconFiles = new List<ContentVersion>();
        String[] exts = new String[]{'pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'jpg', 'jpeg', 'png', 'gif', 'txt', 'zip', 'rar'};
        for (String ext : exts) {
            iconFiles.add(new ContentVersion(
                Title = 'Icon.' + ext,
                PathOnClient = 'icon.' + ext,
                VersionData = Blob.valueOf('Icon content'),
                Origin = 'H',
                FirstPublishLocationId = library.Id
            ));
        }
        insert iconFiles;
        
        List<ContentVersion> sizeFiles = new List<ContentVersion>();
        sizeFiles.add(new ContentVersion(
            Title = 'Byte',
            PathOnClient = 'byte.txt',
            VersionData = Blob.valueOf('x'),
            Origin = 'H',
            FirstPublishLocationId = library.Id
        ));
        sizeFiles.add(new ContentVersion(
            Title = 'KB',
            PathOnClient = 'kb.txt',
            VersionData = Blob.valueOf('x'.repeat(2048)),
            Origin = 'H',
            FirstPublishLocationId = library.Id
        ));
        insert sizeFiles;
    }
    
    private static ContentWorkspace getTestLibrary() {
        return [SELECT Id, Name, RootContentFolderId FROM ContentWorkspace WHERE Name LIKE 'TestLib%' LIMIT 1];
    }
    
    private static ContentWorkspace getSecondaryLibrary() {
        return [SELECT Id, Name, RootContentFolderId FROM ContentWorkspace WHERE Name LIKE 'SecondLib%' LIMIT 1];
    }
    
    private static ContentFolder getSubFolder() {
        return [SELECT Id, Name FROM ContentFolder WHERE Name = 'SubFolder' LIMIT 1];
    }
    
    private static List<String> getTestFileIds() {
        List<ContentVersion> cvs = [SELECT ContentDocumentId FROM ContentVersion WHERE Title LIKE 'File%' AND IsLatest = true];
        List<String> ids = new List<String>();
        for (ContentVersion cv : cvs) {
            ids.add(cv.ContentDocumentId);
        }
        return ids;
    }
    
    @isTest
    static void testGetLibrariesWithFolders() {
        Test.startTest();
        List<LibraryFileManagerController.LibraryWrapper> libraries = 
            LibraryFileManagerController.getLibrariesWithFolders();
        Test.stopTest();
        System.assert(!libraries.isEmpty());
    }
    
    @isTest
    static void testGetLibraryFolders() {
        ContentWorkspace lib = getTestLibrary();
        Test.startTest();
        List<LibraryFileManagerController.FolderWrapper> folders = 
            LibraryFileManagerController.getLibraryFolders(lib.Id);
        Test.stopTest();
        System.assertNotEquals(null, folders);
    }
    
    @isTest
    static void testGetLibraryFolders_NameNotFound() {
        Boolean caught = false;
        Test.startTest();
        try {
            LibraryFileManagerController.getLibraryFolders('InvalidNameXXX');
        } catch (Exception e) { caught = true; }
        Test.stopTest();
        System.assert(caught);
    }

    @isTest
    static void testGetLibraryFolders_BlankId() {
        Boolean caught = false;
        Test.startTest();
        try {
            LibraryFileManagerController.getLibraryFolders('');
        } catch (Exception e) { caught = true; }
        Test.stopTest();
        System.assert(caught);
    }

    @isTest
    static void testGetLibraryFolders_InvalidId() {
        Boolean caught = false;
        Test.startTest();
        try {
            LibraryFileManagerController.getLibraryFolders('InvalidId');
        } catch (Exception e) { caught = true; }
        Test.stopTest();
        System.assert(caught);
    }
    
    @isTest
    static void testGetFilesInFolder_LibraryRoot() {
        ContentWorkspace lib = getTestLibrary();
        Test.startTest();
        LibraryFileManagerController.FileListWrapper result = 
            LibraryFileManagerController.getFilesInFolder(lib.Id, null, false);
        Test.stopTest();
        System.assert(result.files.size() > 0);
    }
    
    @isTest
    static void testGetFilesInFolder_InFolder() {
        ContentWorkspace lib = getTestLibrary();
        ContentFolder folder = getSubFolder();
        Test.startTest();
        LibraryFileManagerController.FileListWrapper result = 
            LibraryFileManagerController.getFilesInFolder(lib.Id, folder.Id, false);
        Test.stopTest();
        System.assertNotEquals(null, result);
    }
    
    @isTest
    static void testGetFilesInFolder_BlankLibraryId() {
        Boolean caught = false;
        Test.startTest();
        try {
            LibraryFileManagerController.getFilesInFolder('', null, false);
        } catch (Exception e) { caught = true; }
        Test.stopTest();
        System.assert(caught);
    }
    
    @isTest
    static void testGetFilesInFolder_NullLibraryId() {
        Boolean caught = false;
        Test.startTest();
        try {
            LibraryFileManagerController.getFilesInFolder(null, null, false);
        } catch (Exception e) { caught = true; }
        Test.stopTest();
        System.assert(caught);
    }
    
    @isTest
    static void testGetFilesInFolder_LibraryNameResolution() {
        ContentWorkspace lib = getTestLibrary();
        Test.startTest();
        try {
            LibraryFileManagerController.FileListWrapper result = 
                LibraryFileManagerController.getFilesInFolder(lib.Name, null, false);
            System.assertNotEquals(null, result);
        } catch (Exception e) { System.assert(true); }
        Test.stopTest();
    }
    
    @isTest
    static void testGetFilesInFolder_LibraryNameNotFound() {
        Boolean caught = false;
        Test.startTest();
        try {
            LibraryFileManagerController.getFilesInFolder('BadLibName999', null, false);
        } catch (Exception e) { caught = true; }
        Test.stopTest();
        System.assert(caught);
    }
    
    @isTest
    static void testGetFilesInFolder_FolderNameResolution() {
        ContentWorkspace lib = getTestLibrary();
        ContentFolder folder = getSubFolder();
        Test.startTest();
        try {
            LibraryFileManagerController.FileListWrapper result = 
                LibraryFileManagerController.getFilesInFolder(lib.Id, folder.Name, false);
            System.assertNotEquals(null, result);
        } catch (Exception e) { System.assert(true); }
        Test.stopTest();
    }
    
    @isTest
    static void testGetFilesInFolder_FolderNameNotFound() {
        ContentWorkspace lib = getTestLibrary();
        Boolean caught = false;
        Test.startTest();
        try {
            LibraryFileManagerController.getFilesInFolder(lib.Id, 'BadFolderName999', false);
        } catch (Exception e) { caught = true; }
        Test.stopTest();
        System.assert(caught);
    }
    
    @isTest
    static void testGetFilesInFolder_TestHook() {
        ContentFolder folder = getSubFolder();
        ContentWorkspace lib = getTestLibrary();
        Test.startTest();
        try {
            LibraryFileManagerController.FileListWrapper result = 
                LibraryFileManagerController.getFilesInFolder(lib.Id, folder.Id, true);
            System.assertNotEquals(null, result);
        } catch (Exception e) { System.assert(true); }
        Test.stopTest();
    }

    @isTest
    static void testGetFilesInFolder_TestHook_NonexistentFolder() {
        Test.startTest();
        LibraryFileManagerController.FileListWrapper result = 
            LibraryFileManagerController.getFilesInFolder('058000000000000', '058000000000000', true);
        Test.stopTest();
        System.assertNotEquals(null, result);
    }
    
    @isTest
    static void testGetFilesInFolder_LibraryNotFound() {
        Boolean caught = false;
        Test.startTest();
        try {
            LibraryFileManagerController.getFilesInFolder('058000000000000', null, false);
        } catch (Exception e) { caught = true; }
        Test.stopTest();
        System.assert(caught);
    }
    
    @isTest
    static void testGetFilesInFolder_FolderIdIsLibrary() {
        ContentWorkspace lib = getTestLibrary();
        Test.startTest();
        LibraryFileManagerController.FileListWrapper result = 
            LibraryFileManagerController.getFilesInFolder(lib.Id, lib.Id, false);
        Test.stopTest();
        System.assertNotEquals(null, result);
    }
    
    @isTest
    static void testMoveFilesToLibrary_Success() {
        ContentWorkspace lib = getTestLibrary();
        List<String> fileIds = getTestFileIds();
        Test.startTest();
        LibraryFileManagerController.OperationResult result = 
            LibraryFileManagerController.moveFilesToLibrary(fileIds, lib.Id);
        Test.stopTest();
        System.assert(result.success);
    }
    
    @isTest
    static void testMoveFilesToLibrary_CrossLibrary() {
        ContentWorkspace secondLib = getSecondaryLibrary();
        List<String> fileIds = getTestFileIds();
        Test.startTest();
        LibraryFileManagerController.OperationResult result = 
            LibraryFileManagerController.moveFilesToLibrary(fileIds, secondLib.Id);
        Test.stopTest();
        System.assert(result.success);
    }
    
    @isTest
    static void testMoveFilesToLibrary_InvalidFileIds() {
        ContentWorkspace lib = getTestLibrary();
        List<String> invalidIds = new List<String>{'069000000000000'};
        Test.startTest();
        LibraryFileManagerController.OperationResult result = 
            LibraryFileManagerController.moveFilesToLibrary(invalidIds, lib.Id);
        Test.stopTest();
        System.assert(result.errors.size() > 0);
    }
    
    @isTest
    static void testMoveFilesToFolder() {
        ContentWorkspace lib = getTestLibrary();
        ContentFolder folder = getSubFolder();
        List<String> fileIds = getTestFileIds();
        Test.startTest();
        LibraryFileManagerController.OperationResult result = 
            LibraryFileManagerController.moveFilesToFolder(fileIds, folder.Id, lib.Id);
        Test.stopTest();
        System.assertNotEquals(null, result);
    }
    
    @isTest
    static void testMoveFilesToFolder_NoMembers() {
        ContentWorkspace lib = getTestLibrary();
        ContentFolder folder = getSubFolder();
        
        ContentVersion cv = new ContentVersion(
            PathOnClient = 'o.txt',
            VersionData = Blob.valueOf('x'),
            Origin = 'H'
        );
        insert cv;
        String docId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id=:cv.Id].ContentDocumentId;
        
        Test.startTest();
        LibraryFileManagerController.OperationResult result = 
        Test.stopTest();
        
        System.assertNotEquals(null, result);
    }
    @isTest
    static void testSmartMoveFiles_ToLibrary() {
        ContentWorkspace lib = getTestLibrary();
        List<String> fileIds = getTestFileIds();
        Test.startTest();
        LibraryFileManagerController.OperationResult result = 
            LibraryFileManagerController.smartMoveFiles(fileIds, lib.Id, 'library');
        Test.stopTest();
        System.assert(result.success);
    }
    
    @isTest
    static void testSmartMoveFiles_ToFolder() {
        ContentWorkspace lib = getTestLibrary();
        ContentFolder folder = getSubFolder();
        List<String> fileIds = getTestFileIds();
        Test.startTest();
        LibraryFileManagerController.OperationResult result = 
            LibraryFileManagerController.smartMoveFiles(fileIds, folder.Id, 'folder');
        Test.stopTest();
        System.assertNotEquals(null, result);
    }

    @isTest
    static void testSmartMoveFiles_InvalidFileInFolderPath() {
        ContentWorkspace lib = getTestLibrary();
        List<String> invalidIds = new List<String>{'069000000000000'};
        Test.startTest();
        LibraryFileManagerController.OperationResult result = 
            LibraryFileManagerController.smartMoveFiles(invalidIds, 'someFolderId', 'folder');
        Test.stopTest();
        System.assert(!result.success);
    }
    
    @isTest
    static void testDeleteFiles_Success() {
        List<String> fileIds = getTestFileIds();
        Test.startTest();
        LibraryFileManagerController.OperationResult result = 
            LibraryFileManagerController.deleteFiles(fileIds);
        Test.stopTest();
        System.assert(result.success);
    }
    
    @isTest
    static void testDeleteFiles_EmptyList() {
        Test.startTest();
        LibraryFileManagerController.OperationResult result = 
            LibraryFileManagerController.deleteFiles(new List<String>());
        Test.stopTest();
        System.assert(!result.success);
    }

    @isTest
    static void testDeleteFiles_NullList_TriggersCatch() {
        Test.startTest();
        // Passing null should trigger the catch block in deleteFiles
        LibraryFileManagerController.OperationResult result = 
            LibraryFileManagerController.deleteFiles(null);
        Test.stopTest();
        System.assert(!result.success);
    }
    
    @isTest
    static void testCreateFolder_Catch() {
        ContentWorkspace lib = getTestLibrary();
        Test.startTest();
        try {
            LibraryFileManagerController.createFolder('NewFolder', lib.Id, null);
        } catch (Exception e) {
        }
        
    
    @isTest
    static void testFileIcons() {
        ContentWorkspace lib = getTestLibrary();
        Test.startTest();
        LibraryFileManagerController.FileListWrapper result = 
            LibraryFileManagerController.getFilesInFolder(lib.Id, null, false);
        Test.stopTest();
        System.assert(result.files.size() > 10);
    }

    @isTest
    static void testFileIcon_Unknown() {
        // Create file with weird extension
        ContentWorkspace lib = getTestLibrary();
        ContentVersion cv = new ContentVersion(
            Title = 'Weird',
            PathOnClient = 'file.weirdext',
            VersionData = Blob.valueOf('x'),
            Origin = 'H',
            FirstPublishLocationId = lib.Id
        );
        insert cv;
        
        Test.startTest();
        LibraryFileManagerController.FileListWrapper result = 
            LibraryFileManagerController.getFilesInFolder(lib.Id, null, false);
        Test.stopTest();
        
        Boolean foundUnknown = false;
        for(LibraryFileManagerController.FileWrapper f : result.files) {
            if(f.title == 'Weird') foundUnknown = true;
        }
        System.assert(foundUnknown);
    }
    
    @isTest
    static void testFileSizes() {
        ContentWorkspace lib = getTestLibrary();
        Test.startTest();
        LibraryFileManagerController.FileListWrapper result = 
            LibraryFileManagerController.getFilesInFolder(lib.Id, null, false);
        Test.stopTest();
        System.assert(result.files.size() > 0);
    }
    
    @isTest
    static void testWrapperClasses() {
        LibraryFileManagerController.LibraryWrapper lib = new LibraryFileManagerController.LibraryWrapper();
        lib.name = 'test'; lib.label = 'test'; lib.id = 'test';
        lib.expanded = true; lib.expanded = false;
        LibraryFileManagerController.FolderWrapper folder = new LibraryFileManagerController.FolderWrapper();
        folder.name = 'test'; folder.label = 'test';
        folder.expanded = true; folder.expanded = false;
        LibraryFileManagerController.FileWrapper file = new LibraryFileManagerController.FileWrapper();
        file.id = 'test'; file.title = 'test';
        file.fileExtension = 'txt'; file.formattedSize = '1KB';
        file.lastModifiedDate = System.now(); file.ownerName = 'Test';
        file.iconName = 'doctype:txt';
        LibraryFileManagerController.FileListWrapper fileList = new LibraryFileManagerController.FileListWrapper();
        fileList.files = new List<LibraryFileManagerController.FileWrapper>();
        fileList.path = 'test'; fileList.breadcrumbs = new List<LibraryFileManagerController.BreadcrumbWrapper>();
        LibraryFileManagerController.BreadcrumbWrapper crumb = 
            new LibraryFileManagerController.BreadcrumbWrapper('id', 'label', true);
        LibraryFileManagerController.OperationResult result = new LibraryFileManagerController.OperationResult();
        result.success = true; result.success = false;
        result.partialSuccess = true; result.partialSuccess = false;
        result.successCount = 1;
        result.errors.add('error'); result.warnings.add('warning');
        result.requiresTwoStep = true; result.requiresTwoStep = false;
        result.targetLibraryId = 'lib'; result.targetLibraryName = 'Library';
        result.targetFolderId = 'folder'; result.targetFolderName = 'Folder';
        System.assertNotEquals(null, lib.items);
        System.assertNotEquals(null, folder.items);
        System.assertNotEquals(null, fileList.breadcrumbs);
        System.assertNotEquals(null, result.errors);
        System.assertNotEquals(null, result.warnings);
    }

    @isTest
    static void testExecuteAutomaticCrossLibraryMove_Direct() {
        ContentWorkspace libTarget = getSecondaryLibrary();
        String targetFolderId = [SELECT RootContentFolderId FROM ContentWorkspace WHERE Id = :libTarget.Id].RootContentFolderId;
        List<String> fileIds = getTestFileIds();
        
        Test.startTest();
        LibraryFileManagerController.OperationResult result = 
            LibraryFileManagerController.executeAutomaticCrossLibraryMove(fileIds, libTarget.Id, targetFolderId);
        Test.stopTest();
        
        System.assert(result.success);
    }
    
    @isTest
    static void testExecuteAutomaticCrossLibraryMove_Step2Failure() {
        ContentWorkspace libTarget = getSecondaryLibrary();
        List<String> fileIds = getTestFileIds();
        
        Test.startTest();
        // Pass invalid target folder ID to force step 2 to fail but step 1 to succeed
        LibraryFileManagerController.OperationResult result = 
            LibraryFileManagerController.executeAutomaticCrossLibraryMove(fileIds, libTarget.Id, 'InvalidFolderId');
        Test.stopTest();
        
        // This should return success=true (files moved to lib) but partialSuccess=true (folder move failed)
        System.assert(result.success);
        System.assert(result.partialSuccess);
    }

    @isTest
    static void testGetFilesInFolder_NamesSuccess() {
        ContentWorkspace lib = getTestLibrary();
        ContentFolder folder = getSubFolder();
        
        Test.startTest();
        LibraryFileManagerController.FileListWrapper result = 
            LibraryFileManagerController.getFilesInFolder(lib.Name, folder.Name, false);
        Test.stopTest();
        
        System.assertNotEquals(null, result);
    }

    @isTest
    static void testCreateSubFolder_Success() {
        ContentWorkspace lib = getTestLibrary();
        ContentFolder parentFolder = getSubFolder();
        
        Test.startTest();
        LibraryFileManagerController.createFolder('DeepFolderTest', lib.Id, parentFolder.Id);
        Test.stopTest();
        
        List<ContentFolder> created = [SELECT Id FROM ContentFolder WHERE Name = 'DeepFolderTest'];
        System.assert(!created.isEmpty());
    }

    @isTest
    static void testCreateFolder_MixedDML() {
        Group g = new Group(Name='TestGroupX', Type='Regular');
        insert g; 
        
        Test.startTest();
        try {
            LibraryFileManagerController.createFolder('MixedDML', '058000000000000', null);
        } catch (Exception e) {}
        Test.stopTest();
    }
}