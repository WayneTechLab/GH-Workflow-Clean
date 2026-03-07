#!/usr/bin/env bash

set -euo pipefail

APP_NAME="gh-actions-cleanup"
APP_DISPLAY_NAME="GH Workflow Clean"
APP_BUNDLE_NAME="${APP_DISPLAY_NAME}.app"
APP_BUNDLE_ID="com.waynetechlab.ghworkflowclean"
APP_VERSION="0.0.1"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_SCRIPT="${SCRIPT_DIR}/${APP_NAME}"
SOURCE_ICON="${SCRIPT_DIR}/assets/app-icon.svg"

INSTALL_CLI=1
INSTALL_APP=1
CLI_TARGET_DIR=""
APP_TARGET_DIR=""
TEMP_DIRS=""

die() {
  printf "[error] %s\n" "$*" >&2
  exit 1
}

usage() {
  cat <<EOF
Install ${APP_NAME} as a terminal command and/or a macOS app bundle.

Usage:
  ./install-gh-actions-cleanup.sh [options]

Options:
  --cli-only           Install only the terminal command
  --app-only           Install only the macOS app bundle
  --cli-dir DIR        Override the command install directory
  --app-dir DIR        Override the app install directory
  --help               Show this help text

Defaults:
  - command install: best writable path from /opt/homebrew/bin, /usr/local/bin, ~/.local/bin, ~/bin
  - app install: ~/Applications
EOF
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"
}

require_macos() {
  [[ "$(uname -s)" == "Darwin" ]] || die "This installer currently supports macOS only"
}

register_temp_dir() {
  if [[ -z "$TEMP_DIRS" ]]; then
    TEMP_DIRS="$1"
  else
    TEMP_DIRS="${TEMP_DIRS}"$'\n'"$1"
  fi
}

cleanup_temp_dirs() {
  local dir=""

  [[ -n "$TEMP_DIRS" ]] || return 0

  while IFS= read -r dir; do
    [[ -n "$dir" && -d "$dir" ]] && rm -rf -- "$dir"
  done <<<"$TEMP_DIRS"
}

pick_cli_install_dir() {
  local dir=""
  local -a candidates=(
    "/opt/homebrew/bin"
    "/usr/local/bin"
    "$HOME/.local/bin"
    "$HOME/bin"
  )

  if [[ -n "$CLI_TARGET_DIR" ]]; then
    printf "%s" "$CLI_TARGET_DIR"
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

pick_app_install_dir() {
  if [[ -n "$APP_TARGET_DIR" ]]; then
    printf "%s" "$APP_TARGET_DIR"
    return 0
  fi

  printf "%s" "$HOME/Applications"
}

render_icon_icns() {
  local tmpdir=""
  local rendered_png=""
  local iconset_dir=""
  local size=""
  local double_size=""
  local icns_path=""

  require_command qlmanage
  require_command sips
  require_command iconutil

  [[ -f "$SOURCE_ICON" ]] || die "Cannot find icon source at $SOURCE_ICON"

  tmpdir="$(mktemp -d /tmp/gh-actions-cleanup-icon.XXXXXX)"
  register_temp_dir "$tmpdir"
  qlmanage -t -s 1024 -o "$tmpdir" "$SOURCE_ICON" >/dev/null 2>&1 || die "Failed to render the app icon source"

  rendered_png="$(find "$tmpdir" -maxdepth 1 -type f -name '*.png' | head -n 1)"
  [[ -n "$rendered_png" ]] || die "Icon rendering did not produce a PNG"

  iconset_dir="$tmpdir/AppIcon.iconset"
  mkdir -p "$iconset_dir"

  for size in 16 32 128 256 512; do
    double_size=$((size * 2))
    sips -z "$size" "$size" "$rendered_png" --out "$iconset_dir/icon_${size}x${size}.png" >/dev/null
    sips -z "$double_size" "$double_size" "$rendered_png" --out "$iconset_dir/icon_${size}x${size}@2x.png" >/dev/null
  done

  icns_path="$tmpdir/AppIcon.icns"
  iconutil -c icns "$iconset_dir" -o "$icns_path" >/dev/null
  printf "%s" "$icns_path"
}

install_cli() {
  local install_dir=""
  local target_path=""

  [[ -f "$SOURCE_SCRIPT" ]] || die "Cannot find ${APP_NAME} in ${SCRIPT_DIR}"

  install_dir="$(pick_cli_install_dir)"
  mkdir -p "$install_dir"
  cp "$SOURCE_SCRIPT" "$install_dir/$APP_NAME"
  chmod +x "$install_dir/$APP_NAME"
  target_path="$install_dir/$APP_NAME"

  printf "[ok] Installed command: %s\n" "$target_path"

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
}

write_info_plist() {
  local plist_path="$1"

  cat >"$plist_path" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleDisplayName</key>
  <string>${APP_DISPLAY_NAME}</string>
  <key>CFBundleExecutable</key>
  <string>launcher</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleIdentifier</key>
  <string>${APP_BUNDLE_ID}</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>${APP_DISPLAY_NAME}</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>${APP_VERSION}</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>11.0</string>
  <key>NSHumanReadableCopyright</key>
  <string>Copyright 2026 Wayne Tech Lab LLC</string>
</dict>
</plist>
EOF
}

write_launcher() {
  local launcher_path="$1"

  cat >"$launcher_path" <<'EOF'
#!/usr/bin/env bash

set -euo pipefail

APP_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CLI_PATH="$APP_ROOT/Resources/gh-actions-cleanup"

if [[ ! -x "$CLI_PATH" ]]; then
  /usr/bin/osascript -e 'display alert "GH Workflow Clean" message "Bundled CLI not found inside the app."' >/dev/null 2>&1 || true
  exit 1
fi

/usr/bin/osascript - "$CLI_PATH" <<'OSA'
on run argv
  set cliPath to item 1 of argv
  set innerCommand to "clear; " & quoted form of cliPath & "; EXIT_CODE=$?; printf '\n'; if [ $EXIT_CODE -eq 0 ]; then echo 'GH Workflow Clean finished.'; else echo \"GH Workflow Clean exited with code $EXIT_CODE.\"; fi"
  set commandLine to "/bin/bash -lc " & quoted form of innerCommand
  tell application "Terminal"
    activate
    do script commandLine
  end tell
end run
OSA
EOF

  chmod +x "$launcher_path"
}

install_app_bundle() {
  local app_dir=""
  local bundle_path=""
  local contents_dir=""
  local resources_dir=""
  local macos_dir=""
  local icon_icns=""

  require_command osascript

  [[ -f "$SOURCE_SCRIPT" ]] || die "Cannot find ${APP_NAME} in ${SCRIPT_DIR}"

  app_dir="$(pick_app_install_dir)"
  bundle_path="$app_dir/$APP_BUNDLE_NAME"
  contents_dir="$bundle_path/Contents"
  resources_dir="$contents_dir/Resources"
  macos_dir="$contents_dir/MacOS"

  mkdir -p "$app_dir"
  if [[ "$bundle_path" != */"$APP_BUNDLE_NAME" ]]; then
    die "Refusing to replace an unexpected app bundle path: $bundle_path"
  fi
  rm -rf -- "$bundle_path"
  mkdir -p "$resources_dir" "$macos_dir"

  cp "$SOURCE_SCRIPT" "$resources_dir/$APP_NAME"
  chmod +x "$resources_dir/$APP_NAME"

  icon_icns="$(render_icon_icns)"
  cp "$icon_icns" "$resources_dir/AppIcon.icns"

  write_info_plist "$contents_dir/Info.plist"
  write_launcher "$macos_dir/launcher"

  printf "[ok] Installed macOS app: %s\n" "$bundle_path"
  printf "[info] Open it from Finder, Spotlight, or Launchpad: %s\n" "$APP_DISPLAY_NAME"
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --cli-only)
        INSTALL_APP=0
        shift
        ;;
      --app-only)
        INSTALL_CLI=0
        shift
        ;;
      --cli-dir)
        [[ $# -ge 2 ]] || die "--cli-dir requires a value"
        CLI_TARGET_DIR="$2"
        shift 2
        ;;
      --app-dir)
        [[ $# -ge 2 ]] || die "--app-dir requires a value"
        APP_TARGET_DIR="$2"
        shift 2
        ;;
      --help|-h)
        usage
        exit 0
        ;;
      *)
        die "Unknown option: $1"
        ;;
    esac
  done

  if [[ "$INSTALL_CLI" -eq 0 && "$INSTALL_APP" -eq 0 ]]; then
    die "Nothing selected to install"
  fi
}

main() {
  trap cleanup_temp_dirs EXIT
  parse_args "$@"
  require_macos

  if [[ "$INSTALL_CLI" -eq 1 ]]; then
    install_cli
  fi

  if [[ "$INSTALL_APP" -eq 1 ]]; then
    install_app_bundle
  fi

  printf "[info] Command help: %s --help\n" "$APP_NAME"
}

main "$@"
