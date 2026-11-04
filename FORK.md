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
- Overflowing layout bars support native horizontal scrolling, ordinary mouse
  wheels and dragging the empty background. Icon dragging remains reserved for
  reordering; browsing preserves the scroll offset through refreshes.
- Tracking-mode event observation peeks at matching events without draining and
  reposting AppKit's event queue. Pending events are delivered once; event
  subscriptions release their subscribers on cancellation.
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
  and the prior native hosts. Content can be blank, trimmed text, or an SF Symbol.
  The editor validates symbol names and preserves current placement when editing
  an older snapshot. Blank content has an explicit image; native items keep
  stable button/accessibility identifiers. Unchanged content reuses its image.
  New native hosts need not already have a saved MenuBarAgent order entry:
  only verified, visible Ice-owned hosts may initialize missing slots, using
  guarded writes that preserve existing positions. Native-host initialization,
  hidden-to-visible moves and undo were checked with temporary preferences.
  Saved-spacer startup registration was verified locally; physical palette
  drag/drop and placement remain unverified.
- Blank-menu-space clicks on macOS 27 route to the modern hidden-section
  reveal path. Only Hidden applications and spacers are revealed; Always Hidden
  stays concealed. The original approvals are journaled separately from image
  capture and restored on hide, permanent layout changes, launch, or normal exit.
  Clicks use a fresh conservative AX hit test, while mouse movement uses cached
  item frames. This behavior passes model fixtures but physical blank-click
  acceptance remains unverified.
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
  The resident image cache retains only currently discovered items; images of
  stopped applications remain on disk and load again when needed.
- Background scans publish only changed entries, images, order or approvals.
  Native layout views skip identical updates and load app icons only when
  displayed, reusing them per process and releasing departed items. Discovery
  caches metadata by retained application-object identity, evicts departed
  applications and reloads new process objects, including PID reuse. Workspace
  notifications compare object identity without querying dynamic PID properties
  and coalesce bursts. The macOS 27 editor skips the legacy background-color
  capture because its bars have their own background. Closed Settings windows
  unmount their native content instead of retaining SwiftUI scroll prefetching;
  reopening restores the selected pane. The five-second discovery fallback
  remains active for delayed status-item registration, automatic display
  profiles, and current menu-item hit-test frames.
- The legacy composite capture path releases its manually allocated window-list
  buffer on success and failure. Previously, every capture leaked that buffer.
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
  Ice/UI/Views/SettingsPaneHeader.swift \
  Ice/MenuBar/ModernMenuBarDiscovery.swift \
  Ice/MenuBar/MenuBarLayoutProfile.swift \
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

swiftc -parse-as-library \
  Ice/Events/EventMonitors/LocalEventMonitor.swift \
  Ice/Events/EventMonitors/GlobalEventMonitor.swift \
  Ice/Events/EventMonitors/UniversalEventMonitor.swift \
  Ice/Events/EventMonitors/RunLoopLocalEventMonitor.swift \
  Scripts/EventMonitorRegression.swift -o /tmp/ice-event-monitor-regression
/tmp/ice-event-monitor-regression
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

The horizontal browsing fixture loads the production scroll view with 30 items
in a narrow viewport. It checks empty-space panning in both directions, mouse
wheel and trackpad deltas, edge clamping, access to the final item, refresh-offset
preservation and selection without starting a native drag session. The model
fixture also checks that departed item images are released while current images
stay reusable and the disk cache remains intact. Event-monitor checks use only
the test process's queue: observation preserves event order without repeated
delivery, cancellation stops delivery, and all four publishers release
cancelled subscribers.

Incremental-refresh checks first reproduced redundant publications from unchanged
background scans. They now require zero publications while still observing
external native-order and approval changes. Native-view checks cover unchanged
updates, on-demand app-icon loading, reuse between items from one process,
fresh glyphs, editing-state changes, PID reuse, missing-icon retry and release
of departed process icons while the strip remains alive.
Application-metadata fixtures count actual property reads: unchanged application
objects must add no queries; departed objects must be released; restarted objects
with reused PIDs and initially unavailable bundle identifiers must load fresh
metadata.

The palette preview checks that a native drag image retains the complete label
and its text, rather than stretching only the glyph over the label's frame.
Optional light/dark English/Chinese appearance snapshots can be generated with
`ICE_LAYOUT_APPEARANCE_SNAPSHOT_DIR=/tmp/ice-layout-appearance /tmp/ice-modern-view-regression`.
The layout page uses a 181-point title panel and 64-point icon measured from the
saved Bartender reference; other settings pages keep their compact header.
Color comparisons convert the reference display profile to sRGB first.
These component renders do not prove full-window pixel parity.

The model fixture additionally checks blank/text/symbol native content,
legacy spacer decoding, invalid-symbol rejection, unchanged-image reuse,
stable identity on resize/content changes and manager removal, content persistence
across profile copy/switch/undo, stale editor anchors, Hidden-only temporary reveal,
Always Hidden exclusion, repeated show requests, unchanged profiles/order,
exact approval restoration, quit/startup recovery, and restoring temporary
visibility before permanent layout edits.

Mixed-order fixtures exhaust every icon/spacer source and destination with one
or two spacers, including adjacent spacer chains and end insertion. They compare
the editor against native position records, preserve unrelated native keys and
visibility, and verify undo restores both positions and anchors. Additional
fixtures cover externally authored order, unregistered hidden spacer targets,
and moving an anchor out of its section. These checks use temporary stores and
preferences domains; they do not rearrange the user's menu bar.

The navigation fixture loads the production sidebar with placeholder detail
panes. It checks all six native table rows, first-mouse acceptance, isolated
search and row hit areas, pane selection, navigation history and search filtering
without unexpected navigation. It also verifies three close/reopen cycles:
closed content is unmounted and reopening restores the selected pane.
On 2026-11-03 the user confirmed that physical
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
The native horizontal scrollbar reached its right end in the installed app.
The later palette drag attempt through background automation did not produce an
accepted drop.
An earlier temporary profile fixture was restored before launch and supplies no
native-registration proof. A later saved-spacer fixture was launched in the
installed Ice, and MenuBarAgent registered its stable native position key.
The temporary spacer was removed and the original profile data restored
byte-for-byte. This proves startup registration, not physical palette drop or
placement. The user's saved pre-validation order and visibility were restored
and checked again after restarting Ice.
The user subsequently arranged the menu bar manually. That newer state is the
baseline for further verification; older restoration snapshots must not replace
it.

Performance samples taken on 2026-11-03 no longer contained the old
`RunLoopLocalEventMonitor` queue-reposting hotspot. The additional performance
pass used signed Release builds on a Mac mini with macOS 27.2. Sampling uses
`top -l <intervals + 1> -s 2 -pid <pid>` and excludes the first cumulative row.

| Sample | Duration | Mean CPU | Peak CPU | Physical footprint |
| --- | --- | --- | --- | --- |
| Original layout page, 2026-11-03 | 30 s | 3.42% | 14.1% | 94.3 MiB |
| Final build, Settings closed, 2026-11-04 | 120 s | 0.66% | 8.3% | 86.3 MiB |

These rows have different UI workloads, process lifetimes and uncontrolled
desktop interaction; they do not establish a controlled overall CPU reduction
or long-term memory savings. Earlier intermediate builds fluctuated between
0.49% and 5.49% mean CPU, so their lowest sample is not an optimization claim.
The final build retains the five-second discovery fallback: skipping it when
Settings is closed would miss display changes and delayed item registration.

The final `leaks -quiet <pid>` snapshot reported 60 allocations / 3,008 bytes
associated with AppKit's `NSToolbarItemViewer` accessibility custom actions.
The separate raw window-list buffer leak found during source review is fixed
with unconditional deallocation. Cache-release and closed-window lifetime
regressions pass, but the snapshot does not establish zero leaks or resolve
ownership of the remaining toolbar allocations.

After the final installation and measurements on 2026-11-04, all 50 native
positions and 53 approval records matched the fresh pre-install files
byte-for-byte. Raw layout profiles and the active profile also matched, and no
temporary visibility journals remained. This preserved the user's current
manually authored layout.

The public stage summary is synchronized in [README.md](README.md) and
[README.zh-CN.md](README.zh-CN.md).

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
