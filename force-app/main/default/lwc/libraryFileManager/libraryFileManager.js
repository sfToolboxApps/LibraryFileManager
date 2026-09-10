import { LightningElement, track } from "lwc";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import MOVE_ICON from "@salesforce/resourceUrl/moveIcon";
import getLibrariesWithFolders from "@salesforce/apex/LibraryFileManagerController.getLibrariesWithFolders";
import getFilesInFolder from "@salesforce/apex/LibraryFileManagerController.getFilesInFolder";
import smartMoveFiles from "@salesforce/apex/LibraryFileManagerController.smartMoveFiles";
import deleteFiles from "@salesforce/apex/LibraryFileManagerController.deleteFiles";
import createFolder from "@salesforce/apex/LibraryFileManagerController.createFolder";

const GITHUB_REPO_URL = "https://github.com/sfToolboxApps/LibraryFileManager";

export default class LibraryFileManager extends LightningElement {
  moveIconUrl = MOVE_ICON;
  githubReadmeUrl = `${GITHUB_REPO_URL}#readme`;
  githubIssuesUrl = `${GITHUB_REPO_URL}/issues`;
  giveBackUrl = "https://biggestlittledreamin.com";

  @track libraries = [];
  @track treeLibraries = [];
  @track selectedFiles = [];
  @track currentFiles = [];
  @track displayedFiles = [];
  @track fileSearchTerm = "";
  @track breadcrumbs = [];
  @track isLoadingLibraries = false;
  @track isLoadingFiles = false;
  @track showCreateFolderModal = false;
  @track showDeleteModal = false;
  @track newFolderName = "";
  @track operationInProgress = false;
  @track selectedLibraryId = "";
  @track selectedFolderId = "";
  @track selectedDestinationId = "";
  @track currentPath = "";
  @track showMovePanel = false;
  @track showFilesToMoveList = false;
  @track selectedDestinationName = "";
  @track currentLocationName = "";
  @track searchTerm = "";
  @track filteredDestinations = [];

  @track currentSelectedItem = "";
  scrollObserver = null;

  fileColumns = [
    {
      label: "Name",
      fieldName: "title",
      type: "text",
      sortable: true,
      cellAttributes: { iconName: { fieldName: "iconName" } }
    },
    {
      label: "Type",
      fieldName: "fileExtension",
      type: "text",
      sortable: true
    },
    {
      label: "Size",
      fieldName: "formattedSize",
      type: "text",
      sortable: true
    },
    {
      label: "Modified",
      fieldName: "lastModifiedDate",
      type: "date",
      sortable: true
    },
    {
      label: "Owner",
      fieldName: "ownerName",
      type: "text",
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
    const scrollWrapper = this.template.querySelector(".tree-scroll-wrapper");
    if (scrollWrapper) {
      const config = {
        childList: true,
        subtree: true,
        attributes: true,
        attributeFilter: ["aria-selected", "aria-expanded", "class"]
      };

      this.scrollObserver = new MutationObserver((mutations) => {
        mutations.forEach((mutation) => {
          if (mutation.type === "attributes") {
            if (
              mutation.attributeName === "aria-selected" &&
              mutation.target.getAttribute("aria-selected") === "true"
            ) {
              this.scrollToElement(mutation.target);
            } else if (
              mutation.attributeName === "aria-expanded" &&
              mutation.target.getAttribute("aria-expanded") === "true"
            ) {
              // eslint-disable-next-line @lwc/lwc/no-async-operation -- deliberate UI timing (scroll-into-view / post-navigation reselection), no clean alternative
              setTimeout(() => this.scrollToElement(mutation.target), 200);
            }
          }
        });
      });

      this.scrollObserver.observe(scrollWrapper, config);
    }
  }

  get mainLayoutClass() {
    return this.showMovePanel
      ? "slds-grid slds-gutters three-column-layout app-content-row"
      : "slds-grid slds-gutters two-column-layout app-content-row";
  }

  get treeColumnClass() {
    return this.showMovePanel
      ? "slds-col slds-size_1-of-1 slds-medium-size_1-of-4 slds-large-size_1-of-4"
      : "slds-col slds-size_1-of-1 slds-medium-size_1-of-3 slds-large-size_1-of-3";
  }

  get fileColumnClass() {
    return this.showMovePanel
      ? "slds-col slds-size_1-of-1 slds-medium-size_1-of-2 slds-large-size_1-of-2"
      : "slds-col slds-size_1-of-1 slds-medium-size_2-of-3 slds-large-size_2-of-3";
  }

  get movePanelClass() {
    return "slds-col slds-size_1-of-1 slds-medium-size_1-of-4 slds-large-size_1-of-4 move-panel-column slide-in";
  }

  get selectedFileCountPlural() {
    return this.selectedFileCount === 1 ? "" : "s";
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

  get noLibrarySelected() {
    return !this.selectedLibraryId;
  }

  // inverse (white) only makes sense against Create Folder's blue enabled background;
  // when disabled the button goes grey with dark text, so the icon must drop back to
  // its default dark color too, or it stays white against the light grey background.
  get createFolderIconVariant() {
    return this.noLibrarySelected ? "" : "inverse";
  }

  get selectedFileCount() {
    return this.selectedFiles.length;
  }

  // Mirrors LibraryFileManagerController.formatFileSize exactly (same
  // thresholds, same integer-division rounding), applied to the sum of the
  // raw contentSize bytes now returned alongside the pre-formatted string.
  get totalSelectedSizeFormatted() {
    const totalBytes = this.selectedFiles.reduce(
      (sum, file) => sum + (file.contentSize || 0),
      0
    );
    if (totalBytes < 1024) {
      return `${totalBytes} B`;
    }
    if (totalBytes < 1024 * 1024) {
      return `${Math.floor(totalBytes / 1024)} KB`;
    }
    if (totalBytes < 1024 * 1024 * 1024) {
      return `${Math.floor(totalBytes / (1024 * 1024))} MB`;
    }
    return `${Math.floor(totalBytes / (1024 * 1024 * 1024))} GB`;
  }

  get deleteModalTitle() {
    return `Delete ${this.selectedFileCount} file${this.selectedFileCountPlural}`;
  }

  get deleteConfirmationText() {
    return `Are you sure you want to delete ${this.selectedFileCount} file${this.selectedFileCountPlural}?`;
  }

  get currentLocationDisplayName() {
    if (this.breadcrumbs && this.breadcrumbs.length > 0) {
      return this.breadcrumbs[this.breadcrumbs.length - 1].label;
    }
    return "Select a library or folder";
  }

  // Full path is always derived from the server-computed breadcrumbs, so it stays
  // accurate at any nesting depth and consistent between library root and subfolders.
  get fullLocationPath() {
    if (this.breadcrumbs && this.breadcrumbs.length > 0) {
      return this.breadcrumbs.map((b) => b.label).join(" > ");
    }
    return "";
  }

  get hasLocationSelected() {
    return this.fullLocationPath !== "";
  }

  get fileRowCount() {
    return (this.currentFiles || []).filter((row) => !row.isFolder).length;
  }

  get folderRowCount() {
    return (this.currentFiles || []).filter((row) => row.isFolder).length;
  }

  get itemCountLabel() {
    const files = this.fileRowCount;
    const folders = this.folderRowCount;

    if (files === 0 && folders === 0) {
      return "No files found";
    }
    if (folders === 0) {
      return `${files} file${files === 1 ? "" : "s"}`;
    }
    if (files === 0) {
      return `${folders} folder${folders === 1 ? "" : "s"}`;
    }
    return `${folders} folder${folders === 1 ? "" : "s"}, ${files} file${files === 1 ? "" : "s"}`;
  }

  get showNavigationBreadcrumbs() {
    return this.breadcrumbs && this.breadcrumbs.length > 1;
  }

  // Tree display only: appends each library's file count to its label without
  // mutating the underlying libraries array (which stays clean for path/name lookups).
  // Built explicitly whenever `libraries` legitimately changes (not a getter) so
  // lightning-tree's items reference stays stable across unrelated re-renders -
  // a getter here previously produced a new array/object identity on EVERY render
  // (even ones triggered by unrelated state like file navigation), which caused
  // lightning-tree to reset its internal expand/select state and collapse the tree.
  // Deliberately no per-item cache here (a WeakMap was tried and removed) - the
  // dataset is small enough (<1000 items) that recomputing fresh every time is
  // cheap, and it removes any possible doubt about stale cached state. The only
  // memoization kept is the last (input array -> output array) pair: calling
  // this again with the EXACT same libraries reference (a genuine no-op) hands
  // back the exact same treeLibraries array too, instead of an equal-but-new one.
  buildTreeLibraries(libraries) {
    if (
      this.lastTreeLibrariesInput === libraries &&
      this.lastTreeLibrariesOutput
    ) {
      return this.lastTreeLibrariesOutput;
    }
    const result = (libraries || []).map((lib) => {
      const count = lib.fileCount || 0;
      return {
        ...lib,
        label: `${lib.label} (${count} file${count === 1 ? "" : "s"})`
      };
    });
    this.lastTreeLibrariesInput = libraries;
    this.lastTreeLibrariesOutput = result;
    return result;
  }

  loadLibraries() {
    this.isLoadingLibraries = true;

    return getLibrariesWithFolders()
      .then((result) => {
        this.libraries = result;
        this.treeLibraries = this.buildTreeLibraries(this.libraries);
        this.updateFilteredDestinations();
        this.isLoadingLibraries = false;
        return result;
      })
      .catch((error) => {
        this.showError(
          "Error loading libraries",
          error.body?.message || error.message
        );
        this.isLoadingLibraries = false;
        throw error;
      });
  }

  // getLibrariesWithFolders (called from loadLibraries) already eager-loads
  // the complete nested folder tree for every library up front - there is no
  // real lazy-loading left in this app, so a select is pure navigation
  // (which folder's files to show) and NEVER touches libraries/treeLibraries.
  //
  // This is deliberately hands-off, and that took two earlier attempts to
  // get right - both failed the same way for a reason worth recording:
  //   1. Toggling only the clicked node's own value (leaving ancestors
  //      alone) let a chevron-opened ancestor's stale expanded:false get
  //      handed back to lightning-tree the moment something inside it was
  //      clicked, snapping that ancestor shut.
  //   2. Fixing that by forcing every ancestor on the clicked path to
  //      expanded:true solved #1, but introduced a worse bug: forcing true
  //      on every click has nothing that ever sets a node back to false, so
  //      after enough clicking around, most/every library in `libraries`
  //      quietly accumulates a permanent expanded:true - even ones the user
  //      has since visually closed via the chevron. The next click that
  //      pushes ANY new treeLibraries reference then resyncs the WHOLE tree
  //      from that data, and everything with leftover true residue pops
  //      back open at once.
  // The common thread: lightning-tree appears to resync every row's visual
  // state from `items` on any reference change, not just the rows whose
  // object reference actually changed - so the only reference our data can
  // safely push is the FULL, exact truth for every single node, which we
  // can never have (the chevron tells us nothing). The only safe move left
  // is to never push at all in response to a click, and let lightning-tree
  // own expand/collapse for both the label and the chevron entirely on its
  // own, uncontrolled, the way the component is actually designed to work.
  handleTreeSelect(event) {
    const selectedItem = event.detail.name;
    if (!selectedItem) {
      return;
    }

    this.selectedLibraryId = "";
    this.selectedFolderId = "";

    if (selectedItem.startsWith("058")) {
      this.selectedLibraryId = selectedItem;
      this.loadFilesInFolder(selectedItem, null);
    } else {
      this.selectedFolderId = selectedItem;
      const libraryId = this.findLibraryForFolder(selectedItem);
      if (!libraryId) {
        this.showError("Error", "Could not find library for selected folder");
        return;
      }
      this.selectedLibraryId = libraryId;
      this.loadFilesInFolder(libraryId, selectedItem);
    }
  }

  // Used only for programmatic re-navigation (e.g. re-selecting a Move
  // destination after libraries reload, or after a folder create/refresh) -
  // never from a direct click. Always starts from a fully collapsed baseline
  // before forcing the target path true, rather than building on top of
  // `libraries`' current state, so it can never surface leftover expanded
  // residue from earlier in the session - the same accumulation bug this
  // whole rewrite exists to eliminate.
  expandPathToTarget(items, targetId) {
    return this.setExpandedOnPath(this.collapseAllNodes(items), targetId);
  }

  collapseAllNodes(items) {
    return (items || []).map((item) => ({
      ...item,
      expanded: false,
      items:
        item.items && item.items.length > 0
          ? this.collapseAllNodes(item.items)
          : item.items
    }));
  }

  setExpandedOnPath(items, targetId) {
    return (items || []).map((item) => {
      if (item.name === targetId) {
        return { ...item, expanded: true };
      }
      if (
        item.items &&
        item.items.length > 0 &&
        this.containsNode(item.items, targetId)
      ) {
        return {
          ...item,
          expanded: true,
          items: this.setExpandedOnPath(item.items, targetId)
        };
      }
      return item;
    });
  }

  containsNode(items, targetId) {
    for (const item of items || []) {
      if (item.name === targetId) {
        return true;
      }
      if (
        item.items &&
        item.items.length > 0 &&
        this.containsNode(item.items, targetId)
      ) {
        return true;
      }
    }
    return false;
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
      this.showError("Error", "Library ID is required");
      return;
    }

    this.isLoadingFiles = true;

    getFilesInFolder({
      libraryId: libraryId,
      folderId: folderId || null
    })
      .then((result) => {
        this.currentFiles = result.files || [];
        this.breadcrumbs = result.breadcrumbs || [];
        this.currentPath = result.path || "";
        this.selectedFiles = [];
        this.fileSearchTerm = "";
        this.isLoadingFiles = false;

        this.updateDisplayedFiles();
        this.updateCurrentLocationName();
      })
      .catch((error) => {
        this.showError(
          "Error loading files",
          error.body?.message || error.message
        );
        this.isLoadingFiles = false;

        this.currentFiles = [];
        this.breadcrumbs = [];
        this.currentPath = "";
        this.selectedFiles = [];
        this.fileSearchTerm = "";
        this.updateDisplayedFiles();
      });
  }

  // Pure client-side filter over the already-loaded currentFiles - no Apex
  // call, no data reload. Matches both file and folder rows (folders are
  // just rows with isFolder:true in the same array), case-insensitive
  // substring against the filename/folder name.
  handleFileSearchChange(event) {
    this.fileSearchTerm = event.target.value;
    this.updateDisplayedFiles();
  }

  updateDisplayedFiles() {
    if (!this.fileSearchTerm) {
      this.displayedFiles = this.currentFiles;
    } else {
      const searchLower = this.fileSearchTerm.toLowerCase();
      this.displayedFiles = this.currentFiles.filter((row) =>
        (row.title || "").toLowerCase().includes(searchLower)
      );
    }

    // lightning-datatable's own selection tracking should not be trusted to
    // survive a data-array swap (filtering changes which rows exist in
    // `data`) - explicitly re-apply the checkbox-checked state for whatever
    // is currently in selectedFiles and still visible, every time the
    // displayed set changes, rather than assuming the datatable remembers.
    // eslint-disable-next-line @lwc/lwc/no-async-operation -- must run after the datatable re-renders against the new displayedFiles
    setTimeout(() => {
      const datatable = this.template.querySelector("lightning-datatable");
      if (datatable) {
        datatable.selectedRows = this.selectedFiles.map((file) => file.id);
      }
    }, 0);
  }

  get hasNoFilesAtAll() {
    return !this.isLoadingFiles && this.currentFiles.length === 0;
  }

  get hasNoSearchMatches() {
    return (
      !this.isLoadingFiles &&
      this.currentFiles.length > 0 &&
      this.displayedFiles.length === 0
    );
  }

  updateCurrentLocationName() {
    if (this.selectedLibraryId) {
      const selectedLibrary = this.libraries.find(
        (lib) =>
          lib.id === this.selectedLibraryId ||
          lib.name === this.selectedLibraryId
      );

      if (selectedLibrary) {
        if (this.selectedFolderId) {
          const folderName = this.findFolderName(
            selectedLibrary.items,
            this.selectedFolderId
          );
          if (folderName) {
            this.currentLocationName = `${selectedLibrary.label} > ${folderName}`;
            return;
          }
        }
        this.currentLocationName = selectedLibrary.label;
        return;
      }
    }

    if (
      this.currentPath &&
      this.currentPath.trim() &&
      this.currentPath !== "Unknown Path" &&
      this.currentPath !== "Unknown Library"
    ) {
      this.currentLocationName = this.currentPath;
      return;
    }

    if (this.breadcrumbs && this.breadcrumbs.length > 0) {
      this.currentLocationName = this.breadcrumbs
        .map((b) => b.label)
        .join(" > ");
      return;
    }

    this.currentLocationName = "Current location";
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
    const selectedRows = event.detail.selectedRows || [];
    const validSelectedRows = selectedRows.filter((row) => !row.isFolder);

    if (validSelectedRows.length !== selectedRows.length) {
      // A folder row got checked - force its checkbox back off since
      // folder rows only support click-to-navigate, never selection.
      const datatable = this.template.querySelector("lightning-datatable");
      if (datatable) {
        datatable.selectedRows = validSelectedRows.map((row) => row.id);
      }
    }

    // onrowselection only ever reports rows currently present in `data`
    // (displayedFiles) - if a search term is hiding some previously-selected
    // files, they simply can't appear in event.detail.selectedRows at all.
    // Overwriting selectedFiles with just this event's rows would silently
    // drop those hidden selections. Preserve anything selected that isn't
    // currently visible, and only let this event control the visible rows.
    const visibleIds = new Set(this.displayedFiles.map((row) => row.id));
    const hiddenStillSelected = this.selectedFiles.filter(
      (file) => !visibleIds.has(file.id)
    );
    this.selectedFiles = [...hiddenStillSelected, ...validSelectedRows];
  }

  handleMoveFiles() {
    if (this.selectedFiles.length === 0) {
      this.showError("Error", "Please select files to move");
      return;
    }
    this.showMovePanel = true;
    // Collapsed by default: destination browsing is the active task, the
    // file selection is checked once, not continuously.
    this.showFilesToMoveList = false;
    this.updateFilteredDestinations();
    this.updateCurrentLocationName();
  }

  handleToggleFilesToMove() {
    this.showFilesToMoveList = !this.showFilesToMoveList;
  }

  get filesToMoveToggleIcon() {
    return this.showFilesToMoveList
      ? "utility:chevrondown"
      : "utility:chevronright";
  }

  closeMovePanel() {
    this.showMovePanel = false;
    this.selectedDestinationId = "";
    this.selectedDestinationName = "";
    this.searchTerm = "";
    this.updateFilteredDestinations();
  }

  handleSearchChange(event) {
    this.searchTerm = event.target.value;
    this.updateFilteredDestinations();
  }

  updateFilteredDestinations() {
    if (!this.searchTerm) {
      this.filteredDestinations = this.libraries.map((lib) => ({
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
      this.selectedDestinationName = "";
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
    this.selectedDestinationName = label || "Selected destination";
  }

  handleMoveConfirm() {
    if (!this.selectedDestinationId) {
      this.showError("Error", "Please select a destination");
      return;
    }

    this.operationInProgress = true;
    const fileIds = this.selectedFiles.map((file) => file.id);
    const destinationType = this.selectedDestinationId.startsWith("058")
      ? "library"
      : "folder";
    const moveToDestinationId = this.selectedDestinationId;

    smartMoveFiles({
      fileIds: fileIds,
      destinationId: this.selectedDestinationId,
      destinationType: destinationType
    })
      .then((result) => {
        if (result.success) {
          if (result.partialSuccess) {
            this.showWarning(
              "Files Moved with Notes",
              result.errors.join("\n")
            );
          } else {
            this.showSuccess(
              "Files Moved Successfully",
              `${result.successCount} files moved to destination successfully.`
            );
          }

          this.closeMovePanel();

          this.loadLibraries()
            .then(() => {
              // eslint-disable-next-line @lwc/lwc/no-async-operation -- deliberate UI timing (scroll-into-view / post-navigation reselection), no clean alternative
              setTimeout(() => {
                this.navigateToDestination(
                  moveToDestinationId,
                  destinationType
                );
              }, 500);
            })
            .catch(() => {
              // eslint-disable-next-line @lwc/lwc/no-async-operation -- deliberate UI timing (scroll-into-view / post-navigation reselection), no clean alternative
              setTimeout(() => {
                this.navigateToDestination(
                  moveToDestinationId,
                  destinationType
                );
              }, 1000);
            });
        } else {
          this.showError("Move Failed", result.errors.join("\n"));
        }
      })
      .catch((error) => {
        this.showError(
          "Error moving files",
          error.body?.message || error.message
        );
      })
      .finally(() => {
        this.operationInProgress = false;
      });
  }

  navigateToDestination(destinationId, destinationType) {
    try {
      if (destinationType === "library") {
        this.selectedLibraryId = destinationId;
        this.selectedFolderId = "";
        this.loadFilesInFolder(destinationId, null);

        // eslint-disable-next-line @lwc/lwc/no-async-operation -- deliberate UI timing (scroll-into-view / post-navigation reselection), no clean alternative
        setTimeout(() => {
          this.updateTreeSelection(destinationId);
        }, 500);
      } else if (destinationType === "folder") {
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

  // Folders are always already loaded (getLibrariesWithFolders eager-loads
  // everything), so this is purely: force the path to this folder open
  // (guaranteed visible, not a risky toggle) and navigate to it.
  ensureLibraryExpandedAndNavigate(libraryId, folderId) {
    const libraryIndex = this.libraries.findIndex(
      (lib) => lib.id === libraryId
    );
    if (libraryIndex === -1) {
      this.refreshCurrentView();
      return;
    }
    this.libraries = this.expandPathToTarget(this.libraries, folderId);
    this.treeLibraries = this.buildTreeLibraries(this.libraries);
    this.loadFilesInFolder(libraryId, folderId);
    // eslint-disable-next-line @lwc/lwc/no-async-operation -- deliberate UI timing (scroll-into-view / post-navigation reselection), no clean alternative
    setTimeout(() => {
      this.updateTreeSelection(folderId);
    }, 500);
  }

  updateTreeSelection(itemId) {
    // eslint-disable-next-line @lwc/lwc/no-async-operation -- deliberate UI timing (scroll-into-view / post-navigation reselection), no clean alternative
    setTimeout(() => {
      const tree = this.template.querySelector("lightning-tree");
      if (tree) {
        tree.selectedItem = itemId;
        // eslint-disable-next-line @lwc/lwc/no-async-operation -- deliberate UI timing (scroll-into-view / post-navigation reselection), no clean alternative
        setTimeout(() => {
          this.scrollTreeIntoView(tree, itemId);
        }, 800);
      }
    }, 300);
  }

  scrollTreeIntoView(tree, itemId) {
    try {
      tree.scrollIntoView({
        behavior: "smooth",
        block: "center"
      });

      const treeContainer = this.template.querySelector(
        ".library-tree-container"
      );
      if (treeContainer) {
        treeContainer.style.transition = "border 0.5s ease";
        treeContainer.style.border = "2px solid rgba(0, 112, 210, 0.8)";
        // eslint-disable-next-line @lwc/lwc/no-async-operation -- deliberate UI timing (scroll-into-view / post-navigation reselection), no clean alternative
        setTimeout(() => {
          treeContainer.style.border = "";
        }, 2000);
      }

      return true;
    } catch (error) {
      return this.tryContainerBasedScroll(itemId);
    }
  }

  tryContainerBasedScroll(itemId) {
    const treeContainer = this.template.querySelector(
      ".library-tree-container"
    );
    if (!treeContainer) {
      return;
    }

    const scrollHeight = treeContainer.scrollHeight;
    const clientHeight = treeContainer.clientHeight;
    const maxScroll = scrollHeight - clientHeight;

    let targetPosition = 0;

    if (itemId && itemId.startsWith("07H")) {
      targetPosition = scrollHeight * 0.75;
    } else if (itemId && itemId.startsWith("058")) {
      targetPosition = scrollHeight * 0.1;
    } else {
      targetPosition = scrollHeight * 0.5;
    }

    const finalPosition = Math.max(0, Math.min(targetPosition, maxScroll));

    treeContainer.scrollTo({
      top: finalPosition,
      behavior: "smooth"
    });

    treeContainer.style.transition = "border 0.5s ease, box-shadow 0.5s ease";
    treeContainer.style.border = "3px solid rgba(40, 180, 40, 0.8)";
    treeContainer.style.boxShadow = "0 0 15px rgba(40, 180, 40, 0.6)";

    // eslint-disable-next-line @lwc/lwc/no-async-operation -- deliberate UI timing (scroll-into-view / post-navigation reselection), no clean alternative
    setTimeout(() => {
      treeContainer.style.border = "";
      treeContainer.style.boxShadow = "";
    }, 3000);
  }

  scrollToElement(targetElement) {
    const scrollWrapper = this.template.querySelector(".tree-scroll-wrapper");

    if (!scrollWrapper || !targetElement) {
      return;
    }

    try {
      const wrapperRect = scrollWrapper.getBoundingClientRect();
      const targetRect = targetElement.getBoundingClientRect();

      const targetTop =
        targetRect.top - wrapperRect.top + scrollWrapper.scrollTop;
      const wrapperCenter = wrapperRect.height / 2;
      const targetCenter = targetRect.height / 2;

      const scrollPosition = targetTop - wrapperCenter + targetCenter;

      const maxScroll = scrollWrapper.scrollHeight - scrollWrapper.clientHeight;
      const finalPosition = Math.max(0, Math.min(scrollPosition, maxScroll));

      scrollWrapper.classList.add("scrolling");

      scrollWrapper.scrollTo({
        top: finalPosition,
        behavior: "smooth"
      });

      // eslint-disable-next-line @lwc/lwc/no-async-operation -- deliberate UI timing (scroll-into-view / post-navigation reselection), no clean alternative
      setTimeout(() => {
        scrollWrapper.classList.remove("scrolling");
      }, 500);

      this.highlightElement(targetElement);
    } catch (error) {
      // Silently fail
    }
  }

  highlightElement(element) {
    const originalStyle = element.style.cssText;

    element.style.transition = "all 0.3s ease";
    element.style.backgroundColor = "rgba(0, 112, 210, 0.2)";
    element.style.transform = "scale(1.02)";
    element.style.boxShadow = "0 2px 8px rgba(0, 112, 210, 0.3)";

    // eslint-disable-next-line @lwc/lwc/no-async-operation -- deliberate UI timing (scroll-into-view / post-navigation reselection), no clean alternative
    setTimeout(() => {
      element.style.backgroundColor = "";
      element.style.transform = "";
      element.style.boxShadow = "";
      // eslint-disable-next-line @lwc/lwc/no-async-operation -- deliberate UI timing (scroll-into-view / post-navigation reselection), no clean alternative
      setTimeout(() => {
        element.style.cssText = originalStyle;
      }, 300);
    }, 2000);
  }

  handleBreadcrumbClick(event) {
    const breadcrumbId = event.target.dataset.id;
    if (breadcrumbId) {
      const isLibrary = breadcrumbId.startsWith("058");
      if (isLibrary) {
        this.selectedLibraryId = breadcrumbId;
        this.selectedFolderId = "";
        this.loadFilesInFolder(breadcrumbId, null);
        // eslint-disable-next-line @lwc/lwc/no-async-operation -- deliberate UI timing (scroll-into-view / post-navigation reselection), no clean alternative
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
    const lightningTree = this.template.querySelector("lightning-tree");
    if (lightningTree && !this.treeObserver) {
      const config = {
        childList: true,
        subtree: true,
        attributes: true,
        attributeFilter: ["aria-expanded", "aria-selected"]
      };

      this.treeObserver = new MutationObserver((mutations) => {
        mutations.forEach((mutation) => {
          if (mutation.type === "attributes") {
            if (
              mutation.attributeName === "aria-expanded" &&
              mutation.target.getAttribute("aria-expanded") === "true"
            ) {
              // eslint-disable-next-line @lwc/lwc/no-async-operation -- deliberate UI timing (scroll-into-view / post-navigation reselection), no clean alternative
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
    if (!this.selectedLibraryId) {
      this.showError("Error", "Please select a library or folder first");
      return;
    }
    this.showCreateFolderModal = true;
  }

  handleFolderNameChange(event) {
    this.newFolderName = event.target.value;
  }

  handleCreateFolderConfirm() {
    if (!this.newFolderName.trim()) {
      this.showError("Error", "Folder name is required");
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
        this.showSuccess("Success", "Folder created successfully");
        this.closeCreateFolderModal();
        this.refreshLibrariesAndMaintainState(
          currentLibraryId,
          currentFolderId,
          currentLocationName
        );
      })
      .catch((error) => {
        this.showError(
          "Error creating folder",
          error.body?.message || error.message
        );
      })
      .finally(() => {
        this.operationInProgress = false;
      });
  }

  refreshLibrariesAndMaintainState(libraryId, folderId, locationName) {
    const treeContainer = this.template.querySelector(
      ".library-tree-container"
    );
    const scrollTop = treeContainer?.scrollTop || 0;

    this.loadLibraries()
      .then(() => {
        this.selectedLibraryId = libraryId;
        this.selectedFolderId = folderId;
        this.currentLocationName = locationName;

        // loadLibraries() already fetched the full folder tree fresh
        // (expanded:false on every node) - force the path to the target
        // back open so it's visible after this reload, same as before a
        // move/refresh collapsed everything back to defaults.
        const targetId = folderId || libraryId;
        if (targetId) {
          this.libraries = this.expandPathToTarget(this.libraries, targetId);
          this.treeLibraries = this.buildTreeLibraries(this.libraries);
        }
      })
      .then(() => {
        // eslint-disable-next-line @lwc/lwc/no-async-operation -- deliberate UI timing (scroll-into-view / post-navigation reselection), no clean alternative
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
      .catch(() => {
        this.refreshCurrentView();
      });
  }

  closeCreateFolderModal() {
    this.showCreateFolderModal = false;
    this.newFolderName = "";
  }

  handleDeleteFiles() {
    if (this.selectedFiles.length === 0) {
      this.showError("Error", "Please select files to delete");
      return;
    }
    this.showDeleteModal = true;
  }

  handleDeleteConfirm() {
    this.operationInProgress = true;
    const fileIds = this.selectedFiles.map((file) => file.id);

    deleteFiles({ fileIds: fileIds })
      .then((result) => {
        if (result.success) {
          this.showSuccess(
            "Success",
            `${result.successCount} files deleted successfully`
          );
          if (result.errors && result.errors.length > 0) {
            this.showWarning(
              "Partial Success",
              `${result.errors.length} files could not be deleted.`
            );
          }
        } else {
          this.showError("Delete Failed", result.errors.join("\n"));
        }
        this.closeDeleteModal();
        this.loadFilesInFolder(this.selectedLibraryId, this.selectedFolderId);
        this.loadLibraries();
      })
      .catch((error) => {
        this.showError(
          "Error deleting files",
          error.body?.message || error.message
        );
      })
      .finally(() => {
        this.operationInProgress = false;
      });
  }

  closeDeleteModal() {
    this.showDeleteModal = false;
  }

  handleRefresh() {
    this.loadLibraries();
    if (this.selectedLibraryId) {
      this.loadFilesInFolder(this.selectedLibraryId, this.selectedFolderId);
    }
  }

  handleExpandAll() {
    this.libraries = this.setTreeExpansion(this.libraries, true);
    this.treeLibraries = this.buildTreeLibraries(this.libraries);
  }

  handleCollapseAll() {
    this.libraries = this.setTreeExpansion(this.libraries, false);
    this.treeLibraries = this.buildTreeLibraries(this.libraries);
  }

  setTreeExpansion(items, expanded) {
    return (items || []).map((item) => ({
      ...item,
      expanded,
      items: item.items
        ? this.setTreeExpansion(item.items, expanded)
        : item.items
    }));
  }

  refreshCurrentView() {
    this.loadFilesInFolder(this.selectedLibraryId, this.selectedFolderId);
    this.loadLibraries();
  }

  showSuccess(title, message) {
    this.dispatchEvent(
      new ShowToastEvent({
        title: title,
        message: message,
        variant: "success"
      })
    );
  }

  showError(title, message) {
    this.dispatchEvent(
      new ShowToastEvent({
        title: title,
        message: message,
        variant: "error",
        mode: "sticky"
      })
    );
  }

  showWarning(title, message) {
    this.dispatchEvent(
      new ShowToastEvent({
        title: title,
        message: message,
        variant: "warning",
        mode: "sticky"
      })
    );
  }
}
