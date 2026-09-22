#ifndef RUNNER_SHOSHOT_NATIVE_H_
#define RUNNER_SHOSHOT_NATIVE_H_

#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <windows.h>

#include <memory>

// Native bridge for ShoShot (Windows).
//
// Exposes screen capture, display/window enumeration, clipboard and overlay
// window management to Dart through the `shoshot/native` method channel.
//
// Coordinate system: every global coordinate returned here is in physical
// pixels (the Win32 virtual-screen space). Each display reports its own
// scale (DPI / 96); the Flutter logical size of the overlay window is
// `physical / scale`.
class ShoShotNative {
 public:
  ShoShotNative(HWND hwnd, flutter::BinaryMessenger* messenger);
  ~ShoShotNative();

 private:
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  flutter::EncodableValue GetDisplays();
  flutter::EncodableValue GetCursorPosition();
  bool CaptureDisplay(int64_t display_id, flutter::EncodableValue* out);
  flutter::EncodableValue ListWindows();
  void EnterOverlay(int64_t display_id);
  void ExitOverlay(double logical_width, double logical_height);
  bool SetClipboardImage(const std::vector<uint8_t>& png,
                         const std::vector<uint8_t>& rgba, int width,
                         int height);
  int64_t CurrentAccentArgb();
  void RecognizeText(
      std::vector<uint8_t> png,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

 public:
  // Called by FlutterWindow::MessageHandler on WM_SETTINGCHANGE /
  // WM_DWMCOLORIZATIONCOLORCHANGED — pushes the current accent color to
  // Dart if it actually changed since the last read.
  void OnSystemAccentMaybeChanged();

 private:
  HWND hwnd_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;

  // Saved window state while the overlay is active.
  bool overlay_ = false;
  LONG_PTR saved_style_ = 0;
  LONG_PTR saved_exstyle_ = 0;
  HMONITOR overlay_monitor_ = nullptr;

  int64_t last_accent_argb_ = 0;
};

#endif  // RUNNER_SHOSHOT_NATIVE_H_
