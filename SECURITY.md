# Security Policy

## Reporting a Vulnerability

If you find a security vulnerability in Library File Manager, please **do not open a public GitHub issue**.

Instead, report it privately using GitHub's [private vulnerability reporting](https://github.com/sfToolboxApps/LibraryFileManager/security/advisories/new) (Security tab → "Report a vulnerability"). This creates a private advisory visible only to maintainers until a fix is ready.

Include, where possible:

- A description of the vulnerability and its potential impact
- Steps to reproduce (an anonymized Apex snippet or a description of the required permission set / library membership state is usually enough — no need to include real org data)
- The affected file(s) and, if known, the specific method or query involved

You should expect an initial response within a few days. If the report is confirmed, a fix will be prepared and released before any public disclosure.

## Supported Versions

This project doesn't maintain multiple released versions — only the latest code on the default branch is supported. Deploy from `master` (or the current active development branch per [CONTRIBUTING.md](CONTRIBUTING.md)) to get fixes.

## Scope

This is an unmanaged Salesforce metadata package deployed directly into your own org — there is no shared hosted service, so most traditional web vulnerability classes (XSS against a shared backend, SSRF, etc.) don't apply in the usual sense. The security surface that matters here is **Salesforce access control**: whether the app's Apex and permission set correctly respect the running user's CRUD/FLS, sharing, and Library permissions rather than acting as System Administrator regardless of who's using it.

See [docs/security.md](docs/security.md) for how that's implemented and verified, and what's intentionally still out of scope for now.
