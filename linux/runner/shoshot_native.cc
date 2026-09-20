#include "shoshot_native.h"

#include <gdk/gdk.h>
#include <gio/gio.h>
#ifdef GDK_WINDOWING_X11
#include <X11/Xatom.h>
#include <X11/Xlib.h>
#include <X11/Xutil.h>
#include <gdk/gdkx.h>
#endif
#ifdef GDK_WINDOWING_WAYLAND
#include <gdk/gdkwayland.h>
#endif

#include <climits>
#include <unistd.h>
#include <cstdio>
#include <cstring>
#include <string>
#include <vector>

namespace {

struct NativeState {
  GtkWindow* window = nullptr;
  FlMethodChannel* channel = nullptr;
  bool overlay = false;
  int overlay_monitor = 0;
  gboolean saved_decorated = TRUE;

  // System accent color, read once via the desktop portal and then kept in
  // sync by subscribing to its change signal (works under both X11 and
  // Wayland — it is a D-Bus session service, not a display-server API).
  GDBusConnection* session_bus = nullptr;
  guint accent_signal_id = 0;
  int64_t last_accent_argb = 0;
};

NativeState* g_state = nullptr;

bool IsWayland() {
#ifdef GDK_WINDOWING_WAYLAND
  return GDK_IS_WAYLAND_DISPLAY(gdk_display_get_default());
#else
  return false;
#endif
}

bool IsX11() {
#ifdef GDK_WINDOWING_X11
  return GDK_IS_X11_DISPLAY(gdk_display_get_default());
#else
  return false;
#endif
}

// ---------------------------------------------------------------------------
// Argument helpers
// ---------------------------------------------------------------------------

int64_t ArgInt(FlValue* args, const char* key, int64_t fallback) {
  if (args == nullptr || fl_value_get_type(args) != FL_VALUE_TYPE_MAP) {
    return fallback;
  }
  FlValue* v = fl_value_lookup_string(args, key);
  if (v == nullptr) return fallback;
  switch (fl_value_get_type(v)) {
    case FL_VALUE_TYPE_INT:
      return fl_value_get_int(v);
    case FL_VALUE_TYPE_FLOAT:
      return (int64_t)fl_value_get_float(v);
    default:
      return fallback;
  }
}

double ArgDouble(FlValue* args, const char* key, double fallback) {
  if (args == nullptr || fl_value_get_type(args) != FL_VALUE_TYPE_MAP) {
    return fallback;
  }
  FlValue* v = fl_value_lookup_string(args, key);
  if (v == nullptr) return fallback;
  switch (fl_value_get_type(v)) {
    case FL_VALUE_TYPE_INT:
      return (double)fl_value_get_int(v);
    case FL_VALUE_TYPE_FLOAT:
      return fl_value_get_float(v);
    default:
      return fallback;
  }
}

std::string ArgString(FlValue* args, const char* key) {
  if (args == nullptr || fl_value_get_type(args) != FL_VALUE_TYPE_MAP) {
    return "";
  }
  FlValue* v = fl_value_lookup_string(args, key);
  if (v == nullptr || fl_value_get_type(v) != FL_VALUE_TYPE_STRING) return "";
  return fl_value_get_string(v);
}

FlValue* ArgBytes(FlValue* args, const char* key) {
  if (args == nullptr || fl_value_get_type(args) != FL_VALUE_TYPE_MAP) {
    return nullptr;
  }
  FlValue* v = fl_value_lookup_string(args, key);
  if (v == nullptr || fl_value_get_type(v) != FL_VALUE_TYPE_UINT8_LIST) {
    return nullptr;
  }
  return v;
}

// ---------------------------------------------------------------------------
// Displays (GDK) — reported in physical pixels
// ---------------------------------------------------------------------------

struct MonitorEntry {
  int index;
  GdkRectangle geometry;   // logical
  GdkRectangle workarea;   // logical
  int scale;
  bool primary;
  std::string name;
};

std::vector<MonitorEntry> EnumerateMonitors() {
  std::vector<MonitorEntry> list;
  GdkDisplay* display = gdk_display_get_default();
  int n = gdk_display_get_n_monitors(display);
  for (int i = 0; i < n; i++) {
    GdkMonitor* monitor = gdk_display_get_monitor(display, i);
    MonitorEntry entry;
    entry.index = i;
    gdk_monitor_get_geometry(monitor, &entry.geometry);
    gdk_monitor_get_workarea(monitor, &entry.workarea);
    entry.scale = gdk_monitor_get_scale_factor(monitor);
    entry.primary = gdk_monitor_is_primary(monitor);
    const char* model = gdk_monitor_get_model(monitor);
    entry.name = model ? model : ("Display " + std::to_string(i + 1));
    list.push_back(entry);
  }
  return list;
}

const MonitorEntry* FindMonitor(const std::vector<MonitorEntry>& list,
                                int64_t id) {
  for (const auto& entry : list) {
    if (entry.index == id) return &entry;
  }
  return list.empty() ? nullptr : &list.front();
}

FlValue* GetDisplays() {
  FlValue* list = fl_value_new_list();
  for (const auto& m : EnumerateMonitors()) {
    FlValue* map = fl_value_new_map();
    fl_value_set_string_take(map, "id", fl_value_new_int(m.index));
    fl_value_set_string_take(map, "x",
                             fl_value_new_float(m.geometry.x * m.scale));
    fl_value_set_string_take(map, "y",
                             fl_value_new_float(m.geometry.y * m.scale));
    fl_value_set_string_take(map, "width",
                             fl_value_new_float(m.geometry.width * m.scale));
    fl_value_set_string_take(map, "height",
                             fl_value_new_float(m.geometry.height * m.scale));
    fl_value_set_string_take(map, "scale", fl_value_new_float(m.scale));
    fl_value_set_string_take(map, "isPrimary", fl_value_new_bool(m.primary));
    fl_value_set_string_take(map, "name", fl_value_new_string(m.name.c_str()));
    fl_value_append_take(list, map);
  }
  return list;
}

FlValue* GetCursorPosition() {
  GdkDisplay* display = gdk_display_get_default();
  GdkSeat* seat = gdk_display_get_default_seat(display);
  GdkDevice* pointer = gdk_seat_get_pointer(seat);
  int x = 0, y = 0;
  gdk_device_get_position(pointer, nullptr, &x, &y);
  GdkMonitor* monitor = gdk_display_get_monitor_at_point(display, x, y);
  int scale = monitor ? gdk_monitor_get_scale_factor(monitor) : 1;
  FlValue* map = fl_value_new_map();
  fl_value_set_string_take(map, "x", fl_value_new_float(x * scale));
  fl_value_set_string_take(map, "y", fl_value_new_float(y * scale));
  return map;
}

// ---------------------------------------------------------------------------
// X11 capture & window list
// ---------------------------------------------------------------------------

#ifdef GDK_WINDOWING_X11

Display* XDisplay() {
  return gdk_x11_display_get_xdisplay(gdk_display_get_default());
}

int ShiftForMask(unsigned long mask) {
  if (mask == 0) return 0;
  int shift = 0;
  while ((mask & 1) == 0) {
    mask >>= 1;
    shift++;
  }
  return shift;
}

int BitsForMask(unsigned long mask) {
  int bits = 0;
  while (mask) {
    bits += mask & 1;
    mask >>= 1;
  }
  return bits;
}

bool CaptureDisplayX11(int64_t display_id, FlValue** out) {
  auto monitors = EnumerateMonitors();
  const MonitorEntry* m = FindMonitor(monitors, display_id);
  if (!m) return false;
  int x = m->geometry.x * m->scale;
  int y = m->geometry.y * m->scale;
  int width = m->geometry.width * m->scale;
  int height = m->geometry.height * m->scale;

  Display* dpy = XDisplay();
  Window root = DefaultRootWindow(dpy);
  XImage* image = XGetImage(dpy, root, x, y, width, height, AllPlanes, ZPixmap);
  if (!image) return false;

  std::vector<uint8_t> rgba((size_t)width * height * 4);
  const int rshift = ShiftForMask(image->red_mask);
  const int gshift = ShiftForMask(image->green_mask);
  const int bshift = ShiftForMask(image->blue_mask);
  const int rbits = BitsForMask(image->red_mask);
  const int gbits = BitsForMask(image->green_mask);
  const int bbits = BitsForMask(image->blue_mask);
  for (int row = 0; row < height; row++) {
    for (int col = 0; col < width; col++) {
      unsigned long pixel = XGetPixel(image, col, row);
      unsigned long r = (pixel & image->red_mask) >> rshift;
      unsigned long g = (pixel & image->green_mask) >> gshift;
      unsigned long b = (pixel & image->blue_mask) >> bshift;
      if (rbits < 8) r = r * 255 / ((1 << rbits) - 1);
      if (gbits < 8) g = g * 255 / ((1 << gbits) - 1);
      if (bbits < 8) b = b * 255 / ((1 << bbits) - 1);
      size_t i = ((size_t)row * width + col) * 4;
      rgba[i + 0] = (uint8_t)r;
      rgba[i + 1] = (uint8_t)g;
      rgba[i + 2] = (uint8_t)b;
      rgba[i + 3] = 0xFF;
    }
  }
  XDestroyImage(image);

  FlValue* map = fl_value_new_map();
  fl_value_set_string_take(map, "width", fl_value_new_int(width));
  fl_value_set_string_take(map, "height", fl_value_new_int(height));
  fl_value_set_string_take(map, "scale", fl_value_new_float(m->scale));
  fl_value_set_string_take(map, "format", fl_value_new_string("rgba"));
  fl_value_set_string_take(
      map, "bytes", fl_value_new_uint8_list(rgba.data(), rgba.size()));
  *out = map;
  return true;
}

// Reads a window property; the caller frees `*data` with XFree.
bool GetProperty(Display* dpy, Window w, Atom property, Atom type,
                 unsigned char** data, unsigned long* nitems, int* format) {
  Atom actual_type;
  unsigned long bytes_after;
  *data = nullptr;
  int status = XGetWindowProperty(dpy, w, property, 0, LONG_MAX, False, type,
                                  &actual_type, format, nitems, &bytes_after,
                                  data);
  if (status != Success || *data == nullptr) return false;
  if (*nitems == 0) {
    XFree(*data);
    *data = nullptr;
    return false;
  }
  return true;
}

std::string WindowTitle(Display* dpy, Window w) {
  Atom net_name = XInternAtom(dpy, "_NET_WM_NAME", False);
  Atom utf8 = XInternAtom(dpy, "UTF8_STRING", False);
  unsigned char* data = nullptr;
  unsigned long nitems = 0;
  int format = 0;
  if (GetProperty(dpy, w, net_name, utf8, &data, &nitems, &format)) {
    std::string title((char*)data, nitems);
    XFree(data);
    return title;
  }
  char* name = nullptr;
  if (XFetchName(dpy, w, &name) && name) {
    std::string title(name);
    XFree(name);
    return title;
  }
  return "";
}

std::string ProcessName(pid_t pid) {
  std::string path = "/proc/" + std::to_string(pid) + "/comm";
  FILE* f = fopen(path.c_str(), "r");
  if (!f) return "";
  char buf[256] = {0};
  if (!fgets(buf, sizeof(buf), f)) {
    fclose(f);
    return "";
  }
  fclose(f);
  std::string name(buf);
  while (!name.empty() && (name.back() == '\n' || name.back() == '\r')) {
    name.pop_back();
  }
  return name;
}

bool HasAtomInList(Display* dpy, Window w, const char* list_prop,
                   const char* atom_name) {
  Atom prop = XInternAtom(dpy, list_prop, False);
  Atom wanted = XInternAtom(dpy, atom_name, False);
  unsigned char* data = nullptr;
  unsigned long nitems = 0;
  int format = 0;
  if (!GetProperty(dpy, w, prop, XA_ATOM, &data, &nitems, &format)) {
    return false;
  }
  bool found = false;
  Atom* atoms = (Atom*)data;
  for (unsigned long i = 0; i < nitems; i++) {
    if (atoms[i] == wanted) {
      found = true;
      break;
    }
  }
  XFree(data);
  return found;
}

FlValue* ListWindowsX11() {
  FlValue* list = fl_value_new_list();
  Display* dpy = XDisplay();
  Window root = DefaultRootWindow(dpy);
  Atom stacking = XInternAtom(dpy, "_NET_CLIENT_LIST_STACKING", True);
  if (stacking == None) return list;

  unsigned char* data = nullptr;
  unsigned long nitems = 0;
  int format = 0;
  if (!GetProperty(dpy, root, stacking, XA_WINDOW, &data, &nitems, &format)) {
    return list;
  }
  Window* windows = (Window*)data;
  Atom pid_atom = XInternAtom(dpy, "_NET_WM_PID", False);
  Atom extents_atom = XInternAtom(dpy, "_NET_FRAME_EXTENTS", False);
  pid_t own_pid = getpid();

  // _NET_CLIENT_LIST_STACKING is bottom-to-top; walk it in reverse so the
  // topmost window comes first.
  for (long i = (long)nitems - 1; i >= 0; i--) {
    Window w = windows[i];
    XWindowAttributes attr;
    if (!XGetWindowAttributes(dpy, w, &attr)) continue;
    if (attr.map_state != IsViewable) continue;
    if (HasAtomInList(dpy, w, "_NET_WM_STATE", "_NET_WM_STATE_HIDDEN")) continue;
    if (HasAtomInList(dpy, w, "_NET_WM_WINDOW_TYPE", "_NET_WM_WINDOW_TYPE_DESKTOP") ||
        HasAtomInList(dpy, w, "_NET_WM_WINDOW_TYPE", "_NET_WM_WINDOW_TYPE_DOCK")) {
      continue;
    }

    pid_t pid = 0;
    unsigned char* pid_data = nullptr;
    unsigned long pid_items = 0;
    int pid_format = 0;
    if (GetProperty(dpy, w, pid_atom, XA_CARDINAL, &pid_data, &pid_items,
                    &pid_format)) {
      pid = (pid_t)(*(unsigned long*)pid_data);
      XFree(pid_data);
    }
    if (pid == own_pid) continue;

    int rx = 0, ry = 0;
    Window child;
    XTranslateCoordinates(dpy, w, root, 0, 0, &rx, &ry, &child);
    long left = 0, right = 0, top = 0, bottom = 0;
    unsigned char* ext_data = nullptr;
    unsigned long ext_items = 0;
    int ext_format = 0;
    if (GetProperty(dpy, w, extents_atom, XA_CARDINAL, &ext_data, &ext_items,
                    &ext_format) &&
        ext_items >= 4) {
      unsigned long* ext = (unsigned long*)ext_data;
      left = ext[0];
      right = ext[1];
      top = ext[2];
      bottom = ext[3];
    }
    if (ext_data) XFree(ext_data);

    int x = rx - (int)left;
    int y = ry - (int)top;
    int width = attr.width + (int)left + (int)right;
    int height = attr.height + (int)top + (int)bottom;
    if (width < 24 || height < 24) continue;

    FlValue* map = fl_value_new_map();
    fl_value_set_string_take(map, "id", fl_value_new_int((int64_t)w));
    fl_value_set_string_take(map, "title",
                             fl_value_new_string(WindowTitle(dpy, w).c_str()));
    fl_value_set_string_take(map, "app",
                             fl_value_new_string(ProcessName(pid).c_str()));
    fl_value_set_string_take(map, "x", fl_value_new_float(x));
    fl_value_set_string_take(map, "y", fl_value_new_float(y));
    fl_value_set_string_take(map, "width", fl_value_new_float(width));
    fl_value_set_string_take(map, "height", fl_value_new_float(height));
    fl_value_append_take(list, map);
  }
  XFree(data);
  return list;
}

#endif  // GDK_WINDOWING_X11

// ---------------------------------------------------------------------------
// Overlay window
// ---------------------------------------------------------------------------

void EnterOverlay(NativeState* state, int64_t display_id) {
  auto monitors = EnumerateMonitors();
  const MonitorEntry* m = FindMonitor(monitors, display_id);
  if (!m) return;
  if (!state->overlay) {
    state->saved_decorated = gtk_window_get_decorated(state->window);
    state->overlay = true;
  }
  state->overlay_monitor = m->index;
  gtk_widget_show(GTK_WIDGET(state->window));
  gtk_window_set_decorated(state->window, FALSE);
  gtk_window_set_keep_above(state->window, TRUE);
  gtk_window_set_skip_taskbar_hint(state->window, TRUE);
  gtk_window_fullscreen_on_monitor(state->window, gdk_screen_get_default(),
                                   m->index);
  gtk_window_present(state->window);
}

void ExitOverlay(NativeState* state, double width, double height) {
  if (!state->overlay) return;
  state->overlay = false;
  auto monitors = EnumerateMonitors();
  const MonitorEntry* m = FindMonitor(monitors, state->overlay_monitor);
  gtk_window_unfullscreen(state->window);
  gtk_window_set_keep_above(state->window, FALSE);
  gtk_window_set_skip_taskbar_hint(state->window, FALSE);
  gtk_window_set_decorated(state->window, state->saved_decorated);
  int w = (int)width;
  int h = (int)height;
  if (m) {
    w = MIN(w, m->workarea.width - 40);
    h = MIN(h, m->workarea.height - 40);
    int x = m->workarea.x + (m->workarea.width - w) / 2;
    int y = m->workarea.y + (m->workarea.height - h) / 2;
    gtk_window_resize(state->window, w, h);
    gtk_window_move(state->window, x, y);
  } else {
    gtk_window_resize(state->window, w, h);
  }
}

// ---------------------------------------------------------------------------
// Clipboard
// ---------------------------------------------------------------------------

void FreePixels(guchar* pixels, gpointer) { g_free(pixels); }

bool SetClipboardImage(FlValue* rgba, int width, int height) {
  if (rgba == nullptr || width <= 0 || height <= 0) return false;
  size_t size = (size_t)width * height * 4;
  if (fl_value_get_length(rgba) < size) return false;
  guchar* copy = (guchar*)g_malloc(size);
  memcpy(copy, fl_value_get_uint8_list(rgba), size);
  GdkPixbuf* pixbuf = gdk_pixbuf_new_from_data(
      copy, GDK_COLORSPACE_RGB, TRUE, 8, width, height, width * 4, FreePixels,
      nullptr);
  if (!pixbuf) {
    g_free(copy);
    return false;
  }
  GtkClipboard* clipboard = gtk_clipboard_get(GDK_SELECTION_CLIPBOARD);
  gtk_clipboard_set_image(clipboard, pixbuf);
  gtk_clipboard_store(clipboard);
  g_object_unref(pixbuf);
  return true;
}

// ---------------------------------------------------------------------------
// System accent color (org.freedesktop.portal.Settings — GNOME/KDE, works
// under X11 and Wayland alike since it is a D-Bus session service).
// ---------------------------------------------------------------------------

constexpr int64_t kFallbackAccentArgb = (int64_t)0xFF7C5CFFLL;

int64_t ArgbFromRgbDoubles(double r, double g, double b) {
  auto byte = [](double component) {
    int v = (int)((component < 0 ? 0 : component > 1 ? 1 : component) * 255.0 +
                  0.5);
    return (int64_t)v;
  };
  return ((int64_t)0xFF << 24) | (byte(r) << 16) | (byte(g) << 8) | byte(b);
}

// `value` is the portal's `(ddd)`-tuple variant for "accent-color"; GVariant
// print format is a debug convenience, not something we parse — read the
// tuple members directly instead.
bool ArgbFromAccentVariant(GVariant* value, int64_t* out) {
  if (value == nullptr) return false;
  // The portal wraps the reply in an extra variant layer ("v" inside "v").
  GVariant* inner = value;
  g_autoptr(GVariant) unwrapped = nullptr;
  if (g_variant_is_of_type(inner, G_VARIANT_TYPE_VARIANT)) {
    unwrapped = g_variant_get_variant(inner);
    inner = unwrapped;
  }
  if (!g_variant_is_of_type(inner, G_VARIANT_TYPE("(ddd)"))) return false;
  double r = 0, g = 0, b = 0;
  g_variant_get(inner, "(ddd)", &r, &g, &b);
  *out = ArgbFromRgbDoubles(r, g, b);
  return true;
}

int64_t ReadPortalAccentArgb(GDBusConnection* bus) {
  if (bus == nullptr) return kFallbackAccentArgb;
  g_autoptr(GError) error = nullptr;
  g_autoptr(GVariant) reply = g_dbus_connection_call_sync(
      bus, "org.freedesktop.portal.Desktop", "/org/freedesktop/portal/desktop",
      "org.freedesktop.portal.Settings", "Read",
      g_variant_new("(ss)", "org.freedesktop.appearance", "accent-color"),
      G_VARIANT_TYPE("(v)"), G_DBUS_CALL_FLAGS_NONE, 1000, nullptr, &error);
  if (reply == nullptr) {
    // Not every desktop implements the accent-color key yet (it is a
    // recent addition to the portal spec) — this is an expected, silent
    // fallback, not necessarily a bug.
    return kFallbackAccentArgb;
  }
  g_autoptr(GVariant) boxed = nullptr;
  g_variant_get(reply, "(v)", &boxed);
  int64_t argb = kFallbackAccentArgb;
  ArgbFromAccentVariant(boxed, &argb);
  return argb;
}

void OnPortalSettingChanged(GDBusConnection*, const gchar*, const gchar*,
                            const gchar*, const gchar* signal_name,
                            GVariant* parameters, gpointer user_data) {
  if (g_strcmp0(signal_name, "SettingChanged") != 0) return;
  auto* state = static_cast<NativeState*>(user_data);
  const gchar* ns = nullptr;
  const gchar* key = nullptr;
  g_autoptr(GVariant) value = nullptr;
  // Signature: (namespace: s, key: s, value: v).
  g_variant_get(parameters, "(&s&sv)", &ns, &key, &value);
  if (g_strcmp0(ns, "org.freedesktop.appearance") != 0 ||
      g_strcmp0(key, "accent-color") != 0) {
    return;
  }
  int64_t argb = state->last_accent_argb;
  if (!ArgbFromAccentVariant(value, &argb) || argb == state->last_accent_argb) {
    return;
  }
  state->last_accent_argb = argb;
  fl_method_channel_invoke_method(
      state->channel, "systemAccentChanged",
      fl_value_new_int(argb), nullptr, nullptr, nullptr);
}

void InitSystemAccent(NativeState* state) {
  g_autoptr(GError) error = nullptr;
  state->session_bus = g_bus_get_sync(G_BUS_TYPE_SESSION, nullptr, &error);
  if (state->session_bus == nullptr) {
    g_warning("Show Shot: could not connect to the session bus for accent "
             "color (%s); using the fixed default instead.",
             error ? error->message : "unknown error");
    state->last_accent_argb = kFallbackAccentArgb;
    return;
  }
  state->last_accent_argb = ReadPortalAccentArgb(state->session_bus);
  state->accent_signal_id = g_dbus_connection_signal_subscribe(
      state->session_bus, "org.freedesktop.portal.Desktop",
      "org.freedesktop.portal.Settings", "SettingChanged",
      "/org/freedesktop/portal/desktop", nullptr, G_DBUS_SIGNAL_FLAGS_NONE,
      OnPortalSettingChanged, state, nullptr);
}

// ---------------------------------------------------------------------------
// Method dispatch
// ---------------------------------------------------------------------------

void MethodCallHandler(FlMethodChannel*, FlMethodCall* call,
                       gpointer user_data) {
  auto* state = static_cast<NativeState*>(user_data);
  const gchar* method = fl_method_call_get_name(call);
  FlValue* args = fl_method_call_get_args(call);
  g_autoptr(FlMethodResponse) response = nullptr;

  if (strcmp(method, "platformInfo") == 0) {
    g_autoptr(FlValue) map = fl_value_new_map();
    bool x11 = IsX11();
    fl_value_set_string_take(map, "globalIsPhysical", fl_value_new_bool(true));
    fl_value_set_string_take(map, "supportsWindowList", fl_value_new_bool(x11));
    fl_value_set_string_take(map, "supportsNativeCapture",
                             fl_value_new_bool(x11));
    fl_value_set_string_take(map, "needsScreenPermission",
                             fl_value_new_bool(false));
    fl_value_set_string_take(map, "wayland", fl_value_new_bool(IsWayland()));
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(map));
  } else if (strcmp(method, "getDisplays") == 0) {
    g_autoptr(FlValue) list = GetDisplays();
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(list));
  } else if (strcmp(method, "getCursorPosition") == 0) {
    g_autoptr(FlValue) map = GetCursorPosition();
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(map));
  } else if (strcmp(method, "captureDisplay") == 0) {
#ifdef GDK_WINDOWING_X11
    if (IsX11()) {
      FlValue* out = nullptr;
      if (CaptureDisplayX11(ArgInt(args, "displayId", 0), &out)) {
        response = FL_METHOD_RESPONSE(fl_method_success_response_new(out));
        fl_value_unref(out);
      } else {
        response = FL_METHOD_RESPONSE(fl_method_error_response_new(
            "capture_failed", "XGetImage failed", nullptr));
      }
    } else
#endif
    {
      response = FL_METHOD_RESPONSE(fl_method_error_response_new(
          "unsupported", "Native capture requires X11", nullptr));
    }
  } else if (strcmp(method, "listWindows") == 0) {
#ifdef GDK_WINDOWING_X11
    if (IsX11()) {
      g_autoptr(FlValue) list = ListWindowsX11();
      response = FL_METHOD_RESPONSE(fl_method_success_response_new(list));
    } else
#endif
    {
      g_autoptr(FlValue) list = fl_value_new_list();
      response = FL_METHOD_RESPONSE(fl_method_success_response_new(list));
    }
  } else if (strcmp(method, "enterOverlay") == 0) {
    EnterOverlay(state, ArgInt(args, "displayId", 0));
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else if (strcmp(method, "exitOverlay") == 0) {
    ExitOverlay(state, ArgDouble(args, "width", 1100),
                ArgDouble(args, "height", 720));
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else if (strcmp(method, "setClipboardImage") == 0) {
    bool ok = SetClipboardImage(ArgBytes(args, "rgba"),
                                (int)ArgInt(args, "width", 0),
                                (int)ArgInt(args, "height", 0));
    g_autoptr(FlValue) v = fl_value_new_bool(ok);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(v));
  } else if (strcmp(method, "hasScreenAccess") == 0 ||
             strcmp(method, "requestScreenAccess") == 0) {
    g_autoptr(FlValue) v = fl_value_new_bool(true);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(v));
  } else if (strcmp(method, "openScreenAccessSettings") == 0 ||
             strcmp(method, "setDockIconVisible") == 0) {
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else if (strcmp(method, "revealFile") == 0) {
    std::string path = ArgString(args, "path");
    if (!path.empty()) {
      gchar* dir = g_path_get_dirname(path.c_str());
      gchar* uri = g_filename_to_uri(dir, nullptr, nullptr);
      if (uri) {
        gtk_show_uri_on_window(state->window, uri, GDK_CURRENT_TIME, nullptr);
        g_free(uri);
      }
      g_free(dir);
    }
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else if (strcmp(method, "getSystemAccent") == 0) {
    g_autoptr(FlValue) v = fl_value_new_int(state->last_accent_argb);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(v));
  } else {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }

  fl_method_call_respond(call, response, nullptr);
}

}  // namespace

void shoshot_native_register(GtkWindow* window, FlView* view) {
  if (g_state != nullptr) return;
  g_state = new NativeState();
  g_state->window = window;
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  g_state->channel = fl_method_channel_new(
      fl_engine_get_binary_messenger(fl_view_get_engine(view)),
      "shoshot/native", FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(g_state->channel,
                                            MethodCallHandler, g_state,
                                            nullptr);
  InitSystemAccent(g_state);
}
