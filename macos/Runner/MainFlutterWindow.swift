import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private var native: ShoShotNative?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    native = ShoShotNative(window: self, messenger: flutterViewController.engine.binaryMessenger)

    // Lets the editor open in macOS full screen (Settings → Editor window).
    collectionBehavior.insert(.fullScreenPrimary)
    alphaValue = 0
    observeTrafficLightLayout()
    // Fail open: if the launch notification never reaches the app delegate,
    // reveal the window anyway rather than leave it invisible.
    DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
      self?.resolveLaunchVisibility()
    }

    super.awakeFromNib()
  }

  private var launchRevealPending = true

  /// Height of the Flutter title bar (`WindowTitleBar.defaultHeight`).
  static let titleBarHeight: CGFloat = 56

  // With the hidden title bar the close/minimize/zoom buttons sit at AppKit's
  // fixed spot, hugging the top edge of a 56 pt Flutter bar. Centre them in
  // it instead: grow the (invisible) system title bar to the same height and
  // put the buttons in its middle. AppKit resets this on resize, style-mask
  // changes and full-screen transitions, so it is re-applied on those.
  private func observeTrafficLightLayout() {
    let center = NotificationCenter.default
    for name in [
      NSWindow.didResizeNotification, NSWindow.didEndLiveResizeNotification,
      NSWindow.didExitFullScreenNotification, NSWindow.didBecomeKeyNotification,
      NSWindow.didBecomeMainNotification,
    ] {
      center.addObserver(forName: name, object: self, queue: .main) { [weak self] _ in
        self?.layoutTrafficLights()
      }
    }
    DispatchQueue.main.async { [weak self] in self?.layoutTrafficLights() }
  }

  func layoutTrafficLights() {
    guard styleMask.contains(.titled), !styleMask.contains(.fullScreen),
      let close = standardWindowButton(.closeButton),
      let mini = standardWindowButton(.miniaturizeButton),
      let zoom = standardWindowButton(.zoomButton),
      let titlebar = close.superview,
      let container = titlebar.superview
    else { return }
    let bar = MainFlutterWindow.titleBarHeight
    container.frame = NSRect(x: 0, y: frame.height - bar, width: frame.width, height: bar)
    titlebar.frame = container.bounds
    let y = (bar - close.frame.height) / 2
    var x: CGFloat = 14
    for button in [close, mini, zoom] {
      button.setFrameOrigin(NSPoint(x: x, y: y))
      x += button.frame.width + 6
    }
  }

  // The launch-time visibility can't be decided when the window is created:
  // "was this a login item?" is only readable from the launch Apple Event,
  // which arrives after the nib has loaded and AppKit has already ordered the
  // window in (that ordering can't be skipped: the Flutter view controller
  // only starts the engine once its view is about to appear, so a window
  // that's never ordered in means Dart never runs — no tray icon, no
  // shortcuts). So it starts fully transparent, and
  // `applicationDidFinishLaunching` calls `resolveLaunchVisibility()` to
  // either reveal it (normal launch) or take it off screen (silent start),
  // with no flash in between.
  func resolveLaunchVisibility() {
    guard launchRevealPending else { return }
    launchRevealPending = false
    if AppDelegate.shouldStartHidden {
      orderOut(nil)
    }
    alphaValue = 1
  }

  // A borderless window (used for the capture overlay) must be able to become
  // key so that keyboard shortcuts such as Esc/Enter reach Flutter.
  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { true }
}
