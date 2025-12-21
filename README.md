# Salesforce Library File Manager

> A powerful Lightning Web Component (LWC) for managing files across Salesforce Libraries with ease.

Connect with me on LinkedIn - [Bill Greenhaw](https://www.linkedin.com/in/billgreenhaw/)

## 📋 Table of Contents

- [Overview](#overview)
- [The Problem](#the-problem)
- [The Solution](#the-solution)
- [Features](#features)
- [Installation](#installation)
- [Usage](#usage)
- [Architecture](#architecture)
- [Testing](#testing)
- [Contributing](#contributing)
- [License](#license)
- [Support](#support)

## 🎯 Overview

Salesforce Library File Manager is a custom Lightning Web Component that dramatically simplifies file organization in Salesforce. Move files between libraries, organize them into folders, and manage your content library structure—all from an intuitive, modern interface.

**What makes this special?** Salesforce's native file management requires moving files one at a time and **completely blocks** moving files between folders in different libraries. This component eliminates those limitations and makes cross-library folder moves possible with automatic intelligent handling of Salesforce's platform constraints.

> 🔒 **Production Safety**: Always install and test in a Sandbox environment first. Never install untested code directly in production.

## 🔥 The Problem

Standard Salesforce file management has significant limitations:

- ❌ **One file at a time** - Moving multiple files requires repetitive manual work
- ❌ **No cross-library folder moves** - Can't move files from a folder in Library A to a folder in Library B
- ❌ **Limited bulk operations** - No way to reorganize large numbers of files efficiently
- ❌ **Poor folder navigation** - Hard to visualize and navigate complex folder hierarchies
- ❌ **No breadcrumb navigation** - Easy to get lost in deep folder structures

## ✨ The Solution

This component provides:

- ✅ **Bulk file operations** - Move dozens or hundreds of files at once
- ✅ **Cross-library folder moves** - The #1 missing feature in Salesforce Libraries! Move files directly from any folder to any folder, even across different libraries. The app automatically handles Salesforce's platform limitations behind the scenes.
- ✅ **Intelligent automation** - Automatically detects complex scenarios and handles multi-step processes for you
- ✅ **Visual tree navigation** - See your entire library and folder structure at a glance
- ✅ **Breadcrumb navigation** - Always know where you are in the hierarchy

## 🚀 Features

### File Operations

- **Move files between libraries** - Transfer files from one library to another with a single click
- **Move files to folders** - Organize files into folders within the same library
- **Cross-library folder moves (GAME CHANGER!)** - The one thing Salesforce won't let you do natively! Move files from a folder in Library A directly to a folder in Library B. The app automatically detects this scenario and handles the required two-step process seamlessly behind the scenes. Just click confirm and it's done!
- **Bulk operations** - Select and move multiple files simultaneously (up to 1000 files at once)
- **Delete files** - Remove unwanted files with confirmation and recycle bin support

### Folder Management

- **Create folders** - Add new folders to any library or subfolder
- **Visual folder hierarchy** - See your entire folder structure in an expandable tree view
- **Folder navigation** - Click through folders to explore content
- **File counts** - Each folder shows how many files it contains

### User Experience

- **Breadcrumb navigation** - Always see your current location in the library/folder hierarchy
- **Search functionality** - Quickly find destination libraries and folders
- **Real-time updates** - File lists refresh automatically after operations
- **Smart error handling** - Clear, actionable error messages
- **Progress indicators** - Visual feedback during long operations

### Technical Features

- **High test coverage** - 76%+ test coverage with 66 comprehensive test methods
- **Managed package ready** - Prepared for AppExchange distribution
- **Secure** - Uses Salesforce `with sharing` for proper record-level security
- **Performant** - Optimized queries and bulk processing
- **Error resilient** - Graceful handling of edge cases and partial failures

## 📦 Installation

> ⚠️ **IMPORTANT: Always test in a Sandbox environment first!** Do not install directly in production. Test thoroughly in a sandbox or developer org before deploying to your production environment.

### Prerequisites

- Salesforce org with Libraries/Content enabled
- Administrator or System Administrator profile
- Users must have Content enabled on their user record

### Option 1: Managed Package (Recommended for Production Use)

**Best for:** Production orgs, easier upgrades, namespace protection

1. Click the installation link:
   - **Production/Developer Orgs**: [Install Managed Package](https://login.salesforce.com/packaging/installPackage.apexp?p0=04tfj0000008pYP)
   - **Sandbox Orgs**: Replace `login.salesforce.com` with `test.salesforce.com` in the URL above

2. Log in to your Salesforce org

3. Choose installation option:
   - **Install for Admins Only** (recommended initially)
   - Install for All Users
   - Install for Specific Profiles

4. Click **Install**

5. Approve Third-Party Access if prompted

6. Wait for installation to complete

### Option 2: Unmanaged Package (Recommended for Customization)

**Best for:** Sandboxes, development orgs, when you need to modify the code

1. Click the installation link:
   - **Production/Developer Orgs**: [Install Unmanaged Package](https://login.salesforce.com/packaging/installPackage.apexp?p0=04tfj0000008lpl)
   - **Sandbox Orgs**: Replace `login.salesforce.com` with `test.salesforce.com` in the URL above

2. Log in to your Salesforce org

3. Choose installation option:
   - **Install for Admins Only** (recommended initially)
   - Install for All Users
   - Install for Specific Profiles

4. Click **Install**

5. Wait for installation to complete

### Option 3: Deploy from Source (For Developers)

**Best for:** Contributing to the project, advanced customization

1. Download the repository:
   ```bash
   git clone https://github.com/sfToolboxApps/LibraryFileManager.git
   cd LibraryFileManager
   ```

2. Deploy to your Salesforce org using SFDX:
   ```bash
   sfdx force:source:deploy -p force-app -u your-org-alias
   ```

### Adding to Lightning Pages

1. Navigate to any Lightning App page, Home page, or Record page
2. Click **Setup (gear icon) → Edit Page**
3. Find **Library File Manager** in the component list
4. Drag it onto the page
5. Save and activate

## 💡 Usage

### Moving Files Within the Same Library

1. **Browse to your library** - Click on the library in the left panel
2. **Navigate to source folder** - Click through folders to find your files
3. **Select files** - Check the boxes next to files you want to move
4. **Click "Move Files"** - The move panel opens on the right
5. **Choose destination** - Select the target folder in the destination tree
6. **Confirm move** - Click "Move Files" button

### Moving Files Between Libraries

1. **Browse to source location** - Navigate to the library/folder containing your files
2. **Select files** - Choose one or more files to move
3. **Click "Move Files"** - The move panel opens
4. **Select target library** - Choose the destination library or folder
5. **Confirm move** - The app handles the rest automatically

### Cross-Library Folder Moves (Two-Step Process)

When moving files from a folder in Library A to a folder in Library B, the app automatically:

1. **Detects the cross-library requirement** - Shows you a two-step confirmation modal
2. **Step 1: Adds files to target library** - Files are shared to the destination library
3. **Step 2: Organizes into folder** - Files are placed in the target folder
4. **Success notification** - You're automatically navigated to the destination

This happens automatically—you just confirm the operation and the app handles both steps.

**Why is this special?** Salesforce doesn't allow direct folder-to-folder moves across libraries. Files must first "join" the target library before they can be organized into folders within it. Your app detects this scenario automatically and handles the complexity behind the scenes. From your perspective, it's just one click!

### Creating Folders

1. **Navigate to parent location** - Go to the library or folder where you want to create a subfolder
2. **Click "Create Folder"** - Opens the folder creation modal
3. **Enter folder name** - Type a descriptive name
4. **Click "Create Folder"** - New folder appears in the tree

### Deleting Files

1. **Select files** - Choose files to delete
2. **Click "Delete Files"** - Confirmation modal appears
3. **Confirm deletion** - Files are moved to Recycle Bin (recoverable for 15 days)

## 🏗 Architecture

### Component Structure

```
LibraryFileManager/
├── force-app/
│   └── main/
│       └── default/
│           ├── classes/
│           │   ├── LibraryFileManagerController.cls       # Main Apex controller
│           │   ├── LibraryFileManagerController.cls-meta.xml
│           │   ├── LibraryFileManagerControllerTest.cls   # Comprehensive tests
│           │   └── LibraryFileManagerControllerTest.cls-meta.xml
│           └── lwc/
│               └── libraryFileManager/
│                   ├── libraryFileManager.html            # Component template
│                   ├── libraryFileManager.js              # Component logic
│                   ├── libraryFileManager.css             # Salesforce Lightning Design System styles
│                   └── libraryFileManager.js-meta.xml     # Component metadata
├── README.md
└── LICENSE
```

### Salesforce Object Model

The component works with Salesforce's Content Management objects:

| Object | Purpose |
|--------|---------|
| `ContentDocument` | Represents the file itself |
| `ContentVersion` | Stores file metadata and versions |
| `ContentWorkspace` | Represents a library |
| `ContentDocumentLink` | Links files to libraries |
| `ContentFolder` | Represents folders within libraries |
| `ContentFolderMember` | Links files to folders |
| `ContentFolderLink` | Links folders to libraries |

### Key Technical Decisions

1. **True Move vs. Share**: The component implements true moves (not sharing) by:
   - Creating links to the target library
   - Updating `ParentId` to transfer ownership
   - Removing links from source libraries

2. **Two-Step Cross-Library Moves**: When moving between library folders:
   - Files must first be added to the target library
   - Then organized into the target folder
   - This is a Salesforce platform limitation, not a component limitation

3. **ContentFolderMember Management**: Uses UPDATE pattern instead of INSERT to:
   - Avoid duplicate errors
   - Work with Salesforce's automatic background processes
   - Maintain data integrity

## 🤝 Contributing

Contributions are welcome! Here's how you can help:

### Getting Started

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

### Development Guidelines

- **Code Style**: Follow Salesforce Apex and JavaScript best practices
- **Testing**: Maintain or improve test coverage (aim for 75%+)
- **Documentation**: Update README for any user-facing changes
- **Commits**: Use clear, descriptive commit messages

### Areas for Contribution

- 🐛 Bug fixes
- ✨ New features (folder renaming, folder deletion, etc.)
- 📝 Documentation improvements
- 🧪 Additional test coverage
- 🌐 Localization/internationalization
- ♿ Accessibility improvements
- 📱 Enhanced mobile experience

## 📄 License

This project is licensed under the **MIT License** - see the [LICENSE](LICENSE) file for details.

### What This Means

- ✅ Free to use for personal and commercial projects
- ✅ Free to modify and distribute
- ✅ No warranty provided
- ℹ️ Must include copyright notice and license

## 🆘 Support

### Getting Help

- **Documentation**: Check this README first
- **Issues**: [GitHub Issues](https://github.com/sfToolboxApps/LibraryFileManager/issues)
- **Discussions**: [GitHub Discussions](https://github.com/sfToolboxApps/LibraryFileManager/discussions)

### Known Limitations

1. **ContentFolderMember Timing**: Background processes may cause slight delays in folder organization
2. **Large Bulk Operations**: Operations with 1000+ files may take time
3. **Mobile Navigation**: Folder tree less optimal on very small screens (phone portrait mode)

### Reporting Issues

When reporting issues, please include:

- Salesforce org edition and API version
- Steps to reproduce the issue
- Expected vs. actual behavior
- Screenshots if applicable
- Browser and device information

## 🎉 Acknowledgments

- Built with [Salesforce Lightning Design System](https://www.lightningdesignsystem.com/)
- Inspired by the need to simplify Salesforce file management

## 🗺 Roadmap

Future enhancements under consideration:

- [ ] Folder renaming
- [ ] Folder deletion (with file handling)
- [ ] Move entire folders (including subfolders)
- [ ] Drag-and-drop interface
- [ ] Advanced filtering and search
- [ ] Audit trail of file moves

---

**Made with ❤️ for the Salesforce community**

*If you find this component useful, please ⭐ star the repository!*
