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
#include <functional>
#include <string>
#include <vector>

namespace {

struct NativeState {
  GtkWindow* window = nullptr;
  FlMethodChannel* channel = nullptr;
  bool overlay = false;
  int overlay_monitor = 0;

  // System accent color, read once via the desktop portal and then kept in
  // sync by subscribing to its change signal (works under both X11 and
  // Wayland — it is a D-Bus session service, not a display-server API).
  GDBusConnection* session_bus = nullptr;
  guint accent_signal_id = 0;
  int64_t last_accent_argb = 0;

  // Global shortcuts portal session (Wayland), created on first bind.
  std::string shortcuts_session;

  // Last value sent as `windowRoundedChanged`.
  bool last_rounded = true;
  guint shortcuts_activated_id = 0;
  guint shortcuts_changed_id = 0;
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
  state->overlay = true;
  state->overlay_monitor = m->index;
  gtk_widget_show(GTK_WIDGET(state->window));
  // No gtk_window_set_decorated(FALSE) here: full screen already drops the
  // client-side frame and shadow, and toggling decorations on a CSD window
  // makes GTK3 swap its GdkWindow under FlView's GL context — the next quick
  // hide/show then segfaults creating an EGL surface for the dead one.
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
  // A window that was maximized before the overlay (a big editor that
  // GNOME auto-maximized) would otherwise return to that state.
  gtk_window_unmaximize(state->window);
  gtk_window_set_keep_above(state->window, FALSE);
  gtk_window_set_skip_taskbar_hint(state->window, FALSE);
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
// Screenshot (org.freedesktop.portal.Screenshot — the only capture path
// under Wayland, where there is no XGetImage equivalent). Two round trips:
// the `Screenshot` call itself just registers the request and hands back a
// `Request` object path; the actual result (a PNG written to a temp file)
// arrives later on that object's `Response` signal, since a real desktop
// may show UI first. With `interactive: false` GNOME takes the shot
// immediately — except the very first time, when it shows a one-time
// access dialog (see `requestScreenAccess`).
// ---------------------------------------------------------------------------

constexpr const char* kPortalBus = "org.freedesktop.portal.Desktop";
constexpr const char* kPortalPath = "/org/freedesktop/portal/desktop";

struct PortalScreenshotRequest {
  FlMethodCall* call = nullptr;
  GDBusConnection* bus = nullptr;
  guint signal_id = 0;
  // Only report success/failure (a permission probe), don't send the PNG.
  bool probe = false;
  // The desktop showed its own screenshot UI.
  bool interactive = false;
};

void OnScreenshotResponse(GDBusConnection*, const gchar*, const gchar*,
                          const gchar*, const gchar* signal_name,
                          GVariant* parameters, gpointer user_data) {
  auto* req = static_cast<PortalScreenshotRequest*>(user_data);
  if (g_strcmp0(signal_name, "Response") == 0) {
    guint32 response_code = 1;
    g_autoptr(GVariant) results = nullptr;
    g_variant_get(parameters, "(u@a{sv})", &response_code, &results);

    g_autoptr(FlMethodResponse) response = nullptr;
    if (req->probe) {
      // Still delete the file the portal wrote for us.
      g_autoptr(GVariant) uri_variant =
          results != nullptr
              ? g_variant_lookup_value(results, "uri", G_VARIANT_TYPE_STRING)
              : nullptr;
      if (uri_variant != nullptr) {
        g_autofree gchar* path = g_filename_from_uri(
            g_variant_get_string(uri_variant, nullptr), nullptr, nullptr);
        if (path != nullptr) remove(path);
      }
      g_autoptr(FlValue) granted = fl_value_new_bool(response_code == 0);
      response = FL_METHOD_RESPONSE(fl_method_success_response_new(granted));
    } else if (response_code == 0 && results != nullptr) {
      g_autoptr(GVariant) uri_variant =
          g_variant_lookup_value(results, "uri", G_VARIANT_TYPE_STRING);
      gchar* path = uri_variant != nullptr
                        ? g_filename_from_uri(
                              g_variant_get_string(uri_variant, nullptr),
                              nullptr, nullptr)
                        : nullptr;
      gchar* contents = nullptr;
      gsize length = 0;
      g_autoptr(GError) error = nullptr;
      if (path != nullptr &&
          g_file_get_contents(path, &contents, &length, &error)) {
        g_autoptr(FlValue) bytes = fl_value_new_uint8_list(
            reinterpret_cast<const uint8_t*>(contents), length);
        response = FL_METHOD_RESPONSE(fl_method_success_response_new(bytes));
        g_free(contents);
      } else {
        response = FL_METHOD_RESPONSE(fl_method_error_response_new(
            "capture_failed",
            error ? error->message : "portal returned no screenshot file",
            nullptr));
      }
      if (path != nullptr) {
        remove(path);
        g_free(path);
      }
    } else if (response_code == 1 || req->interactive) {
      // GNOME answers a dismissed screenshot UI with 2 ("other"), not 1
      // ("cancelled") as the spec says; from the user's side it's the same.
      response = FL_METHOD_RESPONSE(
          fl_method_error_response_new("cancelled", "capture cancelled", nullptr));
    } else {
      response = FL_METHOD_RESPONSE(fl_method_error_response_new(
          "capture_failed", "screenshot portal request failed", nullptr));
    }
    fl_method_call_respond(req->call, response, nullptr);
  }

  g_dbus_connection_signal_unsubscribe(req->bus, req->signal_id);
  g_object_unref(req->call);
  delete req;
}

// `interactive` lets the desktop show its own screenshot UI (GNOME: pick
// area / window / screen) and returns whatever the user took with it.
void StartScreenshotPortal(NativeState* state, FlMethodCall* call,
                           bool interactive, bool probe) {
  if (state->session_bus == nullptr) {
    g_autoptr(FlMethodResponse) response = FL_METHOD_RESPONSE(
        fl_method_error_response_new("unsupported", "no session bus", nullptr));
    fl_method_call_respond(call, response, nullptr);
    return;
  }

  static guint token_counter = 0;
  g_autofree gchar* token = g_strdup_printf("shoshot%u", ++token_counter);

  GVariantBuilder options;
  g_variant_builder_init(&options, G_VARIANT_TYPE("a{sv}"));
  g_variant_builder_add(&options, "{sv}", "handle_token",
                        g_variant_new_string(token));
  g_variant_builder_add(&options, "{sv}", "interactive",
                        g_variant_new_boolean(interactive));

  // The Response signal can in principle race the method reply, so subscribe
  // to the path the portal will use *before* calling (the spec'd pattern):
  // /org/freedesktop/portal/desktop/request/<sender>/<token>.
  g_autofree gchar* sender =
      g_strdup(g_dbus_connection_get_unique_name(state->session_bus) + 1);
  for (gchar* c = sender; *c != '\0'; c++) {
    if (*c == '.') *c = '_';
  }
  g_autofree gchar* expected_path = g_strdup_printf(
      "/org/freedesktop/portal/desktop/request/%s/%s", sender, token);
  auto* req = new PortalScreenshotRequest();
  req->call = FL_METHOD_CALL(g_object_ref(call));
  req->bus = state->session_bus;
  req->probe = probe;
  req->interactive = interactive;
  req->signal_id = g_dbus_connection_signal_subscribe(
      state->session_bus, kPortalBus, "org.freedesktop.portal.Request",
      "Response", expected_path, nullptr, G_DBUS_SIGNAL_FLAGS_NONE,
      OnScreenshotResponse, req, nullptr);

  g_autoptr(GError) error = nullptr;
  g_autoptr(GVariant) reply = g_dbus_connection_call_sync(
      state->session_bus, kPortalBus, kPortalPath,
      "org.freedesktop.portal.Screenshot", "Screenshot",
      g_variant_new("(sa{sv})", "", &options), G_VARIANT_TYPE("(o)"),
      G_DBUS_CALL_FLAGS_NONE, 5000, nullptr, &error);

  const gchar* handle_path = nullptr;
  if (reply != nullptr) g_variant_get(reply, "(&o)", &handle_path);
  if (handle_path == nullptr) {
    g_dbus_connection_signal_unsubscribe(state->session_bus, req->signal_id);
    g_object_unref(req->call);
    delete req;
    g_autoptr(FlMethodResponse) response =
        FL_METHOD_RESPONSE(fl_method_error_response_new(
            "capture_failed",
            error ? error->message : "portal Screenshot call failed",
            nullptr));
    fl_method_call_respond(call, response, nullptr);
    return;
  }
  if (g_strcmp0(handle_path, expected_path) != 0) {
    // Very old portals (< 0.9) picked their own path; follow it.
    g_dbus_connection_signal_unsubscribe(state->session_bus, req->signal_id);
    req->signal_id = g_dbus_connection_signal_subscribe(
        state->session_bus, kPortalBus, "org.freedesktop.portal.Request",
        "Response", handle_path, nullptr, G_DBUS_SIGNAL_FLAGS_NONE,
        OnScreenshotResponse, req, nullptr);
  }
}

// ---------------------------------------------------------------------------
// Screenshot permission (Wayland). GNOME asks once per app, and only lets the
// *focused* app show that dialog — so the Dart side asks while the Home
// window is up, before hiding it for a capture. The grant is stored in the
// portal's permission store (table "screenshot", id "screenshot") under our
// registered app ID.
// ---------------------------------------------------------------------------

// "yes", "no", or "" (never asked / unknown).
std::string ScreenshotPermission(NativeState* state) {
  if (state->session_bus == nullptr) return "";
  g_autoptr(GError) error = nullptr;
  g_autoptr(GVariant) reply = g_dbus_connection_call_sync(
      state->session_bus, "org.freedesktop.impl.portal.PermissionStore",
      "/org/freedesktop/impl/portal/PermissionStore",
      "org.freedesktop.impl.portal.PermissionStore", "Lookup",
      g_variant_new("(ss)", "screenshot", "screenshot"),
      G_VARIANT_TYPE("(a{sas}v)"), G_DBUS_CALL_FLAGS_NONE, 1000, nullptr,
      &error);
  if (reply == nullptr) return "";
  g_autoptr(GVariant) apps = g_variant_get_child_value(reply, 0);
  g_autofree const gchar** values = nullptr;
  if (!g_variant_lookup(apps, APPLICATION_ID, "^a&s", &values) ||
      values == nullptr || values[0] == nullptr) {
    return "";
  }
  return values[0];
}

void ForgetScreenshotPermission(NativeState* state) {
  if (state->session_bus == nullptr) return;
  g_autoptr(GVariant) reply = g_dbus_connection_call_sync(
      state->session_bus, "org.freedesktop.impl.portal.PermissionStore",
      "/org/freedesktop/impl/portal/PermissionStore",
      "org.freedesktop.impl.portal.PermissionStore", "DeletePermission",
      g_variant_new("(sss)", "screenshot", "screenshot", APPLICATION_ID),
      nullptr, G_DBUS_CALL_FLAGS_NONE, 1000, nullptr, nullptr);
}

// ---------------------------------------------------------------------------
// Global shortcuts (org.freedesktop.portal.GlobalShortcuts). Wayland gives no
// app a way to grab keys system-wide; instead the app *describes* its
// shortcuts (id + description + preferred trigger) and the desktop binds
// them — GNOME asks the user once, in its own dialog, and may assign a
// different trigger than the one we suggested. Presses come back as the
// `Activated` signal, carrying an XDG activation token that lets the window
// take focus (GNOME otherwise refuses focus to an app the user didn't click).
// ---------------------------------------------------------------------------

// Generic Request/Response round trip, see the Screenshot section above for
// why it's two steps.
struct PortalRequest {
  GDBusConnection* bus = nullptr;
  guint signal_id = 0;
  std::function<void(guint32 code, GVariant* results)> done;
};

void OnPortalRequestResponse(GDBusConnection*, const gchar*, const gchar*,
                             const gchar*, const gchar*, GVariant* parameters,
                             gpointer user_data) {
  auto* req = static_cast<PortalRequest*>(user_data);
  guint32 code = 2;
  g_autoptr(GVariant) results = nullptr;
  g_variant_get(parameters, "(u@a{sv})", &code, &results);
  g_dbus_connection_signal_unsubscribe(req->bus, req->signal_id);
  auto done = std::move(req->done);
  delete req;
  done(code, results);
}

std::string NewPortalToken() {
  static guint counter = 0;
  return "shoshot_" + std::to_string(++counter);
}

std::string PortalRequestPath(GDBusConnection* bus, const std::string& token) {
  std::string sender = g_dbus_connection_get_unique_name(bus) + 1;
  for (auto& c : sender) {
    if (c == '.') c = '_';
  }
  return "/org/freedesktop/portal/desktop/request/" + sender + "/" + token;
}

// Calls `method`, whose options dict must carry `handle_token = token`, and
// runs `done` with the Response (code 0 = success, 1 = user cancelled,
// 2 = other failure — also used here when the call itself errors).
// `params` is a floating GVariant and is consumed.
void CallPortalRequest(NativeState* state, const char* iface,
                       const char* method, GVariant* params,
                       const std::string& token,
                       std::function<void(guint32, GVariant*)> done) {
  auto* req = new PortalRequest();
  req->bus = state->session_bus;
  req->done = std::move(done);
  const std::string expected = PortalRequestPath(state->session_bus, token);
  req->signal_id = g_dbus_connection_signal_subscribe(
      state->session_bus, kPortalBus, "org.freedesktop.portal.Request",
      "Response", expected.c_str(), nullptr, G_DBUS_SIGNAL_FLAGS_NONE,
      OnPortalRequestResponse, req, nullptr);
  g_autoptr(GError) error = nullptr;
  g_autoptr(GVariant) reply = g_dbus_connection_call_sync(
      state->session_bus, kPortalBus, kPortalPath, iface, method, params,
      G_VARIANT_TYPE("(o)"), G_DBUS_CALL_FLAGS_NONE, 5000, nullptr, &error);
  if (reply == nullptr) {
    g_warning("Show Shot: %s.%s failed: %s", iface, method,
              error ? error->message : "unknown error");
    g_dbus_connection_signal_unsubscribe(state->session_bus, req->signal_id);
    auto failed = std::move(req->done);
    delete req;
    failed(2, nullptr);
    return;
  }
  const gchar* handle = nullptr;
  g_variant_get(reply, "(&o)", &handle);
  if (g_strcmp0(handle, expected.c_str()) != 0) {
    // Very old portals pick their own request path; follow it.
    g_dbus_connection_signal_unsubscribe(state->session_bus, req->signal_id);
    req->signal_id = g_dbus_connection_signal_subscribe(
        state->session_bus, kPortalBus, "org.freedesktop.portal.Request",
        "Response", handle, nullptr, G_DBUS_SIGNAL_FLAGS_NONE,
        OnPortalRequestResponse, req, nullptr);
  }
}

bool HasGlobalShortcutsPortal(NativeState* state) {
  static int cached = -1;
  if (cached >= 0) return cached == 1;
  cached = 0;
  if (!IsWayland() || state->session_bus == nullptr) return false;
  g_autoptr(GVariant) reply = g_dbus_connection_call_sync(
      state->session_bus, kPortalBus, kPortalPath,
      "org.freedesktop.DBus.Properties", "Get",
      g_variant_new("(ss)", "org.freedesktop.portal.GlobalShortcuts",
                    "version"),
      G_VARIANT_TYPE("(v)"), G_DBUS_CALL_FLAGS_NONE, 1000, nullptr, nullptr);
  cached = reply != nullptr ? 1 : 0;
  return cached == 1;
}

// a(sa{sv}) → [{id, trigger, description}]
FlValue* ShortcutsToFl(GVariant* shortcuts) {
  FlValue* list = fl_value_new_list();
  if (shortcuts == nullptr) return list;
  GVariantIter iter;
  g_variant_iter_init(&iter, shortcuts);
  const gchar* id = nullptr;
  GVariant* props = nullptr;
  while (g_variant_iter_next(&iter, "(&s@a{sv})", &id, &props)) {
    const gchar* trigger = "";
    const gchar* description = "";
    g_variant_lookup(props, "trigger_description", "&s", &trigger);
    g_variant_lookup(props, "description", "&s", &description);
    FlValue* map = fl_value_new_map();
    fl_value_set_string_take(map, "id", fl_value_new_string(id));
    fl_value_set_string_take(map, "trigger", fl_value_new_string(trigger));
    fl_value_set_string_take(map, "description",
                             fl_value_new_string(description));
    fl_value_append_take(list, map);
    g_variant_unref(props);
  }
  return list;
}

void OnGlobalShortcutSignal(GDBusConnection*, const gchar*, const gchar*,
                            const gchar*, const gchar* signal_name,
                            GVariant* parameters, gpointer user_data) {
  auto* state = static_cast<NativeState*>(user_data);
  if (g_strcmp0(signal_name, "Activated") == 0) {
    const gchar* session = nullptr;
    const gchar* id = nullptr;
    guint64 timestamp = 0;
    g_autoptr(GVariant) options = nullptr;
    g_variant_get(parameters, "(&o&st@a{sv})", &session, &id, &timestamp,
                  &options);
    if (state->shortcuts_session != session) return;
#ifdef GDK_WINDOWING_WAYLAND
    // Hand the token to GDK so the next gtk_window_present() (the overlay
    // or Home coming up) is allowed to take focus.
    const gchar* token = nullptr;
    if (IsWayland() &&
        g_variant_lookup(options, "activation_token", "&s", &token)) {
      gdk_wayland_display_set_startup_notification_id(
          gdk_display_get_default(), token);
    }
#endif
    g_autoptr(FlValue) value = fl_value_new_string(id);
    fl_method_channel_invoke_method(state->channel, "globalShortcutActivated",
                                    value, nullptr, nullptr, nullptr);
  } else if (g_strcmp0(signal_name, "ShortcutsChanged") == 0) {
    const gchar* session = nullptr;
    g_autoptr(GVariant) shortcuts = nullptr;
    g_variant_get(parameters, "(&o@a(sa{sv}))", &session, &shortcuts);
    if (state->shortcuts_session != session) return;
    g_autoptr(FlValue) list = ShortcutsToFl(shortcuts);
    fl_method_channel_invoke_method(state->channel, "globalShortcutsChanged",
                                    list, nullptr, nullptr, nullptr);
  }
}

void RespondPortalFailure(FlMethodCall* call, guint32 code,
                          const char* what) {
  g_autoptr(FlMethodResponse) response = FL_METHOD_RESPONSE(
      fl_method_error_response_new(code == 1 ? "cancelled" : "failed", what,
                                   nullptr));
  fl_method_call_respond(call, response, nullptr);
}

// `shortcuts` is a(sa{sv}), owned (sunk) by the caller; `call` is ref'd.
void BindShortcutsInSession(NativeState* state, FlMethodCall* call,
                            GVariant* shortcuts) {
  const std::string token = NewPortalToken();
  GVariantBuilder options;
  g_variant_builder_init(&options, G_VARIANT_TYPE_VARDICT);
  g_variant_builder_add(&options, "{sv}", "handle_token",
                        g_variant_new_string(token.c_str()));
  CallPortalRequest(
      state, "org.freedesktop.portal.GlobalShortcuts", "BindShortcuts",
      g_variant_new("(o@a(sa{sv})sa{sv})", state->shortcuts_session.c_str(),
                    shortcuts, "", &options),
      token, [call](guint32 code, GVariant* results) {
        if (code != 0) {
          RespondPortalFailure(call, code, "BindShortcuts failed");
        } else {
          g_autoptr(GVariant) bound =
              results != nullptr
                  ? g_variant_lookup_value(results, "shortcuts",
                                           G_VARIANT_TYPE("a(sa{sv})"))
                  : nullptr;
          g_autoptr(FlValue) list = ShortcutsToFl(bound);
          g_autoptr(FlMethodResponse) response =
              FL_METHOD_RESPONSE(fl_method_success_response_new(list));
          fl_method_call_respond(call, response, nullptr);
        }
        g_object_unref(call);
      });
}

// args: {shortcuts: [{id, description, trigger}]}, `trigger` in the XDG
// shortcuts format ("CTRL+SHIFT+1") — only a preference, see above.
void StartBindGlobalShortcuts(NativeState* state, FlMethodCall* call,
                              FlValue* args) {
  if (!HasGlobalShortcutsPortal(state)) {
    RespondPortalFailure(call, 2, "GlobalShortcuts portal unavailable");
    return;
  }
  GVariantBuilder list;
  g_variant_builder_init(&list, G_VARIANT_TYPE("a(sa{sv})"));
  FlValue* items =
      args != nullptr && fl_value_get_type(args) == FL_VALUE_TYPE_MAP
          ? fl_value_lookup_string(args, "shortcuts")
          : nullptr;
  if (items != nullptr && fl_value_get_type(items) == FL_VALUE_TYPE_LIST) {
    for (size_t i = 0; i < fl_value_get_length(items); i++) {
      FlValue* item = fl_value_get_list_value(items, i);
      const std::string id = ArgString(item, "id");
      if (id.empty()) continue;
      GVariantBuilder props;
      g_variant_builder_init(&props, G_VARIANT_TYPE_VARDICT);
      g_variant_builder_add(
          &props, "{sv}", "description",
          g_variant_new_string(ArgString(item, "description").c_str()));
      const std::string trigger = ArgString(item, "trigger");
      if (!trigger.empty()) {
        g_variant_builder_add(&props, "{sv}", "preferred_trigger",
                              g_variant_new_string(trigger.c_str()));
      }
      g_variant_builder_add(&list, "(sa{sv})", id.c_str(), &props);
    }
  }
  GVariant* shortcuts = g_variant_ref_sink(g_variant_builder_end(&list));
  call = FL_METHOD_CALL(g_object_ref(call));

  // GNOME accepts a single BindShortcuts per session ("Session already has
  // bound shortcuts"), so changing them means starting a fresh session.
  if (!state->shortcuts_session.empty()) {
    g_autoptr(GVariant) closed = g_dbus_connection_call_sync(
        state->session_bus, kPortalBus, state->shortcuts_session.c_str(),
        "org.freedesktop.portal.Session", "Close", nullptr, nullptr,
        G_DBUS_CALL_FLAGS_NONE, 1000, nullptr, nullptr);
    state->shortcuts_session.clear();
  }

  const std::string token = NewPortalToken();
  GVariantBuilder options;
  g_variant_builder_init(&options, G_VARIANT_TYPE_VARDICT);
  g_variant_builder_add(&options, "{sv}", "handle_token",
                        g_variant_new_string(token.c_str()));
  g_variant_builder_add(&options, "{sv}", "session_handle_token",
                        g_variant_new_string(NewPortalToken().c_str()));
  CallPortalRequest(
      state, "org.freedesktop.portal.GlobalShortcuts", "CreateSession",
      g_variant_new("(a{sv})", &options), token,
      [state, call, shortcuts](guint32 code, GVariant* results) {
        // The spec says `s`; some implementations send an object path.
        g_autoptr(GVariant) handle =
            code == 0 && results != nullptr
                ? g_variant_lookup_value(results, "session_handle", nullptr)
                : nullptr;
        const gchar* session =
            handle != nullptr &&
                    (g_variant_is_of_type(handle, G_VARIANT_TYPE_STRING) ||
                     g_variant_is_of_type(handle, G_VARIANT_TYPE_OBJECT_PATH))
                ? g_variant_get_string(handle, nullptr)
                : nullptr;
        if (session == nullptr) {
          RespondPortalFailure(call, code, "CreateSession failed");
          g_object_unref(call);
        } else {
          state->shortcuts_session = session;
          if (state->shortcuts_activated_id == 0) {
            state->shortcuts_activated_id = g_dbus_connection_signal_subscribe(
                state->session_bus, kPortalBus,
                "org.freedesktop.portal.GlobalShortcuts", "Activated",
                kPortalPath, nullptr, G_DBUS_SIGNAL_FLAGS_NONE,
                OnGlobalShortcutSignal, state, nullptr);
            state->shortcuts_changed_id = g_dbus_connection_signal_subscribe(
                state->session_bus, kPortalBus,
                "org.freedesktop.portal.GlobalShortcuts", "ShortcutsChanged",
                kPortalPath, nullptr, G_DBUS_SIGNAL_FLAGS_NONE,
                OnGlobalShortcutSignal, state, nullptr);
          }
          BindShortcutsInSession(state, call, shortcuts);
        }
        g_variant_unref(shortcuts);
      });
}

// Opens the desktop's own UI for changing our shortcuts (portal v2). False
// when unsupported, so Dart can fall back to the system keyboard settings.
bool ConfigureGlobalShortcuts(NativeState* state) {
  if (state->shortcuts_session.empty()) return false;
  GVariantBuilder options;
  g_variant_builder_init(&options, G_VARIANT_TYPE_VARDICT);
  g_autoptr(GError) error = nullptr;
  g_autoptr(GVariant) reply = g_dbus_connection_call_sync(
      state->session_bus, kPortalBus, kPortalPath,
      "org.freedesktop.portal.GlobalShortcuts", "ConfigureShortcuts",
      g_variant_new("(osa{sv})", state->shortcuts_session.c_str(), "",
                    &options),
      nullptr, G_DBUS_CALL_FLAGS_NONE, 5000, nullptr, &error);
  if (reply == nullptr) {
    g_message("Show Shot: ConfigureShortcuts unavailable (%s)",
              error ? error->message : "unknown error");
  }
  return reply != nullptr;
}

// ---------------------------------------------------------------------------
// Notifications (org.freedesktop.Notifications over the session bus)
// ---------------------------------------------------------------------------

void OnNotifyDone(GObject* source, GAsyncResult* res, gpointer user_data) {
  FlMethodCall* call = FL_METHOD_CALL(user_data);
  GError* error = nullptr;
  GVariant* reply =
      g_dbus_connection_call_finish(G_DBUS_CONNECTION(source), res, &error);
  bool ok = reply != nullptr;
  if (reply != nullptr) g_variant_unref(reply);
  if (error != nullptr) g_error_free(error);
  g_autoptr(FlValue) value = fl_value_new_bool(ok);
  g_autoptr(FlMethodResponse) response =
      FL_METHOD_RESPONSE(fl_method_success_response_new(value));
  fl_method_call_respond(call, response, nullptr);
  g_object_unref(call);
}

// Sends the notification and answers `call` (true when a notification daemon
// accepted it) from the D-Bus reply, so Dart can fall back to an in-app toast.
void ShowNotification(NativeState* state, FlMethodCall* call,
                      const std::string& title, const std::string& body) {
  if (state->session_bus == nullptr) {
    g_autoptr(FlValue) value = fl_value_new_bool(false);
    g_autoptr(FlMethodResponse) response =
        FL_METHOD_RESPONSE(fl_method_success_response_new(value));
    fl_method_call_respond(call, response, nullptr);
    return;
  }
  GVariantBuilder actions;
  g_variant_builder_init(&actions, G_VARIANT_TYPE("as"));
  GVariantBuilder hints;
  g_variant_builder_init(&hints, G_VARIANT_TYPE("a{sv}"));
  g_dbus_connection_call(
      state->session_bus, "org.freedesktop.Notifications",
      "/org/freedesktop/Notifications", "org.freedesktop.Notifications",
      "Notify",
      g_variant_new("(susssasa{sv}i)", "Show Shot", 0u, APPLICATION_ID,
                    title.c_str(), body.c_str(), &actions, &hints, 5000),
      G_VARIANT_TYPE("(u)"), G_DBUS_CALL_FLAGS_NONE, 2000, nullptr,
      OnNotifyDone, g_object_ref(call));
}

// ---------------------------------------------------------------------------
// Window frame. GTK draws the rounded corners (client-side decorations, see
// my_application.cc) only for a free-floating window; maximized, full screen
// or tiled windows are square, like every other GNOME app. Dart clips its
// content to match, so it needs to know which one applies.
// ---------------------------------------------------------------------------

bool WindowRounded(NativeState* state) {
  GdkWindow* gdk_window = gtk_widget_get_window(GTK_WIDGET(state->window));
  if (gdk_window == nullptr) return true;
  const GdkWindowState square =
      (GdkWindowState)(GDK_WINDOW_STATE_MAXIMIZED |
                       GDK_WINDOW_STATE_FULLSCREEN | GDK_WINDOW_STATE_TILED |
                       GDK_WINDOW_STATE_TOP_TILED |
                       GDK_WINDOW_STATE_RIGHT_TILED |
                       GDK_WINDOW_STATE_BOTTOM_TILED |
                       GDK_WINDOW_STATE_LEFT_TILED);
  return (gdk_window_get_state(gdk_window) & square) == 0 &&
         gtk_window_get_decorated(state->window);
}

gboolean OnWindowStateEvent(GtkWidget*, GdkEventWindowState*,
                            gpointer user_data) {
  auto* state = static_cast<NativeState*>(user_data);
  const bool rounded = WindowRounded(state);
  if (rounded != state->last_rounded) {
    state->last_rounded = rounded;
    g_autoptr(FlValue) value = fl_value_new_bool(rounded);
    fl_method_channel_invoke_method(state->channel, "windowRoundedChanged",
                                    value, nullptr, nullptr, nullptr);
  }
  return FALSE;
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
    // Wayland: the screenshot portal needs a one-time grant (see
    // ScreenshotPermission); X11 can read the root window freely.
    fl_value_set_string_take(map, "needsScreenPermission",
                             fl_value_new_bool(IsWayland()));
    fl_value_set_string_take(map, "wayland", fl_value_new_bool(IsWayland()));
    fl_value_set_string_take(map, "globalShortcutsPortal",
                             fl_value_new_bool(HasGlobalShortcutsPortal(state)));
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
  } else if (strcmp(method, "captureScreenshotPortal") == 0) {
    FlValue* interactive =
        args != nullptr && fl_value_get_type(args) == FL_VALUE_TYPE_MAP
            ? fl_value_lookup_string(args, "interactive")
            : nullptr;
    StartScreenshotPortal(
        state, call,
        interactive != nullptr &&
            fl_value_get_type(interactive) == FL_VALUE_TYPE_BOOL &&
            fl_value_get_bool(interactive),
        false);
    return;  // Responds asynchronously once the portal's Response arrives.
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
  } else if (strcmp(method, "hideWindow") == 0) {
    // Hiding destroys the window's wl_surface. FlView's draw handler can
    // block waiting for a correctly sized frame, and while it waits it runs
    // Flutter's platform tasks — including this very method call. Hiding
    // there pulls the surface out from under the draw in progress (segfault
    // in wl_proxy_get_version, traced from a core dump). That wait doesn't
    // iterate the GLib main loop, so hiding from an idle callback is always
    // outside any draw.
    g_idle_add(
        [](gpointer data) -> gboolean {
          auto* call = FL_METHOD_CALL(data);
          gtk_widget_hide(GTK_WIDGET(g_state->window));
          g_autoptr(FlMethodResponse) response =
              FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
          fl_method_call_respond(call, response, nullptr);
          g_object_unref(call);
          return G_SOURCE_REMOVE;
        },
        g_object_ref(call));
    return;
  } else if (strcmp(method, "setClipboardImage") == 0) {
    bool ok = SetClipboardImage(ArgBytes(args, "rgba"),
                                (int)ArgInt(args, "width", 0),
                                (int)ArgInt(args, "height", 0));
    g_autoptr(FlValue) v = fl_value_new_bool(ok);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(v));
  } else if (strcmp(method, "hasScreenAccess") == 0) {
    g_autoptr(FlValue) v =
        fl_value_new_bool(!IsWayland() || ScreenshotPermission(state) == "yes");
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(v));
  } else if (strcmp(method, "requestScreenAccess") == 0) {
    if (!IsWayland()) {
      g_autoptr(FlValue) v = fl_value_new_bool(true);
      response = FL_METHOD_RESPONSE(fl_method_success_response_new(v));
    } else {
      // A remembered "no" makes the portal fail silently forever; when the
      // user explicitly asks again, forget it so GNOME shows the dialog.
      FlValue* reset =
          args != nullptr && fl_value_get_type(args) == FL_VALUE_TYPE_MAP
              ? fl_value_lookup_string(args, "reset")
              : nullptr;
      if (reset != nullptr && fl_value_get_type(reset) == FL_VALUE_TYPE_BOOL &&
          fl_value_get_bool(reset) && ScreenshotPermission(state) == "no") {
        ForgetScreenshotPermission(state);
      }
      StartScreenshotPortal(state, call, false, true);
      return;  // Responds once the user answered the access dialog.
    }
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
  } else if (strcmp(method, "bindGlobalShortcuts") == 0) {
    StartBindGlobalShortcuts(state, call, args);
    return;  // Responds once the desktop answered (may show a dialog first).
  } else if (strcmp(method, "configureGlobalShortcuts") == 0) {
    g_autoptr(FlValue) v = fl_value_new_bool(ConfigureGlobalShortcuts(state));
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(v));
  } else if (strcmp(method, "notify") == 0) {
    ShowNotification(state, call, ArgString(args, "title"),
                     ArgString(args, "body"));
    return;  // answered from OnNotifyDone
  } else if (strcmp(method, "windowRounded") == 0) {
    g_autoptr(FlValue) v = fl_value_new_bool(WindowRounded(state));
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(v));
  } else if (strcmp(method, "getSystemAccent") == 0) {
    g_autoptr(FlValue) v = fl_value_new_int(state->last_accent_argb);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(v));
  } else {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }

  fl_method_call_respond(call, response, nullptr);
}

}  // namespace

void shoshot_register_host_app_id(const char* app_id) {
  // Sandboxed builds (Flatpak/Snap) get their app ID from the sandbox; the
  // portal rejects this call there, so don't bother.
  if (g_file_test("/.flatpak-info", G_FILE_TEST_EXISTS) ||
      g_getenv("SNAP") != nullptr) {
    return;
  }
  g_autoptr(GError) error = nullptr;
  g_autoptr(GDBusConnection) bus =
      g_bus_get_sync(G_BUS_TYPE_SESSION, nullptr, &error);
  if (bus == nullptr) return;
  GVariantBuilder options;
  g_variant_builder_init(&options, G_VARIANT_TYPE_VARDICT);
  g_autoptr(GVariant) reply = g_dbus_connection_call_sync(
      bus, "org.freedesktop.portal.Desktop", "/org/freedesktop/portal/desktop",
      "org.freedesktop.host.portal.Registry", "Register",
      g_variant_new("(sa{sv})", app_id, &options), nullptr,
      G_DBUS_CALL_FLAGS_NONE, 2000, nullptr, &error);
  if (reply == nullptr) {
    // Older portals (< 1.19) have no registry: permissions then get keyed by
    // whatever the portal infers (systemd scope), which still works, just
    // less predictably.
    g_message("Show Shot: portal app-id registration unavailable (%s)",
              error ? error->message : "unknown error");
  }
}

void shoshot_native_app_reactivated() {
  if (g_state == nullptr) return;
  fl_method_channel_invoke_method(g_state->channel, "appReactivated", nullptr,
                                  nullptr, nullptr, nullptr);
}

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
  g_signal_connect(window, "window-state-event",
                   G_CALLBACK(OnWindowStateEvent), g_state);
}
