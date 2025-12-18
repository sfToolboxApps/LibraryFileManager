public with sharing class LibraryFileManagerController {
    
    @AuraEnabled(cacheable=false)
    public static List<LibraryWrapper> getLibrariesWithFolders() {
        try {
            List<LibraryWrapper> libraries = new List<LibraryWrapper>();
            
            List<ContentWorkspace> workspaces = [
                SELECT Id, Name, Description, RootContentFolderId
                FROM ContentWorkspace 
                ORDER BY Name
            ];
            
            for (ContentWorkspace workspace : workspaces) {
                LibraryWrapper library = new LibraryWrapper();
                library.id = workspace.Id;
                library.name = workspace.Id;
                library.label = workspace.Name;
                library.expanded = false;
                library.items = getFoldersForLibrary(workspace.Id);
                libraries.add(library);
            }
            
            return libraries;
            
        } catch (Exception e) {
            throw new AuraHandledException('Error loading libraries: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static List<FolderWrapper> getLibraryFolders(String libraryId) {
        if (String.isBlank(libraryId)) {
            throw new AuraHandledException('Library ID cannot be blank');
        }
        
        try {
            String resolvedLibraryId = libraryId;
            if (!isValidId(libraryId)) {
                String tryId = resolveLibraryNameToId(libraryId);
                if (tryId == null) {
                    throw new AuraHandledException('Library not found for Id or Name: ' + libraryId);
                }
                resolvedLibraryId = tryId;
            }
            
            List<ContentWorkspace> libraries = [SELECT Id FROM ContentWorkspace WHERE Id = :resolvedLibraryId LIMIT 1];
            if (libraries.isEmpty()) {
                throw new AuraHandledException('Library not found for Id: ' + resolvedLibraryId);
            }
            
            return getFoldersForLibrary(resolvedLibraryId);
            
        } catch (QueryException e) {
            throw new AuraHandledException('Library not found for Id or Name: ' + libraryId);
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException('Library not found for Id or Name: ' + libraryId);
        }
    }

    @AuraEnabled
    public static FileListWrapper getFilesInFolder(String libraryId, String folderId, Boolean isTestRootFolder) {
        try {
            FileListWrapper result = new FileListWrapper();
            
            if (String.isBlank(libraryId)) {
                throw new AuraHandledException('Library ID cannot be null or empty');
            }
            
            if (!isValidId(libraryId)) {
                String resolvedId = resolveLibraryNameToId(libraryId);
                if (resolvedId == null) {
                    throw new AuraHandledException('No library found for name: ' + libraryId);
                }
                libraryId = resolvedId;
            }
            
            if (!String.isBlank(folderId) && !isValidId(folderId)) {
                String resolvedFolderId = resolveFolderNameToId(folderId, libraryId);
                if (resolvedFolderId == null) {
                    throw new AuraHandledException('No folder found for name: ' + folderId + ' in library: ' + libraryId);
                }
                folderId = resolvedFolderId;
            }
            
            if (isTestRootFolder && !String.isBlank(folderId)) {
                List<ContentFolder> folders = [SELECT Id, Name FROM ContentFolder WHERE Id = :folderId LIMIT 1];
                if (folders.isEmpty()) {
                    result.files = new List<FileWrapper>();
                    result.path = '';
                    result.breadcrumbs = new List<BreadcrumbWrapper>();
                    return result;
                }
                
                try {
                    result.files = getFilesInContentFolder(folderId);
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
            
            List<ContentWorkspace> libraries = [SELECT Id, Name FROM ContentWorkspace WHERE Id = :libraryId LIMIT 1];
            if (libraries.isEmpty()) {
                throw new AuraHandledException('ContentWorkspace (library) not found for Id: ' + libraryId);
            }
            
            if (String.isBlank(folderId)) {
                result.files = getFilesInLibraryRoot(libraryId);
                result.path = getLibraryNammbs = new List<BreadcrumbWrapper>{
                    new BreadcrumbWrapper(libraryId, getLibraryName(libraryId), true)
                };
            } else {
                List<ContentWorkspace> libs = [SELECT Id FROM ContentWorkspace WHERE Id = :folderId LIMIT 1];
                if (!libs.isEmpty()) {
                    result.path = getLibraryName(folderId);
                    result.breadcrumbs = new List<BreadcrumbWrapper>{
                        new BreadcrumbWrapper(folderId, getLibraryName(folderId), true)
                    };
                } else {
                    result.files = getFilesInContentFolder(folderId);
                    result.path = getFolderPath(folderId);
                    
            }
            
            return result;
            
        } catch (Exception e) {
            throw new AuraHandledException('Error loading files: ' + e.getMessage());
        }
    }
    
    @AuraEnabled
    public static OperationResult moveFilesToLibrary(List<String> fileIds, String targetLibraryId) {
        OperationResult result = new OperationResult();
        result.errors = new List<String>();
        
        try {
            Map<String, List<ContentDocumentLink>> fileToLinksMap = new Map<String, List<ContentDocumentLink>>();
            List<ContentDocumentLink> allCurrentLinks = [
                SELECT Id, ContentDocumentId, LinkedEntityId
                FROM ContentDocumentLink 
                WHERE ContentDocumentId IN :fileIds
                AND LinkedEntityId IN (SELECT Id FROM ContentWorkspace)
            ];
            
            for (ContentDocumentLink link : allCurrentLinks) {
                if (!fileToLinksMap.containsKey(link.ContentDocumentId)) {
                    fileToLinksMap.put(link.ContentDocumentId, new List<ContentDocumentLink>());
                }
                fileToLinksMap.get(link.ContentDocumentId).add(link);
            }
            
            List<ContentDocumentLink> linksToAdd = new List<ContentDocumentLink>();
            List<ContentDocumentLink> linksToRemove = new List<ContentDocumentLink>();
            List<ContentDocument> documentsToUpdate = new List<ContentDocument>();
            Integer alreadyInTargetCount = 0;
            Integer trueMovesCount = 0;
            
            for (String fileId : fileIds) {
                List<ContentDocument> docs = [SELECT Id, ParentId FROM ContentDocument WHERE Id = :fileId];
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
                    linksToAdd.add(new ContentDocumentLink(
                        ContentDocumentId = fileId,
                        LinkedEntityId = targetLibraryId,
                        ShareType = 'I'
                    ));
                }
                
                documentsToUpdate.add(new ContentDocument(
                    Id = fileId,
                    ParentId = targetLibraryId
                ));
                
                if (fileLinks != null) {
                    for (ContentDocumentLink link : fileLinks) {
                        if (link.LinkedEntityId != targetLibraryId) {
                            linksToRemove.add(link);
                            trueMovesCount++;
                        }
                    }
                }
            }
            
            if (!linksToAdd.isEmpty()) {
                insert linksToAdd;
                result.successCount += linksToAdd.size();
            }
            
            if (!documentsToUpdate.isEmpty()) {
                update documentsToUpdate;
            }
            
            if (!linksToRemove.isEmpty()) {
                Database.DeleteResult[] deleteResults = Database.delete(linksToRemove, false);
                
                for (Integer i = 0; i < deleteResults.size(); i++) {
                    if (!deleteResults[i].isSuccess()) {
                        result.errors.add('Failed to remove file from library: ' + deleteResults[i].getErrors()[0].getMessage());
                    }
                }
            }
            
            result.successCount += alreadyInTargetCount;
            result.success = result.successCount > 0;
            
            if (trueMovesCount > 0) {
                result.warnings.add(trueMovesCount + ' files moved completely to target library.');
            }
            
            return result;
            
        } catch (Exception e) {
            result.success = false;
            result.errors.add('Error moving files to library: ' + e.getMessage());
            return result;
        }
    }
    
    @AuraEnabled
    public static OperationResult moveFilesToFolder(List<String> fileIds, String targetFolderId, String targetLibraryId) {
        OperationResult result = new OperationResult();
        result.errors = new List<String>();
        
        try {
            List<String> filesToMoveLibrary = new List<String>();
            Map<String, String> fileToLibraryMap = getCurrentLibrariesForFiles(fileIds);
            for (String fileId : fileIds) {
                String currentLibrary = fileToLibraryMap.get(fileId);
                if (currentLibrary != targetLibraryId) {
                    filesToMoveLibrary.add(fileId);
                }
            }
            
            if (!filesToMoveLibrary.isEmpty()) {
                OperationResult libraryMoveResult = moveFilesToLibrary(filesToMoveLibrary, targetLibraryId);
                if (!libraryMoveResult.success) {
                    result.errors.addAll(libraryMoveResult.errors);
                    result.success = false;
                    return result;
                }
            }
            
            List<ContentFolderMember> existingMembers = [
                SELECT Id, ChildRecordId, ParentContentFolderId
                FROM ContentFolderMember 
                WHERE ChildRecordId IN :fileIds
            ];
            
            if (!existingMembers.isEmpty()) {
                for (ContentFolderMember member : existingMembers) {
                    member.ParentContentFolderId = targetFolderId;
                }
                
                Database.SaveResult[] updateResults = Database.update(existingMembers, false);
                Integer successCount = 0;
                
                for (Integer i = 0; i < updateResults.size(); i++) {
                    if (updateResults[i].isSuccess()) {
                        successCount++;
                    } else {
                        result.errors.add('Failed to move file to folder: ' + updateResults[i].getErrors()[0].getMessage());
                    }
                }
                
                result.successCount = successCount;
                result.success = successCount > 0;
                
                if (successCount < existingMembers.size()) {
                    result.partialSuccess = true;
                    result.warnings.add(successCount + ' of ' + existingMembers.size() + ' files moved to folder successfully.');
                }
                
            } else {
                result.success = false;
                result.errors.add('No folder associations found for files. Files may need time to process in the library before folder organization.');
                result.warnings.add('Try refreshing and moving to folder again in a few moments.');
            }
            
            return result;
            
        } catch (Exception e) {
            result.success = false;
            result.errors.add('Error moving files to folder: ' + e.getMessage());
            return result;
        }
    }
        
    @AuraEnabled
    public static OperationResult smartMoveFiles(List<String> fileIds, String destinationId, String destinationType) {
        OperationResult result = new OperationResult();
        
        try {
            if (destinationType == 'library') {
                result = moveFilesToLibrary(fileIds, destinationId);
            } else if (destinationType == 'folder') {
                for (String fileId : fileIds) {
                    List<ContentDocument> docs = [SELECT Id FROM ContentDocument WHERE Id = :fileId];
                    if (docs.isEmpty()) {
                        result.errors.add('ContentDocument not found for Id: ' + fileId);
                        result.success = false;
                        return result;
                    }
                }
                
                String targetLibraryId = findLibraryForFolder(destinationId);
                if (targetLibraryId == null) {
                    result.success = false;
                    result.errors.add('Unable to determine target library for folder.');
                    return result;
                }
                
                Map<String, String> fileCurrentLibraries = getCurrentLibrariesForFiles(fileIds);
                Boolean needsCrossLibraryMove = false;
                
                for (String currentLibrary : fileCurrentLibraries.values()) {
                    if (currentLibrary != null && currentLibrary != targetLibraryId) {
                        needsCrossLibraryMove = true;
                        break;
                    }
                }
                
                if (needsCrossLibraryMove) {
                    result = executeAutomaticCrossLibraryMove(fileIds, targetLibraryId, destinationId);
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

    @AuraEnabled
    public static OperationResult executeAutomaticCrossLibraryMove(List<String> fileIds, String targetLibraryId, String targetFolderId) {
        OperationResult result = new OperationResult();
        result.errors = new List<String>();
        
        try {
            OperationResult libraryMoveResult = moveFilesToLibrary(fileIds, targetLibraryId);
            
            if (!libraryMoveResult.success) {
                result.success = false;
                result.errors.add('Step 1 Failed - Could not move files to target library: ' + String.join(libraryMoveResult.errors, '; '));
                return result;
            }
            
            OperationResult folderMoveResult = moveFilesToFolder(fileIds, targetFolderId, targetLibraryId);
            
            if (folderMoveResult.success) {
                result.success = true;
                result.successCount = libraryMoveResult.successCount;
                result.warnings.add('Cross-library move completed successfully. Files moved to target library and organized into folder.');
                
                if (libraryMoveResult.partialSuccess) {
                    result.partialSuccess = true;
                    result.warnings.add('Note: Some files may remain accessible in original libraries due to Salesforce ownership rules.');
                }
            } else {
                result.success = true;
                result.partialSuccess = true;
                result.successCount = libraryMoveResult.successCount;
                result.warnings.add('Files successfully moved to target library, but folder organization encountered issues: ' + String.join(folderMoveResult.errors, '; '));
                result.warnings.add('Files should appear in the target library root and may automatically organize into the folder after a few moments.');
            }
            
            return result;
            
        } catch (Exception e) {
            result.success = false;
            result.errors.add('Error in automatic cross-library move: ' + e.getMessage());
            return result;
        }
    }
    
    @AuraEnabled
    public static OperationResult deleteFiles(List<String> fileIds) {
        OperationResult result = new OperationResult();
        result.errors = new List<String>();
        
        try {
            List<ContentDocument> documentsToDelete = [
                SELECT Id FROM ContentDocument WHERE Id IN :fileIds
            ];
            
            if (!documentsToDelete.isEmpty()) {
                delete documentsToDelete;
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
    
    @AuraEnabled
    public static void createFolder(String folderName, String parentLibraryId, String parentFolderId) {
        try {
            ContentFolder newFolder = new ContentFolder();
            newFolder.Name = folderName;
            
            if (String.isBlank(parentFolderId)) {
                // Creating folder under library root
                List<ContentWorkspace> workspaces = [
                    SELECT Id, RootContentFolderId 
                    FROM ContentWorkspace 
                    WHERE Id = :parentLibraryId 
                    LIMIT 1
                ];
                
                if (workspaces.isEmpty()) {
                    throw new AuraHandledException('Library not found for Id: ' + parentLibraryId);
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
            
            insert newFolder;
            
        } catch (Exception e) {
            if (e.getMessage().contains('MIXED_DML_OPERATION')) {
                throw new AuraHandledException('Cannot create folder in same transaction as library operations. Please try again.');
            } else {
                throw new AuraHandledException('Error creating folder: ' + e.getMessage());
            }
        }
    }
    
    private static List<FolderWrapper> getFoldersForLibrary(String libraryId) {
        List<FolderWrapper> folders = new List<FolderWrapper>();
        
        try {
            Set<String> rootFolderIds = new Set<String>();
            
            ContentWorkspace workspace = [
                SELECT Id, RootContentFolderId 
                FROM ContentWorkspace 
                WHERE Id = :libraryId 
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
                ]) {
                    rootFolderIds.add(link.ContentFolderId);
                }
            }
            
            // Get folder hierarchy
            if (!rootFolderIds.isEmpty()) {
                Map<String, ContentFolder> allFoldersMap = new Map<String, ContentFolder>();
                Set<String> foldersToQuery = new Set<String>(rootFolderIds);
                Set<String> processedFolders = new Set<String>();
                
                // Iteratively load folders (max 5 levels)
                for (Integer level = 0; level < 5 && !foldersToQuery.isEmpty(); level++) {
                    List<ContentFolder> currentLevelFolders = [
                        SELECT Id, Name, ParentContentFolderId
                        FROM ContentFolder
                        WHERE Id IN :foldersToQuery
                        OR ParentContentFolderId IN :foldersToQuery
                        ORDER BY Name
                    ];
                    
                    Set<String> nextLevelFolders = new Set<String>();
                    
                    for (ContentFolder folder : currentLevelFolders) {
                        allFoldersMap.put(folder.Id, folder);
                        
                        if (!processedFolders.contains(folder.Id)) {
                            nextLevelFolders.add(folder.Id);
                        }
                    }
                    
                    processedFolders.addAll(foldersToQuery);
                    foldersToQuery = nextLevelFolders;
                    foldersToQuery.removeAll(processedFolders);
                }
                
                // Bulk load file counts
                Map<String, Integer> folderFileCounts = new Map<String, Integer>();
                try {
                    for (AggregateResult ar : [
                        SELECT ParentContentFolderId, COUNT(Id) fileCount
                        FROM ContentFolderMember 
                        WHERE ParentContentFolderId IN :allFoldersMap.keySet()
                        GROUP BY ParentContentFolderId
                    ]) {
                        String folderId = (String)ar.get('ParentContentFolderId');
                        Integer count = (Integer)ar.get('fileCount');
                        folderFileCounts.put(folderId, count);
                    }
                } catch (Exception e) {
                    // Continue without file counts
                }

                // Build folder tree
                for (String rootFolderId : rootFolderIds) {
                    if (allFoldersMap.containsKey(rootFolderId)) {
                        ContentFolder rootFolder = allFoldersMap.get(rootFolderId);
                        
                        if (rootFolder.Name == libraryId) {
                            // Skip root folder, show children
                            List<FolderWrapper> subFolders = getSubFoldersFromMap(rootFolder.Id, allFoldersMap, folderFileCounts);
                            folders.addAll(subFolders);
                        } else {
                            FolderWrapper folderWrapper = new FolderWrapper();
                            folderWrapper.name = rootFolder.Id;
                            Integer fileCount = folderFileCounts.get(rootFolder.Id);
                            if (fileCount == null) fileCount = 0;
                            folderWrapper.label = rootFolder.Name + ' (' + fileCount + ' files)';
                            folderWrapper.expanded = false;
                            folderWrapper.items = getSubFoldersFromMap(rootFolder.Id, allFoldersMap, folderFileCounts);
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
    
    private static List<FolderWrapper> getSubFoldersFromMap(String parentFolderId, Map<String, ContentFolder> allFoldersMap, Map<String, Integer> folderFileCounts) {
        List<FolderWrapper> subFolders = new List<FolderWrapper>();
        
        for (ContentFolder folder : allFoldersMap.values()) {
            if (folder.ParentContentFolderId == parentFolderId) {
                FolderWrapper folderWrapper = new FolderWrapper();
                folderWrapper.name = folder.Id;
                
                Integer fileCount = folderFileCounts.get(folder.Id);
                if (fileCount == null) fileCount = 0;
                
                folderWrapper.label = folder.Name + ' (' + fileCount + ' files)';
                folderWrapper.expanded = false;
                folderWrapper.items = getSubFoldersFromMap(folder.Id, allFoldersMap, folderFileCounts);
                subFolders.add(folderWrapper);
            }
        }
        
        return subFolders;
    }
    
    private static String getFolderName(String folderId) {
        try {
            ContentFolder folder = [SELECT Name FROM ContentFolder WHERE Id = :folderId LIMIT 1];
            return folder.Name;
        } catch (Exception e) {
            return 'Unknown Folder';
        }
    }
    
    private static Map<String, String> getCurrentLibrariesForFiles(List<String> fileIds) {
        Map<String, String> fileToLibraryMap = new Map<String, String>();
        
        try {
            for (ContentDocumentLink link : [
                SELECT ContentDocumentId, LinkedEntityId 
                FROM ContentDocumentLink 
                WHERE ContentDocumentId IN :fileIds
                AND LinkedEntityId IN (SELECT Id FROM ContentWorkspace)
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
            List<ContentWorkspace> libs = [SELECT Id FROM ContentWorkspace WHERE Id = :folderId LIMIT 1];
            if (!libs.isEmpty()) {
                return folderId;
            }
            
            // Traverse folder hierarchy to root
            String currentFolderId = folderId;
            String rootFolderId = null;
            Integer safety = 0;
            
            while (currentFolderId != null && safety++ < 10) {
                List<ContentFolder> folders = [
                    SELECT Id, ParentContentFolderId 
                    FROM ContentFolder 
                    WHERE Id = :currentFolderId 
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
            List<ContentVersion> versions = [
                SELECT ContentDocumentId, Title, FileExtension, ContentSize, 
                    LastModifiedDate, Owner.Name
                FROM ContentVersion
                WHERE ContentDocumentId IN (
                    SELECT ContentDocumentId 
                    FROM ContentDocumentLink 
                    WHERE LinkedEntityId = :libraryId
                )
                AND IsLatest = true
                ORDER BY Title
            ];
            
            for (ContentVersion version : versions) {
                FileWrapper file = new FileWrapper();
                file.id = version.ContentDocumentId;
                file.title = version.Title;
                file.fileExtension = version.FileExtension != null ? version.FileExtension : '';
                file.formattedSize = formatFileSize(version.ContentSize);
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
    
    private static List<FileWrapper> getFilesInContentFolder(String folderId) {
        try {
            List<ContentFolder> folders = [SELECT Id, Name FROM ContentFolder WHERE Id = :folderId LIMIT 1];
            if (folders.isEmpty()) {
                return new List<FileWrapper>();
            }
            
            List<FileWrapper> files = new List<FileWrapper>();
            List<ContentFolderMember> members = [
                SELECT ChildRecordId 
                FROM ContentFolderMember 
                WHERE ParentContentFolderId = :folderId
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
                SELECT ContentDocumentId, Title, FileExtension, ContentSize, 
                       LastModifiedDate, Owner.Name
                FROM ContentVersion
                WHERE ContentDocumentId IN :documentIds
                AND IsLatest = true
                ORDER BY Title
            ];
            
            for (ContentVersion version : versions) {
                FileWrapper file = new FileWrapper();
                file.id = version.ContentDocumentId;
                file.title = version.Title;
                file.fileExtension = version.FileExtension != null ? version.FileExtension : '';
                file.formattedSize = formatFileSize(version.ContentSize);
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
            ContentWorkspace workspace = [SELECT Name FROM ContentWorkspace WHERE Id = :libraryId LIMIT 1];
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
            
            while (currentFolderId != null && safety++ < 10) {
                List<ContentFolder> folders = [
                    SELECT Name, ParentContentFolderId 
                    FROM ContentFolder 
                    WHERE Id = :currentFolderId 
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
            
            while (currentFolderId != null && safety++ < 10) {
                List<ContentFolder> folders = [
                    SELECT Name, ParentContentFolderId 
                    FROM ContentFolder 
                    WHERE Id = :currentFolderId 
                    LIMIT 1
                ];
                
                if (folders.isEmpty()) {
                    return breadcrumbs;
                }
                
                ContentFolder folder = folders[0];
                breadcrumbs.add(0, new BreadcrumbWrapper(currentFolderId, folder.Name, false));
                
                if (folder.ParentContentFolderId == null) {
                    break;
                }
                currentFolderId = folder.ParentContentFolderId;
            }
            
            String libraryId = findLibraryForFolder(folderId);
            if (libraryId != null) {
                String libraryName = getLibraryName(libraryId);
                if (libraryName != 'Unknown Library') {
                    breadcrumbs.add(0, new BreadcrumbWrapper(libraryId, libraryName, false));
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
    
    private static List<String> getFileNames(List<String> fileIds) {
        List<String> fileNames = new List<String>();
        try {
            for (ContentVersion version : [
                SELECT Title FROM ContentVersion 
                WHERE ContentDocumentId IN :fileIds AND IsLatest = true
            ]) {
                fileNames.add(version.Title);
            }
        } catch (Exception e) {
            // Return empty list
        }
        return fileNames;
    }
    
    private static String formatFileSize(Integer bytes) {
        if (bytes == null) return '0 B';
        
        if (bytes < 1024) return bytes + ' B';
        if (bytes < 1024 * 1024) return String.valueOf(bytes / 1024) + ' KB';
        if (bytes < 1024 * 1024 * 1024) return String.valueOf(bytes / (1024 * 1024)) + ' MB';
        return String.valueOf(bytes / (1024 * 1024 * 1024)) + ' GB';
    }
    
    private static String getFileIcon(String fileExtension) {
        if (String.isBlank(fileExtension)) return 'doctype:unknown';
        
        String ext = fileExtension.toLowerCase();
        if (ext == 'pdf') return 'doctype:pdf';
        if (ext == 'doc' || ext == 'docx') return 'doctype:word';
        if (ext == 'xls' || ext == 'xlsx') return 'doctype:excel';
        if (ext == 'ppt' || ext == 'pptx') return 'doctype:ppt';
        if (ext == 'jpg' || ext == 'jpeg' || ext == 'png' || ext == 'gif') return 'doctype:image';
        if (ext == 'txt') return 'doctype:txt';
        if (ext == 'zip' || ext == 'rar') return 'doctype:zip';
        return 'doctype:unknown';
    }
    
    private static Boolean isValidId(String s) {
        if (String.isBlank(s)) return false;
        if (s.length() != 15 && s.length() != 18) return false;
        String pattern = '^[a-zA-Z0-9]{15,18}$';
        System.Pattern p = System.Pattern.compile(pattern);
        System.Matcher m = p.matcher(s);
        return m.matches();
    }

    private static String resolveLibraryNameToId(String name) {
        if (String.isBlank(name)) return null;
        List<ContentWorkspace> libs = [SELECT Id FROM ContentWorkspace WHERE Name = :name LIMIT 1];
        if (!libs.isEmpty()) return libs[0].Id;
        return null;
    }

    // Helper: Resolve folder name to ID
    private static String resolveFolderNameToId(String folderName, String libraryId) {
        if (String.isBlank(folderName) || String.isBlank(libraryId)) return null;
        
        if (!libs.isEmpty()) {
            String rootFolderId = libs[0].RootContentFolderId;
            if (rootFolderId != null) {
                List<ContentFolder> folders = [
                    SELECT Id 
                    FROM ContentFolder 
                    WHERE Name = :folderName 
                    AND ParentContentFolderId = :rootFolderId 
                    LIMIT 1
                ];
                if (!folders.isEmpty()) return folders[0].Id;
            }
        }
        
        List<ContentFolder> allFolders = [
            SELECT Id 
            FROM ContentFolder 
            WHERE Name = :folderName 
            AND Id IN (
                SELECT ContentFolderId 
                FROM ContentFolderLink 
                WHERE ParentEntityId = :libraryId
            ) 
            LIMIT 1
        ];
        if (!allFolders.isEmpty()) return allFolders[0].Id;
        
        List<ContentFolder> anyFolders = [SELECT Id FROM ContentFolder WHERE Name = :folderName LIMIT 1];
        if (!anyFolders.isEmpty()) return anyFolders[0].Id;
        
        return null;
    }
    
    // Wrapper Classes - ALL PUBLIC
    
    public class LibraryWrapper {
        @AuraEnabled public String name;
        @AuraEnabled public String label;
        @AuraEnabled public String id;
        @AuraEnabled public Boolean expanded;
        @AuraEnabled public List<FolderWrapper> items;
        
        public LibraryWrapper() {
            this.items = new List<FolderWrapper>();
        }
    }

    public class FolderWrapper {
        @AuraEnabled public String name;
        @AuraEnabled public String label;
        @AuraEnabled public Boolean expanded;
        @AuraEnabled public List<FolderWrapper> items;
        
        public FolderWrapper() {
            this.items = new List<FolderWrapper>();
        }
    }

    public class FileWrapper {
        @AuraEnabled public String id;
        @AuraEnabled public String title;
        @AuraEnabled public String fileExtension;
        @AuraEnabled public String formattedSize;
        @AuraEnabled public DateTime lastModifiedDate;
        @AuraEnabled public String ownerName;
        @AuraEnabled public String iconName;
    }

    public class FileListWrapper {
        @AuraEnabled public List<FileWrapper> files;
        @AuraEnabled public String path;
        @AuraEnabled public List<BreadcrumbWrapper> breadcrumbs;
        
        public FileListWrapper() {
            this.files = new List<FileWrapper>();
            this.breadcrumbs = new List<BreadcrumbWrapper>();
        }
    }

    public class BreadcrumbWrapper {
        @AuraEnabled public String id;
        @AuraEnabled public String label;
        @AuraEnabled public Boolean isLast;
        
        public BreadcrumbWrapper(String id, String label, Boolean isLast) {
            this.id = id;
            this.label = label;
            this.isLast = isLast;
        }
    }
        
    public class OperationResult {
        @AuraEnabled public Boolean success;
        @AuraEnabled public Boolean partialSuccess;
        @AuraEnabled public Integer successCount;
        @AuraEnabled public List<String> errors;
        @AuraEnabled public List<String> warnings;
        @AuraEnabled public Boolean requiresTwoStep;
        @AuraEnabled public String targetLibraryId;
        @AuraEnabled public String targetLibraryName;
        @AuraEnabled public String targetFolderId;
        @AuraEnabled public String targetFolderName;
        
        public OperationResult() {
            this.success = false;
            this.partialSuccess = false;
            this.successCount = 0;
            this.errors = new List<String>();
            this.warnings = new List<String>();
            this.requiresTwoStep = false;
        }
    }
}
