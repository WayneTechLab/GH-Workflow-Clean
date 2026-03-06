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

If the installer uses `~/.local/bin` and that path is not already in your shell `PATH`, add the export line it prints into `~/.zshrc`, then open a new terminal.

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

## Common Commands

Disable workflows only:

```bash
gh-actions-cleanup --repo OWNER/REPO --disable-workflows --yes
```

Delete workflow runs only:

```bash
gh-actions-cleanup --repo OWNER/REPO --delete-runs --yes
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
- `--dry-run` is the safest way to confirm intended changes before deleting anything.

## Notice

- Copyright (c) 2026 Wayne Tech Lab LLC
- Use at your own risk.
- This project is provided as-is, without warranties or guarantees of any kind.
- You are responsible for reviewing any cleanup action before running it against your repositories.

## Creator Note

Built by Lucas / SatoshiUNO.

- Wayne Tech Lab LLC: [WayneTechLab.com](https://WayneTechLab.com)
- Public portfolio: [Networks.CHAT](https://Networks.CHAT)
