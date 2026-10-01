#include "my_application.h"

#include <flutter_linux/flutter_linux.h>
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif
#ifdef GDK_WINDOWING_WAYLAND
#include <gdk/gdkwayland.h>
#endif

#include "flutter/generated_plugin_registrant.h"
#include "shoshot_native.h"

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

// True when started by the launch-at-login entry (`--autostart`, see
// StartupService.launchArg in Dart) or with `--hidden`.
static gboolean starts_hidden(MyApplication* self) {
  if (self->dart_entrypoint_arguments == nullptr) return FALSE;
  for (char** arg = self->dart_entrypoint_arguments; *arg != nullptr; ++arg) {
    if (g_strcmp0(*arg, "--autostart") == 0 ||
        g_strcmp0(*arg, "--hidden") == 0) {
      return TRUE;
    }
  }
  return FALSE;
}

// GTK3 on Wayland can deliver a draw to the window while it has no
// wl_surface — right after it was hidden, or while it's being shown again
// (GTK destroys the surface on hide and recreates it on show). FlView then
// creates its EGL surface on a null wl_surface and segfaults in
// wl_proxy_get_version; easy to hit by hiding/showing in quick succession
// (backtraced from a core dump). There's nothing to paint at that point, so
// drop those draws before they reach FlView; the next frame repaints.
static gboolean skip_draw_without_surface(GtkWidget* widget, cairo_t*,
                                          gpointer) {
  GdkWindow* gdk_window = gtk_widget_get_window(widget);
  if (!gtk_widget_get_mapped(widget) || gdk_window == nullptr ||
      !gdk_window_is_visible(gdk_window)) {
    return TRUE;
  }
#ifdef GDK_WINDOWING_WAYLAND
  if (GDK_IS_WAYLAND_WINDOW(gdk_window) &&
      gdk_wayland_window_get_wl_surface(gdk_window) == nullptr) {
    return TRUE;
  }
#endif
  return FALSE;
}

static void guard_renderer_draws(GtkWidget* widget) {
  if (g_strcmp0(G_OBJECT_TYPE_NAME(widget), "FlViewRenderer") == 0) {
    g_signal_connect(widget, "draw", G_CALLBACK(skip_draw_without_surface),
                     nullptr);
    return;
  }
  if (GTK_IS_CONTAINER(widget)) {
    gtk_container_forall(
        GTK_CONTAINER(widget),
        [](GtkWidget* child, gpointer) { guard_renderer_draws(child); },
        nullptr);
  }
}

// Called when first Flutter frame received.
static void first_frame_cb(MyApplication* self, FlView* view) {
  // Silent start: stay in the tray. On a normal start the Dart side shows the
  // window itself (window_manager), so this only changes the hidden case.
  if (starts_hidden(self)) return;
  gtk_widget_show(gtk_widget_get_toplevel(GTK_WIDGET(view)));
}

// Implements GApplication::activate.
static void my_application_activate(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);
  GtkWindow* window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(application)));

  // Use a header bar when running in GNOME as this is the common style used
  // by applications and is the setup most users will be using (e.g. Ubuntu
  // desktop).
  // If running on X and not using GNOME then just use a traditional title bar
  // in case the window manager does more exotic layout, e.g. tiling.
  // If running on Wayland assume the header bar will work (may need changing
  // if future cases occur).
  // Show Shot draws its own window chrome, so never install a GTK header bar.
  gboolean use_header_bar = FALSE;
#ifdef GDK_WINDOWING_X11
  GdkScreen* screen = gtk_window_get_screen(window);
  if (GDK_IS_X11_SCREEN(screen)) {
    const gchar* wm_name = gdk_x11_screen_get_window_manager_name(screen);
    if (g_strcmp0(wm_name, "GNOME Shell") != 0) {
      use_header_bar = FALSE;
    }
  }
#endif
  if (use_header_bar) {
    GtkHeaderBar* header_bar = GTK_HEADER_BAR(gtk_header_bar_new());
    gtk_widget_show(GTK_WIDGET(header_bar));
    gtk_header_bar_set_title(header_bar, "Show Shot");
    gtk_header_bar_set_show_close_button(header_bar, TRUE);
    gtk_window_set_titlebar(window, GTK_WIDGET(header_bar));
  } else {
    gtk_window_set_title(window, "Show Shot");
  }

  // GNOME windows get their rounded corners, shadow and resize edges from
  // GTK's client-side decorations, not from the compositor (unlike macOS and
  // Windows 11). Flutter draws its own title bar, so give GTK an empty,
  // never-shown titlebar: that keeps CSD on without adding a GTK title bar.
  // The Dart side clips its content to the same radius (`windowRounded`).
  GtkWidget* no_titlebar = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 0);
  gtk_window_set_titlebar(window, no_titlebar);
  g_autoptr(GtkCssProvider) css = gtk_css_provider_new();
  gtk_css_provider_load_from_data(
      css,
      "window.csd, window.csd decoration { border-radius: 12px; }"
      "window.csd { background-color: transparent; }",
      -1, nullptr);
  gtk_style_context_add_provider_for_screen(
      gtk_window_get_screen(window), GTK_STYLE_PROVIDER(css),
      GTK_STYLE_PROVIDER_PRIORITY_APPLICATION);

  g_signal_connect(window, "draw", G_CALLBACK(skip_draw_without_surface),
                   nullptr);

  gtk_window_set_default_size(window, 960, 640);
  gtk_window_set_position(window, GTK_WIN_POS_CENTER);

  g_autoptr(FlDartProject) project = fl_dart_project_new();
  fl_dart_project_set_dart_entrypoint_arguments(
      project, self->dart_entrypoint_arguments);

  FlView* view = fl_view_new(project);
  GdkRGBA background_color;
  // Background defaults to black, override it here if necessary, e.g. #00000000
  // for transparent.
  // Transparent, so the rounded corners Flutter leaves empty show the
  // desktop (see the CSD note above).
  gdk_rgba_parse(&background_color, "#00000000");
  fl_view_set_background_color(view, &background_color);
  gtk_widget_show(GTK_WIDGET(view));
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));
  // The GL drawing itself happens in FlView's internal FlViewRenderer
  // widget, which can have its own GdkWindow (a Wayland subsurface with its
  // own wl_surface) — guard that one too.
  guard_renderer_draws(GTK_WIDGET(view));

  // Show the window when Flutter renders.
  // Requires the view to be realized so we can start rendering.
  g_signal_connect_swapped(view, "first-frame", G_CALLBACK(first_frame_cb),
                           self);
  gtk_widget_realize(GTK_WIDGET(view));

  fl_register_plugins(FL_PLUGIN_REGISTRY(view));
  shoshot_native_register(window, view);

  gtk_widget_grab_focus(GTK_WIDGET(view));
}

// Implements GApplication::local_command_line.
static gboolean my_application_local_command_line(GApplication* application,
                                                  gchar*** arguments,
                                                  int* exit_status) {
  MyApplication* self = MY_APPLICATION(application);
  // Strip out the first argument as it is the binary name.
  self->dart_entrypoint_arguments = g_strdupv(*arguments + 1);

  g_autoptr(GError) error = nullptr;
  if (!g_application_register(application, nullptr, &error)) {
    g_warning("Failed to register: %s", error->message);
    *exit_status = 1;
    return TRUE;
  }

  g_application_activate(application);
  *exit_status = 0;

  return TRUE;
}

// Implements GApplication::startup.
static void my_application_startup(GApplication* application) {
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application startup.

  G_APPLICATION_CLASS(my_application_parent_class)->startup(application);
}

// Implements GApplication::shutdown.
static void my_application_shutdown(GApplication* application) {
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application shutdown.

  G_APPLICATION_CLASS(my_application_parent_class)->shutdown(application);
}

// Implements GObject::dispose.
static void my_application_dispose(GObject* object) {
  MyApplication* self = MY_APPLICATION(object);
  g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
  G_OBJECT_CLASS(my_application_parent_class)->dispose(object);
}

static void my_application_class_init(MyApplicationClass* klass) {
  G_APPLICATION_CLASS(klass)->activate = my_application_activate;
  G_APPLICATION_CLASS(klass)->local_command_line =
      my_application_local_command_line;
  G_APPLICATION_CLASS(klass)->startup = my_application_startup;
  G_APPLICATION_CLASS(klass)->shutdown = my_application_shutdown;
  G_OBJECT_CLASS(klass)->dispose = my_application_dispose;
}

static void my_application_init(MyApplication* self) {}

MyApplication* my_application_new() {
  // Set the program name to the application ID, which helps various systems
  // like GTK and desktop environments map this running application to its
  // corresponding .desktop file. This ensures better integration by allowing
  // the application to be recognized beyond its binary name.
  g_set_prgname(APPLICATION_ID);

  return MY_APPLICATION(g_object_new(my_application_get_type(),
                                     "application-id", APPLICATION_ID, "flags",
                                     G_APPLICATION_NON_UNIQUE, nullptr));
}
