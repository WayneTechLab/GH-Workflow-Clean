#!/usr/bin/env bash

set -euo pipefail

APP_NAME="gh-actions-cleanup"
APP_DISPLAY_NAME="GH Workflow Clean"
APP_BUNDLE_NAME="${APP_DISPLAY_NAME}.app"
APP_BUNDLE_ID="com.waynetechlab.ghworkflowclean"
APP_EXECUTABLE_NAME="GHWorkflowCleanGUI"
COPYRIGHT_TEXT="Copyright 2026 Wayne Tech Lab LLC"
LEGACY_APP_BUNDLE_NAMES=("GitHub (Action) Clean-UP Tool.app")

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_SCRIPT="${SCRIPT_DIR}/${APP_NAME}"
SOURCE_GUI="${SCRIPT_DIR}/macos/GHWorkflowCleanGUI.swift"
SOURCE_INFO_PLIST_TEMPLATE="${SCRIPT_DIR}/macos/Info.plist.template"
SOURCE_ICONSET_DIR="${SCRIPT_DIR}/assets/AppIcon.appiconset"
SOURCE_LOGO_CARD="${SCRIPT_DIR}/assets/logos/logo-card-square.png"
SOURCE_LOGO_LOCKUP="${SCRIPT_DIR}/assets/logos/logo-horizontal-lockup.png"
SOURCE_HERO="${SCRIPT_DIR}/assets/social/hero-2560x1600.png"
SOURCE_README="${SCRIPT_DIR}/README.md"
SOURCE_SECURITY="${SCRIPT_DIR}/SECURITY.md"
SOURCE_LICENSE="${SCRIPT_DIR}/LICENSE"
SOURCE_TOS="${SCRIPT_DIR}/TERMS-OF-SERVICE.md"
SOURCE_HELP_DIR="${SCRIPT_DIR}/docs"
SOURCE_PROJECT_INFO="${SCRIPT_DIR}/macos/PROJECT-INFO.md"
APP_VERSION="$(sed -n 's/^VERSION=\"\\([^\"]*\\)\"/\\1/p' "$SOURCE_SCRIPT" | head -n 1)"
APP_VERSION="${APP_VERSION:-0.2.0}"

INSTALL_CLI=1
INSTALL_APP=1
UNINSTALL_ONLY=0
CLI_TARGET_DIR=""
APP_TARGET_DIR=""
TEMP_DIRS=""

die() {
  printf "[error] %s\n" "$*" >&2
  exit 1
}

usage() {
  cat <<EOF
Uninstall older copies, then install ${APP_NAME} as a terminal command and/or a native macOS app bundle.

Usage:
  ./install-gh-actions-cleanup.sh [options]

Options:
  --cli-only           Install only the terminal command
  --app-only           Install only the native macOS GUI app bundle
  --uninstall-only     Remove existing CLI and app installs, then exit
  --cli-dir DIR        Override the command install directory
  --app-dir DIR        Override the app install directory
  --help               Show this help text

Defaults:
  - command install: best writable path from /opt/homebrew/bin, /usr/local/bin, ~/.local/bin, ~/bin
  - app install: /Applications when writable, otherwise ~/Applications

Notes:
  - stale copies in /Applications, ~/Applications, and common CLI bin paths are removed first
  - the CLI has no GUI build dependency
  - the GUI app is compiled locally with the Swift toolchain on macOS
  - the native app bundle includes brand artwork, help files, and production metadata
EOF
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"
}

require_macos() {
  [[ "$(uname -s)" == "Darwin" ]] || die "This installer currently supports macOS only"
}

has_swift_toolchain() {
  command -v xcrun >/dev/null 2>&1 && xcrun --find swiftc >/dev/null 2>&1
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

stop_running_app() {
  if pgrep -x "$APP_EXECUTABLE_NAME" >/dev/null 2>&1; then
    printf "[info] Closing running app: %s\n" "$APP_DISPLAY_NAME"
    pkill -x "$APP_EXECUTABLE_NAME" >/dev/null 2>&1 || true
    sleep 1
  fi
}

remove_existing_cli() {
  local candidate=""
  local path=""
  local -a dirs=(
    "/opt/homebrew/bin"
    "/usr/local/bin"
    "$HOME/.local/bin"
    "$HOME/bin"
  )

  if [[ -n "$CLI_TARGET_DIR" ]]; then
    dirs+=("$CLI_TARGET_DIR")
  fi

  for candidate in "${dirs[@]}"; do
    path="$candidate/$APP_NAME"
    if [[ -f "$path" || -L "$path" ]]; then
      rm -f -- "$path"
      printf "[info] Removed old command: %s\n" "$path"
    fi
  done
}

remove_existing_apps() {
  local candidate=""
  local bundle_path=""
  local bundle_name=""
  local -a app_dirs=(
    "/Applications"
    "$HOME/Applications"
  )
  local -a bundle_names=("$APP_BUNDLE_NAME" "${LEGACY_APP_BUNDLE_NAMES[@]}")

  if [[ -n "$APP_TARGET_DIR" ]]; then
    app_dirs+=("$APP_TARGET_DIR")
  fi

  stop_running_app

  for candidate in "${app_dirs[@]}"; do
    for bundle_name in "${bundle_names[@]}"; do
      bundle_path="$candidate/$bundle_name"
      if [[ -d "$bundle_path" ]]; then
        rm -rf -- "$bundle_path"
        printf "[info] Removed old app: %s\n" "$bundle_path"
      fi
    done
  done
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

  if [[ -d "/Applications" && -w "/Applications" ]]; then
    printf "%s" "/Applications"
    return 0
  fi

  printf "%s" "$HOME/Applications"
}

render_icon_icns() {
  local tmpdir=""
  local iconset_dir=""
  local icns_path=""

  require_command iconutil

  [[ -d "$SOURCE_ICONSET_DIR" ]] || die "Cannot find AppIcon.appiconset at $SOURCE_ICONSET_DIR"

  tmpdir="$(mktemp -d /tmp/gh-actions-cleanup-icon.XXXXXX)"
  register_temp_dir "$tmpdir"

  iconset_dir="$tmpdir/AppIcon.iconset"
  mkdir -p "$iconset_dir"
  cp "$SOURCE_ICONSET_DIR/appicon-16x16@1x.png" "$iconset_dir/icon_16x16.png"
  cp "$SOURCE_ICONSET_DIR/appicon-16x16@2x.png" "$iconset_dir/icon_16x16@2x.png"
  cp "$SOURCE_ICONSET_DIR/appicon-32x32@1x.png" "$iconset_dir/icon_32x32.png"
  cp "$SOURCE_ICONSET_DIR/appicon-32x32@2x.png" "$iconset_dir/icon_32x32@2x.png"
  cp "$SOURCE_ICONSET_DIR/appicon-128x128@1x.png" "$iconset_dir/icon_128x128.png"
  cp "$SOURCE_ICONSET_DIR/appicon-128x128@2x.png" "$iconset_dir/icon_128x128@2x.png"
  cp "$SOURCE_ICONSET_DIR/appicon-256x256@1x.png" "$iconset_dir/icon_256x256.png"
  cp "$SOURCE_ICONSET_DIR/appicon-256x256@2x.png" "$iconset_dir/icon_256x256@2x.png"
  cp "$SOURCE_ICONSET_DIR/appicon-512x512@1x.png" "$iconset_dir/icon_512x512.png"
  cp "$SOURCE_ICONSET_DIR/appicon-512x512@2x.png" "$iconset_dir/icon_512x512@2x.png"

  icns_path="$tmpdir/AppIcon.icns"
  iconutil -c icns "$iconset_dir" -o "$icns_path" >/dev/null
  printf "%s" "$icns_path"
}

install_cli() {
  local install_dir=""
  local target_path=""

  [[ -f "$SOURCE_SCRIPT" ]] || die "Cannot find ${APP_NAME} in ${SCRIPT_DIR}"

  remove_existing_cli
  install_dir="$(pick_cli_install_dir)"
  mkdir -p "$install_dir"
  cp "$SOURCE_SCRIPT" "$install_dir/$APP_NAME"
  chmod +x "$install_dir/$APP_NAME"
  target_path="$install_dir/$APP_NAME"

  printf "[ok] Installed command: %s\n" "$target_path"
  printf "[ok] Installed command version: %s\n" "$APP_VERSION"

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

  if [[ -f "$SOURCE_INFO_PLIST_TEMPLATE" ]]; then
    sed \
      -e "s|__APP_DISPLAY_NAME__|${APP_DISPLAY_NAME}|g" \
      -e "s|__APP_EXECUTABLE_NAME__|${APP_EXECUTABLE_NAME}|g" \
      -e "s|__APP_BUNDLE_ID__|${APP_BUNDLE_ID}|g" \
      -e "s|__APP_VERSION__|${APP_VERSION}|g" \
      -e "s|__COPYRIGHT_TEXT__|${COPYRIGHT_TEXT}|g" \
      "$SOURCE_INFO_PLIST_TEMPLATE" >"$plist_path"
    return 0
  fi

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
  <string>${APP_EXECUTABLE_NAME}</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon.icns</string>
  <key>CFBundleIconName</key>
  <string>AppIcon</string>
  <key>CFBundleIdentifier</key>
  <string>${APP_BUNDLE_ID}</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>${APP_DISPLAY_NAME}</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
  <key>LSApplicationCategoryType</key>
  <string>public.app-category.developer-tools</string>
  <key>CFBundleShortVersionString</key>
  <string>${APP_VERSION}</string>
  <key>CFBundleVersion</key>
  <string>${APP_VERSION}</string>
  <key>LSMinimumSystemVersion</key>
  <string>12.0</string>
  <key>NSAppleEventsUsageDescription</key>
  <string>GH Workflow Clean opens Terminal only when you explicitly choose the CLI fallback.</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSHumanReadableCopyright</key>
  <string>${COPYRIGHT_TEXT}</string>
</dict>
</plist>
EOF
}

copy_file_if_present() {
  local source_path="$1"
  local destination_path="$2"

  [[ -f "$source_path" ]] || return 0
  mkdir -p "$(dirname "$destination_path")"
  cp "$source_path" "$destination_path"
}

copy_help_resources() {
  local resources_dir="$1"
  local help_dir="$resources_dir/Help"
  local file=""

  mkdir -p "$help_dir"

  copy_file_if_present "$SOURCE_README" "$help_dir/README.md"
  copy_file_if_present "$SOURCE_SECURITY" "$help_dir/SECURITY.md"
  copy_file_if_present "$SOURCE_LICENSE" "$help_dir/LICENSE"
  copy_file_if_present "$SOURCE_TOS" "$help_dir/TERMS-OF-SERVICE.md"
  copy_file_if_present "$SOURCE_PROJECT_INFO" "$help_dir/PROJECT-INFO.md"

  if [[ -d "$SOURCE_HELP_DIR" ]]; then
    while IFS= read -r file; do
      [[ -n "$file" ]] || continue
      copy_file_if_present "$file" "$help_dir/$(basename "$file")"
    done < <(find "$SOURCE_HELP_DIR" -maxdepth 1 -type f -name '*.md' | sort)
  fi
}

build_gui_executable() {
  local target_path="$1"
  local target_arch=""

  require_command xcrun
  xcrun --find swiftc >/dev/null 2>&1 || die "Swift toolchain not found. Install Xcode or Command Line Tools to build the GUI app."

  [[ -f "$SOURCE_GUI" ]] || die "Cannot find GUI source at $SOURCE_GUI"
  target_arch="$(uname -m)"

  xcrun swiftc \
    -parse-as-library \
    -O \
    -target "${target_arch}-apple-macos12.0" \
    -framework SwiftUI \
    -framework AppKit \
    "$SOURCE_GUI" \
    -o "$target_path"

  chmod +x "$target_path"
}

install_app_bundle() {
  local app_dir=""
  local bundle_path=""
  local contents_dir=""
  local resources_dir=""
  local macos_dir=""
  local icon_icns=""
  local executable_path=""

  [[ -f "$SOURCE_SCRIPT" ]] || die "Cannot find ${APP_NAME} in ${SCRIPT_DIR}"
  [[ -f "$SOURCE_GUI" ]] || die "Cannot find GUI source in ${SCRIPT_DIR}"

  app_dir="$(pick_app_install_dir)"
  bundle_path="$app_dir/$APP_BUNDLE_NAME"
  contents_dir="$bundle_path/Contents"
  resources_dir="$contents_dir/Resources"
  macos_dir="$contents_dir/MacOS"

  mkdir -p "$app_dir"
  if [[ "$bundle_path" != */"$APP_BUNDLE_NAME" ]]; then
    die "Refusing to replace an unexpected app bundle path: $bundle_path"
  fi
  remove_existing_apps
  mkdir -p "$resources_dir" "$macos_dir"

  cp "$SOURCE_SCRIPT" "$resources_dir/$APP_NAME"
  chmod +x "$resources_dir/$APP_NAME"
  printf "%s\n" "$APP_VERSION" > "$resources_dir/VERSION"
  if [[ -f "$SOURCE_TOS" ]]; then
    cp "$SOURCE_TOS" "$resources_dir/TERMS-OF-SERVICE.md"
  fi
  copy_file_if_present "$SOURCE_LOGO_CARD" "$resources_dir/logo-card-square.png"
  copy_file_if_present "$SOURCE_LOGO_LOCKUP" "$resources_dir/logo-horizontal-lockup.png"
  copy_file_if_present "$SOURCE_HERO" "$resources_dir/hero-2560x1600.png"
  copy_help_resources "$resources_dir"

  icon_icns="$(render_icon_icns)"
  cp "$icon_icns" "$resources_dir/AppIcon.icns"

  write_info_plist "$contents_dir/Info.plist"
  executable_path="$macos_dir/$APP_EXECUTABLE_NAME"
  build_gui_executable "$executable_path"

  printf "[ok] Installed native macOS app: %s\n" "$bundle_path"
  printf "[ok] Installed app version: %s\n" "$APP_VERSION"
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
      --uninstall-only)
        UNINSTALL_ONLY=1
        INSTALL_CLI=0
        INSTALL_APP=0
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

  if [[ "$UNINSTALL_ONLY" -eq 0 && "$INSTALL_CLI" -eq 0 && "$INSTALL_APP" -eq 0 ]]; then
    die "Nothing selected to install"
  fi
}

main() {
  trap cleanup_temp_dirs EXIT
  parse_args "$@"
  require_macos

  printf "[info] Preparing %s %s\n" "$APP_DISPLAY_NAME" "$APP_VERSION"

  if [[ "$UNINSTALL_ONLY" -eq 1 ]]; then
    remove_existing_cli
    remove_existing_apps
    printf "[ok] Uninstall complete for %s\n" "$APP_DISPLAY_NAME"
    exit 0
  fi

  printf "[info] Uninstalling older copies before install\n"
  if [[ "$INSTALL_CLI" -eq 1 ]]; then
    remove_existing_cli
  fi
  if [[ "$INSTALL_APP" -eq 1 ]]; then
    remove_existing_apps
  fi

  if [[ "$INSTALL_APP" -eq 1 ]] && ! has_swift_toolchain; then
    if [[ "$INSTALL_CLI" -eq 1 ]]; then
      printf "[warn] Swift toolchain not found. Installing CLI only.\n"
      printf "[info] Install Xcode or Command Line Tools, then rerun with --app-only if you want the native GUI app.\n"
      INSTALL_APP=0
    else
      die "Swift toolchain not found. Install Xcode or Command Line Tools to build the native GUI app."
    fi
  fi

  if [[ "$INSTALL_CLI" -eq 1 ]]; then
    install_cli
  fi

  if [[ "$INSTALL_APP" -eq 1 ]]; then
    install_app_bundle
  fi

  printf "[info] Command help: %s --help\n" "$APP_NAME"
}

main "$@"
