# GH Workflow Clean macOS Project Info

## Product

- App name: `GH Workflow Clean`
- Executable: `GHWorkflowCleanGUI`
- Bundle ID: `com.waynetechlab.ghworkflowclean`
- Category: `public.app-category.developer-tools`
- Minimum macOS: `12.0`

## Brand Sources

- Canonical artwork: `assets/master-artwork.svg`
- App icon source: `assets/AppIcon.appiconset`
- Primary UI lockup: `assets/logos/logo-horizontal-lockup.png`
- Brand mark: `assets/logos/logo-card-square.png`

## Bundle Resources

The installer bundles:

- `gh-actions-cleanup`
- `AppIcon.icns`
- `logo-horizontal-lockup.png`
- `logo-card-square.png`
- `hero-2560x1600.png`
- Terms of Service
- Help markdown files from `docs/`
- repo-level support docs such as `README.md` and `SECURITY.md`

## Xcode Notes

This repo currently builds the native app with `swiftc` from `install-gh-actions-cleanup.sh`.

To move into a full Xcode app target later:

1. Use `macos/Info.plist.template` as the starting plist.
2. Import `macos/Assets.xcassets`.
3. Keep the bundle ID and versioning aligned with the CLI version.
4. Add bundled markdown help resources to the Copy Bundle Resources phase.
5. Preserve the app icon from the supplied `AppIcon.appiconset`.
