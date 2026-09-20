import Cocoa
import FlutterMacOS
import ScreenCaptureKit
import ServiceManagement

/// Native bridge for ShoShot (macOS).
///
/// Exposes screen capture, display/window enumeration, clipboard and overlay
/// window management to Dart through the `shoshot/native` method channel.
///
/// Coordinate system: every global coordinate returned here uses the
/// CoreGraphics "global display" space (origin at the top-left corner of the
/// main display, in points). Image pixels are `points * scale`.
final class ShoShotNative: NSObject {
  private let window: NSWindow
  private var channel: FlutterMethodChannel!
  private var launchChannel: FlutterMethodChannel!

  // Saved window state while the overlay is active.
  private var isOverlay = false
  private var savedStyleMask: NSWindow.StyleMask = []
  private var savedCollectionBehavior: NSWindow.CollectionBehavior = []
  private var savedLevel: NSWindow.Level = .normal
  private var savedHasShadow = true
  private var overlayScreen: NSScreen?

  init(window: NSWindow, messenger: FlutterBinaryMessenger) {
    self.window = window
    super.init()
    channel = FlutterMethodChannel(name: "shoshot/native", binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result: result)
    }
    // Backs the `launch_at_startup` package using SMAppService (macOS 13+).
    launchChannel = FlutterMethodChannel(name: "launch_at_startup", binaryMessenger: messenger)
    launchChannel.setMethodCallHandler { call, result in
      switch call.method {
      case "launchAtStartupIsEnabled":
        result(SMAppService.mainApp.status == .enabled)
      case "launchAtStartupSetEnabled":
        let enabled = (call.arguments as? [String: Any])?["setEnabledValue"] as? Bool ?? false
        do {
          if enabled {
            try SMAppService.mainApp.register()
          } else {
            try SMAppService.mainApp.unregister()
          }
          result(nil)
        } catch {
          result(FlutterError(code: "launch_at_login", message: error.localizedDescription, details: nil))
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  // MARK: - Dispatch

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "platformInfo":
      result([
        "globalIsPhysical": false,
        "supportsWindowList": true,
        "supportsNativeCapture": true,
        "needsScreenPermission": true,
      ])
    case "getDisplays":
      result(displays())
    case "getCursorPosition":
      let p = CGEvent(source: nil)?.location ?? .zero
      result(["x": Double(p.x), "y": Double(p.y)])
    case "captureDisplay":
      let id = CGDirectDisplayID((args["displayId"] as? Int) ?? Int(CGMainDisplayID()))
      captureDisplay(id, result: result)
    case "listWindows":
      result(listWindows())
    case "enterOverlay":
      let id = CGDirectDisplayID((args["displayId"] as? Int) ?? Int(CGMainDisplayID()))
      enterOverlay(displayId: id)
      result(nil)
    case "exitOverlay":
      let w = (args["width"] as? Double) ?? 1100
      let h = (args["height"] as? Double) ?? 720
      exitOverlay(width: w, height: h)
      result(nil)
    case "setClipboardImage":
      guard let png = (args["png"] as? FlutterStandardTypedData)?.data else {
        result(false)
        return
      }
      result(setClipboardImage(png: png))
    case "hasScreenAccess":
      result(CGPreflightScreenCaptureAccess())
    case "requestScreenAccess":
      result(CGRequestScreenCaptureAccess())
    case "openScreenAccessSettings":
      if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
        NSWorkspace.shared.open(url)
      }
      result(nil)
    case "setDockIconVisible":
      let visible = (args["visible"] as? Bool) ?? false
      NSApp.setActivationPolicy(visible ? .regular : .accessory)
      result(nil)
    case "revealFile":
      if let path = args["path"] as? String {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
      }
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: - Displays

  private func screen(for displayId: CGDirectDisplayID) -> NSScreen? {
    NSScreen.screens.first { screen in
      let key = NSDeviceDescriptionKey("NSScreenNumber")
      return (screen.deviceDescription[key] as? NSNumber)?.uint32Value == displayId
    }
  }

  private func displays() -> [[String: Any]] {
    var count: UInt32 = 0
    CGGetActiveDisplayList(0, nil, &count)
    var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
    CGGetActiveDisplayList(count, &ids, &count)
    let main = CGMainDisplayID()
    return ids.map { id in
      let bounds = CGDisplayBounds(id)
      let screen = screen(for: id)
      return [
        "id": Int(id),
        "x": Double(bounds.origin.x),
        "y": Double(bounds.origin.y),
        "width": Double(bounds.width),
        "height": Double(bounds.height),
        "scale": Double(screen?.backingScaleFactor ?? 1.0),
        "isPrimary": id == main,
        "name": screen?.localizedName ?? "Display \(id)",
      ]
    }
  }

  // MARK: - Capture

  private func captureDisplay(_ id: CGDirectDisplayID, result: @escaping FlutterResult) {
    let scale = Double(screen(for: id)?.backingScaleFactor ?? 1.0)
    if #available(macOS 14.0, *) {
      SCShareableContent.getExcludingDesktopWindows(false, onScreenWindowsOnly: true) { [weak self] content, error in
        guard let self = self else { return }
        guard error == nil, let content = content,
              let display = content.displays.first(where: { $0.displayID == id }) else {
          self.captureLegacy(id, scale: scale, result: result)
          return
        }
        let myPid = ProcessInfo.processInfo.processIdentifier
        let ownApps = content.applications.filter { $0.processID == myPid }
        let filter = SCContentFilter(display: display, excludingApplications: ownApps, exceptingWindows: [])
        let config = SCStreamConfiguration()
        config.width = Int(Double(display.width) * scale)
        config.height = Int(Double(display.height) * scale)
        config.showsCursor = false
        config.captureResolution = .best
        config.pixelFormat = kCVPixelFormatType_32BGRA
        SCScreenshotManager.captureImage(contentFilter: filter, configuration: config) { image, error in
          guard error == nil, let image = image else {
            self.captureLegacy(id, scale: scale, result: result)
            return
          }
          self.respond(image: image, scale: scale, result: result)
        }
      }
    } else {
      captureLegacy(id, scale: scale, result: result)
    }
  }

  private func captureLegacy(_ id: CGDirectDisplayID, scale: Double, result: @escaping FlutterResult) {
    guard let image = CGDisplayCreateImage(id) else {
      DispatchQueue.main.async {
        result(FlutterError(code: "capture_failed", message: "CGDisplayCreateImage returned nil", details: nil))
      }
      return
    }
    respond(image: image, scale: scale, result: result)
  }

  private func respond(image: CGImage, scale: Double, result: @escaping FlutterResult) {
    // Convert off the main thread; the buffer may be > 50 MB on large displays.
    DispatchQueue.global(qos: .userInitiated).async {
      let width = image.width
      let height = image.height
      let bytesPerRow = width * 4
      var data = Data(count: bytesPerRow * height)
      let ok = data.withUnsafeMutableBytes { (ptr: UnsafeMutableRawBufferPointer) -> Bool in
        guard let base = ptr.baseAddress,
              let ctx = CGContext(
                data: base,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
              ) else { return false }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return true
      }
      DispatchQueue.main.async {
        if ok {
          result([
            "width": width,
            "height": height,
            "scale": scale,
            "format": "rgba",
            "bytes": FlutterStandardTypedData(bytes: data),
          ])
        } else {
          result(FlutterError(code: "capture_failed", message: "Could not convert image", details: nil))
        }
      }
    }
  }

  // MARK: - Windows

  private func listWindows() -> [[String: Any]] {
    let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
    guard let info = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
      return []
    }
    let myPid = ProcessInfo.processInfo.processIdentifier
    var out: [[String: Any]] = []
    for item in info {
      guard let layer = item[kCGWindowLayer as String] as? Int, layer == 0 else { continue }
      guard let pid = item[kCGWindowOwnerPID as String] as? Int32, pid != myPid else { continue }
      guard let boundsDict = item[kCGWindowBounds as String] as? NSDictionary,
            let bounds = CGRect(dictionaryRepresentation: boundsDict) else { continue }
      if bounds.width < 24 || bounds.height < 24 { continue }
      if let alpha = item[kCGWindowAlpha as String] as? Double, alpha <= 0.01 { continue }
      let owner = item[kCGWindowOwnerName as String] as? String ?? ""
      let title = item[kCGWindowName as String] as? String ?? ""
      let number = item[kCGWindowNumber as String] as? Int ?? 0
      out.append([
        "id": number,
        "title": title,
        "app": owner,
        "x": Double(bounds.origin.x),
        "y": Double(bounds.origin.y),
        "width": Double(bounds.width),
        "height": Double(bounds.height),
      ])
    }
    return out
  }

  // MARK: - Overlay window

  private func enterOverlay(displayId: CGDirectDisplayID) {
    guard let screen = screen(for: displayId) ?? NSScreen.main else { return }
    if !isOverlay {
      savedStyleMask = window.styleMask
      savedCollectionBehavior = window.collectionBehavior
      savedLevel = window.level
      savedHasShadow = window.hasShadow
      isOverlay = true
    }
    overlayScreen = screen
    window.styleMask = [.borderless, .fullSizeContentView]
    window.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
    window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
    window.hasShadow = false
    window.isOpaque = true
    window.backgroundColor = .black
    window.setFrame(screen.frame, display: true)
    window.setIsVisible(true)
    NSApp.activate(ignoringOtherApps: true)
    window.makeKeyAndOrderFront(nil)
  }

  private func exitOverlay(width: Double, height: Double) {
    guard isOverlay else { return }
    isOverlay = false
    window.styleMask = savedStyleMask
    window.level = .normal
    window.collectionBehavior = savedCollectionBehavior
    window.hasShadow = savedHasShadow
    window.isOpaque = false
    let screen = overlayScreen ?? NSScreen.main
    let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
    let w = min(width, visible.width - 40)
    let h = min(height, visible.height - 40)
    let frame = NSRect(x: visible.midX - w / 2, y: visible.midY - h / 2, width: w, height: h)
    window.setFrame(frame, display: true)
  }

  // MARK: - Clipboard

  private func setClipboardImage(png: Data) -> Bool {
    guard let image = NSImage(data: png) else { return false }
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    return pasteboard.writeObjects([image])
  }
}
