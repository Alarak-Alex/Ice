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
- Settings use a compact sidebar and grouped cards. English, Simplified Chinese,
  and the system language are selectable in General without restarting Ice.
  The sidebar uses `NSSearchField` and a native `NSTableView` source list with
  separate hit areas, system selection and keyboard navigation. The unified
  toolbar, semantic surface colors and compact section headers follow the
  installed macOS appearance.
- On macOS 27, Menu Bar Layout discovers items through Accessibility rather than
  individual WindowServer windows. Bartender-style configuration, display
  assignment, palette spacers, customization controls, and three fixed single-row
  section bars are rendered in SwiftUI/AppKit. Dragging writes native order,
  palette spacers persist in profiles, and clicking an item only selects it; it
  never opens the item's menu. A position must match one existing native
  preference key (including `module:*` system items) before it can be edited. Changes update only
  `TrailingItemPreferredPositions`, keep a private backup in
  `~/Library/Application Support/Ice/MenuBarLayout.before.plist`, verify readback,
  and reject stale writes. A file picker provides access when needed.
- Native drag sessions require an active app, key window and a physically pressed
  left mouse button. Background synthetic drags are rejected. An earlier
  background automation test left a native drag session active and interfered
  with Dock clicks; terminating Ice restored the Dock. No background drag tests
  should be repeated.
- Hidden and always-hidden moves use the existing Control Center approval
  records. A separate file picker provides access when reading that file fails.
  Order/visibility changes share one undo snapshot and stale-state preflight.
- Palette spacers own native NSStatusItems with stable autosave names and
  validated widths of 1–200 points. Profile selection registers visible spacers
  before restoring their saved positions. Registration failures restore metadata
  and the prior native hosts.
- The draggable “New Items here” marker saves a section and insertion anchor
  per profile. Existing applications keep their saved memberships, including
  stopped applications; newly discovered applications use the marker's section
  and native order. The existing item-manager timer drives discovery without
  disabling the editor during background scans. Moving the marker changes only
  the profile and supports undo.
- The macOS 27 spacing picker offers Default, Small, Tiny and None. It saves
  global values (unset, 8, 2 and 0 respectively), clears host overrides and
  preserves unrelated settings. It does not restart other applications; the UI
  explains that logging out applies spacing to every item.
- The modern layout captures the actual display menu-bar strip with
  ScreenCaptureKit and crops only items whose AX frame stayed still through the
  capture. Background removal follows Icey's `ItemImages27` rules at the
  revision below. Only cropped glyphs and their scale are cached in
  `~/Library/Application Support/Ice/MenuBarItemImages.v5`. Hidden-item recapture
  temporarily allows one existing application at a time, then restores its
  original visibility on success, failure or cancellation. A private journal
  restores interrupted captures at launch and normal exit.
  Photos with uncertain mixed white badges or wide colored metrics use the app
  icon fallback when their background cannot be removed safely.
- The legacy Ice Bar and hiding engine have not been ported to MenuBarAgent.
  macOS 14–26 retain the original section editor, with drag cancellation, view
  reuse, and image-cache publication fixes.
- Launch at login reports registration errors and offers System Settings when
  approval is required.

The macOS 27 AX discovery approach was checked against
[Icey](https://github.com/leonardovida/icey), revision
`0cb4b09cd401326adb19a15cdb4040235b70c924` (GPL-3.0), and Bartender 7's packaged
platform documentation. No Bartender code or assets are included.

## Focused regression checks

```bash
swiftc -parse-as-library \
  Ice/UI/LayoutBar/LayoutBarContainer.swift \
  Ice/Utilities/AppLanguage.swift \
  Ice/MenuBar/MenuBarPositionStore.swift \
  Ice/MenuBar/MenuBarVisibilityStore.swift \
  Ice/MenuBar/MenuBarLayoutProfile.swift \
  Ice/MenuBar/MenuBarItemIdentityResolver.swift \
  Scripts/LayoutBarRegression.swift -o /tmp/ice-layout-regression
/tmp/ice-layout-regression
```

These checks use the production container, language model and preference writer
with isolated items and temporary preference files. They cover stable view
identity, refresh during drag, removal, language persistence, native order,
backup, preservation of unrelated preferences, stale-write rejection, and undo.

Local validation on 2026-11-02 also confirmed a signed Release build, live
English/Chinese switching, sidebar navigation, launch-at-login on/off, live
native position changes, and exact restoration of original position values by
undo. Multi-display behavior and a complete mouse-driven drag remain unverified.

Additional isolated checks:

```bash
swiftc -parse-as-library \
  Ice/MenuBar/ModernMenuBarLayoutModel.swift \
  Ice/MenuBar/ModernMenuBarImageStore.swift \
  Ice/MenuBar/ModernMenuBarItemImages.swift \
  Ice/MenuBar/ModernMenuBarDiscovery.swift \
  Ice/MenuBar/MenuBarItemIdentityResolver.swift \
  Ice/MenuBar/MenuBarLayoutProfile.swift \
  Ice/MenuBar/MenuBarSpacerManager.swift \
  Ice/MenuBar/MenuBarPositionStore.swift \
  Ice/MenuBar/MenuBarVisibilityStore.swift \
  Ice/Utilities/AppLanguage.swift \
  Scripts/ModernLayoutModelRegression.swift -o /tmp/ice-modern-model-regression
/tmp/ice-modern-model-regression

swiftc -parse-as-library \
  Ice/MenuBar/ModernMenuBarItemImages.swift \
  Scripts/ModernItemImagesRegression.swift -o /tmp/ice-modern-images-regression
/tmp/ice-modern-images-regression

swiftc -parse-as-library \
  Ice/UI/LayoutBar/ModernMenuBarCollection.swift \
  Ice/MenuBar/ModernMenuBarDiscovery.swift \
  Ice/MenuBar/MenuBarItemIdentityResolver.swift \
  Ice/Utilities/AppLanguage.swift \
  Scripts/ModernLayoutViewRegression.swift -o /tmp/ice-modern-view-regression
/tmp/ice-modern-view-regression

swiftc -parse-as-library \
  Ice/MenuBar/Spacing/MenuBarLayoutSpacing.swift \
  Ice/Utilities/AppLanguage.swift \
  Scripts/MenuBarLayoutSpacingRegression.swift -o /tmp/ice-spacing-regression
/tmp/ice-spacing-regression

swiftc -parse-as-library \
  Ice/Settings/SettingsView.swift \
  Ice/Settings/SettingsSidebar.swift \
  Ice/Main/Navigation/AppNavigationState.swift \
  Ice/Main/Navigation/NavigationIdentifiers/NavigationIdentifier.swift \
  Ice/Main/Navigation/NavigationIdentifiers/SettingsNavigationIdentifier.swift \
  Ice/UI/ViewModifiers/ReadWindow.swift \
  Ice/UI/ViewModifiers/RemoveSidebarToggle.swift \
  Ice/Utilities/AppLanguage.swift \
  Scripts/SettingsNavigationRegression.swift -o /tmp/ice-settings-navigation-regression
/tmp/ice-settings-navigation-regression
```

The model fixtures cover both reorder directions, empty/nonempty cross-section
moves, shown-state restoration between profiles, registration timeout rollback,
stale spacer drops, native spacer position restoration, width validation, profile
copy/delete undo, insertion-marker migration and placement, automatic new-app
ordering/visibility, stale visibility undo and temporary recapture visibility,
including interrupted-capture recovery. The image fixture checks Retina and
secondary-display crops, movement rejection, gradient removal, colored
highlights, empty images and faint marks. The view fixture checks single-row
geometry, icon fallback, hit testing, stable views and background drag rejection.
The spacing fixture uses a separate random preferences domain; it does not
change system spacing.

The navigation fixture loads the production sidebar with placeholder detail
panes. It checks all six native table rows, first-mouse acceptance, isolated
search and row hit areas, pane selection, navigation history and search filtering
without unexpected navigation. On 2026-11-03 the user confirmed that physical
sidebar clicks work after this rewrite. The latest installed style also passed
a General-to-Menu-Bar accessibility navigation check and an App Icons switch
on/off check, restoring the original preference afterward.

The current build uses the locally installed Xcode 27.2 / macOS SDK 27.2.
The source-list selection, 20pt sidebar icons, unified transparent titlebar,
smaller page headers and semantic content panels were visually checked on
macOS 27. macOS 26 appearance has not been checked on a running system.

On 2026-11-03, actual Bartender screenshots and its four-option spacing menu were
recorded. UI matching remains incomplete: unavailable status images still fall
back to app icons, and exact pixel parity has not been demonstrated. The insertion
marker and new-app placement pass isolated model and native-view fixtures.
Foreground mouse dragging, native spacer placement,
hidden-spacer reveal behavior and multiple displays still require runtime proof.

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
