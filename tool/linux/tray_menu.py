#!/usr/bin/env python3
"""Lists Show Shot's tray menu, or clicks an item, over D-Bus (dbusmenu) —
the same event GNOME's AppIndicator extension sends on a real click.

    tool/linux/tray_menu.py            # list items
    tool/linux/tray_menu.py "Área"     # click the first item containing it
"""
import subprocess
import sys
import time

import gi

gi.require_version('Gio', '2.0')
from gi.repository import Gio, GLib  # noqa: E402

bus = Gio.bus_get_sync(Gio.BusType.SESSION)
names = bus.call_sync('org.freedesktop.DBus', '/org/freedesktop/DBus',
                      'org.freedesktop.DBus', 'ListNames', None, None, 0, 3000,
                      None).unpack()[0]
item = None
for name in names:
    if not name.startswith('org.kde.StatusNotifierItem-'):
        continue
    pid = int(name.split('-')[1])
    try:
        comm = open(f'/proc/{pid}/comm').read().strip()
    except OSError:
        continue
    if comm == 'shoshot':
        item = name
        break
if item is None:
    sys.exit('Show Shot tray item not found (is the app running?)')

path = '/StatusNotifierItem/Menu'
layout = bus.call_sync(item, path, 'com.canonical.dbusmenu', 'GetLayout',
                       GLib.Variant('(iias)', (0, -1, [])), None, 0, 3000,
                       None).unpack()[1]
entries = [(child[0], child[1].get('label', '')) for child in layout[2]]
if len(sys.argv) < 2:
    for entry_id, label in entries:
        print(entry_id, label or '—')
    sys.exit()
entry_id = next(i for i, label in entries if sys.argv[1] in label)
bus.call_sync(item, path, 'com.canonical.dbusmenu', 'Event',
              GLib.Variant('(isvu)', (entry_id, 'clicked', GLib.Variant('i', 0),
                                      int(time.time()))), None, 0, 3000, None)
print('clicked', entry_id)
