import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:window_manager/window_manager.dart';

import '../core/app_scope.dart';
import '../flow/capture_flow.dart';
import '../models/app_settings.dart';
import '../models/annotation.dart';
import '../models/capture_mode.dart';
import '../models/capture_session.dart';
import '../models/display_info.dart';
import '../services/export_service.dart';
import '../ui/editor/editor_controller.dart';

/// Hooks that screens register so the debug server can drive them.
class DebugHooks {
  DebugHooks._();

  static void Function(Rect rect)? overlaySelect;
  static void Function(OverlayAction action)? overlayConfirm;
  static void Function(Offset point)? overlayHover;
  static EditorController? editor;
  static Future<void> Function(String action)? editorAction;
  static VoidCallback? settingsBack;

  /// What `main()` decided about the launch (login item? hidden?).
  static String launchSummary = 'n/a';
}

/// Debug-only automation: a line-oriented TCP server on localhost that lets
/// developers trigger the capture flow without global shortcuts or a mouse.
///
/// Compiled out of release builds (`kDebugMode`). Example:
///
///     printf 'capture area\n' | nc 127.0.0.1 47391
///     printf 'select 100 100 600 400\nconfirm edit\n' | nc 127.0.0.1 47391
///     printf 'tool arrow\ndraw 50 50 300 200\n' | nc 127.0.0.1 47391
class DebugCommandServer {
  DebugCommandServer._();

  static const port = 47391;
  static ServerSocket? _server;

  static Future<void> start(AppServices services) async {
    if (!kDebugMode || _server != null) return;
    try {
      _server = await ServerSocket.bind(InternetAddress.loopbackIPv4, port);
    } catch (error) {
      debugPrint('Debug server unavailable: $error');
      return;
    }
    debugPrint('Debug command server listening on 127.0.0.1:$port');
    _server!.listen((socket) {
      socket
          .cast<List<int>>()
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
            (line) async {
              final reply = await _handle(services, line.trim());
              try {
                socket.add(utf8.encode('$reply\n'));
              } catch (_) {}
            },
            onDone: () => socket.close(),
            onError: (_) => socket.close(),
          );
    });
  }

  static Future<String> _handle(AppServices services, String line) async {
    final parts = line
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return 'empty';
    final flow = services.flow;
    try {
      switch (parts.first) {
        case 'capture':
          final mode = CaptureMode.values.firstWhere(
            (m) =>
                m.name.toLowerCase() ==
                    (parts.elementAtOrNull(1) ?? 'area').toLowerCase() ||
                (parts.elementAtOrNull(1) == 'screen' &&
                    m == CaptureMode.fullScreen),
            orElse: () => CaptureMode.area,
          );
          // `capture area fromHome` mimics clicking a card on the Home window.
          await flow.start(mode, fromHome: parts.contains('fromHome'));
          return 'ok stage=${flow.stage.name}';
        case 'demo':
          // Opens the editor on a generated 3840x2160 image: no screen
          // capture, so it works without the screen recording permission.
          await flow.debugOpenEditor(
            CaptureSession(
              mode: CaptureMode.fullScreen,
              display: const DisplayInfo(
                id: 0,
                bounds: Rect.fromLTWH(0, 0, 1920, 1080),
                scale: 2,
                isPrimary: true,
                name: 'demo',
                globalPixelRatio: 1,
              ),
              image: await _demoImage(),
              windows: const [],
            ),
          );
          return 'ok stage=${flow.stage.name}';
        case 'render':
          // Flattens the annotations exactly as Copy/Save would and writes the
          // PNG to ~/Pictures (the one place both the sandboxed app and a
          // shell can reach); returns its path. Delete it afterwards.
          final editor = DebugHooks.editor;
          if (editor == null) return 'no editor';
          final image = await ExportService.render(
            editor.image,
            editor.exportable,
          );
          final png = await image.toByteData(format: ImageByteFormat.png);
          image.dispose();
          final home =
              Platform.environment['HOME'] ?? Directory.systemTemp.path;
          final file = File('$home/Pictures/shoshot_debug_render.png');
          await file.writeAsBytes(png!.buffer.asUint8List());
          return file.path;
        case 'select':
          final n = parts.skip(1).map(double.parse).toList();
          if (n.length != 4) return 'usage: select x y w h';
          DebugHooks.overlaySelect?.call(Rect.fromLTWH(n[0], n[1], n[2], n[3]));
          return DebugHooks.overlaySelect == null ? 'no overlay' : 'ok';
        case 'windows':
          final session = flow.session;
          if (session == null) return 'no session';
          final list = session.windows
              .take(15)
              .map(
                (w) =>
                    '${w.app}|${w.title}|'
                    '${w.bounds.left.round()},${w.bounds.top.round()},'
                    '${w.bounds.width.round()}x${w.bounds.height.round()}',
              )
              .join(';');
          return 'count=${session.windows.length} $list';
        case 'hover':
          final n = parts.skip(1).map(double.parse).toList();
          if (n.length != 2) return 'usage: hover x y';
          DebugHooks.overlayHover?.call(Offset(n[0], n[1]));
          return DebugHooks.overlayHover == null ? 'no overlay' : 'ok';
        case 'confirm':
          final action = OverlayAction.values.firstWhere(
            (a) => a.name == (parts.elementAtOrNull(1) ?? 'edit'),
            orElse: () => OverlayAction.edit,
          );
          DebugHooks.overlayConfirm?.call(action);
          return DebugHooks.overlayConfirm == null ? 'no overlay' : 'ok';
        case 'tool':
          final editor = DebugHooks.editor;
          if (editor == null) return 'no editor';
          final tool = ToolType.values.firstWhere(
            (t) => t.name == parts.elementAtOrNull(1),
            orElse: () => ToolType.arrow,
          );
          editor.setTool(tool);
          return 'ok tool=${tool.name}';
        case 'draw':
          final editor = DebugHooks.editor;
          if (editor == null) return 'no editor';
          // `draw shift x1 y1 ...` holds Shift during the moves.
          final shift = parts.elementAtOrNull(1) == 'shift';
          final n = parts.skip(shift ? 2 : 1).map(double.parse).toList();
          if (n.length < 4) return 'usage: draw [shift] x1 y1 x2 y2 ...';
          editor.pointerDown(Offset(n[0], n[1]));
          for (var i = 2; i + 1 < n.length; i += 2) {
            editor.pointerMove(Offset(n[i], n[i + 1]), shift: shift);
          }
          editor.pointerUp(Offset(n[n.length - 2], n[n.length - 1]));
          return 'ok annotations=${editor.annotations.length}';
        case 'text':
          final editor = DebugHooks.editor;
          if (editor == null) return 'no editor';
          final x = double.parse(parts[1]);
          final y = double.parse(parts[2]);
          editor.setTool(ToolType.text);
          editor.pointerDown(Offset(x, y));
          editor.updateEditingText(parts.skip(3).join(' '));
          editor.commitTextEditing();
          return 'ok annotations=${editor.annotations.length}';
        case 'typing':
          // Like `text`, but leaves the inline editor open (see `commit`).
          final editor = DebugHooks.editor;
          if (editor == null) return 'no editor';
          editor.setTool(ToolType.text);
          editor.pointerDown(
            Offset(double.parse(parts[1]), double.parse(parts[2])),
          );
          editor.updateEditingText(parts.skip(3).join(' '));
          return 'ok editing=${editor.editingText != null}';
        case 'commit':
          DebugHooks.editor?.commitTextEditing();
          return 'ok';
        case 'color':
          final editor = DebugHooks.editor;
          if (editor == null) return 'no editor';
          editor.setStyle(
            editor.style.copyWith(color: Color(int.parse(parts[1], radix: 16))),
          );
          return 'ok';
        case 'style':
          final editor = DebugHooks.editor;
          if (editor == null) return 'no editor';
          editor.setStyle(
            editor.style.copyWith(
              strokeWidth: double.tryParse(parts.elementAtOrNull(1) ?? ''),
              opacity: double.tryParse(parts.elementAtOrNull(2) ?? ''),
              filled: parts.elementAtOrNull(3) == 'fill',
            ),
          );
          return 'ok';
        case 'smooth':
          // `smooth 0..1`: curve smoothing for the pen/marker (and selection).
          final editor = DebugHooks.editor;
          if (editor == null) return 'no editor';
          editor.setStyle(
            editor.style.copyWith(smoothing: double.parse(parts[1])),
          );
          return 'ok';
        case 'action':
          final action = DebugHooks.editorAction;
          if (action == null) return 'no editor';
          await action(parts.elementAtOrNull(1) ?? 'save');
          return 'ok';
        case 'setting':
          final key = parts.elementAtOrNull(1);
          final raw = parts.elementAtOrNull(2) ?? '';
          final value = raw == 'true';
          await services.settings.update(
            (s) => switch (key) {
              'ask' => s.copyWith(askWhereToSave: value),
              'copyAfterSave' => s.copyWith(copyAfterSave: value),
              'magnifier' => s.copyWith(showMagnifier: value),
              'jpg' => s.copyWith(
                saveFormat: value ? ImageFormat.jpg : ImageFormat.png,
              ),
              'language' => s.copyWith(
                language: AppLanguage.values.firstWhere(
                  (l) => l.name.toLowerCase() == raw.toLowerCase(),
                  orElse: () => s.language,
                ),
              ),
              _ => s,
            },
          );
          return 'ok';
        case 'undo':
          DebugHooks.editor?.undo();
          return 'ok';
        case 'notify':
          // `notify copied|saved|saveFailed|textCopied|noTextFound`: sends
          // that message as an OS notification; replies whether it was shown.
          final kind = FlowMessageKind.values.firstWhere(
            (k) => k.name == parts.elementAtOrNull(1),
            orElse: () => FlowMessageKind.copied,
          );
          final shown = await flow.notify(
            FlowMessage(
              kind,
              path: '/Users/demo/Pictures/ShowShot/capture.png',
            ),
          );
          return 'delivered=$shown';
        case 'trayaction':
          // `trayaction area|window|fullScreen|text|openApp|menu` sets the
          // left-click action; `trayaction click` simulates the left click.
          final arg = parts.elementAtOrNull(1);
          if (arg == 'click') {
            services.tray.debugLeftClick();
            return 'ok stage=${flow.stage.name}';
          }
          final action = TrayAction.values.firstWhere(
            (a) => a.name == arg,
            orElse: () => TrayAction.area,
          );
          await services.settings.update(
            (s) => s.copyWith(trayLeftClick: action),
          );
          return 'ok action=${services.settings.settings.trayLeftClick.name}';
        case 'editorwindow':
          // `editorwindow normal|maximized|fullScreen`: how the editor opens.
          final mode = EditorWindowMode.values.firstWhere(
            (m) => m.name == parts.elementAtOrNull(1),
            orElse: () => EditorWindowMode.maximized,
          );
          await services.settings.update((s) => s.copyWith(editorWindow: mode));
          return 'ok editorWindow=${services.settings.settings.editorWindow.name}';
        case 'winstate':
          final size = await windowManager.getSize();
          return 'visible=${await windowManager.isVisible()} '
              'maximized=${await windowManager.isMaximized()} '
              'fullScreen=${await windowManager.isFullScreen()} '
              'size=${size.width.round()}x${size.height.round()}';
        case 'banner':
          // `banner on|off`: Home's screen-recording permission banner.
          flow.debugPermissionMissing = parts.elementAtOrNull(1) != 'off';
          return 'ok';
        case 'home':
          await flow.showHome();
          return 'ok';
        case 'settingsBack':
          DebugHooks.settingsBack?.call();
          return DebugHooks.settingsBack == null ? 'no settings screen' : 'ok';
        case 'settings':
          await flow.openSettings();
          return 'ok';
        case 'hide':
          await flow.hideWindow();
          return 'ok';
        case 'close':
          await flow.closeEditor();
          return 'ok';
        case 'dump':
          final editor = DebugHooks.editor;
          if (editor == null) return 'no editor';
          String o(Offset p) =>
              '(${p.dx.toStringAsFixed(1)},${p.dy.toStringAsFixed(1)})';
          final lines = <String>[
            for (final a in editor.annotations)
              '${a.id}:${a.runtimeType} rot=${a.rotation.toStringAsFixed(3)} '
                  'bounds=${a.bounds.left.toStringAsFixed(1)},${a.bounds.top.toStringAsFixed(1)},'
                  '${a.bounds.width.toStringAsFixed(1)}x${a.bounds.height.toStringAsFixed(1)}'
                  '${a is TextAnnotation ? ' font=${a.style.fontSize.toStringAsFixed(1)} pos=${o(a.position)}' : ''}'
                  '${a is ShapeAnnotation ? ' start=${o(a.start)} end=${o(a.end)}' : ''}',
          ];
          final sel = editor.selected;
          if (sel != null) {
            lines.add(
              'selected=${sel.id} handles=${sel.handles.map(o).join(',')} '
              'rotateHandle=${o(sel.rotationHandle(editor.rotateHandleDistance))} '
              'panelFont=${editor.style.fontSize.toStringAsFixed(1)}',
            );
          }
          return lines.join('\n');
        case 'launch':
          return DebugHooks.launchSummary;
        case 'visible':
          return 'visible=${await windowManager.isVisible()}';
        case 'stage':
          return 'stage=${flow.stage.name} session=${flow.session != null} document=${flow.document != null}';
        case 'quit':
          await flow.quit();
          return 'bye';
        default:
          return 'unknown command';
      }
    } catch (error, stack) {
      debugPrint('Debug command failed: $error\n$stack');
      return 'error: $error';
    }
  }
}

/// A busy 3840x2160 backdrop (gradient, grid, paragraphs of text) so blur,
/// rotation and hit-testing are easy to judge by eye.
Future<Image> _demoImage() async {
  const w = 3840.0, h = 2160.0;
  final recorder = PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    const Rect.fromLTWH(0, 0, w, h),
    Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xFF203A43), Color(0xFF2C5364), Color(0xFF5B86A0)],
      ).createShader(const Rect.fromLTWH(0, 0, w, h)),
  );
  final grid = Paint()
    ..color = const Color(0x22FFFFFF)
    ..strokeWidth = 2;
  for (var x = 0.0; x <= w; x += 120) {
    canvas.drawLine(Offset(x, 0), Offset(x, h), grid);
  }
  for (var y = 0.0; y <= h; y += 120) {
    canvas.drawLine(Offset(0, y), Offset(w, y), grid);
  }
  final text = TextPainter(
    text: TextSpan(
      text: List.filled(
        14,
        'The quick brown fox jumps over the lazy dog 0123456789\n',
      ).join(),
      style: const TextStyle(color: Color(0xFFFFFFFF), fontSize: 46),
    ),
    textDirection: TextDirection.ltr,
  )..layout(maxWidth: w);
  text.paint(canvas, const Offset(2100, 820));
  text.paint(canvas, const Offset(160, 160));
  final picture = recorder.endRecording();
  final image = await picture.toImage(w.toInt(), h.toInt());
  picture.dispose();
  return image;
}
