# Installation Guide

> ⚠️ **CRITICAL: Test in Sandbox First!** Never install code directly in production. Always test thoroughly in a sandbox or developer org before deploying to production.

This guide provides detailed instructions for installing the Salesforce Library File Manager in your Salesforce org.

## Table of Contents

- [Prerequisites](#prerequisites)
- [Installation Methods](#installation-methods)
  - [Method 1: Managed Package (Recommended for Production Use)](#method-1-managed-package-recommended-for-production-use)
  - [Method 2: Unmanaged Package (For Customization)](#method-2-unmanaged-package-for-customization)
  - [Method 3: SFDX CLI (For Developers and Contributors)](#method-3-sfdx-cli-for-developers-and-contributors)
- [Post-Installation Steps](#post-installation-steps)
- [Adding to Lightning Pages](#adding-to-lightning-pages)
- [Troubleshooting](#troubleshooting)

---

## Prerequisites

Before installing, ensure you have:

1. **Salesforce Org Requirements:**
   - Salesforce org with Libraries/Content enabled
   - Administrator or System Administrator profile
   - Users who access this must have Contented enabled on their user record

2. **For SFDX Installation (Method 3 only):**
   - [Salesforce CLI](https://developer.salesforce.com/tools/sfdxcli) installed
   - Git installed (optional, but recommended)
   - Visual Studio Code with Salesforce Extensions (optional, but recommended)

3. **Permissions Required:**
   - System Administrator access or equivalent permissions to:
     - Install packages
     - Create/assign Permission Sets
     - Edit Lightning pages

---

## Installation Methods

### Method 1: Managed Package (Recommended for Production Use)

This is the recommended method for production environments and most users.

**Best for:** Production orgs, easier upgrades, namespace protection

#### Step 1: Install the Package

1. Click the appropriate installation link:
   - **Production/Developer Orgs**: [Install Managed Package](https://login.salesforce.com/packaging/installPackage.apexp?p0=04tfj0000008pYP)
   - **Sandbox Orgs**: [Install in Sandbox](https://test.salesforce.com/packaging/installPackage.apexp?p0=04tfj0000008pYP)

2. Log in with your Salesforce credentials

3. On the package installation page, choose your installation security level:
   - **Install for Admins Only** (recommended initially for testing)
   - Install for All Users
   - Install for Specific Profiles

4. Click **Install**

5. If prompted, approve Third-Party Access

6. Wait for the installation to complete (usually 1-5 minutes)

7. You'll receive an email when installation is complete


### Method 2: Unmanaged Package (For Customization)

Use this method if you need to modify the code or are installing in a development/sandbox environment.

**Best for:** Sandboxes, development orgs, when you need to customize

#### Step 1: Install the Package

1. Click the appropriate installation link:
   - **Production/Developer Orgs**: [Install Unmanaged Package](https://login.salesforce.com/packaging/installPackage.apexp?p0=04tfj0000008lpl)
   - **Sandbox Orgs**: [Install in Sandbox](https://test.salesforce.com/packaging/installPackage.apexp?p0=04tfj0000008lpl)

2. Log in with your Salesforce credentials

3. On the package installation page, choose your installation security level:
   - **Install for Admins Only** (recommended initially)
   - Install for All Users
   - Install for Specific Profiles

4. Click **Install**

5. Wait for installation to complete

#### Step 2: Create Permission Set (Required for Unmanaged Package)

Since the unmanaged package doesn't include a permission set, you'll need to create one:

1. Navigate to **Setup → Permission Sets → New**
2. Enter the following:
   - **Label**: Library File Manager Access
   - **API Name**: Library_File_Manager_Access
3. Click **Save**
4. Click **Object Settings**
5. Grant the following permissions:
   - **Apex Classes**: Find and enable `LibraryFileManagerController`
   - **Lightning Components**: Find and enable `libraryFileManager`
6. Click **Save**

Follow the same steps as Method 1, Step 2 above.

### Method 3: SFDX CLI (For Developers and Contributors)

This method is for developers who want to contribute to the project or need complete control over the deployment.

**Best for:** Contributing to the project, advanced customization, CI/CD pipelines

#### Step 1: Clone the Repository

```bash
# Clone the repository
git clone https://github.com/sfToolboxApps/LibraryFileManager.git

# Navigate to the project directory
cd LibraryFileManager
```

#### Step 2: Authenticate to Your Org

```bash
# Authenticate to a sandbox org
sfdx auth:web:login -a MyOrgAlias

# Or authenticate to a production org (use with caution)
sfdx auth:web:login -r https://login.salesforce.com -a MyProdOrg
```

#### Step 3: Deploy the Source

```bash
# Deploy all source to the org
sfdx force:source:deploy -p force-app -u MyOrgAlias

# Wait for deployment to complete
```

#### Step 4: Run Tests (Optional but Recommended)

```bash
# Run all tests in the test class
sfdx force:apex:test:run -n LibraryFileManagerControllerTest -u MyOrgAlias -r human

# Verify test coverage is 75%+

---

## Post-Installation Steps

> **Note**: If you installed the Managed Package, the permission set is already included. Skip to Step 2 to assign it to users.

### 1. Verify Libraries are Enabled

1. Navigate to **Setup → Feature Settings → Salesforce Files → General Settings**
2. Ensure **Content Deliveries and Public Links** is enabled
3. Ensure **Libraries** is enabled
4. Save if you made changes

### 2. Test the Installation

1. Navigate to any Lightning page
2. Add the component to the page (see next section)
3. Verify you can see libraries and folders
4. Test creating a folder
5. Test moving a file

---

## Adding to Lightning Pages

### Option 1: Home Page

1. Navigate to **Setup → App Manager**
2. Find your Lightning app and click **Edit**
3. Go to **Lightning Pages**
4. Edit the Home page
5. Drag **Library File Manager** from the component list onto the page
6. Save and activate

### Option 2: App Page

1. Go to the app where you want to add the component
2. Click **Setup (gear icon) → Edit Page**
3. Drag **Library File Manager** component onto the page
4. Adjust size as needed (recommend full width)
5. Save and activate

### Option 3: Custom Tab

1. Navigate to **Setup → Tabs → Lightning Component Tabs → New**
2. Select `libraryFileManager` from the dropdown
3. Name the tab: `Library Manager`
4. Choose an icon
5. Save
6. Add the tab to your Lightning app

### Recommended Placement

- **Full width**: The component works best at full page width
- **Top of page**: Place near the top for easy access
- **Dedicated page**: Consider creating a dedicated app page for file management

---

## Verification Checklist

After installation, verify these work:

- [ ] Component appears on Lightning page
- [ ] Libraries list loads
- [ ] Folders tree expands and collapses
- [ ] Files list shows in right panel
- [ ] Can select files
- [ ] Can create a new folder
- [ ] Can move files within same library
- [ ] Can move files between libraries
- [ ] Can delete files
- [ ] Error messages display correctly
- [ ] Success messages display correctly

---

## Getting Help

If you encounter issues not covered here:

1. Check [GitHub Issues](https://github.com/sfToolboxApps/LibraryFileManager/issues)
2. Review [README.md](README.md) for additional documentation
3. Open a new issue with:
   - Detailed error messages
   - Steps to reproduce
   - Salesforce org edition
   - Browser and device info

---

**Congratulations!** You've successfully installed the Salesforce Library File Manager. 🎉

For usage instructions, see the [README.md](README.md) file.
