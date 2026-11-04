<div align="center">
    <img src="Ice/Assets.xcassets/AppIcon.appiconset/icon_256x256.png" width=200 height=200>
    <h1>Ice</h1>
</div>

<p align="center">
    <strong>English</strong> · <a href="README.zh-CN.md">简体中文</a>
</p>

Ice is an open-source menu bar manager for macOS. This is the
[Alarak-Alex/Ice](https://github.com/Alarak-Alex/Ice) fork of
[jordanbaird/Ice](https://github.com/jordanbaird/Ice), with updated settings,
English and Simplified Chinese support, and a dedicated menu bar layout editor
for macOS 27.

![Banner](https://github.com/user-attachments/assets/4423085c-4e4b-4f3d-ad0f-90a217c03470)

[![Development branch](https://img.shields.io/badge/branch-main-brightgreen?style=flat-square)](https://github.com/Alarak-Alex/Ice/tree/main)
![Platform](https://img.shields.io/badge/platform-macOS-blue?style=flat-square)
![Requirements](https://img.shields.io/badge/requirements-macOS%2014%2B-fa4e49?style=flat-square)
[![Sponsor](https://img.shields.io/badge/Sponsor%20%E2%9D%A4%EF%B8%8F-8A2BE2?style=flat-square)](https://github.com/sponsors/jordanbaird)
[![Website](https://img.shields.io/badge/Website-015FBA?style=flat-square)](https://icemenubar.app)
[![License](https://img.shields.io/github/license/Alarak-Alex/Ice?style=flat-square)](LICENSE)

> [!NOTE]
> This fork is under development on `main`. The macOS 27 layout and
> visibility features are experimental; see the validation limits below.
> Upstream releases and the Homebrew cask install the original Ice, without
> this fork's changes.

## Changes in this fork

The English and Chinese READMEs describe the same development stage, updated
November 4, 2026.

- **Settings and navigation:** native AppKit search and sidebar selection,
  separate click targets, keyboard navigation, back/forward history, unified
  toolbar, semantic colors, and compact grouped settings.
- **Language selection:** choose System, English, or Simplified Chinese in
  General. The interface switches immediately and remembers the selection.
- **macOS 27 layout:** Accessibility discovery for MenuBarAgent-hosted items,
  three single-row sections, configuration profiles, automatic display
  assignment, and a draggable insertion marker for newly discovered apps.
  Editor clicks select items without opening their application menus.
- **Horizontal browsing:** use a horizontal trackpad gesture, a mouse wheel,
  the native scrollbar, or drag the strip's empty background to reach overflow
  items. Refresh preserves the browsing position; dragging an icon reorders it.
- **Palette spacers:** widths of 1–200 points with blank, text, or SF Symbol
  content, an editor with symbol validation, removal, and rollback when native
  registration fails. Native identities remain stable through content edits,
  and existing blank spacers remain compatible. Icon/spacer sorting uses the
  same native order, preserves hidden spacer anchors, and supports undo.
  The palette uses a shaded label and retains its complete text during dragging.
  Startup registration of a saved
  spacer was verified locally; physical palette drag/drop and placement still
  need runtime acceptance.
- **Hidden-item reveal on macOS 27:** blank-space clicks are routed to
  temporarily reveal the Hidden section, excluding Always Hidden. Separate
  recovery journals restore original visibility after image recapture or
  temporary reveal, including interrupted sessions. Physical blank-click
  behavior still needs runtime acceptance.
- **Native preference handling:** guarded order and visibility writes,
  stale-state detection, backups, file-access pickers, and undo.
- **Images and spacing:** cropped menu bar glyphs with app-icon fallback,
  recapture controls, and Default / Small / Tiny / None spacing. Logging out
  and back in applies spacing to all status items.
- **Performance and lifetime fixes:** tracking monitors observe the event queue
  without draining and reposting it, pending events are deduplicated, cancelled
  subscriptions release subscribers, and departed items leave the resident
  image cache while remaining available on disk. Unchanged background scans
  no longer invalidate the settings interface. Layout strips reuse app icons
  per process, load them only when displayed, release departed icons, and skip
  identical image/layout updates. Application-list notifications are coalesced,
  and discovery reuses process metadata instead of querying Launch Services
  every scan. Departed process metadata is released and restarted apps are
  reloaded. Closed Settings windows unmount their content and restore the
  selected pane when reopened. The macOS 27 editor skips unused background-color
  captures, and the legacy capture path now releases its temporary window-list
  buffer on every exit. The five-second discovery fallback remains active for
  delayed status items and automatic display profiles.
- **Build and startup:** launch-at-login error feedback, vendored CompactSlider
  compatibility fixes, and a signed local installation script.

Implementation details and reproducible regression commands are in
[FORK.md](FORK.md).

## Compatibility and validation

| Area | Current status |
| --- | --- |
| Minimum deployment target | macOS 14 |
| macOS 14–26 | Original layout/hiding engine retained; macOS 26 runtime and appearance have not been verified |
| macOS 27 | Separate layout editor and native order/visibility paths; signed Release build and installation verified locally |
| Local toolchain | Xcode 27.2 / macOS SDK 27.2 |
| Focused checks | Layout and language persistence, native preference transactions, profiles and undo, hidden-only reveal and recovery, mixed icon/spacer order and anchors, spacer content/lifetime, single-row views and horizontal input, image handling, navigation, spacing, and event-monitor cancellation |
| Runtime checks | Live language switching, sidebar selection, preference restoration, and reaching the right end of an overflowing strip verified; see limits below |

The original Ice Bar has not been ported to macOS 27's MenuBarAgent. Exact
Bartender visual parity, physical foreground dragging/panning, native spacer
placement, physical blank-space reveal, multiple-display behavior, and macOS 26
runtime parity remain unverified.

Performance samples no longer show the former tracking-loop hotspot. Local
sampling on November 4, 2026 with Settings closed averaged 0.66% CPU over
120 seconds, peaked at 8.3%, and ended at an 86.3 MiB physical footprint.
Desktop activity was not controlled, so these observations do not establish an
overall CPU reduction. A leak snapshot still reported 60 allocations / 3,008
bytes associated with AppKit toolbar accessibility actions. This stage does
**not** establish zero leaks or long-term memory stability.

## Install

### Build this fork

```sh
git clone --branch main https://github.com/Alarak-Alex/Ice.git
cd Ice
open Ice.xcodeproj
```

Select the Ice scheme, choose your signing team, and build with Xcode. To use
the local Release installation script, supply your own installed signing
identity and team:

```sh
SIGN_IDENTITY="Apple Development: Your Name (CERTIFICATE_ID)" \
SIGN_TEAM="YOUR_TEAM_ID" \
./Scripts/install-local.sh
```

The script installs `/Applications/Ice.app`, verifies its signature, and
disables automatic Sparkle updates to prevent replacement by an upstream
build. Keep the same bundle identifier and signing identity across rebuilds
to preserve existing permission grants.

Allow Accessibility in System Settings for menu bar management. Screen
Recording is used to capture item images. If native preference access is
unavailable, the layout editor provides file-access pickers.

### Original upstream distribution

Download `Ice.zip` from the
[upstream releases](https://github.com/jordanbaird/Ice/releases/latest) and
move the unzipped app into `Applications`, or install the upstream Homebrew cask:

```sh
brew install --cask jordanbaird-ice
```

These distributions do not include the fork changes described above.

## Original features and roadmap

The following list describes the inherited feature set. On macOS 27, use the
compatibility table above rather than assuming every legacy feature is ported.
Experimental profiles and spacers added by this fork are described separately.

### Menu bar item management

- [x] Hide menu bar items
- [x] "Always-hidden" menu bar section
- [x] Show hidden menu bar items when hovering over the menu bar
- [x] Show hidden menu bar items when an empty area in the menu bar is clicked
- [x] Show hidden menu bar items by scrolling or swiping in the menu bar
- [x] Automatically rehide menu bar items
- [x] Hide application menus when they overlap with shown menu bar items
- [x] Drag and drop interface to arrange individual menu bar items
- [x] Display hidden menu bar items in a separate bar (e.g. for MacBooks with the notch)
- [x] Search menu bar items
- [x] Menu bar item spacing (BETA)
- [ ] Menu bar item groups
- [ ] Show menu bar items when trigger conditions are met

### Menu bar appearance

- [x] Menu bar tint (solid and gradient)
- [x] Menu bar shadow
- [x] Menu bar border
- [x] Custom menu bar shapes (rounded and/or split)
- [ ] Remove background behind menu bar
- [ ] Rounded screen corners
- [ ] Different settings for light/dark mode

### Hotkeys

- [x] Toggle individual menu bar sections
- [x] Show the search panel
- [x] Enable/disable the Ice Bar
- [x] Show/hide section divider icons
- [x] Toggle application menus
- [ ] Enable/disable auto rehide
- [ ] Temporarily show individual menu bar items

### Other

- [x] Launch at login
- [x] Automatic updates
- [ ] Menu bar widgets

## Why does Ice only support macOS 14 and later?

Ice uses a number of system APIs that are available starting in macOS 14. As such, there are no plans to support earlier versions of macOS.

## Gallery

These screenshots show the original upstream interface.

#### Show hidden menu bar items below the menu bar

![Ice Bar](https://github.com/user-attachments/assets/f1429589-6186-4e1b-8aef-592219d49b9b)

#### Drag-and-drop interface to arrange menu bar items

![Menu Bar Layout](https://github.com/user-attachments/assets/095442ba-f2d0-4bb4-9632-91e26ef8d45b)

#### Customize the menu bar's appearance

![Menu Bar Appearance](https://github.com/user-attachments/assets/8c22c185-c3d2-49bb-971e-e1fc17df04b3)

#### Menu bar item search

![Menu Bar Item Search](https://github.com/user-attachments/assets/d1a7df3a-4989-4077-a0b1-8e7d5a1ba5b8)

#### Custom menu bar item spacing

![Menu Bar Item Spacing](https://github.com/user-attachments/assets/b196aa7e-184a-4d4c-b040-502f4aae40a6)

## License

Ice is available under the [GPL-3.0 license](LICENSE).

The original Ice project is by Jordan Baird and its contributors. This fork's
macOS 27 discovery and image work also references
[Icey](https://github.com/leonardovida/icey), revision
`0cb4b09cd401326adb19a15cdb4040235b70c924` (GPL-3.0). Bartender is a behavior
and visual reference; its code and assets are not included.

You can support the original author through
[GitHub Sponsors](https://github.com/sponsors/jordanbaird) or
[Buy Me a Coffee](https://www.buymeacoffee.com/jordanbaird).
