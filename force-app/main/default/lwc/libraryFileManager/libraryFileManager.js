import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getLibrariesWithFolders from '@salesforce/apex/LibraryFileManagerController.getLibrariesWithFolders';
import getLibraryFolders from '@salesforce/apex/LibraryFileManagerController.getLibraryFolders';
import getFilesInFolder from '@salesforce/apex/LibraryFileManagerController.getFilesInFolder';
import smartMoveFiles from '@salesforce/apex/LibraryFileManagerController.smartMoveFiles';
import moveFilesToLibrary from '@salesforce/apex/LibraryFileManagerController.moveFilesToLibrary';
import moveFilesToFolder from '@salesforce/apex/LibraryFileManagerController.moveFilesToFolder';
import deleteFiles from '@salesforce/apex/LibraryFileManagerController.deleteFiles';
import createFolder from '@salesforce/apex/LibraryFileManagerController.createFolder';

export default class LibraryFileManager extends LightningElement {
    @track libraries = [];
    @track selectedFiles = [];
    @track currentFiles = [];
    @track breadcrumbs = [];
    @track isLoadingLibraries = false;
    @track isLoadingFiles = false;
    @track showCreateFolderModal = false;
    @track showDeleteModal = false;
    @track showTwoStepModal = false;
    @track newFolderName = '';
    @track operationInProgress = false;
    @track selectedLibraryId = '';
    @track selectedFolderId = '';
    @track selectedDestinationId = '';
    @track currentPath = '';
    @track showMovePanel = false;
    @track selectedDestinationName = '';
    @track currentLocationName = '';
    @track searchTerm = '';
    @track filteredDestinations = [];
    @track twoStepTargetLibraryId = '';
    @track twoStepTargetLibraryName = '';
    @track twoStepTargetFolderId = '';
    @track twoStepTargetFolderName = '';

    @track currentSelectedItem = '';
    scrollObserver = null;

    fileColumns = [
        {
            label: 'Name',
            fieldName: 'title',
            type: 'text',
            sortable: true,
            cellAttributes: { iconName: { fieldName: 'iconName' } }
        },
        {
            label: 'Type',
            fieldName: 'fileExtension',
            type: 'text',
            sortable: true
        },
        {
            label: 'Size',
            fieldName: 'formattedSize',
            type: 'text',
            sortable: true
        },
        {
            label: 'Modified',
            fieldName: 'lastModifiedDate',
            type: 'date',
            sortable: true
        }
    ];

    connectedCallback() {
        this.loadLibraries();
        this.setupTreeObserver();
    }

    disconnectedCallback() {
        if (this.scrollObserver) {
            this.scrollObserver.disconnect();
            this.scrollObserver = null;
        }
    }

    renderedCallback() {
        if (!this.scrollObserver) {
            this.initializeScrollObserver();
        }
    }

    initializeScrollObserver() {
        const scrollWrapper = this.template.querySelector('.tree-scroll-wrapper');
        if (scrollWrapper) {
            const config = {
                childList: true,
                subtree: true,
                attributes: true,
                attributeFilter: ['aria-selected', 'aria-expanded', 'class']
            };
            
            this.scrollObserver = new MutationObserver((mutations) => {
                mutations.forEach((mutation) => {
                    if (mutation.type === 'attributes') {
                        if (mutation.attributeName === 'aria-selected' && 
                            mutation.target.getAttribute('aria-selected') === 'true') {
                            this.scrollToElement(mutation.target);
                        }
                        else if (mutation.attributeName === 'aria-expanded' && 
                                 mutation.target.getAttribute('aria-expanded') === 'true') {
                            setTimeout(() => this.scrollToElement(mutation.target), 200);
                        }
                    }
                });
            });
            
            this.scrollObserver.observe(scrollWrapper, config);
        }
    }

    get mainLayoutClass() {
        return this.showMovePanel ? 
            'slds-grid slds-gutters three-column-layout' : 
            'slds-grid slds-gutters two-column-layout';
    }

    get treeColumnClass() {
        return this.showMovePanel ? 
            'slds-col slds-size_1-of-1 slds-medium-size_1-of-4 slds-large-size_1-of-4' : 
            'slds-col slds-size_1-of-1 slds-medium-size_1-of-3 slds-large-size_1-of-3';
    }

    get fileColumnClass() {
        return this.showMovePanel ? 
            'slds-col slds-size_1-of-1 slds-medium-size_1-of-2 slds-large-size_1-of-2' : 
            'slds-col slds-size_1-of-1 slds-medium-size_2-of-3 slds-large-size_2-of-3';
    }

    get movePanelClass() {
        return 'slds-col slds-size_1-of-1 slds-medium-size_1-of-4 slds-large-size_1-of-4 move-panel-column slide-in';
    }

    get selectedFileCountPlural() {
        return this.selectedFileCount === 1 ? '' : 's';
    }

    get moveButtonDisabled() {
        return !this.selectedDestinationId || this.operationInProgress;
    }

    get isDestinationMissing() {
        return !this.selectedDestinationId;
    }

    get hasSelectedFiles() {
        return this.selectedFiles.length > 0;
    }

    get noSelectedFiles() {
        return !this.hasSelectedFiles;
    }

    get selectedFileCount() {
        return this.selectedFiles.length;
    }

    get deleteModalTitle() {
        return `Delete ${this.selectedFileCount} file${this.selectedFileCountPlural}`;
    }

    get deleteConfirmationText() {
        return `Are you sure you want to delete ${this.selectedFileCount} file${this.selectedFileCountPlural}?`;
    }

    get currentLocationDisplayName() {
        if (this.currentLocationName && this.currentLocationName !== 'Unknown Path') {
            const parts = this.currentLocationName.split(' > ');
            let finalPart = parts[parts.length - 1];
            finalPart = finalPart.replace(/\s*\(\d+\s*files?\)$/, '');
            return finalPart;
        }
        
        if (this.currentPath && this.currentPath !== 'Unknown Path') {
            const parts = this.currentPath.split(' > ');
            return parts[parts.length - 1];
        }
        
        if (this.breadcrumbs && this.breadcrumbs.length > 0) {
            const lastBreadcrumb = this.breadcrumbs[this.breadcrumbs.length - 1];
            return lastBreadcrumb.label;
        }
        
        return 'Select a library or folder';
    }

    get breadcrumbPath() {
        if (this.currentLocationName && this.currentLocationName !== 'Unknown Path') {
            return this.currentLocationName;
        }
        
        if (this.breadcrumbs && this.breadcrumbs.length > 1) {
            return this.breadcrumbs.map(b => b.label).join(' > ');
        }
        
        return '';
    }

    get showNavigationBreadcrumbs() {
        return this.breadcrumbs && this.breadcrumbs.length > 1;
    }

    loadLibraries() {
        this.isLoadingLibraries = true;
        
        return getLibrariesWithFolders()
            .then(result => {
                this.libraries = result;
                this.updateFilteredDestinations();
                this.isLoadingLibraries = false;
                return result;
            })
            .catch(error => {
                this.showError('Error loading libraries', error.body?.message || error.message);
                this.isLoadingLibraries = false;
                throw error;
            });
    }

    loadFoldersForLibrary(libraryId) {
        const treeContainer = this.template.querySelector('.library-tree-container');
        const scrollTop = treeContainer?.scrollTop || 0;
        
        return getLibraryFolders({ libraryId: libraryId })
            .then(folders => {
                function normalizeFolders(folders) {
                    return (folders || []).map(folder => ({
                        label: (folder.label && typeof folder.label === 'string') ? folder.label : (folder.name || ''),
                        name: folder.name || '',
                        items: Array.isArray(folder.items) ? normalizeFolders(folder.items) : [],
                        expanded: folder.expanded === true
                    }));
                }
                
                const normalizedFolders = normalizeFolders(folders);
                const libIdx = this.libraries.findIndex(lib => lib.id === libraryId);
                
                if (libIdx !== -1) {
                    const updatedLibrary = {
                        ...this.libraries[libIdx],
                        items: normalizedFolders,
                        expanded: true
                    };
                    this.libraries = [
                        ...this.libraries.slice(0, libIdx),
                        updatedLibrary,
                        ...this.libraries.slice(libIdx + 1)
                    ];
                    this.updateFilteredDestinations();
                }
                
                if (scrollTop > 0) {
                    setTimeout(() => {
                        if (treeContainer) {
                            treeContainer.scrollTop = scrollTop;
                        }
                    }, 100);
                }
                
                return normalizedFolders;
            })
            .catch(error => {
                this.showError('Error loading library folders', error.body?.message || error.message);
                return [];
            });
    }

    handleTreeSelect(event) {
        const selectedItem = event.detail.name;
        if (!selectedItem) {
            return;
        }
        
        this.selectedLibraryId = '';
        this.selectedFolderId = '';
        
        if (selectedItem.startsWith('058')) {
            this.selectedLibraryId = selectedItem;
            this.loadFilesInFolder(selectedItem, null);
        } else if (selectedItem.startsWith('placeholder_')) {
            const libraryId = selectedItem.replace('placeholder_', '');
            this.selectedLibraryId = libraryId;
            this.loadFoldersForLibrary(libraryId);
        } else {
            this.selectedFolderId = selectedItem;
            const libraryId = this.findLibraryForFolder(selectedItem);
            if (!libraryId) {
                this.showError('Error', 'Could not find library for selected folder');
                return;
            }
            this.selectedLibraryId = libraryId;
            this.loadFilesInFolder(libraryId, selectedItem);
        }
    }

    findLibraryForFolder(folderId) {
        for (let library of this.libraries) {
            if (this.searchFolderInTree(library.items, folderId)) {
                return library.id;
            }
        }
        return null;
    }

    searchFolderInTree(folders, targetId) {
        for (let folder of folders) {
            if (folder.name === targetId) {
                return true;
            }
            if (folder.items && this.searchFolderInTree(folder.items, targetId)) {
                return true;
            }
        }
        return false;
    }

    loadFilesInFolder(libraryId, folderId) {
        if (!libraryId) {
            this.showError('Error', 'Library ID is required');
            return;
        }
        
        this.isLoadingFiles = true;
        
        getFilesInFolder({ 
            libraryId: libraryId, 
            folderId: folderId || null,
            isTestRootFolder: false 
        })
            .then(result => {
                this.currentFiles = result.files || [];
                this.breadcrumbs = result.breadcrumbs || [];
                this.currentPath = result.path || '';
                this.selectedFiles = [];
                this.isLoadingFiles = false;
                
                this.updateCurrentLocationName();
            })
            .catch(error => {
                this.showError('Error loading files', error.body?.message || error.message);
                this.isLoadingFiles = false;
                
                this.currentFiles = [];
                this.breadcrumbs = [];
                this.currentPath = '';
                this.selectedFiles = [];
            });
    }

    updateCurrentLocationName() {
        if (this.selectedLibraryId) {
            const selectedLibrary = this.libraries.find(lib => 
                lib.id === this.selectedLibraryId || lib.name === this.selectedLibraryId
            );
            
            if (selectedLibrary) {
                if (this.selectedFolderId) {
                    const folderName = this.findFolderName(selectedLibrary.items, this.selectedFolderId);
                    if (folderName) {
                        this.currentLocationName = `${selectedLibrary.label} > ${folderName}`;
                        return;
                    }
                }
                this.currentLocationName = selectedLibrary.label;
                return;
            }
        }
        
        if (this.currentPath && 
            this.currentPath.trim() && 
            this.currentPath !== 'Unknown Path' && 
            this.currentPath !== 'Unknown Library') {
            this.currentLocationName = this.currentPath;
            return;
        }
        
        if (this.breadcrumbs && this.breadcrumbs.length > 0) {
            this.currentLocationName = this.breadcrumbs.map(b => b.label).join(' > ');
            return;
        }
        
        this.currentLocationName = 'Current location';
    }

    findFolderName(folders, targetId) {
        if (!folders || !Array.isArray(folders)) return null;
        
        for (let folder of folders) {
            if (folder.name === targetId) {
                return folder.label || folder.name;
            }
            if (folder.items && folder.items.length > 0) {
                const found = this.findFolderName(folder.items, targetId);
                if (found) return found;
            }
        }
        return null;
    }

    handleFileSelection(event) {
        this.selectedFiles = event.detail.selectedRows;
    }

    handleMoveFiles() {
        if (this.selectedFiles.length === 0) {
            this.showError('Error', 'Please select files to move');
            return;
        }
        this.showMovePanel = true;
        this.updateFilteredDestinations();
        this.updateCurrentLocationName();
    }

    closeMovePanel() {
        this.showMovePanel = false;
        this.selectedDestinationId = '';
        this.selectedDestinationName = '';
        this.searchTerm = '';
        this.updateFilteredDestinations();
    }

    handleSearchChange(event) {
        this.searchTerm = event.target.value;
        this.updateFilteredDestinations();
    }

    updateFilteredDestinations() {
        if (!this.searchTerm) {
            this.filteredDestinations = this.libraries.map(lib => ({
                ...lib,
                expanded: lib.items && lib.items.length > 0
            }));
            return;
        }

        const searchLower = this.searchTerm.toLowerCase();
        
        const filterTree = (items) => {
            return items.reduce((filtered, item) => {
                const matchesSearch = item.label.toLowerCase().includes(searchLower);
                const filteredChildren = item.items ? filterTree(item.items) : [];
                
                if (matchesSearch || filteredChildren.length > 0) {
                    filtered.push({
                        ...item,
                        items: filteredChildren,
                        expanded: filteredChildren.length > 0
                    });
                }
                
                return filtered;
            }, []);
        };

        this.filteredDestinations = filterTree(this.libraries);
    }

    handleDestinationSelect(event) {
        this.selectedDestinationId = event.detail.name;
        this.updateSelectedDestinationName();
    }

    updateSelectedDestinationName() {
        if (!this.selectedDestinationId) {
            this.selectedDestinationName = '';
            return;
        }

        const findLabel = (items, targetId) => {
            for (let item of items) {
                if (item.name === targetId || item.id === targetId) {
                    return item.label;
                }
                if (item.items) {
                    const childResult = findLabel(item.items, targetId);
                    if (childResult) return childResult;
                }
            }
            return null;
        };

        const label = findLabel(this.libraries, this.selectedDestinationId);
        this.selectedDestinationName = label || 'Selected destination';
    }

    handleMoveConfirm() {
        if (!this.selectedDestinationId) {
            this.showError('Error', 'Please select a destination');
            return;
        }

        this.operationInProgress = true;
        const fileIds = this.selectedFiles.map(file => file.id);
        const destinationType = this.selectedDestinationId.startsWith('058') ? 'library' : 'folder';
        const moveToDestinationId = this.selectedDestinationId;
        
        smartMoveFiles({
            fileIds: fileIds,
            destinationId: this.selectedDestinationId,
            destinationType: destinationType
        })
            .then(result => {
                if (result.success) {
                    if (result.partialSuccess) {
                        this.showWarning('Files Moved with Notes', 
                            result.errors.join('\n'));
                    } else {
                        this.showSuccess('Files Moved Successfully', 
                            `${result.successCount} files moved to destination successfully.`);
                    }
                    
                    this.closeMovePanel();
                    
                    this.loadLibraries().then(() => {
                        setTimeout(() => {
                            this.navigateToDestination(moveToDestinationId, destinationType);
                        }, 500);
                    }).catch(() => {
                        setTimeout(() => {
                            this.navigateToDestination(moveToDestinationId, destinationType);
                        }, 1000);
                    });
                    
                } else {
                    if (result.requiresTwoStep) {
                        this.twoStepTargetLibraryId = result.targetLibraryId;
                        this.twoStepTargetLibraryName = result.targetLibraryName;
                        this.twoStepTargetFolderId = result.targetFolderId;
                        this.twoStepTargetFolderName = result.targetFolderName;
                        this.closeMovePanel();
                        this.showTwoStepModal = true;
                    } else {
                        this.showError('Move Failed', result.errors.join('\n'));
                    }
                }
            })
            .catch(error => {
                this.showError('Error moving files', error.body?.message || error.message);
            })
            .finally(() => {
                this.operationInProgress = false;
            });
    }

    navigateToDestination(destinationId, destinationType) {
        try {
            if (destinationType === 'library') {
                this.selectedLibraryId = destinationId;
                this.selectedFolderId = '';
                this.loadFilesInFolder(destinationId, null);
                
                setTimeout(() => {
                    this.updateTreeSelection(destinationId);
                }, 500);
                
            } else if (destinationType === 'folder') {
                const libraryId = this.findLibraryForFolder(destinationId);
                if (libraryId) {
                    this.selectedLibraryId = libraryId;
                    this.selectedFolderId = destinationId;
                    this.ensureLibraryExpandedAndNavigate(libraryId, destinationId);
                } else {
                    this.refreshCurrentView();
                }
            }
            
        } catch (error) {
            this.refreshCurrentView();
        }
    }

    ensureLibraryExpandedAndNavigate(libraryId, folderId) {
        const libraryIndex = this.libraries.findIndex(lib => lib.id === libraryId);
        if (libraryIndex !== -1) {
            if (!this.libraries[libraryIndex].expanded) {
                this.loadFoldersForLibrary(libraryId).then(() => {
                    this.loadFilesInFolder(libraryId, folderId);
                    setTimeout(() => {
                        this.updateTreeSelection(folderId);
                    }, 800);
                });
            } else {
                this.loadFilesInFolder(libraryId, folderId);
                setTimeout(() => {
                    this.updateTreeSelection(folderId);
                }, 500);
            }
        } else {
            this.refreshCurrentView();
        }
    }

    updateTreeSelection(itemId) {
        setTimeout(() => {
            const tree = this.template.querySelector('lightning-tree');
            if (tree) {
                tree.selectedItem = itemId;
                setTimeout(() => {
                    this.scrollTreeIntoView(tree, itemId);
                }, 800);
            }
        }, 300);
    }

    scrollTreeIntoView(tree, itemId) {
        try {
            tree.scrollIntoView({
                behavior: 'smooth',
                block: 'center'
            });
            
            const treeContainer = this.template.querySelector('.library-tree-container');
            if (treeContainer) {
                treeContainer.style.transition = 'border 0.5s ease';
                treeContainer.style.border = '2px solid rgba(0, 112, 210, 0.8)';
                setTimeout(() => {
                    treeContainer.style.border = '';
                }, 2000);
            }
            
            return true;
            
        } catch (error) {
            this.tryContainerBasedScroll(itemId);
        }
    }
    
    tryContainerBasedScroll(itemId) {
        const treeContainer = this.template.querySelector('.library-tree-container');
        if (!treeContainer) {
            return;
        }
        
        const scrollHeight = treeContainer.scrollHeight;
        const clientHeight = treeContainer.clientHeight;
        const maxScroll = scrollHeight - clientHeight;
        
        let targetPosition = 0;
        
        if (itemId && itemId.startsWith('07H')) {
            targetPosition = scrollHeight * 0.75;
        } else if (itemId && itemId.startsWith('058')) {
            targetPosition = scrollHeight * 0.1;
        } else {
            targetPosition = scrollHeight * 0.5;
        }
        
        const finalPosition = Math.max(0, Math.min(targetPosition, maxScroll));
        
        treeContainer.scrollTo({
            top: finalPosition,
            behavior: 'smooth'
        });
        
        treeContainer.style.transition = 'border 0.5s ease, box-shadow 0.5s ease';
        treeContainer.style.border = '3px solid rgba(40, 180, 40, 0.8)';
        treeContainer.style.boxShadow = '0 0 15px rgba(40, 180, 40, 0.6)';
        
        setTimeout(() => {
            treeContainer.style.border = '';
            treeContainer.style.boxShadow = '';
        }, 3000);
    }

    scrollToElement(targetElement) {
        const scrollWrapper = this.template.querySelector('.tree-scroll-wrapper');
        
        if (!scrollWrapper || !targetElement) {
            return;
        }
        
        try {
            const wrapperRect = scrollWrapper.getBoundingClientRect();
            const targetRect = targetElement.getBoundingClientRect();
            
            const targetTop = targetRect.top - wrapperRect.top + scrollWrapper.scrollTop;
            const wrapperCenter = wrapperRect.height / 2;
            const targetCenter = targetRect.height / 2;
            
            const scrollPosition = targetTop - wrapperCenter + targetCenter;
            
            const maxScroll = scrollWrapper.scrollHeight - scrollWrapper.clientHeight;
            const finalPosition = Math.max(0, Math.min(scrollPosition, maxScroll));
            
            scrollWrapper.classList.add('scrolling');
            
            scrollWrapper.scrollTo({
                top: finalPosition,
                behavior: 'smooth'
            });
            
            setTimeout(() => {
                scrollWrapper.classList.remove('scrolling');
            }, 500);
            
            this.highlightElement(targetElement);
            
        } catch (error) {
            // Silently fail
        }
    }

    highlightElement(element) {
        const originalStyle = element.style.cssText;
        
        element.style.transition = 'all 0.3s ease';
        element.style.backgroundColor = 'rgba(0, 112, 210, 0.2)';
        element.style.transform = 'scale(1.02)';
        element.style.boxShadow = '0 2px 8px rgba(0, 112, 210, 0.3)';
        
        setTimeout(() => {
            element.style.backgroundColor = '';
            element.style.transform = '';
            element.style.boxShadow = '';
            setTimeout(() => {
                element.style.cssText = originalStyle;
            }, 300);
        }, 2000);
    }

    handleBreadcrumbClick(event) {
        const breadcrumbId = event.target.dataset.id;
        if (breadcrumbId) {
            const isLibrary = breadcrumbId.startsWith('058');
            if (isLibrary) {
                this.selectedLibraryId = breadcrumbId;
                this.selectedFolderId = '';
                this.loadFilesInFolder(breadcrumbId, null);
                setTimeout(() => {
                    this.updateTreeSelection(breadcrumbId);
                }, 500);
            } else {
                const libraryId = this.findLibraryForFolder(breadcrumbId);
                if (libraryId) {
                    this.selectedLibraryId = libraryId;
                    this.selectedFolderId = breadcrumbId;
                    this.ensureLibraryExpandedAndNavigate(libraryId, breadcrumbId);
                }
            }
        }
    }

    setupTreeObserver() {
        const lightningTree = this.template.querySelector('lightning-tree');
        if (lightningTree && !this.treeObserver) {
            const config = {
                childList: true,
                subtree: true,
                attributes: true,
                attributeFilter: ['aria-expanded', 'aria-selected']
            };
            
            this.treeObserver = new MutationObserver((mutations) => {
                mutations.forEach((mutation) => {
                    if (mutation.type === 'attributes') {
                        if (mutation.attributeName === 'aria-expanded' && 
                            mutation.target.getAttribute('aria-expanded') === 'true') {
                            setTimeout(() => {
                                this.scrollToElement(mutation.target);
                            }, 100);
                        }
                    }
                });
            });
            
            this.treeObserver.observe(lightningTree, config);
        }
    }

    handleCreateFolder() {
        this.showCreateFolderModal = true;
    }

    handleFolderNameChange(event) {
        this.newFolderName = event.target.value;
    }

    handleCreateFolderConfirm() {
        if (!this.newFolderName.trim()) {
            this.showError('Error', 'Folder name is required');
            return;
        }

        const currentLibraryId = this.selectedLibraryId;
        const currentFolderId = this.selectedFolderId;
        const currentLocationName = this.currentLocationName;

        this.operationInProgress = true;
        createFolder({
            folderName: this.newFolderName.trim(),
            parentLibraryId: this.selectedLibraryId,
            parentFolderId: this.selectedFolderId
        })
            .then(() => {
                this.showSuccess('Success', 'Folder created successfully');
                this.closeCreateFolderModal();
                this.refreshLibrariesAndMaintainState(currentLibraryId, currentFolderId, currentLocationName);
            })
            .catch(error => {
                this.showError('Error creating folder', error.body?.message || error.message);
            })
            .finally(() => {
                this.operationInProgress = false;
            });
    }

    refreshLibrariesAndMaintainState(libraryId, folderId, locationName) {
        const treeContainer = this.template.querySelector('.library-tree-container');
        const scrollTop = treeContainer?.scrollTop || 0;
        
        this.loadLibraries()
            .then(() => {
                this.selectedLibraryId = libraryId;
                this.selectedFolderId = folderId;
                this.currentLocationName = locationName;
                
                if (libraryId) {
                    return this.loadFoldersForLibrary(libraryId);
                }
            })
            .then(() => {
                setTimeout(() => {
                    const targetId = folderId || libraryId;
                    if (targetId) {
                        this.updateTreeSelection(targetId);
                    }
                    
                    if (scrollTop > 0 && treeContainer) {
                        treeContainer.scrollTop = scrollTop;
                    }
                }, 500);
                
                this.loadFilesInFolder(libraryId, folderId);
            })
            .catch(error => {
                this.refreshCurrentView();
            });
    }

    closeCreateFolderModal() {
        this.showCreateFolderModal = false;
        this.newFolderName = '';
    }

    handleDeleteFiles() {
        if (this.selectedFiles.length === 0) {
            this.showError('Error', 'Please select files to delete');
            return;
        }
        this.showDeleteModal = true;
    }

    handleDeleteConfirm() {
        this.operationInProgress = true;
        const fileIds = this.selectedFiles.map(file => file.id);
        
        deleteFiles({ fileIds: fileIds })
            .then(result => {
                if (result.success) {
                    this.showSuccess('Success', `${result.successCount} files deleted successfully`);
                    if (result.errors && result.errors.length > 0) {
                        this.showWarning('Partial Success', `${result.errors.length} files could not be deleted.`);
                    }
                } else {
                    this.showError('Delete Failed', result.errors.join('\n'));
                }
                this.closeDeleteModal();
                this.loadFilesInFolder(this.selectedLibraryId, this.selectedFolderId);
                this.loadLibraries();
            })
            .catch(error => {
                this.showError('Error deleting files', error.body?.message || error.message);
            })
            .finally(() => {
                this.operationInProgress = false;
            });
    }

    closeDeleteModal() {
        this.showDeleteModal = false;
    }

    closeTwoStepModal() {
        this.showTwoStepModal = false;
        this.twoStepTargetLibraryId = '';
        this.twoStepTargetLibraryName = '';
        this.twoStepTargetFolderId = '';
        this.twoStepTargetFolderName = '';
    }

    executeTwoStepMove() {
        this.operationInProgress = true;
        const fileIds = this.selectedFiles.map(file => file.id);
        const targetLibraryId = this.twoStepTargetLibraryId;
        const targetFolderId = this.twoStepTargetFolderId;
        
        moveFilesToLibrary({ fileIds: fileIds, targetLibraryId: targetLibraryId })
            .then(libraryResult => {
                if (libraryResult.success) {
                    let stepMessage = `Files added to ${this.twoStepTargetLibraryName}.`;
                    
                    if (libraryResult.partialSuccess) {
                        stepMessage += ' Some files remain shared in their original libraries.';
                    }
                    
                    this.showInfo('Step 1 Complete', stepMessage + ' Now organizing into folder...');
                    
                    return moveFilesToFolder({ 
                        fileIds: fileIds, 
                        targetFolderId: targetFolderId,
                        targetLibraryId: targetLibraryId 
                    });
                } else {
                    throw new Error('Library move failed: ' + libraryResult.errors.join(', '));
                }
            })
            .then(folderResult => {
                if (folderResult.success) {
                    this.showSuccess('Two-Step Move Complete!', 
                        `Files successfully organized in ${this.twoStepTargetFolderName}`);
                    this.closeTwoStepModal();
                    
                    this.loadLibraries().then(() => {
                        setTimeout(() => {
                            this.navigateToDestination(targetFolderId, 'folder');
                        }, 500);
                    }).catch(() => {
                        setTimeout(() => {
                            this.navigateToDestination(targetFolderId, 'folder');
                        }, 1000);
                    });
                    
                } else {
                    this.showWarning('Partial Organization Complete', 
                        `Files moved to ${this.twoStepTargetLibraryName} but folder organization had issues.`);
                    this.closeTwoStepModal();
                    
                    this.loadLibraries().then(() => {
                        setTimeout(() => {
                            this.navigateToDestination(targetLibraryId, 'library');
                        }, 500);
                    }).catch(() => {
                        setTimeout(() => {
                            this.navigateToDestination(targetLibraryId, 'library');
                        }, 1000);
                    });
                }
            })
            .catch(error => {
                this.showError('Two-Step Move Failed', error.message || error.body?.message);
            })
            .finally(() => {
                this.operationInProgress = false;
            });
    }

    handleRefresh() {
        this.loadLibraries();
        if (this.selectedLibraryId) {
            this.loadFilesInFolder(this.selectedLibraryId, this.selectedFolderId);
        }
    }

    refreshCurrentView() {
        this.loadFilesInFolder(this.selectedLibraryId, this.selectedFolderId);
        this.loadLibraries();
    }

    showSuccess(title, message) {
        this.dispatchEvent(new ShowToastEvent({
            title: title,
            message: message,
            variant: 'success'
        }));
    }

    showError(title, message) {
        this.dispatchEvent(new ShowToastEvent({
            title: title,
            message: message,
            variant: 'error',
            mode: 'sticky'
        }));
    }

    showWarning(title, message) {
        this.dispatchEvent(new ShowToastEvent({
            title: title,
            message: message,
            variant: 'warning',
            mode: 'sticky'
        }));
    }

    showInfo(title, message) {
        this.dispatchEvent(new ShowToastEvent({
            title: title,
            message: message,
            variant: 'info',
            mode: 'dismissable'
        }));
    }
}