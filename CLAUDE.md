# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**WhisperFoot** (package name: FootPedalOptionKey) is a macOS menu bar utility that transforms a USB foot pedal into an Option (⌥) modifier key. It intercepts the pedal's native "b" keystroke via a CGEvent tap and injects Option key modifier events instead, enabling hands-free push-to-talk, Option-click, and other modifier workflows.

## Scripts

All build/install/uninstall actions are run via StreamDeck scripts that open a Terminal window and show progress:

```bash
# Build from source, install to /Applications, start the service
./scripts/streamdeck/build-and-install.sh

# Stop service, remove app, LaunchAgent, logs, config, and Accessibility permission
./scripts/streamdeck/stop-and-uninstall.sh
```

Utility scripts for non-default pedal hardware:

```bash
# Find USB pedal Vendor/Product IDs
./scripts/discover-pedal.sh

# Save custom pedal IDs to ~/.config/footpedal/config.json
./scripts/configure-pedal.sh
```

There are no tests. The project has no external dependencies — only macOS system frameworks.

## Architecture

The entire application lives in a single file: `sources/FootPedalOptionKey/main.swift`. It uses Swift Package Manager (swift-tools-version:5.7, macOS 12+). Build artifacts go in `output/`.

### Key Components (all in main.swift)

- **`PedalConfig`** — Static configuration for USB Vendor/Product IDs. Defaults to iKKEGOL FS2007U1SW (`0x3553`/`0xB001`). Loads overrides from `~/.config/footpedal/config.json`.

- **`injectOptionKey(keyDown:)`** — Posts CGEvent `flagsChanged` events for Left Option (keycode 58) to `cghidEventTap`.

- **`FootPedalManager`** — Core class managing the full lifecycle:
  - **IOKit HID**: Matches pedal by Vendor/Product ID, monitors connect/disconnect, captures input values across 4 HID usage pages (KeyboardOrKeypad, Button, Consumer, GenericDesktop).
  - **CGEvent tap**: Session-level tap that blocks the pedal's "b" keystroke (keycode 11) and inserts `.maskAlternate` into all events while pedal is held.
  - **Debouncing**: 100ms debounce via `mach_absolute_time` to handle pedals that expose dual HID interfaces.
  - **Delegate pattern**: `PedalStatusDelegate` protocol notifies AppDelegate of state changes.

- **`AppDelegate`** — NSStatusBar menu bar app (LSUIElement, no dock icon). Shows custom footprint icons in the menu bar with visual feedback on press. Menu provides connection status, enable/disable toggle, and quit.

### Icons

Source images live in `images/` and all generated sizes live in `images/icons/` with one subfolder per variant:

- **`footprint-off`** (`images/icons/footprint-off/`) — White footprint on transparent background, used as the menu bar icon in its default (released) state; set as a template image so macOS renders it appropriately in both light and dark mode.
- **`footprint-on`** (`images/icons/footprint-on/`) — Orange footprint on transparent background, used as the menu bar icon when the pedal is pressed; displayed as non-template so the orange color shows through as visual feedback.
- **`footprint-icon`** (`images/icons/footprint-icon/`) — Orange footprint on dark navy background, used as the app icon (`AppIcon.icns`) that appears in System Settings, Accessibility permissions, and Finder.

Each subfolder contains Apple-compliant icon sizes pre-generated from the original 360x360 source: standard app icon sizes (16x16 through 512x512, with @2x retina variants), menu bar sizes (18x18, 18x18@2x) where applicable, and a full `.iconset` for `footprint-icon` used to build `AppIcon.icns`. The `resources/` folder contains the build-ready copies: `footprint-off.png`/`@2x` and `footprint-on.png`/`@2x` for the menu bar, and `AppIcon.icns` for the app bundle.

### Build Pipeline

`build-and-install.sh` compiles via `swift build -c release`, then assembles the app bundle in `output/WhisperFoot.app`: copies binary (renamed from `FootPedalOptionKey` to `WhisperFoot`), copies `resources/` (PNG icons, ICNS), generates `Info.plist`, embeds git version, and code signs with the `Terrance-MacGregor-Local-CodeSign` certificate. It then copies the bundle to `/Applications/`, installs the LaunchAgent, and starts the service.

### Deployment

The app runs as a LaunchAgent (`com.periscoped.footpedal`) configured in `launchagents/com.periscoped.footpedal.plist`. It auto-starts at login, restarts on crash, and logs to `/tmp/footpedal.log` and `/tmp/footpedal.error.log`.

## Important Notes

- The app requires **Accessibility permissions** (System Settings → Privacy & Security → Accessibility) for the event tap and event injection to work. Permissions must be re-granted after each reinstall.
- The device is opened with `kIOHIDOptionsTypeSeizeDevice` to prevent the native "b" keystroke from leaking through.
- The event tap blocks keycode 11 ("b") unconditionally when a pedal is connected, even when disabled — this prevents phantom keystrokes.
- Bundle ID: `com.periscoped.footpedal`
