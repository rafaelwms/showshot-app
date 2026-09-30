/// Notification shown to the user after a flow completes.
class FlowMessage {
  const FlowMessage(this.kind, {this.path});
  final FlowMessageKind kind;
  final String? path;
}

enum FlowMessageKind {
  copied,
  saved,
  saveFailed,
  captureFailed,
  textCopied,
  noTextFound,
}
