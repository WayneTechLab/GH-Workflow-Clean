#!/usr/bin/env bash

set -euo pipefail

REPO_OWNER="WayneTechLab"
REPO_NAME="GH-Workflow-Clean"
REPO_REF=""
TMP_DIR=""

die() {
  printf "[error] %s\n" "$*" >&2
  exit 1
}

info() {
  printf "[info] %s\n" "$*"
}

resolve_latest_ref() {
  local latest_url=""
  local tag=""

  latest_url="$(curl -fsSL -o /dev/null -w '%{url_effective}' "https://github.com/${REPO_OWNER}/${REPO_NAME}/releases/latest" || true)"
  tag="${latest_url##*/}"

  if [[ -n "$tag" && "$tag" != "latest" && "$tag" != "releases" ]]; then
    printf "%s" "$tag"
    return 0
  fi

  printf "%s" "main"
}

archive_url_for_ref() {
  local ref="$1"

  if [[ "$ref" == "main" ]]; then
    printf "https://github.com/%s/%s/archive/refs/heads/%s.tar.gz" "$REPO_OWNER" "$REPO_NAME" "$ref"
    return 0
  fi

  printf "https://github.com/%s/%s/archive/refs/tags/%s.tar.gz" "$REPO_OWNER" "$REPO_NAME" "$ref"
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
  REPO_REF="$(resolve_latest_ref)"

  if [[ "$REPO_REF" == "main" ]]; then
    info "No tagged release was found. Falling back to ${REPO_OWNER}/${REPO_NAME}@main"
  else
    info "Resolved latest version tag: ${REPO_REF}"
  fi

  info "Downloading ${REPO_OWNER}/${REPO_NAME} (${REPO_REF})"
  curl -fsSL "$(archive_url_for_ref "$REPO_REF")" -o "$TMP_DIR/repo.tar.gz"
  tar -xzf "$TMP_DIR/repo.tar.gz" -C "$TMP_DIR"

  local source_dir=""
  source_dir="$(find "$TMP_DIR" -mindepth 1 -maxdepth 1 -type d -name "${REPO_NAME}-*" | head -n 1)"
  [[ -n "$source_dir" ]] || die "Unable to locate extracted source directory for ${REPO_NAME} (${REPO_REF})"

  info "Removing old copies and installing ${REPO_OWNER}/${REPO_NAME} ${REPO_REF}"
  (
    cd "$source_dir"
    chmod +x gh-actions-cleanup install-gh-actions-cleanup.sh install.sh
    ./install-gh-actions-cleanup.sh
  )

  printf "\n"
  info "Installed version: ${REPO_REF}"
  info "Next steps"
  printf "1. gh auth login -h github.com\n"
  printf "2. gh-actions-cleanup\n"
  printf "3. Or open /Applications/GH Workflow Clean.app\n"
}

main "$@"
