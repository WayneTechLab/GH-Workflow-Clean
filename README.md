# GH-Workflow-Clean

`gh-actions-cleanup` is a terminal-first macOS CLI for shutting down and cleaning up GitHub Actions usage across repositories.

It can:

- ask which GitHub host and authenticated account to use
- ask which repository to target
- disable all workflows
- delete all workflow runs
- delete all Actions artifacts
- delete all Actions caches

## Requirements

- macOS terminal
- `gh` installed
- `gh auth login` completed for the account you want to use

## Install

From this folder:

```bash
chmod +x gh-actions-cleanup install-gh-actions-cleanup.sh
./install-gh-actions-cleanup.sh
```

If the installer uses `~/.local/bin` and that path is not already in your shell `PATH`, add the export line it prints into `~/.zshrc`, then open a new terminal.

## Usage

Interactive:

```bash
gh-actions-cleanup
```

Full cleanup without extra prompts:

```bash
gh-actions-cleanup --repo WayneTechLab/networkschat --all --yes
```

Dry run:

```bash
gh-actions-cleanup --repo WayneTechLab/networkschat --all --dry-run --yes
```

Target only one cleanup action:

```bash
gh-actions-cleanup --repo WayneTechLab/networkschat --delete-runs --yes
gh-actions-cleanup --repo WayneTechLab/networkschat --delete-caches --yes
gh-actions-cleanup --repo WayneTechLab/networkschat --disable-workflows --yes
```

## Notice

- Copyright (c) 2026 Wayne Tech Lab LLC
- Use at your own risk.
- This project is provided as-is, without warranties or guarantees of any kind.
- You are responsible for reviewing any cleanup action before running it against your repositories.

## Creator Note

Built by Lucas / SatoshiUNO.

- Wayne Tech Lab LLC: [WayneTechLab.com](https://WayneTechLab.com)
- Public portfolio: [Networks.CHAT](https://Networks.CHAT)

## Notes

- The command works against whichever account is active for the selected host. If you have multiple authenticated accounts on the same host, it can switch using `gh auth switch`.
- Your token needs repository and workflow access to delete Actions resources.
- `--dry-run` is the safest way to confirm what would be touched before deleting anything.
