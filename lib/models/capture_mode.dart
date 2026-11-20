/// How a capture is started.
enum CaptureMode {
  /// Freeze the screen and let the user drag a rectangle (or click a window).
  area,

  /// Freeze the screen and highlight windows under the cursor.
  window,

  /// Capture the whole display under the cursor and open the editor directly.
  fullScreen,

  /// Freeze the screen and let the user drag a rectangle to recognize text
  /// in, instead of an image.
  text,

  /// Captures every connected display at once and saves straight to disk
  /// (no overlay, no editor). Handled by `CaptureFlow`, never reaches the
  /// overlay.
  allScreens,
}
