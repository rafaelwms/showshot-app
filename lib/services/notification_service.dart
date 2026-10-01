import '../core/strings.dart';
import '../models/flow_message.dart';
import 'native_bridge.dart';
import 'settings_service.dart';

/// Reports the outcome of a capture (copied, saved, text recognized…) as an
/// operating-system notification, so it's visible even while Show Shot's
/// window is hidden in the menu bar / tray.
class NotificationService {
  NotificationService({required this.settings, required this.native});

  final SettingsService settings;
  final NativeBridge native;

  /// Shows [message] as a system notification. Returns false when the user
  /// turned system notifications off, or the OS refused/couldn't show it
  /// (permission denied, no notification daemon…) — callers then fall back to
  /// an in-app toast.
  Future<bool> show(FlowMessage message) async {
    if (!settings.settings.systemNotifications) return false;
    final strings = Strings.forLanguage(settings.settings.language);
    return native.notify(
      title: strings.appName,
      body: textFor(strings, message),
    );
  }

  /// The human-readable text of [message], shared with the in-app toasts.
  static String textFor(Strings strings, FlowMessage message) =>
      switch (message.kind) {
        FlowMessageKind.copied => strings.copied,
        FlowMessageKind.saved => strings.savedTo(message.path ?? ''),
        FlowMessageKind.saveFailed => strings.saveFailed,
        FlowMessageKind.captureFailed => strings.captureFailed,
        FlowMessageKind.textCopied => strings.textCopied,
        FlowMessageKind.noTextFound => strings.noTextFound,
      };
}
