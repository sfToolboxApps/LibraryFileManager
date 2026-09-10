import { LightningElement } from "lwc";
import { NavigationMixin } from "lightning/navigation";
import MOVE_ICON from "@salesforce/resourceUrl/moveIcon";

const GITHUB_REPO_URL = "https://github.com/sfToolboxApps/LibraryFileManager";

export default class GettingStarted extends NavigationMixin(LightningElement) {
  moveIconUrl = MOVE_ICON;
  githubReadmeUrl = `${GITHUB_REPO_URL}#readme`;
  githubIssuesUrl = `${GITHUB_REPO_URL}/issues`;
  giveBackUrl = "https://biggestlittledreamin.com";

  handleOpenLibraryManager() {
    this[NavigationMixin.Navigate]({
      type: "standard__navItemPage",
      attributes: {
        apiName: "LibraryFileManager"
      }
    });
  }
}
