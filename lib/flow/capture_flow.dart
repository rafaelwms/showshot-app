import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../models/capture_mode.dart';
import '../models/capture_session.dart';
import '../services/capture_service.dart';
import '../services/export_service.dart';
import '../services/native_bridge.dart';
import '../services/settings_service.dart';

enum FlowStage { idle, capturing, overlay, editor }

enum OverlayAction { edit, copy, save, cancel }

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

/// Notification shown to the user after a flow completes.
class FlowMessage {
  const FlowMessage(this.kind, {this.path});
  final FlowMessageKind kind;
  final String? path;
}

enum FlowMessageKind { copied, saved, saveFailed, captureFailed }

/// Orchestrates capture → overlay → editor and the window transitions between
/// them. There is a single OS window that changes role along the way.
class CaptureFlow extends ChangeNotifier with WindowListener {
  CaptureFlow({
    required this.settings,
    required this.native,
    required this.capture,
    required this.export,
  }) {
    windowManager.addListener(this);
  }

  static const homeSize = Size(960, 640);
  static const minSize = Size(760, 520);

  final SettingsService settings;
  final NativeBridge native;
  final CaptureService capture;
  final ExportService export;

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

  Future<void> start(CaptureMode mode) async {
    if (_busy || _stage == FlowStage.overlay) return;
    if (_stage == FlowStage.editor) {
      // A new capture replaces the one being edited.
      await closeEditor();
    }
    _busy = true;
    _setStage(FlowStage.capturing);
    try {
      final wasVisible = await windowManager.isVisible();
      _returnToHome = wasVisible;
      if (wasVisible) {
        await windowManager.hide();
        // Give the compositor a moment to remove our window from the screen.
        await Future<void>.delayed(const Duration(milliseconds: 220));
      }

      final info = await native.platformInfo();
      if (info.needsScreenPermission && !await native.hasScreenAccess()) {
        await native.requestScreenAccess();
        _permissionMissing = true;
        _setStage(FlowStage.idle);
        await showHome();
        return;
      }
      _permissionMissing = false;

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
      _lastMessage = const FlowMessage(FlowMessageKind.captureFailed);
      _setStage(FlowStage.idle);
      await showHome();
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<void> completeOverlay(OverlayResult result) async {
    debugPrint('DIAG: completeOverlay entered action=${result.action} stage=$_stage session=${_session != null}');
    final session = _session;
    if (session == null || _stage != FlowStage.overlay) {
      debugPrint('DIAG: completeOverlay early-return guard');
      return;
    }
    _busy = true;
    try {
      // Hide before restoring the window style so the user never sees the
      // overlay collapse into a regular window.
      debugPrint('DIAG: before windowManager.hide()');
      await windowManager.hide();
      debugPrint('DIAG: after windowManager.hide(), before _showBlank()');
      await _showBlank();
      debugPrint('DIAG: after _showBlank(), before native.exitOverlay()');
      final size = _editorWindowSize(session.image, session);
      await native.exitOverlay(width: size.width, height: size.height);
      debugPrint('DIAG: after native.exitOverlay()');

      final rect = result.rect ?? session.logicalRect;
      switch (result.action) {
        case OverlayAction.cancel:
          _disposeSession();
          _setStage(FlowStage.idle);
          debugPrint('DIAG: before _finish() [cancel]');
          await _finish();
          debugPrint('DIAG: after _finish() [cancel]');
        case OverlayAction.edit:
          final image = await session.crop(rect);
          await _openEditor(image, session);
        case OverlayAction.copy:
          final image = await session.crop(rect);
          final ok = await export.copyToClipboard(image);
          image.dispose();
          _disposeSession();
          _lastMessage = ok ? const FlowMessage(FlowMessageKind.copied) : null;
          _setStage(FlowStage.idle);
          await _finish();
        case OverlayAction.save:
          final image = await session.crop(rect);
          if (settings.settings.askWhereToSave) {
            // The dialog needs a visible parent window: open the editor and
            // let it trigger the save panel.
            await _openEditor(image, session, autoSave: true);
          } else {
            await _saveDirect(image);
            image.dispose();
            _disposeSession();
            _setStage(FlowStage.idle);
            await _finish();
          }
      }
    } catch (error, stack) {
      debugPrint('Overlay completion failed: $error\n$stack');
      _disposeSession();
      _lastMessage = const FlowMessage(FlowMessageKind.captureFailed);
      _setStage(FlowStage.idle);
      await showHome();
    } finally {
      debugPrint('DIAG: completeOverlay finally -> setting _busy=false + notifyListeners()');
      _busy = false;
      notifyListeners();
      debugPrint('DIAG: completeOverlay finally done, _busy=$_busy');
    }
  }

  Future<void> _saveDirect(ui.Image image) async {
    final path = await export.save(image, settings.settings);
    if (path == null) {
      _lastMessage = const FlowMessage(FlowMessageKind.saveFailed);
      return;
    }
    await settings.addRecentFile(path);
    if (settings.settings.copyAfterSave) await export.copyToClipboard(image);
    _lastMessage = FlowMessage(FlowMessageKind.saved, path: path);
  }

  /// Called by the editor once the user copied/saved/discarded.
  Future<void> closeEditor({FlowMessage? message}) async {
    if (_stage != FlowStage.editor) return;
    await windowManager.hide();
    await _showBlank();
    _document?.image.dispose();
    _document = null;
    if (message != null) _lastMessage = message;
    _setStage(FlowStage.idle);
    await _finish();
  }

  Future<void> showHome({String route = '/'}) async {
    debugPrint('DIAG: showHome entered route=$route stage=$_stage busy=$_busy');
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
    debugPrint('DIAG: showHome mid, before isVisible check, busy=$_busy');
    if (!await windowManager.isVisible()) {
      await windowManager.setSize(homeSize);
      await windowManager.center();
    }
    await windowManager.show();
    await windowManager.focus();
    _returnToHome = false;
    notifyListeners();
    debugPrint('DIAG: showHome done, busy=$_busy stage=$_stage');
  }

  Future<void> openSettings() => showHome(route: '/settings');

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
    await windowManager.show();
    await windowManager.focus();
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
