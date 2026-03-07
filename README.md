# GH-Workflow-Clean

`gh-actions-cleanup` is a macOS terminal CLI for shutting down and cleaning up GitHub Actions usage across repositories.

## What It Does

- selects the GitHub host and authenticated account to use
- selects the target repository
- disables GitHub Actions workflows
- deletes workflow runs
- deletes Actions artifacts
- deletes Actions caches

## Requirements

- macOS terminal
- GitHub CLI (`gh`)
- a GitHub account authenticated with `gh auth login`

## Install

From the project folder:

```bash
chmod +x gh-actions-cleanup install-gh-actions-cleanup.sh
./install-gh-actions-cleanup.sh
```

By default, the installer:

- installs the terminal command into a writable bin directory
- installs a macOS app bundle into `~/Applications`
- generates the app icon locally during install

The installer is intended for macOS and will stop if you run it on another platform.

If the command install path is not already in your shell `PATH`, add the export line the installer prints into `~/.zshrc`, then open a new terminal.

You can also install only one target:

```bash
./install-gh-actions-cleanup.sh --cli-only
./install-gh-actions-cleanup.sh --app-only
```

## Quick Start

Interactive mode:

```bash
gh-actions-cleanup
```

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
- the app opens Terminal and starts the interactive CLI

## Common Commands

Disable workflows only:

```bash
gh-actions-cleanup --repo OWNER/REPO --disable-workflows --yes
```

Delete workflow runs only:

```bash
gh-actions-cleanup --repo OWNER/REPO --delete-runs --yes
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

- The CLI uses the selected active GitHub account on the selected host.
- If multiple accounts are authenticated on one host, it can switch using `gh auth switch`.
- The token in use needs repository and workflow access to delete Actions resources.
- If the active token is invalid or the GitHub API core rate limit is exhausted, the CLI now stops early and tells you exactly what to fix.
- `--dry-run` is the safest way to confirm intended changes before deleting anything.
- The macOS app uses Terminal for the interactive session and may ask for automation permission the first time it launches.

## Notice

- Copyright (c) 2026 Wayne Tech Lab LLC
- Use at your own risk.
- This project is provided as-is, without warranties or guarantees of any kind.
- You are responsible for reviewing any cleanup action before running it against your repositories.

## Creator Note

Built by Lucas / SatoshiUNO.

- Wayne Tech Lab LLC: [WayneTechLab.com](https://WayneTechLab.com)
- Public portfolio: [Networks.CHAT](https://Networks.CHAT)
