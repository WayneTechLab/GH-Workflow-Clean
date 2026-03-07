#!/usr/bin/env bash

set -euo pipefail

REPO_OWNER="WayneTechLab"
REPO_NAME="GH-Workflow-Clean"
REPO_REF="main"
RAW_BASE="https://raw.githubusercontent.com/${REPO_OWNER}/${REPO_NAME}/${REPO_REF}"
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

download_file() {
  local remote_path="$1"
  local local_path="$2"

  curl -fsSL "${RAW_BASE}/${remote_path}" -o "$local_path"
}

main() {
  trap cleanup EXIT
  require_macos
  require_command curl

  if ! command -v gh >/dev/null 2>&1; then
    if command -v brew >/dev/null 2>&1; then
      die "GitHub CLI is required. Install it first with: brew install gh"
    fi
    die "GitHub CLI is required. Install it first from https://cli.github.com/"
  fi

  TMP_DIR="$(mktemp -d /tmp/gh-workflow-clean-install.XXXXXX)"
  mkdir -p "$TMP_DIR/assets" "$TMP_DIR/macos"

  info "Downloading ${REPO_OWNER}/${REPO_NAME} (${REPO_REF})"
  download_file "gh-actions-cleanup" "$TMP_DIR/gh-actions-cleanup"
  download_file "install-gh-actions-cleanup.sh" "$TMP_DIR/install-gh-actions-cleanup.sh"
  download_file "assets/app-icon.svg" "$TMP_DIR/assets/app-icon.svg"
  download_file "macos/GHWorkflowCleanGUI.swift" "$TMP_DIR/macos/GHWorkflowCleanGUI.swift"

  chmod +x "$TMP_DIR/gh-actions-cleanup" "$TMP_DIR/install-gh-actions-cleanup.sh"

  info "Installing command-line tool and macOS app"
  (
    cd "$TMP_DIR"
    ./install-gh-actions-cleanup.sh
  )

  printf "\n"
  info "Next steps"
  printf "1. gh auth login -h github.com\n"
  printf "2. gh-actions-cleanup\n"
  printf "3. Or open ~/Applications/GH Workflow Clean.app\n"
}

main "$@"
