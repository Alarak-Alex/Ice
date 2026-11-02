# Fork notes

Personal fork of [jordanbaird/Ice](https://github.com/jordanbaird/Ice), kept
building and usable on macOS 27 (Xcode 27.2 SDK). Upstream has not been
updated since 2025-09.

## What differs from upstream

- `Vendor/CompactSlider` — CompactSlider 1.2.1 sources vendored in place of the
  remote package. `ProminentCompactSliderStyle` applied `.opacity` to a
  `LinearGradient`, which is ambiguous against the macOS 27 SDK. The gradient is
  wrapped in `Rectangle().fill(...)`. Upgrading to CompactSlider 2.x instead
  would require API changes in `IceSlider.swift` and `AdvancedSettingsPane.swift`.
- `Scripts/install-local.sh` — Release build, signed with a fixed Apple
  Development certificate and installed to `/Applications/Ice.app`.

## Build and install

```bash
./Scripts/install-local.sh
```

Signing is pinned to `Apple Development: zlh153200@icloud.com (NL6JWT93LX)`,
team `2W8MYZ8HF8`. The designated requirement therefore names the certificate
subject instead of the binary hash, so the Accessibility and Screen Recording
grants survive rebuilds. Override with `SIGN_IDENTITY` / `SIGN_TEAM` if the
certificate is renewed.

The script also disables Sparkle's automatic updates, so an upstream release
cannot overwrite this build and reset the grants. Manual "Check for Updates"
still exists in the About pane — do not take an upstream update on macOS 27.

## Syncing with upstream

```bash
git fetch upstream
git merge upstream/main
```

Conflicts are expected only in `Ice.xcodeproj/project.pbxproj` if upstream
changes the CompactSlider dependency.
