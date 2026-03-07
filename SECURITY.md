## Security Notes

GH Workflow Clean is designed to use the existing GitHub CLI authentication state rather than embedding or storing GitHub tokens itself.

### What This Project Stores

The project stores only the last-used:

- GitHub host
- GitHub account name
- repository target

That data is stored in:

- `~/Library/Application Support/GH Workflow Clean/last-session.env`

Older versions may have stored the same non-secret session values in:

- `~/Library/Application Support/GitHub Action Clean-Up Tool/last-session.env`

### What This Project Does Not Store

This project does not intentionally store:

- GitHub personal access tokens
- GitHub API keys
- private SSH keys
- cloud provider secret keys

### Review Summary

Review pass completed: March 6, 2026

Checks performed:

- tracked file scan for common token, key, and private key patterns
- git history scan for the same high-risk patterns
- review of CLI, installer, and native app auth/session logic
- review of local persistence paths and log output behavior

Findings:

- no hardcoded GitHub tokens or API keys were found in tracked files
- no matching token or private key patterns were found in git history
- no code path was found that intentionally writes GitHub auth secrets to disk
- the native app now redacts common token and key patterns from its live log panel before display

### Residual Risk

- the tool relies on the user’s existing `gh` authentication state
- GitHub CLI output can still include non-secret account and host information
- destructive operations remain the primary operational risk, not secret exposure

### Reporting

If you discover a security issue, review the repository owner and contact channels at:

- [www.WayneTechLab.com](https://www.WayneTechLab.com)
