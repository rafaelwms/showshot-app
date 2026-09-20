#ifndef RUNNER_SHOSHOT_NATIVE_H_
#define RUNNER_SHOSHOT_NATIVE_H_

#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>

// Native bridge for ShoShot (Linux).
//
// Exposes screen capture (X11), display/window enumeration, clipboard and
// overlay window management to Dart through the `shoshot/native` method
// channel. On Wayland sessions native capture and window listing are not
// available; the Dart side falls back to portal/CLI tools.
//
// Coordinate system: every global coordinate returned here is in physical
// pixels (the X11 root window space). Each display reports its GDK scale
// factor; the Flutter logical size of the overlay window is
// `physical / scale`.
void shoshot_native_register(GtkWindow* window, FlView* view);

#endif  // RUNNER_SHOSHOT_NATIVE_H_
