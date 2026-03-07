# GH Workflow Clean Help Center

## What This App Does

GH Workflow Clean is a native macOS cleanup utility for GitHub Actions maintenance.

It can:

- verify `gh` authentication first
- show authenticated GitHub hosts and accounts
- list repositories for an owner or organization
- target one repository, many repositories, or all loaded repositories
- disable workflows
- delete workflow runs
- delete artifacts
- delete caches
- keep quick auth actions in the lower status bar
- move full GitHub host and account controls to a dedicated `Settings` page

## Safe First Run

1. Install GitHub CLI if it is not already present.
2. Authenticate with `gh auth login -h github.com`.
3. Open the app and review the warning screen.
4. Confirm the current session in the lower status bar or open `Settings`.
5. Load repositories and verify the target list.
6. Turn on `Dry run only` first.
7. Review the live output before using destructive cleanup.

## Navigation Model

The app now uses a cleaner two-layer workflow:

- `Control Center` for repository targeting, cleanup scope, execution, and logs
- `Settings` for GitHub host, account, login, logout, and session management

The bottom status bar stays visible and provides:

- current GitHub session state
- selected repo target summary
- `Refresh`
- `Login` or `Re-Login`
- `Logout`
- direct `Settings` access

## Repository Selection

The app supports two target modes:

- checked repositories from the built-in repository browser
- one manual repository or URL in the fallback field

If one or more repositories are checked in the browser, the manual field is ignored.

## Cleanup Scope

You can run:

- full cleanup
- workflows only
- runs only
- artifacts only
- caches only
- a single run by ID or run URL
- filtered runs by name text

## Safety Model

The app is intentionally destructive.

Before cleanup runs:

- the user must already be logged into GitHub CLI
- the app shows a warning and terms screen every launch
- the user must explicitly arm destructive cleanup

## Stored Data

The app stores only the last selected:

- host
- account
- repository target

It does not intentionally store GitHub tokens.

## Help Files

Bundled help content includes:

- README
- CHANGELOG
- Terms of Service
- Security Notes
- Brand System
- macOS App Notes
- Project Info
- Metadata and press-kit files

## Support

Provided by Wayne Tech Lab LLC  
[www.WayneTechLab.com](https://www.WayneTechLab.com)
