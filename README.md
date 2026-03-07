# GH-Workflow-Clean

`gh-actions-cleanup` is a terminal-first macOS cleanup tool with two delivery modes:

- a native macOS GUI app
- the original CLI engine

Current release: `0.0.6`

## What It Does

- checks GitHub CLI authentication status first
- lets you choose the GitHub host and authenticated account to use
- lets you choose the target repository or paste a full GitHub repo URL
- disables GitHub Actions workflows
- deletes workflow runs
- deletes Actions artifacts
- deletes Actions caches
- remembers the last host, account, and repo you used without storing any tokens or secrets
- keeps the CLI as the source of truth, with the native GUI running the CLI under the hood

## Requirements

- macOS terminal
- GitHub CLI (`gh`)
- a GitHub account authenticated with `gh auth login`
- Xcode or Command Line Tools if you want the native GUI app built locally from source

## One-Line Install

From any Mac:

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/WayneTechLab/GH-Workflow-Clean/main/install.sh)"
```

Then log into GitHub CLI:

```bash
gh auth login -h github.com
gh-actions-cleanup
```

Installer behavior:

- the bootstrap installer resolves the latest tagged release before downloading
- the CLI installs everywhere GitHub CLI is available
- the native GUI app is built automatically when the local Mac has a Swift toolchain
- if Swift is missing, the installer falls back to CLI-only and tells you how to add the GUI later
- when possible, the native app installs into `/Applications`; otherwise it falls back to `~/Applications`
- older app and CLI copies are removed first so upgrades are clean

## Install

From the project folder:

```bash
chmod +x gh-actions-cleanup install-gh-actions-cleanup.sh
./install-gh-actions-cleanup.sh
```

By default, the installer:

- removes stale CLI installs from common macOS bin paths before installing the new version
- removes stale app bundles from `/Applications` and `~/Applications` before reinstalling
- installs the terminal command into a writable bin directory
- installs a native macOS app bundle into `~/Applications`
- prefers `/Applications` when that location is writable
- compiles the GUI locally with Swift when the toolchain is available
- generates the app icon locally during install
- writes the current app version into the bundle metadata and bundled `VERSION` file
- keeps GitHub authentication in the user's existing `gh` keychain session

The installer is intended for macOS and will stop if you run it on another platform.

If the command install path is not already in your shell `PATH`, add the export line the installer prints into `~/.zshrc`, then open a new terminal.

You can also install only one target:

```bash
./install-gh-actions-cleanup.sh --cli-only
./install-gh-actions-cleanup.sh --app-only
./install-gh-actions-cleanup.sh --uninstall-only
```

## Quick Start

Guided mode:

```bash
gh-actions-cleanup
```

The CLI starts with a W.T.L. menu. In guided mode, the tool:

- checks which GitHub hosts are already authenticated
- asks which account to use
- asks which repository to target
- stores only the last host, account, and repo for convenience
- never stores or exports GitHub tokens

Full cleanup:

```bash
gh-actions-cleanup --repo OWNER/REPO --all --yes
```

Safe preview first:

```bash
gh-actions-cleanup --repo OWNER/REPO --all --dry-run --yes
```

App launch:

- open `GH Workflow Clean.app` from Finder, Spotlight, or Launchpad
- the native app opens a real macOS window
- the GUI runs the bundled CLI in the background and streams the output into a log panel
- the GUI includes buttons to open GitHub login or the raw CLI flow in Terminal when needed

## GUI Highlights

- native macOS SwiftUI window with a single-screen panel layout
- high-contrast dark UI with readable text and a unified visual system
- clear GitHub login state banner with host and account readiness
- account/host controls that avoid pointless dropdowns for single fixed items
- repo/URL input, destructive scope toggles, and explicit safety arm switch
- logout button for the selected GitHub account
- live output console with readable CLI logs inside the app
- login and CLI fallback buttons so users can stay in the secure `gh` auth flow

## Common Commands

Disable workflows only:

```bash
gh-actions-cleanup --repo OWNER/REPO --disable-workflows --yes
```

Delete workflow runs only:

```bash
gh-actions-cleanup --repo OWNER/REPO --delete-runs --yes
```

Delete one exact run by ID or URL:

```bash
gh-actions-cleanup --repo OWNER/REPO --run 21023858697 --yes
gh-actions-cleanup --repo OWNER/REPO --run "https://github.com/OWNER/REPO/actions/runs/21023858697/workflow" --yes
```

Use a custom GitHub host or a full repo URL:

```bash
gh-actions-cleanup --host github.example.com --repo OWNER/REPO --all --yes
gh-actions-cleanup --repo https://github.example.com/OWNER/REPO --all --yes
gh-actions-cleanup --repo github.example.com/OWNER/REPO --all --yes
```

Delete only one run series:

```bash
gh-actions-cleanup --repo OWNER/REPO --delete-runs --run-filter "Sync Google Analytics Data" --yes
```

Delete artifacts only:

```bash
gh-actions-cleanup --repo OWNER/REPO --delete-artifacts --yes
```

Delete caches only:

```bash
gh-actions-cleanup --repo OWNER/REPO --delete-caches --yes
```

## Notes

- Users must authenticate first with `gh auth login -h <host>`.
- The CLI uses the selected active GitHub account on the selected host.
- The GUI uses the same `gh` login state and the same bundled CLI engine.
- If multiple accounts are authenticated on one host, it can switch using `gh auth switch` and restore the prior active account when the session ends.
- The tool does not embed, print, or save GitHub tokens.
- The token in use needs repository and workflow access to delete Actions resources.
- You can target one exact workflow run by numeric ID or by pasting the GitHub run URL.
- If the GitHub API core rate limit is exhausted, the CLI stops early and tells you when it resets.
- The tool stores only the last host, account, and repo in `~/Library/Application Support/GH Workflow Clean/last-session.env`.
- `--dry-run` is the safest way to confirm intended changes before deleting anything.
- The native GUI app currently targets macOS 12 or newer.

## Notice

- Copyright (c) 2026 Wayne Tech Lab LLC
- Use at your own risk.
- This project is provided as-is, without warranties or guarantees of any kind.
- You are responsible for reviewing any cleanup action before running it against your repositories.

## Creator Note

Built by Lucas / SatoshiUNO.

- Wayne Tech Lab LLC: [WayneTechLab.com](https://WayneTechLab.com)
- Public portfolio: [Networks.CHAT](https://Networks.CHAT)
