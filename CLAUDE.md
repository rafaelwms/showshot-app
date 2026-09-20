# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Show Shot — a Flutter desktop screenshot/annotation app for macOS, Windows and Linux (Flameshot/Lightshot-style: freeze the screen, pick an area/window/full display, annotate, copy or save). Lives in the menu bar/tray, responds to global hotkeys. See [README.md](README.md) for the full user-facing feature list and platform build steps — this file is for working *on* the code, not using the app.

**Cross-machine note:** this project gets worked on from multiple machines (macOS, Windows 11, Ubuntu 26.04 x64/arm64). This file is the shared source of truth for status/next-steps across those sessions — keep the "Current status" section below updated as work lands, so a Claude session opened on a different OS picks up where the last one left off instead of re-discovering it.

## Commands

```bash
flutter pub get                          # install deps (run after any pubspec.yaml change)
flutter analyze                          # static analysis — keep this at "No issues found!" before wrapping up
dart format lib                          # format (CI-equivalent: dart format --set-exit-if-changed lib)
flutter run -d macos|windows|linux       # run in debug (starts the debug automation server, see below)
flutter build macos|windows|linux --release
```

There is no automated test suite yet (`test/` is empty — the app is verified via `flutter analyze` plus the debug automation server below). If you add tests, `flutter test` / `flutter test test/some_test.dart` is standard.

### Debug automation server (no mouse/keyboard needed)

Debug builds (`kDebugMode`) open a line-oriented TCP server on `127.0.0.1:47391` (`lib/debug/debug_server.dart`) that drives the whole capture → overlay → editor flow programmatically — essential when you can't simulate real clicks (no Accessibility permission on macOS, and Wayland blocks synthetic input entirely on Linux):

```bash
printf 'capture area\n' | nc 127.0.0.1 47391
printf 'select 100 100 600 400\nconfirm edit\n' | nc 127.0.0.1 47391
printf 'tool arrow\ndraw 50 50 300 200\ntext 100 300 hi\naction save\n' | nc 127.0.0.1 47391
```

Commands: `capture area|window|fullScreen`, `select x y w h`, `hover x y`, `windows` (lists detected windows), `confirm edit|copy|save|cancel`, `tool <name>`, `draw x1 y1 x2 y2 [...]`, `text x y <text>`, `color AARRGGBB`, `style <width> <opacity> [fill]`, `undo`, `action save|saveAs|copy|discard`, `setting ask|copyAfterSave|magnifier|jpg|language true|false|<value>`, `home`, `settings`, `hide`, `close`, `stage`, `quit`.

Hot-reload a running `flutter run` session from another shell with `kill -USR1 <pid>` (find the `dartvm ... flutter_tools.snapshot` process), rather than restarting — the debug server survives reloads.

## Architecture

**One OS window, three roles.** There's a single native window that switches between *home* (Material UI), *overlay* (borderless, frozen-screen selection) and *editor* (annotation canvas) roles — `lib/flow/capture_flow.dart`'s `CaptureFlow` orchestrates the transitions (`window_manager` for resize/show/hide, `Navigator.pushNamedAndRemoveUntil` for the route swap). Routes: `/`, `/settings`, `/overlay`, `/editor`, and a `/blank` route used briefly during transitions specifically to drop widget references to a `ui.Image` *before* it gets disposed (skipping that step throws "Cannot clone a disposed image").

**Native bridge, one per platform, same Dart-side contract.** `lib/services/native_bridge.dart` talks to a `shoshot/native` method channel implemented independently per platform — there is no shared native code:

| Platform | File | Capture | Window list | Overlay |
| --- | --- | --- | --- | --- |
| macOS | `macos/Runner/ShoShotNative.swift` | ScreenCaptureKit (`SCScreenshotManager`, macOS 14+) → `CGDisplayCreateImage` fallback | `CGWindowListCopyWindowInfo` | borderless `NSWindow` at `.screenSaver` level |
| Windows | `windows/runner/shoshot_native.cpp` | GDI `BitBlt` per monitor (per-monitor DPI) | `EnumWindows` + DWM (skips cloaked/tool windows) | `WS_POPUP` + `WS_EX_TOPMOST` sized to the monitor rect |
| Linux | `linux/runner/shoshot_native.cc` | X11 `XGetImage`; Wayland has **no native capture path yet** (see below) | `_NET_CLIENT_LIST_STACKING`, X11 only | `gtk_window_fullscreen_on_monitor` |

`DisplayInfo` (`lib/models/display_info.dart`) normalizes the coordinate systems: macOS reports points (`globalIsPhysical: false`), Windows/Linux report physical pixels (`globalIsPhysical: true`) — `NativeBridge.getDisplays()` reads `platformInfo()` once and converts accordingly. Never assume one scale everywhere.

**Capture flow:** `CaptureService.captureUnderCursor()` freezes the display under the *cursor* (not the focused display) into a `CaptureSession` (`lib/models/capture_session.dart`), which holds the raw `ui.Image` plus the window list already translated into that display's local logical coordinates (`CaptureSession._localizeWindows`). The overlay (`lib/ui/overlay/overlay_screen.dart`) never touches native APIs directly — it only reads the frozen `CaptureSession`.

**Overlay hit-testing gotcha (already fixed once, don't reintroduce):** the overlay's full-screen `Listener` (drag-to-select) must **not** be an ancestor of the floating action bar / hint / magnifier. A `Listener` receives every raw pointer event under its subtree regardless of which descendant widget consumed it — so if the action bar is a child, clicking a toolbar button also re-triggers `_onDown` on the Listener and looks like "the selection just expanded". They must be siblings inside the same `Stack` so the Stack's hit-test short-circuits at the topmost hit child. See the `build()` method's structure/comment in `overlay_screen.dart`.

**Window-picker mode vs. area mode** (`CaptureMode.window` vs `.area`) share the same `OverlayScreen`, differentiated by mode checks in the pointer handlers: window mode never builds a free-drag rectangle (any mouse-down+up resolves to whichever window is under the cursor at release, regardless of incidental drag distance — real clicks always have a few pixels of jitter, so gating on "did it move" breaks window-picking). Window mode also swaps the system cursor for a custom camera-icon badge and drops the magnifier/crosshair (`_isWindowPickPhase` in `overlay_screen.dart`), and the hovered window is "spotlighted" (undimmed, like a live selection preview) in `overlay_painter.dart`.

**Editor** (`lib/ui/editor/`): `EditorController` (a `ChangeNotifier`, not a widget) owns the annotation list, undo/redo stack, active tool/style and viewport transform; `EditorCanvasPainter` just renders `controller.paintable`. Annotations (`lib/models/annotation.dart`) are a small sealed-ish hierarchy (`ShapeAnnotation`, `StrokeAnnotation`, `TextAnnotation`, `NumberAnnotation`) each implementing `paint`/`hitTest`/`translated`/`withHandle` — add new tools here, not by branching on `ToolType` elsewhere. Coordinates throughout the editor are *image pixel* space, not logical/window space (`EditorController.pixelRatio` converts UI slider values like stroke width to pixels).

**Services are plain classes wired by hand** in `lib/main.dart` and exposed via `AppScope` (a thin `InheritedWidget`, `lib/core/app_scope.dart`) — there's no DI framework. `SettingsService` and `CaptureFlow` are `ChangeNotifier`s persisted/observed the normal Flutter way; widgets read them via `AppScope.of(context)` + `ListenableBuilder`.

**i18n gotcha:** `Strings.of(context)` (`lib/core/strings.dart`) returns a `const` PT/EN instance — cheap, but that means a screen that captures it *outside* a `ListenableBuilder` reactive to `services.settings` will show stale text after an in-page language change (this happened once in `SettingsScreen` — fixed by moving the whole screen inside one `ListenableBuilder`). Any screen with a live language-dependent control needs the same pattern.

## Current status (update this as work lands)

Built and iterated on **macOS** — capture (area/window/full-screen), overlay, editor (all tools), copy/save, tray, hotkeys, settings, launch-at-login all manually verified there via the debug server. `flutter analyze` is clean.

**Windows and Linux native code has never run on real hardware.** It was written against the official Win32/GDI/DWM and GTK/X11 APIs and syntax-checked in Docker (mingw-w64 + real Flutter Windows headers for `shoshot_native.cpp`; GTK3/X11 dev headers for `shoshot_native.cc`, including a `-Werror` pass) — but never actually built or run. Expect real build errors on first attempt; fix them there, not here.

**Linux/Wayland has no native capture, window list, or global hotkeys at all today** — `CaptureService` falls back to shelling out to `gnome-screenshot`/`spectacle`/`grim`/`scrot` (whichever is on `$PATH`) for a screenshot and returns an empty window list; `hotkey_manager`'s X11 backend (`keybinder-3.0`) doesn't work under Wayland either. This is a real gap, not a nice-to-have: the primary Linux target is Ubuntu 26.04 (GNOME/Wayland by default, both x64 and arm64), so this needs proper portal-based support, not just a CLI fallback:

- **Screenshot:** use the `org.freedesktop.portal.Screenshot` D-Bus interface (via `xdg-desktop-portal` + `xdg-desktop-portal-gnome` on Ubuntu) instead of shelling out. It shows a native permission/picker dialog per call (no persistent grant for plain screenshots, unlike ScreenCast) — factor that into the UX (can't freeze-then-ask; may need to ask first, or accept the portal's own picker instead of our custom overlay for the initial capture).
- **Window enumeration:** Wayland deliberately has no global "list all windows" API for security reasons — there is no drop-in replacement for `_NET_CLIENT_LIST_STACKING`. The realistic path is to lean on the portal's own window/screen picker UI for "Window" mode under Wayland (i.e., a different, portal-driven UX from the X11 custom-overlay picker, not a like-for-like replacement), or use the ScreenCast portal's source picker if `capture window` needs to keep working.
- **Global hotkeys:** the modern answer is the `org.freedesktop.portal.GlobalShortcuts` portal (needs a recent `xdg-desktop-portal`; verify what Ubuntu 26.04 ships). GNOME also has its own custom-keybinding path via `gsettings`/`org.gnome.settings-daemon` as a fallback if the portal isn't available.
- Detect Wayland vs X11 at runtime the same way `shoshot_native.cc` already does (`GDK_IS_WAYLAND_DISPLAY`) and branch the whole capture/hotkey/window strategy on it — X11 (still selectable at login on Ubuntu) should keep using the existing, working native path.
- This needs to be built and iterated *on* an actual Ubuntu Wayland session — portal APIs are version- and compositor-sensitive enough that guessing from outside is unreliable.

**Branding:** display name is "Show Shot" (with a space); bundle/application id `com.rafaelwms.showshot`; site `showshot.rafaelwms.com`. The Dart package name (`shoshot`), repo folder (`app-shoshot`), method channel (`shoshot/native`), and class names (`ShoShotNative`, `ShoShotApp`) were deliberately left as internal technical identifiers — a full rename would touch 30+ files across 3 native build systems; flag it to the user before doing that, don't do it silently.
