import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
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
