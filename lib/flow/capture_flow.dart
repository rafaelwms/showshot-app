import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:window_manager/window_manager.dart';

import '../models/app_settings.dart';
import '../models/capture_mode.dart';
import '../models/capture_session.dart';
import '../models/flow_message.dart';
import '../services/capture_service.dart';
import '../services/export_service.dart';
import '../services/native_bridge.dart';
import '../services/notification_service.dart';
import '../services/ocr_service.dart';
import '../services/settings_service.dart';

export '../models/flow_message.dart';

enum FlowStage { idle, capturing, overlay, editor }

enum OverlayAction { edit, copy, save, extractText, cancel }

class OverlayResult {
  const OverlayResult(this.action, [this.rect]);
  final OverlayAction action;
  final Rect? rect;
}

/// What the editor works on.
class EditorDocument {
  EditorDocument({
    required this.image,
    required this.pixelRatio,
    this.autoSave = false,
  });

  /// Cropped screenshot in device pixels.
  final ui.Image image;

  /// Device pixels per logical pixel of the source display (used to pick
  /// sensible default stroke widths).
  final double pixelRatio;

  /// Open the save dialog as soon as the editor appears.
  final bool autoSave;
}

/// Orchestrates capture → overlay → editor and the window transitions between
/// them. There is a single OS window that changes role along the way.
class CaptureFlow extends ChangeNotifier with WindowListener {
  CaptureFlow({
    required this.settings,
    required this.native,
    required this.capture,
    required this.export,
    required this.ocr,
    required this.notifications,
  }) {
    windowManager.addListener(this);
  }

  static const homeSize = Size(960, 640);
  static const minSize = Size(760, 520);

  final SettingsService settings;
  final NativeBridge native;
  final CaptureService capture;
  final ExportService export;
  final OcrService ocr;
  final NotificationService notifications;

  final navigatorKey = GlobalKey<NavigatorState>();
  final messengerKey = GlobalKey<ScaffoldMessengerState>();

  FlowStage _stage = FlowStage.idle;
  CaptureSession? _session;
  EditorDocument? _document;
  bool _busy = false;
  bool _returnToHome = false;
  bool _permissionMissing = false;
  FlowMessage? _lastMessage;

  FlowStage get stage => _stage;
  CaptureSession? get session => _session;
  EditorDocument? get document => _document;
  bool get busy => _busy;
  bool get permissionMissing => _permissionMissing;

  /// Debug automation: shows/hides the "screen recording permission" banner on
  /// Home without going through the OS permission prompt.
  set debugPermissionMissing(bool value) {
    _permissionMissing = value;
    notifyListeners();
  }

  FlowMessage? get lastMessage => _lastMessage;

  NavigatorState? get _navigator => navigatorKey.currentState;

  /// Waits for the next frame, but never longer than [timeout]: a hidden
  /// window may not produce frames on every platform.
  Future<void> _settle([Duration timeout = const Duration(milliseconds: 300)]) {
    return Future.any([
      WidgetsBinding.instance.endOfFrame,
      Future<void>.delayed(timeout),
    ]);
  }

  /// Replaces the current screen with an empty one so that no widget keeps a
  /// handle to an image we are about to dispose.
  Future<void> _showBlank() async {
    _navigator?.pushNamedAndRemoveUntil('/blank', (_) => false);
    await _settle();
  }

  // ---------------------------------------------------------------------------
  // Entry points
  // ---------------------------------------------------------------------------

  /// [fromHome] is true only when the capture was started by clicking a card
  /// on the Home window itself; hotkeys and the tray menu leave it false.
  /// Whether to bring Home back afterwards is decided by that, not by
  /// whether the window happens to be visible: a Home window left open
  /// behind other windows (or on another Space) is still "visible" to the OS,
  /// and would otherwise pop back up after every hotkey capture.
  Future<void> start(CaptureMode mode, {bool fromHome = false}) async {
    if (_busy || _stage == FlowStage.overlay) return;
    // Set before closing the editor below: closeEditor() ends in _finish(),
    // which reads it, and it should follow *this* capture's origin rather
    // than a stale value from whichever capture opened that editor.
    _returnToHome = fromHome;
    if (_stage == FlowStage.editor) {
      // A new capture replaces the one being edited.
      await closeEditor();
    }
    _busy = true;
    _setStage(FlowStage.capturing);
    try {
      final info = await native.platformInfo();
      if (info.needsScreenPermission && !await native.hasScreenAccess()) {
        if (Platform.isLinux) {
          // GNOME shows its one-time screenshot access dialog only for the
          // *focused* app, so ask with our window up — before hiding it —
          // and carry on with the capture once the user allowed it.
          await showHome();
          if (!await native.requestScreenAccess()) {
            _permissionMissing = true;
            _setStage(FlowStage.idle);
            return;
          }
        } else {
          // macOS: the grant only takes effect after a restart.
          await native.requestScreenAccess();
          _permissionMissing = true;
          _setStage(FlowStage.idle);
          await showHome();
          return;
        }
      }
      _permissionMissing = false;

      if (await windowManager.isVisible()) {
        await windowManager.hide();
        // Give the compositor a moment to remove our window from the screen.
        await Future<void>.delayed(const Duration(milliseconds: 220));
      }

      final session = await capture.captureUnderCursor(mode);
      _session = session;

      if (mode == CaptureMode.fullScreen) {
        await _openEditor(session.image.clone(), session);
        return;
      }

      _setStage(FlowStage.overlay);
      _navigator?.pushNamedAndRemoveUntil('/overlay', (_) => false);
      await _settle();
      await native.enterOverlay(session.display.id);
      await windowManager.focus();
    } catch (error, stack) {
      debugPrint('Capture failed: $error\n$stack');
      _session?.dispose();
      _session = null;
      // Access revoked since we last checked (e.g. in GNOME Settings)?
      final info = await native.platformInfo();
      _permissionMissing =
          info.needsScreenPermission && !await native.hasScreenAccess();
      _lastMessage = const FlowMessage(FlowMessageKind.captureFailed);
      _setStage(FlowStage.idle);
      await showHome();
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<void> completeOverlay(OverlayResult result) async {
    final session = _session;
    if (session == null || _stage != FlowStage.overlay) return;
    _busy = true;
    try {
      final rect = result.rect ?? session.logicalRect;
      final saveDirect =
          result.action == OverlayAction.save &&
          !settings.settings.askWhereToSave;

      // Clipboard writes happen *before* hiding the overlay: Wayland only
      // accepts them from the focused window, and drops them silently
      // otherwise (harmless ordering everywhere else).
      ui.Image? image;
      FlowMessage? copyResult;
      switch (result.action) {
        case OverlayAction.copy:
          image = await session.crop(rect);
          copyResult = await export.copyToClipboard(image)
              ? const FlowMessage(FlowMessageKind.copied)
              : null;
        case OverlayAction.extractText:
          copyResult = await _extractText(await session.crop(rect));
        case OverlayAction.save when saveDirect:
          image = await session.crop(rect);
          if (settings.settings.copyAfterSave) {
            await export.copyToClipboard(image);
          }
        case OverlayAction.save || OverlayAction.edit || OverlayAction.cancel:
          break;
      }

      // Hide before restoring the window style so the user never sees the
      // overlay collapse into a regular window.
      await windowManager.hide();
      await _showBlank();
      final size = _editorWindowSize(session.image, session);
      await native.exitOverlay(width: size.width, height: size.height);

      switch (result.action) {
        case OverlayAction.cancel:
          _disposeSession();
          _setStage(FlowStage.idle);
          await _finish();
        case OverlayAction.edit:
          await _openEditor(await session.crop(rect), session);
        case OverlayAction.copy || OverlayAction.extractText:
          image?.dispose();
          _disposeSession();
          if (copyResult != null) {
            await _report(copyResult);
          } else {
            _lastMessage = null;
          }
          _setStage(FlowStage.idle);
          await _finish();
        case OverlayAction.save when saveDirect:
          await _saveDirect(image!, copied: true);
          image.dispose();
          _disposeSession();
          _setStage(FlowStage.idle);
          await _finish();
        case OverlayAction.save:
          // The dialog needs a visible parent window: open the editor and
          // let it trigger the save panel.
          await _openEditor(await session.crop(rect), session, autoSave: true);
      }
    } catch (error, stack) {
      debugPrint('Overlay completion failed: $error\n$stack');
      _disposeSession();
      _lastMessage = const FlowMessage(FlowMessageKind.captureFailed);
      _setStage(FlowStage.idle);
      await showHome();
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// [copied]: the caller already handled "copy after save" (it has to
  /// happen while a window is focused, see [completeOverlay]).
  Future<void> _saveDirect(ui.Image image, {bool copied = false}) async {
    final path = await export.save(image, settings.settings);
    if (path == null) {
      await _report(const FlowMessage(FlowMessageKind.saveFailed));
      return;
    }
    await settings.addRecentFile(path);
    if (!copied && settings.settings.copyAfterSave) {
      await export.copyToClipboard(image);
    }
    await _report(FlowMessage(FlowMessageKind.saved, path: path));
  }

  /// Recognizes text in [image] and copies it to the clipboard. Disposes
  /// [image]; returns the outcome for the caller to report.
  Future<FlowMessage> _extractText(ui.Image image) async {
    final png = await ExportService.encodePng(image);
    image.dispose();
    final text = await ocr.recognize(png);
    if (text == null) return const FlowMessage(FlowMessageKind.noTextFound);
    await Clipboard.setData(ClipboardData(text: text));
    return const FlowMessage(FlowMessageKind.textCopied);
  }

  /// Called by the editor once the user copied/saved/discarded.
  Future<void> closeEditor({FlowMessage? message}) async {
    if (_stage != FlowStage.editor) return;
    await _leaveEditorWindowMode();
    await windowManager.hide();
    await _showBlank();
    _document?.image.dispose();
    _document = null;
    if (message != null) _lastMessage = message;
    _setStage(FlowStage.idle);
    await _finish();
  }

  Future<void> showHome({String route = '/'}) async {
    if (_stage == FlowStage.overlay) return;
    if (_stage == FlowStage.editor) {
      // Keep the editor; just bring the window up.
      await windowManager.show();
      await windowManager.focus();
      return;
    }
    final navigator = _navigator;
    if (navigator != null) {
      navigator.pushNamedAndRemoveUntil(route, (_) => false);
      await _settle();
    }
    if (!await windowManager.isVisible()) {
      // The editor may have left the window maximized (GNOME auto-maximizes
      // windows created close to the screen size).
      if (await windowManager.isMaximized()) await windowManager.unmaximize();
      await windowManager.setSize(homeSize);
      await windowManager.center();
    }
    await windowManager.show();
    await windowManager.focus();
    _returnToHome = false;
    notifyListeners();
  }

  Future<void> openSettings() => showHome(route: '/settings');

  /// The permission banner's "request" button. On Linux the answer applies
  /// right away (no restart), so the banner can go as soon as it's granted.
  Future<void> requestScreenAccess() async {
    if (!Platform.isLinux) {
      await native.requestScreenAccess();
      return;
    }
    if (await native.requestScreenAccess(reset: true)) {
      _permissionMissing = false;
      notifyListeners();
    }
  }

  Future<void> hideWindow() async {
    if (_stage == FlowStage.overlay) return;
    await windowManager.hide();
    _returnToHome = false;
  }

  Future<void> quit() async {
    await windowManager.setPreventClose(false);
    await windowManager.destroy();
    exit(0);
  }

  /// Shows [message] as an OS notification when possible (see
  /// [NotificationService]); false means the caller should show it in-app.
  Future<bool> notify(FlowMessage message) => notifications.show(message);

  /// Reports a finished flow's outcome: as an OS notification when possible,
  /// otherwise left in [lastMessage] for Home's toast. (Capture failures stay
  /// in-app — they bring Home up, so the message has somewhere to show.)
  Future<void> _report(FlowMessage message) async {
    final delivered =
        message.kind != FlowMessageKind.captureFailed && await notify(message);
    _lastMessage = delivered ? null : message;
  }

  void consumeMessage() {
    _lastMessage = null;
  }

  // ---------------------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------------------

  Future<void> _openEditor(
    ui.Image image,
    CaptureSession session, {
    bool autoSave = false,
  }) async {
    final size = _editorWindowSize(image, session);
    _document = EditorDocument(
      image: image,
      pixelRatio: session.pixelRatio,
      autoSave: autoSave,
    );
    _disposeSession();
    _setStage(FlowStage.editor);
    _navigator?.pushNamedAndRemoveUntil('/editor', (_) => false);
    await windowManager.setSize(size);
    await windowManager.center();
    await _settle();
    // OS full screen isn't offered on Windows; treat it as maximized there.
    var mode = settings.settings.editorWindow;
    if (mode == EditorWindowMode.fullScreen && Platform.isWindows) {
      mode = EditorWindowMode.maximized;
    }
    // Maximize before showing so the window never flashes at the small size.
    if (mode == EditorWindowMode.maximized) await windowManager.maximize();
    await windowManager.show();
    await windowManager.focus();
    if (mode == EditorWindowMode.fullScreen) {
      await windowManager.setFullScreen(true);
    }
  }

  /// Undoes [_openEditor]'s maximize / full screen so the window goes back to
  /// a normal frame (Home and the overlay size it themselves).
  Future<void> _leaveEditorWindowMode() async {
    if (await windowManager.isFullScreen()) {
      // macOS animates the exit, and hiding the window mid-animation gets
      // undone when it finishes: wait for the real "left full screen" event.
      final left = _leftFullScreen = Completer<void>();
      await windowManager.setFullScreen(false);
      await left.future.timeout(const Duration(seconds: 3), onTimeout: () {});
      _leftFullScreen = null;
    }
    if (await windowManager.isMaximized()) await windowManager.unmaximize();
  }

  Completer<void>? _leftFullScreen;

  @override
  void onWindowLeaveFullScreen() {
    final completer = _leftFullScreen;
    if (completer != null && !completer.isCompleted) completer.complete();
  }

  /// Debug automation: opens the editor on a synthetic [session] instead of a
  /// real screen capture, so the editor can be driven without the OS screen
  /// recording permission (see the `demo` command in `debug_server.dart`).
  Future<void> debugOpenEditor(CaptureSession session) async {
    _session = session;
    await _openEditor(session.image.clone(), session);
  }

  Size _editorWindowSize(ui.Image image, CaptureSession session) {
    final logical = Size(
      image.width / session.pixelRatio,
      image.height / session.pixelRatio,
    );
    final screen = session.display.logicalSize;
    final maxWidth = (screen.width * 0.92).clamp(
      minSize.width,
      double.infinity,
    );
    final maxHeight = (screen.height * 0.9).clamp(
      minSize.height,
      double.infinity,
    );
    final width = (logical.width + 200).clamp(homeSize.width, maxWidth);
    final height = (logical.height + 220).clamp(homeSize.height, maxHeight);
    return Size(width.roundToDouble(), height.roundToDouble());
  }

  Future<void> _finish() async {
    if (_returnToHome || _lastMessage?.kind == FlowMessageKind.captureFailed) {
      await showHome();
    } else {
      _navigator?.pushNamedAndRemoveUntil('/', (_) => false);
    }
    notifyListeners();
  }

  void _disposeSession() {
    _session?.dispose();
    _session = null;
  }

  void _setStage(FlowStage stage) {
    _stage = stage;
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // WindowListener
  // ---------------------------------------------------------------------------

  @override
  void onWindowClose() {
    if (_stage == FlowStage.editor) {
      closeEditor();
    } else if (_stage == FlowStage.overlay) {
      completeOverlay(const OverlayResult(OverlayAction.cancel));
    } else {
      hideWindow();
    }
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }
}
