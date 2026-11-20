/// Notification shown to the user after a flow completes.
class FlowMessage {
  const FlowMessage(this.kind, {this.path, this.count = 1});
  final FlowMessageKind kind;
  final String? path;

  /// Number of files, for [FlowMessageKind.savedMany] (`path` is then the folder).
  final int count;
}

enum FlowMessageKind {
  copied,
  saved,

  /// "All screens" saved as several files into one folder.
  savedMany,
  saveFailed,
  captureFailed,
  textCopied,
  noTextFound,
}
