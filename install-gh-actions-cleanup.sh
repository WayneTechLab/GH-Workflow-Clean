#!/usr/bin/env bash

set -euo pipefail

APP_NAME="gh-actions-cleanup"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_SCRIPT="${SCRIPT_DIR}/${APP_NAME}"
TARGET_DIR="${1:-}"

die() {
  printf "[error] %s\n" "$*" >&2
  exit 1
}

pick_install_dir() {
  local dir=""
  local -a candidates=(
    "/opt/homebrew/bin"
    "/usr/local/bin"
    "$HOME/.local/bin"
    "$HOME/bin"
  )

  if [[ -n "$TARGET_DIR" ]]; then
    printf "%s" "$TARGET_DIR"
    return 0
  fi

  for dir in "${candidates[@]}"; do
    if [[ -d "$dir" && -w "$dir" ]]; then
      printf "%s" "$dir"
      return 0
    fi
  done

  printf "%s" "$HOME/.local/bin"
}

main() {
  local install_dir=""
  local target_path=""

  [[ -f "$SOURCE_SCRIPT" ]] || die "Cannot find ${APP_NAME} in ${SCRIPT_DIR}"

  install_dir="$(pick_install_dir)"
  mkdir -p "$install_dir"
  cp "$SOURCE_SCRIPT" "$install_dir/$APP_NAME"
  chmod +x "$install_dir/$APP_NAME"
  target_path="$install_dir/$APP_NAME"

  printf "[ok] Installed %s\n" "$target_path"

  case ":$PATH:" in
    *":$install_dir:"*)
      printf "[ok] %s is already in PATH\n" "$install_dir"
      ;;
    *)
      printf "[warn] %s is not in PATH\n" "$install_dir"
      printf "[info] Add this line to ~/.zshrc if you want the command available in new terminals:\n"
      printf "export PATH=\"%s:\$PATH\"\n" "$install_dir"
      ;;
  esac

  printf "[info] Run: %s --help\n" "$APP_NAME"
}

main "$@"
