#!/usr/bin/env python3
"""Screenshot of the whole desktop through org.freedesktop.portal.Screenshot,
to *see* the screen from a shell on Wayland (where no CLI tool can capture).

    tool/linux/portal_screenshot.py out.png [downscale]

The first run asks GNOME for permission (keyed on the calling app's id —
when run from a terminal, the terminal's), so someone has to click Allow.
"""
import os
import shutil
import sys
import urllib.parse

import gi

gi.require_version('Gio', '2.0')
from gi.repository import Gio, GLib  # noqa: E402

out = sys.argv[1]
downscale = int(sys.argv[2]) if len(sys.argv) > 2 else 1
bus = Gio.bus_get_sync(Gio.BusType.SESSION)
loop = GLib.MainLoop()
token = f'shoshot_tool_{os.getpid()}'
sender = bus.get_unique_name()[1:].replace('.', '_')
request = f'/org/freedesktop/portal/desktop/request/{sender}/{token}'
result = {}


def on_response(_conn, _sender, _path, _iface, _signal, params):
    result['code'], result['results'] = params.unpack()
    loop.quit()


bus.signal_subscribe('org.freedesktop.portal.Desktop',
                     'org.freedesktop.portal.Request', 'Response', request,
                     None, 0, on_response)
bus.call_sync('org.freedesktop.portal.Desktop', '/org/freedesktop/portal/desktop',
              'org.freedesktop.portal.Screenshot', 'Screenshot',
              GLib.Variant('(sa{sv})', ('', {
                  'handle_token': GLib.Variant('s', token),
                  'interactive': GLib.Variant('b', False),
              })), None, 0, 5000, None)
GLib.timeout_add_seconds(15, loop.quit)
loop.run()
if result.get('code') != 0:
    sys.exit(f'screenshot failed: {result}')
source = urllib.parse.unquote(result['results']['uri'][len('file://'):])
if downscale > 1:
    from PIL import Image
    image = Image.open(source)
    image.resize((image.width // downscale, image.height // downscale)).save(out)
    os.remove(source)
else:
    shutil.move(source, out)
print(out)
