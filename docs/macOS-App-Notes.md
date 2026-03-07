# macOS App Asset Notes

## App icon
Use the PNGs inside `assets/AppIcon.appiconset` for Xcode.
The repo also includes an Xcode-ready mirror at `macos/Assets.xcassets/AppIcon.appiconset`.

## Favicon
Use `assets/favicon/favicon.ico` and PNG variants for web.

## Installer
Use `assets/dmg-background.png` as the DMG background starter.
The native installer converts the shipped AppIcon set into `AppIcon.icns` for Finder and Dock.

## Current UI model

The native app now uses:

- `Control Center` as the primary cleanup workspace
- `Settings` as the dedicated GitHub host/account/session page
- a lower status bar for fast `Refresh`, `Login`, `Logout`, and `Settings` access
- a collapsible app menu for in-app pages and focus mode

This keeps the home workspace cleaner while preserving one-click access to auth controls.

## Social / website
Use:
- `assets/social/hero-2560x1600.png`
- `assets/social/social-banner-2400x900.png`

## Xcode metadata
Use `macos/Info.plist.template` and `macos/PROJECT-INFO.md` as the starting point for a formal Xcode target.
