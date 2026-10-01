import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  /// True when macOS started us as a login item (System Settings > Login
  /// Items, or `SMAppService.mainApp.register()` — which is what the "Launch
  /// at startup" setting uses). `SMAppService` can't pass command-line
  /// arguments, so this launch Apple Event is the only signal. It's only
  /// readable while the app is still launching, hence capturing it here
  /// rather than when Dart asks for it later (see `launchInfo` in
  /// ShoShotNative.swift).
  private(set) static var launchedAsLoginItem = false

  /// Silent start: launched at login, or a dev passed `--hidden`
  /// (`--autostart` is the flag the Windows/Linux entries pass).
  static var shouldStartHidden: Bool {
    let args = CommandLine.arguments
    return launchedAsLoginItem || args.contains("--hidden") || args.contains("--autostart")
  }

  override func applicationWillFinishLaunching(_ notification: Notification) {
    AppDelegate.launchedAsLoginItem = AppDelegate.launchedAsLoginItem || Self.currentEventIsLoginItemLaunch()
    super.applicationWillFinishLaunching(notification)
  }

  override func applicationDidFinishLaunching(_ notification: Notification) {
    AppDelegate.launchedAsLoginItem = AppDelegate.launchedAsLoginItem || Self.currentEventIsLoginItemLaunch()
    (NSApp.windows.first { $0 is MainFlutterWindow } as? MainFlutterWindow)?
      .resolveLaunchVisibility()
    super.applicationDidFinishLaunching(notification)
  }

  private static func currentEventIsLoginItemLaunch() -> Bool {
    guard let event = NSAppleEventManager.shared().currentAppleEvent else { return false }
    return event.eventID == kAEOpenApplication
      && event.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
  }

  // Show Shot lives in the menu bar; closing the window must not quit the app.
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return false
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  // Clicking the app in Finder/Launchpad while it is already running re-opens the window.
  override func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    if !flag, let window = sender.windows.first {
      window.makeKeyAndOrderFront(nil)
      NSApp.activate(ignoringOtherApps: true)
    }
    return true
  }
}
