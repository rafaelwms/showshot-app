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

    super.awakeFromNib()
  }

  // A borderless window (used for the capture overlay) must be able to become
  // key so that keyboard shortcuts such as Esc/Enter reach Flutter.
  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { true }
}
