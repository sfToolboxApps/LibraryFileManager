import { createElement } from "@lwc/engine-dom";
import LibraryFileManager from "c/libraryFileManager";
import getLibrariesWithFolders from "@salesforce/apex/LibraryFileManagerController.getLibrariesWithFolders";
import getLibraryFolders from "@salesforce/apex/LibraryFileManagerController.getLibraryFolders";
import getFilesInFolder from "@salesforce/apex/LibraryFileManagerController.getFilesInFolder";
import smartMoveFiles from "@salesforce/apex/LibraryFileManagerController.smartMoveFiles";

jest.mock(
  "@salesforce/apex/LibraryFileManagerController.getLibrariesWithFolders",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/LibraryFileManagerController.getLibraryFolders",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/LibraryFileManagerController.getFilesInFolder",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/LibraryFileManagerController.smartMoveFiles",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/LibraryFileManagerController.deleteFiles",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/LibraryFileManagerController.createFolder",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

function flushPromises() {
  return Promise.resolve().then(() => Promise.resolve());
}

const MOCK_LIBRARIES = [
  {
    id: "058000000000001AAA",
    name: "058000000000001AAA",
    label: "Marketing Assets",
    expanded: false,
    fileCount: 1,
    items: [
      {
        name: "07H000000000001AAA",
        label: "Campaigns (2 files)",
        expanded: false,
        items: []
      }
    ]
  },
  {
    id: "058000000000002AAA",
    name: "058000000000002AAA",
    label: "Sales Enablement",
    expanded: false,
    fileCount: 0,
    items: []
  }
];

describe("c-library-file-manager", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it("bakes correctly-pluralized file counts into the tree item labels", async () => {
    getLibrariesWithFolders.mockResolvedValue(MOCK_LIBRARIES);

    const element = createElement("c-library-file-manager", {
      is: LibraryFileManager
    });
    document.body.appendChild(element);
    await flushPromises();

    const tree = element.shadowRoot.querySelector("lightning-tree");
    expect(tree).not.toBeNull();
    expect(tree.items[0].label).toBe("Marketing Assets (1 file)");
    expect(tree.items[1].label).toBe("Sales Enablement (0 files)");
  });

  it("REGRESSION GUARD: selecting a library or a nested folder never touches the tree items reference at all", async () => {
    getLibrariesWithFolders.mockResolvedValue(MOCK_LIBRARIES);
    getFilesInFolder.mockResolvedValue({
      files: [],
      path: "",
      breadcrumbs: []
    });

    const element = createElement("c-library-file-manager", {
      is: LibraryFileManager
    });
    document.body.appendChild(element);
    await flushPromises();

    const tree = element.shadowRoot.querySelector("lightning-tree");
    const itemsBefore = tree.items;

    // Two prior attempts at "expand the clicked node's own path on select"
    // both eventually caused the tree to snap open or shut unexpectedly,
    // because lightning-tree appears to resync every row's visual state from
    // `items` on any reference change - not just the rows that actually
    // changed. The only reliably safe behavior is for select to never touch
    // `items` at all, for ANY node, library or folder, ever - expand/collapse
    // is entirely lightning-tree's own business now, both for the label and
    // the chevron.
    tree.dispatchEvent(
      new CustomEvent("select", { detail: { name: "058000000000001AAA" } })
    );
    await flushPromises();
    tree.dispatchEvent(
      new CustomEvent("select", { detail: { name: "07H000000000001AAA" } })
    );
    await flushPromises();
    tree.dispatchEvent(
      new CustomEvent("select", { detail: { name: "058000000000002AAA" } })
    );
    await flushPromises();

    expect(tree.items).toBe(itemsBefore);
  });

  it("Expand All still intentionally produces a new tree items reference with expanded=true", async () => {
    getLibrariesWithFolders.mockResolvedValue(MOCK_LIBRARIES);

    const element = createElement("c-library-file-manager", {
      is: LibraryFileManager
    });
    document.body.appendChild(element);
    await flushPromises();

    const tree = element.shadowRoot.querySelector("lightning-tree");
    const itemsBefore = tree.items;

    const buttons = Array.from(
      element.shadowRoot.querySelectorAll("lightning-button")
    );
    const expandAllButton = buttons.find((btn) => btn.label === "Expand All");
    expect(expandAllButton).toBeDefined();

    expandAllButton.click();
    await flushPromises();

    const itemsAfter = tree.items;
    expect(itemsAfter).not.toBe(itemsBefore);
    expect(itemsAfter[0].expanded).toBe(true);
    expect(itemsAfter[0].items[0].expanded).toBe(true);
    // Pluralized label must survive the expand-all rebuild too
    expect(itemsAfter[0].label).toBe("Marketing Assets (1 file)");
  });

  it("does not call getLibraryFolders on load (sanity check for the mock wiring)", async () => {
    getLibrariesWithFolders.mockResolvedValue(MOCK_LIBRARIES);

    const element = createElement("c-library-file-manager", {
      is: LibraryFileManager
    });
    document.body.appendChild(element);
    await flushPromises();

    expect(getLibraryFolders).not.toHaveBeenCalled();
  });

  it("REGRESSION GUARD: selecting a file in the datatable does not reset tree items reference", async () => {
    getLibrariesWithFolders.mockResolvedValue(MOCK_LIBRARIES);
    getFilesInFolder.mockResolvedValue({
      files: [{ id: "069AAA", title: "Some File", isFolder: false }],
      path: "Marketing Assets",
      breadcrumbs: [
        { id: "058000000000001AAA", label: "Marketing Assets", isLast: true }
      ]
    });

    const element = createElement("c-library-file-manager", {
      is: LibraryFileManager
    });
    document.body.appendChild(element);
    await flushPromises();

    const tree = element.shadowRoot.querySelector("lightning-tree");
    tree.dispatchEvent(
      new CustomEvent("select", { detail: { name: "058000000000001AAA" } })
    );
    await flushPromises();

    const itemsBefore = tree.items;

    // Checking a file's row checkbox only updates selectedFiles - it must not
    // touch libraries/treeLibraries at all.
    const datatable = element.shadowRoot.querySelector("lightning-datatable");
    datatable.dispatchEvent(
      new CustomEvent("rowselection", {
        detail: {
          selectedRows: [{ id: "069AAA", title: "Some File", isFolder: false }]
        }
      })
    );
    await flushPromises();

    expect(tree.items).toBe(itemsBefore);
  });

  it("file search filters both file and folder rows live, case-insensitively, on every keystroke", async () => {
    getLibrariesWithFolders.mockResolvedValue(MOCK_LIBRARIES);
    getFilesInFolder.mockResolvedValue({
      files: [
        { id: "069AAA", title: "Q1 Report", isFolder: false },
        { id: "069BBB", title: "Q2 Report", isFolder: false },
        { id: "07HCampaigns", title: "Campaigns", isFolder: true }
      ],
      path: "Marketing Assets",
      breadcrumbs: [
        { id: "058000000000001AAA", label: "Marketing Assets", isLast: true }
      ]
    });

    const element = createElement("c-library-file-manager", {
      is: LibraryFileManager
    });
    document.body.appendChild(element);
    await flushPromises();

    const tree = element.shadowRoot.querySelector("lightning-tree");
    tree.dispatchEvent(
      new CustomEvent("select", { detail: { name: "058000000000001AAA" } })
    );
    await flushPromises();

    let datatable = element.shadowRoot.querySelector("lightning-datatable");
    expect(datatable.data.length).toBe(3);

    const searchInput = element.shadowRoot.querySelector(
      ".file-search-col lightning-input"
    );
    searchInput.value = "cam";
    searchInput.dispatchEvent(new CustomEvent("change"));
    await flushPromises();

    // "cam" (lowercase, partial) must match "Campaigns" (a folder row) even
    // though neither file matches - this is a pure client-side filter, no
    // new Apex call.
    datatable = element.shadowRoot.querySelector("lightning-datatable");
    expect(datatable.data.length).toBe(1);
    expect(datatable.data[0].title).toBe("Campaigns");
    expect(getFilesInFolder).toHaveBeenCalledTimes(1);
  });

  it("REGRESSION GUARD: selected files survive applying and then clearing the search filter", async () => {
    jest.useFakeTimers();
    getLibrariesWithFolders.mockResolvedValue(MOCK_LIBRARIES);
    getFilesInFolder.mockResolvedValue({
      files: [
        { id: "069AAA", title: "Q1 Report", isFolder: false },
        { id: "069BBB", title: "Q2 Report", isFolder: false }
      ],
      path: "Marketing Assets",
      breadcrumbs: [
        { id: "058000000000001AAA", label: "Marketing Assets", isLast: true }
      ]
    });

    const element = createElement("c-library-file-manager", {
      is: LibraryFileManager
    });
    document.body.appendChild(element);
    await flushPromises();

    const tree = element.shadowRoot.querySelector("lightning-tree");
    tree.dispatchEvent(
      new CustomEvent("select", { detail: { name: "058000000000001AAA" } })
    );
    await flushPromises();

    // Select "Q1 Report" while both rows are visible.
    let datatable = element.shadowRoot.querySelector("lightning-datatable");
    datatable.dispatchEvent(
      new CustomEvent("rowselection", {
        detail: {
          selectedRows: [{ id: "069AAA", title: "Q1 Report", isFolder: false }]
        }
      })
    );
    await flushPromises();

    // Now search for something that hides the selected file entirely.
    const searchInput = element.shadowRoot.querySelector(
      ".file-search-col lightning-input"
    );
    searchInput.value = "Q2";
    searchInput.dispatchEvent(new CustomEvent("change"));
    await flushPromises();
    jest.runOnlyPendingTimers();
    await flushPromises();

    datatable = element.shadowRoot.querySelector("lightning-datatable");
    expect(datatable.data.length).toBe(1);
    expect(datatable.data[0].title).toBe("Q2 Report");

    // Move Files must still be enabled - the hidden selection is not lost.
    const moveButton = Array.from(
      element.shadowRoot.querySelectorAll("button.action-button")
    ).find((btn) => btn.textContent.includes("Move Files"));
    expect(moveButton.disabled).toBe(false);

    // Clear the search - the file reappears, and must still show as selected.
    searchInput.value = "";
    searchInput.dispatchEvent(new CustomEvent("change"));
    await flushPromises();
    jest.runOnlyPendingTimers();
    await flushPromises();

    datatable = element.shadowRoot.querySelector("lightning-datatable");
    expect(datatable.data.length).toBe(2);
    expect(datatable.selectedRows).toContain("069AAA");

    jest.useRealTimers();
  });

  it("shows a distinct no-search-matches message, not the genuinely-empty-folder message", async () => {
    getLibrariesWithFolders.mockResolvedValue(MOCK_LIBRARIES);
    getFilesInFolder.mockResolvedValue({
      files: [{ id: "069AAA", title: "Q1 Report", isFolder: false }],
      path: "Marketing Assets",
      breadcrumbs: [
        { id: "058000000000001AAA", label: "Marketing Assets", isLast: true }
      ]
    });

    const element = createElement("c-library-file-manager", {
      is: LibraryFileManager
    });
    document.body.appendChild(element);
    await flushPromises();

    const tree = element.shadowRoot.querySelector("lightning-tree");
    tree.dispatchEvent(
      new CustomEvent("select", { detail: { name: "058000000000001AAA" } })
    );
    await flushPromises();

    const searchInput = element.shadowRoot.querySelector(
      ".file-search-col lightning-input"
    );
    searchInput.value = "nothing matches this";
    searchInput.dispatchEvent(new CustomEvent("change"));
    await flushPromises();

    const heading = element.shadowRoot.querySelector(
      ".slds-illustration h3.slds-text-heading_medium"
    );
    expect(heading.textContent).toContain("No files match");
    expect(heading.textContent).not.toBe("No files found");
  });

  it("a successful move reloads libraries (intentionally) and still re-selects the destination", async () => {
    // NOTE: this scenario is different from the others above. A move legitimately
    // calls loadLibraries() afterward (counts may have changed), which fetches
    // fresh data from Apex with expanded:false on every node - so a NEW
    // treeLibraries reference here is correct, not the bug. What must still work
    // is the pre-existing, separate reselection mechanism (tree.selectedItem) that
    // re-expands/re-selects the destination after that reload.
    jest.useFakeTimers();
    // jsdom doesn't implement these layout APIs; the component calls them purely
    // for a cosmetic scroll-into-view highlight, unrelated to what's under test.
    Element.prototype.scrollTo = jest.fn();
    Element.prototype.scrollIntoView = jest.fn();
    getLibrariesWithFolders.mockResolvedValue(MOCK_LIBRARIES);
    getFilesInFolder.mockResolvedValue({
      files: [{ id: "069AAA", title: "Some File", isFolder: false }],
      path: "Marketing Assets",
      breadcrumbs: [
        { id: "058000000000001AAA", label: "Marketing Assets", isLast: true }
      ]
    });
    smartMoveFiles.mockResolvedValue({
      success: true,
      partialSuccess: false,
      successCount: 1,
      errors: [],
      warnings: []
    });

    async function settle() {
      // Promises must be flushed BEFORE timers on each pass so that a resolved
      // .then() chain gets a chance to schedule its setTimeout before we run it;
      // this component chains several nested setTimeout-after-promise steps
      // (loadLibraries -> setTimeout -> navigateToDestination -> setTimeout ->
      // updateTreeSelection -> setTimeout) after a successful move.
      for (let i = 0; i < 15; i++) {
        // Deliberate sequential drain: each pass must resolve pending promises
        // before the next batch of timers they schedule can be run.
        // eslint-disable-next-line no-await-in-loop
        await flushPromises();
        jest.runOnlyPendingTimers();
      }
      await flushPromises();
    }

    const element = createElement("c-library-file-manager", {
      is: LibraryFileManager
    });
    document.body.appendChild(element);
    await settle();

    const tree = element.shadowRoot.querySelector("lightning-tree");
    tree.dispatchEvent(
      new CustomEvent("select", { detail: { name: "058000000000001AAA" } })
    );
    await settle();

    // Select the file to move.
    const datatable = element.shadowRoot.querySelector("lightning-datatable");
    datatable.dispatchEvent(
      new CustomEvent("rowselection", {
        detail: {
          selectedRows: [{ id: "069AAA", title: "Some File", isFolder: false }]
        }
      })
    );
    await settle();

    // Open the move panel (toolbar "Move Files" is a plain <button>, not lightning-button).
    const moveFilesButton = Array.from(
      element.shadowRoot.querySelectorAll("button.action-button")
    ).find((btn) => btn.textContent.trim().includes("Move Files"));
    expect(moveFilesButton).toBeDefined();
    moveFilesButton.click();
    await settle();

    // Choose the other library as the destination in the move panel's tree.
    const destinationTree = element.shadowRoot.querySelector(
      ".destination-tree-container lightning-tree"
    );
    expect(destinationTree).not.toBeNull();
    destinationTree.dispatchEvent(
      new CustomEvent("select", { detail: { name: "058000000000002AAA" } })
    );
    await settle();

    // Confirm the move (this one is still the lightning-button footer confirm button).
    const confirmMoveButton = Array.from(
      element.shadowRoot.querySelectorAll("lightning-button")
    ).find(
      (btn) =>
        btn.label === "Move Files" && btn.className === "slds-button_stretch"
    );
    expect(confirmMoveButton).toBeDefined();
    confirmMoveButton.click();
    await settle();

    expect(smartMoveFiles).toHaveBeenCalledWith({
      fileIds: ["069AAA"],
      destinationId: "058000000000002AAA",
      destinationType: "library"
    });
    // loadLibraries is called once on initial load, once more after the move.
    expect(getLibrariesWithFolders).toHaveBeenCalledTimes(2);
    // The tree element gets unmounted/remounted while isLoadingLibraries is true
    // during the reload (its if:false guard hides it), so the original `tree`
    // reference is now stale - re-query the live node before asserting.
    const treeAfterMove = element.shadowRoot.querySelector("lightning-tree");
    expect(treeAfterMove).not.toBeNull();
    // The pre-existing reselection mechanism must still land on the destination.
    expect(treeAfterMove.selectedItem).toBe("058000000000002AAA");

    jest.useRealTimers();
  });

  it("REGRESSION GUARD: does not render the datatable in the empty-files state (only the illustration)", async () => {
    getLibrariesWithFolders.mockResolvedValue(MOCK_LIBRARIES);
    getFilesInFolder.mockResolvedValue({
      files: [],
      path: "Marketing Assets",
      breadcrumbs: [
        { id: "058000000000001AAA", label: "Marketing Assets", isLast: true }
      ]
    });

    const element = createElement("c-library-file-manager", {
      is: LibraryFileManager
    });
    document.body.appendChild(element);
    await flushPromises();

    const tree = element.shadowRoot.querySelector("lightning-tree");
    tree.dispatchEvent(
      new CustomEvent("select", { detail: { name: "058000000000001AAA" } })
    );
    await flushPromises();

    // Previously <template if:true={currentFiles}> checked array truthiness, which
    // is always true even for []. That rendered an empty datatable stacked on top
    // of the "No files found" illustration inside a fixed-height scroll container,
    // producing a scrollbar with nothing meaningful to scroll.
    expect(element.shadowRoot.querySelector("lightning-datatable")).toBeNull();
    expect(element.shadowRoot.textContent).toContain("No files found");
  });

  it("REGRESSION GUARD: Create Folder is disabled with no library/folder selected, and enabled once one is", async () => {
    getLibrariesWithFolders.mockResolvedValue(MOCK_LIBRARIES);
    getFilesInFolder.mockResolvedValue({
      files: [],
      path: "Marketing Assets",
      breadcrumbs: [
        { id: "058000000000001AAA", label: "Marketing Assets", isLast: true }
      ]
    });

    const element = createElement("c-library-file-manager", {
      is: LibraryFileManager
    });
    document.body.appendChild(element);
    await flushPromises();

    const findCreateFolderButton = () =>
      Array.from(
        element.shadowRoot.querySelectorAll("button.action-button")
      ).find((btn) => btn.textContent.trim().includes("Create Folder"));

    // Default "Select a library or folder" screen - nothing selected yet.
    let createFolderButton = findCreateFolderButton();
    expect(createFolderButton).toBeDefined();
    expect(createFolderButton.disabled).toBe(true);

    // Clicking it while disabled must not open the modal or throw.
    createFolderButton.click();
    await flushPromises();
    expect(
      element.shadowRoot.querySelector('section[role="dialog"]')
    ).toBeNull();

    // Selecting a library enables it.
    const tree = element.shadowRoot.querySelector("lightning-tree");
    tree.dispatchEvent(
      new CustomEvent("select", { detail: { name: "058000000000001AAA" } })
    );
    await flushPromises();

    createFolderButton = findCreateFolderButton();
    expect(createFolderButton.disabled).toBe(false);

    createFolderButton.click();
    await flushPromises();
    expect(
      element.shadowRoot.querySelector('section[role="dialog"]')
    ).not.toBeNull();
  });

  it("REGRESSION GUARD: all three action buttons are plain native buttons sharing the same disabled mechanism", async () => {
    getLibrariesWithFolders.mockResolvedValue(MOCK_LIBRARIES);
    getFilesInFolder.mockResolvedValue({
      files: [{ id: "069AAA", title: "Some File", isFolder: false }],
      path: "Marketing Assets",
      breadcrumbs: [
        { id: "058000000000001AAA", label: "Marketing Assets", isLast: true }
      ]
    });

    const element = createElement("c-library-file-manager", {
      is: LibraryFileManager
    });
    document.body.appendChild(element);
    await flushPromises();

    const findButton = (text) =>
      Array.from(
        element.shadowRoot.querySelectorAll("button.action-button")
      ).find((btn) => btn.textContent.trim().includes(text));

    // Create Folder / Move Files / Delete Files must be real native <button>
    // elements (no shadow root of their own), not lightning-button, so their
    // disabled styling is governed by a plain :disabled CSS rule with no hooks.
    expect(findButton("Create Folder").tagName).toBe("BUTTON");
    expect(findButton("Move Files").tagName).toBe("BUTTON");
    expect(findButton("Delete Files").tagName).toBe("BUTTON");
    expect(findButton("Create Folder").shadowRoot).toBeNull();

    // Default screen: nothing selected - all three disabled.
    expect(findButton("Create Folder").disabled).toBe(true);
    expect(findButton("Move Files").disabled).toBe(true);
    expect(findButton("Delete Files").disabled).toBe(true);

    // Select a library: Create Folder's condition clears, Move/Delete's does not
    // (no files selected yet).
    const tree = element.shadowRoot.querySelector("lightning-tree");
    tree.dispatchEvent(
      new CustomEvent("select", { detail: { name: "058000000000001AAA" } })
    );
    await flushPromises();

    expect(findButton("Create Folder").disabled).toBe(false);
    expect(findButton("Move Files").disabled).toBe(true);
    expect(findButton("Delete Files").disabled).toBe(true);

    // Select a file: Move/Delete's condition clears too.
    const datatable = element.shadowRoot.querySelector("lightning-datatable");
    datatable.dispatchEvent(
      new CustomEvent("rowselection", {
        detail: {
          selectedRows: [{ id: "069AAA", title: "Some File", isFolder: false }]
        }
      })
    );
    await flushPromises();

    expect(findButton("Move Files").disabled).toBe(false);
    expect(findButton("Delete Files").disabled).toBe(false);
  });

  it("clicking a library or folder name navigates into it (loads its files) without touching the tree's expand state", async () => {
    getLibrariesWithFolders.mockResolvedValue(MOCK_LIBRARIES);
    getFilesInFolder.mockResolvedValue({
      files: [],
      path: "Marketing Assets",
      breadcrumbs: [
        { id: "058000000000001AAA", label: "Marketing Assets", isLast: true }
      ]
    });

    const element = createElement("c-library-file-manager", {
      is: LibraryFileManager
    });
    document.body.appendChild(element);
    await flushPromises();

    const tree = element.shadowRoot.querySelector("lightning-tree");

    tree.dispatchEvent(
      new CustomEvent("select", { detail: { name: "058000000000001AAA" } })
    );
    await flushPromises();

    // Navigation still works - the right panel loads that library's files...
    expect(getFilesInFolder).toHaveBeenCalledWith({
      libraryId: "058000000000001AAA",
      folderId: null
    });
    // ...but expand/collapse is entirely lightning-tree's own business now;
    // our data is never touched by a select, for a library OR a folder.
    expect(tree.items[0].expanded).toBe(false);

    tree.dispatchEvent(
      new CustomEvent("select", { detail: { name: "07H000000000001AAA" } })
    );
    await flushPromises();

    expect(getFilesInFolder).toHaveBeenCalledWith({
      libraryId: "058000000000001AAA",
      folderId: "07H000000000001AAA"
    });
    expect(tree.items[0].expanded).toBe(false);
    expect(tree.items[0].items[0].expanded).toBe(false);
  });
});
