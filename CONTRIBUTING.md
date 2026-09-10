# Contributing to Salesforce Library File Manager

Thanks for your interest in contributing! This project welcomes bug reports, feature suggestions, and pull requests.

## Reporting Bugs

Open an issue on GitHub and include:

- What you expected to happen vs. what actually happened
- Steps to reproduce
- Your Salesforce org type (Developer Edition, sandbox, production) and whether Salesforce CRM Content is enabled
- Any relevant error messages or screenshots
- Browser and version, if it's a UI issue

## Suggesting Features

Open an issue describing:

- The problem you're trying to solve (not just the solution you have in mind)
- How it fits with the project's core goal: making Salesforce file/library management simpler than the native tools allow
- Any relevant examples from other tools, if helpful

## Development Setup

This is a standard Salesforce DX (SFDX) project.

```bash
git clone https://github.com/sfToolboxApps/LibraryFileManager.git
cd LibraryFileManager
npm install
sf org login web --alias dev --instance-url https://login.salesforce.com
sf project deploy start --source-dir force-app --target-org dev
```

Ensure Salesforce CRM Content is enabled in your dev org (Setup → Salesforce CRM Content Settings) before testing — the app won't function without it.

### Running tests

Apex tests:

```bash
sf apex run test --class-names LibraryFileManagerLibrariesTest,LibraryFileManagerFilesTest,LibraryFileManagerMoveTest,LibraryFileManagerFolderAndDeleteTest --code-coverage --target-org dev
```

LWC Jest tests:

```bash
npm run test:unit
```

## Coding Standards

### Apex

- Bulkify all SOQL/DML — no queries or DML statements inside loops.
- Wrap public entry points in `try/catch` and surface errors as `AuraHandledException` with a clean, user-facing message.
- Add a guard clause for any required parameter rather than relying on downstream code to fail informatively.
- New logic needs test coverage: a positive path, a negative/error path, and a bulk path where relevant. Run the full test class before submitting a PR — all tests must pass, and coverage should not regress.

### LWC

- Prefer plain native HTML elements (e.g. `<button>`) over base Lightning components when you need reliable, guaranteed control over styling — several bugs in this project's history came from fighting `lightning-button`'s shadow DOM and undocumented styling hooks for disabled states.
- Keep `@track` state mutations explicit and intentional. Avoid getters that rebuild arrays/objects on every render if the result is bound to a component (like `lightning-tree`) that relies on reference stability to preserve internal UI state — this caused a real regression (tree collapsing on unrelated state changes) fixed earlier in this project's history.
- Add or update Jest tests (`__tests__/*.test.js`) alongside any behavior change.

## Pull Request Process

1. Fork the repo and create a branch from `master` (or the current active development branch).
2. Make your change, with tests.
3. Run the full Apex test suite and the Jest suite locally — both must pass.
4. Open a PR describing what changed and why. Reference any related issue.
5. Be responsive to review feedback — small, focused PRs get merged faster than large ones.
