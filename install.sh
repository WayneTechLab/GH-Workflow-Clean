#!/usr/bin/env bash

set -euo pipefail

REPO_OWNER="WayneTechLab"
REPO_NAME="GH-Workflow-Clean"
REPO_REF="main"
ARCHIVE_URL="https://github.com/${REPO_OWNER}/${REPO_NAME}/archive/refs/heads/${REPO_REF}.tar.gz"
TMP_DIR=""

die() {
  printf "[error] %s\n" "$*" >&2
  exit 1
}

info() {
  printf "[info] %s\n" "$*"
}

cleanup() {
  [[ -n "$TMP_DIR" && -d "$TMP_DIR" ]] && rm -rf -- "$TMP_DIR"
}

require_macos() {
  [[ "$(uname -s)" == "Darwin" ]] || die "This installer currently supports macOS only."
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"
}

main() {
  trap cleanup EXIT
  require_macos
  require_command curl
  require_command tar

  if ! command -v gh >/dev/null 2>&1; then
    if command -v brew >/dev/null 2>&1; then
      die "GitHub CLI is required. Install it first with: brew install gh"
    fi
    die "GitHub CLI is required. Install it first from https://cli.github.com/"
  fi

  TMP_DIR="$(mktemp -d /tmp/gh-workflow-clean-install.XXXXXX)"
  mkdir -p "$TMP_DIR"

  info "Downloading ${REPO_OWNER}/${REPO_NAME} (${REPO_REF})"
  curl -fsSL "$ARCHIVE_URL" -o "$TMP_DIR/repo.tar.gz"
  tar -xzf "$TMP_DIR/repo.tar.gz" -C "$TMP_DIR"

  info "Installing command-line tool and macOS app"
  (
    cd "$TMP_DIR/${REPO_NAME}-${REPO_REF}"
    chmod +x gh-actions-cleanup install-gh-actions-cleanup.sh install.sh
    ./install-gh-actions-cleanup.sh
  )

  printf "\n"
  info "Next steps"
  printf "1. gh auth login -h github.com\n"
  printf "2. gh-actions-cleanup\n"
  printf "3. Or open ~/Applications/GH Workflow Clean.app\n"
}

main "$@"
