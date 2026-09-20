import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../core/app_scope.dart';
import '../flow/capture_flow.dart';
import '../models/app_settings.dart';
import '../models/annotation.dart';
import '../models/capture_mode.dart';
import '../ui/editor/editor_controller.dart';

/// Hooks that screens register so the debug server can drive them.
class DebugHooks {
  DebugHooks._();

  static void Function(Rect rect)? overlaySelect;
  static void Function(OverlayAction action)? overlayConfirm;
  static void Function(Offset point)? overlayHover;
  static EditorController? editor;
  static Future<void> Function(String action)? editorAction;
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
          await flow.start(mode);
          return 'ok stage=${flow.stage.name}';
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
          final n = parts.skip(1).map(double.parse).toList();
          if (n.length < 4) return 'usage: draw x1 y1 x2 y2 [x3 y3 ...]';
          editor.pointerDown(Offset(n[0], n[1]));
          for (var i = 2; i + 1 < n.length; i += 2) {
            editor.pointerMove(Offset(n[i], n[i + 1]));
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
        case 'home':
          await flow.showHome();
          return 'ok';
        case 'settings':
          await flow.openSettings();
          return 'ok';
        case 'hide':
          await flow.hideWindow();
          return 'ok';
        case 'close':
          await flow.closeEditor();
          return 'ok';
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
