#include "shoshot_native.h"

#include <dwmapi.h>
#include <flutter/standard_method_codec.h>
#include <shellapi.h>
#include <shellscalingapi.h>
#include <shlobj.h>
#include <winreg.h>

#include <algorithm>
#include <cstring>
#include <string>
#include <vector>

namespace {

using flutter::EncodableList;
using flutter::EncodableMap;
using flutter::EncodableValue;

struct MonitorEntry {
  HMONITOR handle;
  RECT rect;
  RECT work;
  bool primary;
  UINT dpi;
  std::wstring name;
};

BOOL CALLBACK MonitorEnumProc(HMONITOR monitor, HDC, LPRECT, LPARAM lparam) {
  auto* list = reinterpret_cast<std::vector<MonitorEntry>*>(lparam);
  MONITORINFOEXW info{};
  info.cbSize = sizeof(info);
  if (!GetMonitorInfoW(monitor, &info)) {
    return TRUE;
  }
  UINT dpi_x = 96, dpi_y = 96;
  if (FAILED(GetDpiForMonitor(monitor, MDT_EFFECTIVE_DPI, &dpi_x, &dpi_y))) {
    dpi_x = 96;
  }
  list->push_back({monitor, info.rcMonitor, info.rcWork,
                   (info.dwFlags & MONITORINFOF_PRIMARY) != 0, dpi_x,
                   info.szDevice});
  return TRUE;
}

std::vector<MonitorEntry> EnumerateMonitors() {
  std::vector<MonitorEntry> list;
  EnumDisplayMonitors(nullptr, nullptr, MonitorEnumProc,
                      reinterpret_cast<LPARAM>(&list));
  return list;
}

const MonitorEntry* FindMonitor(const std::vector<MonitorEntry>& list,
                                int64_t id) {
  for (const auto& entry : list) {
    if (reinterpret_cast<int64_t>(entry.handle) == id) {
      return &entry;
    }
  }
  return list.empty() ? nullptr : &list.front();
}

std::string Utf8FromWide(const std::wstring& wide) {
  if (wide.empty()) return std::string();
  int size = WideCharToMultiByte(CP_UTF8, 0, wide.c_str(), (int)wide.size(),
                                 nullptr, 0, nullptr, nullptr);
  std::string out(size, '\0');
  WideCharToMultiByte(CP_UTF8, 0, wide.c_str(), (int)wide.size(), &out[0],
                      size, nullptr, nullptr);
  return out;
}

std::wstring WideFromUtf8(const std::string& utf8) {
  if (utf8.empty()) return std::wstring();
  int size = MultiByteToWideChar(CP_UTF8, 0, utf8.c_str(), (int)utf8.size(),
                                 nullptr, 0);
  std::wstring out(size, L'\0');
  MultiByteToWideChar(CP_UTF8, 0, utf8.c_str(), (int)utf8.size(), &out[0],
                      size);
  return out;
}

template <typename T>
T GetArg(const EncodableMap* args, const char* key, T fallback) {
  if (!args) return fallback;
  auto it = args->find(EncodableValue(key));
  if (it == args->end()) return fallback;
  if (const auto* value = std::get_if<T>(&it->second)) {
    return *value;
  }
  return fallback;
}

double GetNumberArg(const EncodableMap* args, const char* key,
                    double fallback) {
  if (!args) return fallback;
  auto it = args->find(EncodableValue(key));
  if (it == args->end()) return fallback;
  if (const auto* d = std::get_if<double>(&it->second)) return *d;
  if (const auto* i = std::get_if<int32_t>(&it->second)) return *i;
  if (const auto* l = std::get_if<int64_t>(&it->second)) return (double)*l;
  return fallback;
}

int64_t GetIntArg(const EncodableMap* args, const char* key,
                  int64_t fallback) {
  if (!args) return fallback;
  auto it = args->find(EncodableValue(key));
  if (it == args->end()) return fallback;
  if (const auto* i = std::get_if<int32_t>(&it->second)) return *i;
  if (const auto* l = std::get_if<int64_t>(&it->second)) return *l;
  if (const auto* d = std::get_if<double>(&it->second)) return (int64_t)*d;
  return fallback;
}

std::vector<uint8_t> GetBytesArg(const EncodableMap* args, const char* key) {
  if (!args) return {};
  auto it = args->find(EncodableValue(key));
  if (it == args->end()) return {};
  if (const auto* bytes = std::get_if<std::vector<uint8_t>>(&it->second)) {
    return *bytes;
  }
  return {};
}

struct WindowEnumContext {
  DWORD own_pid;
  EncodableList* list;
};

std::string ProcessNameForPid(DWORD pid) {
  HANDLE process =
      OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid);
  if (!process) return std::string();
  wchar_t path[MAX_PATH];
  DWORD size = MAX_PATH;
  std::string name;
  if (QueryFullProcessImageNameW(process, 0, path, &size)) {
    std::wstring full(path, size);
    size_t slash = full.find_last_of(L"\\/");
    std::wstring base =
        slash == std::wstring::npos ? full : full.substr(slash + 1);
    size_t dot = base.find_last_of(L'.');
    if (dot != std::wstring::npos) base = base.substr(0, dot);
    name = Utf8FromWide(base);
  }
  CloseHandle(process);
  return name;
}

BOOL CALLBACK WindowEnumProc(HWND hwnd, LPARAM lparam) {
  auto* ctx = reinterpret_cast<WindowEnumContext*>(lparam);
  if (!IsWindowVisible(hwnd) || IsIconic(hwnd)) return TRUE;

  DWORD pid = 0;
  GetWindowThreadProcessId(hwnd, &pid);
  if (pid == ctx->own_pid) return TRUE;

  LONG_PTR exstyle = GetWindowLongPtrW(hwnd, GWL_EXSTYLE);
  if (exstyle & WS_EX_TOOLWINDOW) return TRUE;

  DWORD cloaked = 0;
  if (SUCCEEDED(DwmGetWindowAttribute(hwnd, DWMWA_CLOAKED, &cloaked,
                                      sizeof(cloaked))) &&
      cloaked != 0) {
    return TRUE;
  }

  wchar_t class_name[128];
  GetClassNameW(hwnd, class_name, 128);
  std::wstring cls(class_name);
  if (cls == L"Progman" || cls == L"WorkerW" || cls == L"Shell_TrayWnd" ||
      cls == L"Shell_SecondaryTrayWnd" ||
      cls == L"Windows.UI.Core.CoreWindow") {
    return TRUE;
  }

  int title_len = GetWindowTextLengthW(hwnd);
  if (title_len <= 0) return TRUE;
  std::wstring title(title_len + 1, L'\0');
  GetWindowTextW(hwnd, &title[0], title_len + 1);
  title.resize(title_len);

  RECT rect{};
  if (FAILED(DwmGetWindowAttribute(hwnd, DWMWA_EXTENDED_FRAME_BOUNDS, &rect,
                                   sizeof(rect)))) {
    if (!GetWindowRect(hwnd, &rect)) return TRUE;
  }
  int width = rect.right - rect.left;
  int height = rect.bottom - rect.top;
  if (width < 24 || height < 24) return TRUE;

  EncodableMap entry;
  entry[EncodableValue("id")] = EncodableValue((int64_t)hwnd);
  entry[EncodableValue("title")] = EncodableValue(Utf8FromWide(title));
  entry[EncodableValue("app")] = EncodableValue(ProcessNameForPid(pid));
  entry[EncodableValue("x")] = EncodableValue((double)rect.left);
  entry[EncodableValue("y")] = EncodableValue((double)rect.top);
  entry[EncodableValue("width")] = EncodableValue((double)width);
  entry[EncodableValue("height")] = EncodableValue((double)height);
  ctx->list->push_back(EncodableValue(entry));
  return TRUE;
}

}  // namespace

ShoShotNative::ShoShotNative(HWND hwnd, flutter::BinaryMessenger* messenger)
    : hwnd_(hwnd) {
  channel_ = std::make_unique<flutter::MethodChannel<EncodableValue>>(
      messenger, "shoshot/native",
      &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler(
      [this](const auto& call, auto result) {
        HandleMethodCall(call, std::move(result));
      });
  last_accent_argb_ = CurrentAccentArgb();
}

ShoShotNative::~ShoShotNative() {
  if (channel_) channel_->SetMethodCallHandler(nullptr);
}

void ShoShotNative::HandleMethodCall(
    const flutter::MethodCall<EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
  const auto* args = std::get_if<EncodableMap>(call.arguments());
  const std::string& method = call.method_name();

  if (method == "platformInfo") {
    EncodableMap info;
    info[EncodableValue("globalIsPhysical")] = EncodableValue(true);
    info[EncodableValue("supportsWindowList")] = EncodableValue(true);
    info[EncodableValue("supportsNativeCapture")] = EncodableValue(true);
    info[EncodableValue("needsScreenPermission")] = EncodableValue(false);
    result->Success(EncodableValue(info));
  } else if (method == "getDisplays") {
    result->Success(GetDisplays());
  } else if (method == "getCursorPosition") {
    result->Success(GetCursorPosition());
  } else if (method == "captureDisplay") {
    EncodableValue out;
    if (CaptureDisplay(GetIntArg(args, "displayId", 0), &out)) {
      result->Success(out);
    } else {
      result->Error("capture_failed", "BitBlt failed");
    }
  } else if (method == "listWindows") {
    result->Success(ListWindows());
  } else if (method == "enterOverlay") {
    EnterOverlay(GetIntArg(args, "displayId", 0));
    result->Success();
  } else if (method == "exitOverlay") {
    ExitOverlay(GetNumberArg(args, "width", 1100),
                GetNumberArg(args, "height", 720));
    result->Success();
  } else if (method == "setClipboardImage") {
    bool ok = SetClipboardImage(GetBytesArg(args, "png"),
                                GetBytesArg(args, "rgba"),
                                (int)GetIntArg(args, "width", 0),
                                (int)GetIntArg(args, "height", 0));
    result->Success(EncodableValue(ok));
  } else if (method == "hasScreenAccess") {
    result->Success(EncodableValue(true));
  } else if (method == "requestScreenAccess") {
    result->Success(EncodableValue(true));
  } else if (method == "openScreenAccessSettings" ||
             method == "setDockIconVisible") {
    result->Success();
  } else if (method == "revealFile") {
    std::string path = GetArg<std::string>(args, "path", "");
    std::wstring wide = WideFromUtf8(path);
    PIDLIST_ABSOLUTE pidl = ILCreateFromPathW(wide.c_str());
    if (pidl) {
      SHOpenFolderAndSelectItems(pidl, 0, nullptr, 0);
      ILFree(pidl);
    }
    result->Success();
  } else if (method == "getSystemAccent") {
    result->Success(EncodableValue(CurrentAccentArgb()));
  } else {
    result->NotImplemented();
  }
}

int64_t ShoShotNative::CurrentAccentArgb() {
  // Settings > Personalization > Colors' accent color, stored as a DWORD in
  // ABGR order (not ARGB) by DWM.
  HKEY key;
  int64_t fallback = (int64_t)0xFF7C5CFFLL;  // matches the Dart-side default
  if (RegOpenKeyExW(HKEY_CURRENT_USER,
                    L"Software\\Microsoft\\Windows\\DWM", 0, KEY_READ,
                    &key) != ERROR_SUCCESS) {
    return fallback;
  }
  DWORD abgr = 0;
  DWORD size = sizeof(abgr);
  DWORD type = 0;
  LSTATUS status = RegQueryValueExW(key, L"AccentColor", nullptr, &type,
                                    reinterpret_cast<BYTE*>(&abgr), &size);
  RegCloseKey(key);
  if (status != ERROR_SUCCESS || type != REG_DWORD) return fallback;

  // Byte 3 (alpha) is unused: the output is always forced fully opaque.
  uint8_t b = (abgr >> 16) & 0xFF;
  uint8_t g = (abgr >> 8) & 0xFF;
  uint8_t r = abgr & 0xFF;
  return ((int64_t)0xFF << 24) | ((int64_t)r << 16) | ((int64_t)g << 8) | b;
}

void ShoShotNative::OnSystemAccentMaybeChanged() {
  int64_t current = CurrentAccentArgb();
  if (current == last_accent_argb_) return;
  last_accent_argb_ = current;
  channel_->InvokeMethod("systemAccentChanged",
                        std::make_unique<EncodableValue>(current));
}

EncodableValue ShoShotNative::GetDisplays() {
  EncodableList list;
  for (const auto& monitor : EnumerateMonitors()) {
    EncodableMap entry;
    entry[EncodableValue("id")] =
        EncodableValue(reinterpret_cast<int64_t>(monitor.handle));
    entry[EncodableValue("x")] = EncodableValue((double)monitor.rect.left);
    entry[EncodableValue("y")] = EncodableValue((double)monitor.rect.top);
    entry[EncodableValue("width")] =
        EncodableValue((double)(monitor.rect.right - monitor.rect.left));
    entry[EncodableValue("height")] =
        EncodableValue((double)(monitor.rect.bottom - monitor.rect.top));
    entry[EncodableValue("scale")] = EncodableValue(monitor.dpi / 96.0);
    entry[EncodableValue("isPrimary")] = EncodableValue(monitor.primary);
    entry[EncodableValue("name")] = EncodableValue(Utf8FromWide(monitor.name));
    list.push_back(EncodableValue(entry));
  }
  return EncodableValue(list);
}

EncodableValue ShoShotNative::GetCursorPosition() {
  POINT point{};
  GetCursorPos(&point);
  EncodableMap map;
  map[EncodableValue("x")] = EncodableValue((double)point.x);
  map[EncodableValue("y")] = EncodableValue((double)point.y);
  return EncodableValue(map);
}

bool ShoShotNative::CaptureDisplay(int64_t display_id, EncodableValue* out) {
  auto monitors = EnumerateMonitors();
  const MonitorEntry* monitor = FindMonitor(monitors, display_id);
  if (!monitor) return false;

  const int width = monitor->rect.right - monitor->rect.left;
  const int height = monitor->rect.bottom - monitor->rect.top;
  if (width <= 0 || height <= 0) return false;

  HDC screen_dc = GetDC(nullptr);
  HDC mem_dc = CreateCompatibleDC(screen_dc);

  BITMAPINFO bmi{};
  bmi.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
  bmi.bmiHeader.biWidth = width;
  bmi.bmiHeader.biHeight = -height;  // top-down
  bmi.bmiHeader.biPlanes = 1;
  bmi.bmiHeader.biBitCount = 32;
  bmi.bmiHeader.biCompression = BI_RGB;

  void* bits = nullptr;
  HBITMAP bitmap =
      CreateDIBSection(screen_dc, &bmi, DIB_RGB_COLORS, &bits, nullptr, 0);
  bool ok = false;
  if (bitmap && bits) {
    HGDIOBJ old = SelectObject(mem_dc, bitmap);
    ok = BitBlt(mem_dc, 0, 0, width, height, screen_dc, monitor->rect.left,
                monitor->rect.top, SRCCOPY | CAPTUREBLT) != 0;
    GdiFlush();
    if (ok) {
      const size_t size = (size_t)width * height * 4;
      std::vector<uint8_t> bytes(size);
      std::memcpy(bytes.data(), bits, size);
      // GDI leaves the alpha channel undefined; make the image opaque.
      for (size_t i = 3; i < size; i += 4) bytes[i] = 0xFF;

      EncodableMap map;
      map[EncodableValue("width")] = EncodableValue(width);
      map[EncodableValue("height")] = EncodableValue(height);
      map[EncodableValue("scale")] = EncodableValue(monitor->dpi / 96.0);
      map[EncodableValue("format")] = EncodableValue("bgra");
      map[EncodableValue("bytes")] = EncodableValue(std::move(bytes));
      *out = EncodableValue(map);
    }
    SelectObject(mem_dc, old);
  }
  if (bitmap) DeleteObject(bitmap);
  DeleteDC(mem_dc);
  ReleaseDC(nullptr, screen_dc);
  return ok;
}

EncodableValue ShoShotNative::ListWindows() {
  EncodableList list;
  WindowEnumContext ctx{GetCurrentProcessId(), &list};
  // EnumWindows visits top-level windows in z-order, front to back.
  EnumWindows(WindowEnumProc, reinterpret_cast<LPARAM>(&ctx));
  return EncodableValue(list);
}

void ShoShotNative::EnterOverlay(int64_t display_id) {
  auto monitors = EnumerateMonitors();
  const MonitorEntry* monitor = FindMonitor(monitors, display_id);
  if (!monitor) return;

  if (!overlay_) {
    saved_style_ = GetWindowLongPtrW(hwnd_, GWL_STYLE);
    saved_exstyle_ = GetWindowLongPtrW(hwnd_, GWL_EXSTYLE);
    overlay_ = true;
  }
  overlay_monitor_ = monitor->handle;

  SetWindowLongPtrW(hwnd_, GWL_STYLE, WS_POPUP | WS_VISIBLE | WS_CLIPCHILDREN);
  SetWindowLongPtrW(hwnd_, GWL_EXSTYLE,
                    (saved_exstyle_ | WS_EX_TOPMOST | WS_EX_TOOLWINDOW) &
                        ~WS_EX_APPWINDOW);
  SetWindowPos(hwnd_, HWND_TOPMOST, monitor->rect.left, monitor->rect.top,
               monitor->rect.right - monitor->rect.left,
               monitor->rect.bottom - monitor->rect.top,
               SWP_FRAMECHANGED | SWP_SHOWWINDOW);
  SetForegroundWindow(hwnd_);
  SetFocus(hwnd_);
}

void ShoShotNative::ExitOverlay(double logical_width, double logical_height) {
  if (!overlay_) return;
  overlay_ = false;

  auto monitors = EnumerateMonitors();
  const MonitorEntry* monitor =
      FindMonitor(monitors, reinterpret_cast<int64_t>(overlay_monitor_));

  SetWindowLongPtrW(hwnd_, GWL_STYLE, saved_style_ | WS_VISIBLE);
  SetWindowLongPtrW(hwnd_, GWL_EXSTYLE, saved_exstyle_);

  RECT work = monitor ? monitor->work : RECT{0, 0, 1920, 1080};
  double scale = monitor ? monitor->dpi / 96.0 : 1.0;
  int work_w = work.right - work.left;
  int work_h = work.bottom - work.top;
  int w = std::min((int)(logical_width * scale), work_w - 40);
  int h = std::min((int)(logical_height * scale), work_h - 40);
  int x = work.left + (work_w - w) / 2;
  int y = work.top + (work_h - h) / 2;
  SetWindowPos(hwnd_, HWND_NOTOPMOST, x, y, w, h,
               SWP_FRAMECHANGED | SWP_SHOWWINDOW);
}

bool ShoShotNative::SetClipboardImage(const std::vector<uint8_t>& png,
                                      const std::vector<uint8_t>& rgba,
                                      int width, int height) {
  if (width <= 0 || height <= 0 || rgba.size() < (size_t)width * height * 4) {
    return false;
  }

  // CF_DIB: BITMAPINFOHEADER followed by bottom-up BGRA rows.
  const size_t row_bytes = (size_t)width * 4;
  const size_t dib_size = sizeof(BITMAPINFOHEADER) + row_bytes * height;
  HGLOBAL dib = GlobalAlloc(GMEM_MOVEABLE, dib_size);
  if (!dib) return false;
  auto* dib_ptr = static_cast<uint8_t*>(GlobalLock(dib));
  auto* header = reinterpret_cast<BITMAPINFOHEADER*>(dib_ptr);
  std::memset(header, 0, sizeof(BITMAPINFOHEADER));
  header->biSize = sizeof(BITMAPINFOHEADER);
  header->biWidth = width;
  header->biHeight = height;  // bottom-up
  header->biPlanes = 1;
  header->biBitCount = 32;
  header->biCompression = BI_RGB;
  header->biSizeImage = (DWORD)(row_bytes * height);
  uint8_t* pixels = dib_ptr + sizeof(BITMAPINFOHEADER);
  for (int row = 0; row < height; ++row) {
    const uint8_t* src = rgba.data() + (size_t)row * row_bytes;
    uint8_t* dst = pixels + (size_t)(height - 1 - row) * row_bytes;
    for (int col = 0; col < width; ++col) {
      dst[col * 4 + 0] = src[col * 4 + 2];  // B
      dst[col * 4 + 1] = src[col * 4 + 1];  // G
      dst[col * 4 + 2] = src[col * 4 + 0];  // R
      dst[col * 4 + 3] = src[col * 4 + 3];  // A
    }
  }
  GlobalUnlock(dib);

  HGLOBAL png_mem = nullptr;
  UINT png_format = RegisterClipboardFormatW(L"PNG");
  if (!png.empty()) {
    png_mem = GlobalAlloc(GMEM_MOVEABLE, png.size());
    if (png_mem) {
      void* ptr = GlobalLock(png_mem);
      std::memcpy(ptr, png.data(), png.size());
      GlobalUnlock(png_mem);
    }
  }

  bool ok = false;
  if (OpenClipboard(hwnd_)) {
    EmptyClipboard();
    ok = SetClipboardData(CF_DIB, dib) != nullptr;
    if (ok) dib = nullptr;  // ownership transferred to the clipboard
    if (png_mem && png_format != 0) {
      if (SetClipboardData(png_format, png_mem) != nullptr) png_mem = nullptr;
    }
    CloseClipboard();
  }
  if (dib) GlobalFree(dib);
  if (png_mem) GlobalFree(png_mem);
  return ok;
}
