import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:shoshot/services/hotkey_service.dart';

void main() {
  group(
    'xdgTrigger (preferred trigger sent to the GlobalShortcuts portal)',
    () {
      test('modifiers + digit', () {
        final hotKey = HotKey(
          key: PhysicalKeyboardKey.digit1,
          modifiers: [HotKeyModifier.control, HotKeyModifier.shift],
        );
        expect(xdgTrigger(hotKey), 'CTRL+SHIFT+1');
      });

      test('named keys use xkb keysym names', () {
        expect(
          xdgTrigger(HotKey(key: PhysicalKeyboardKey.printScreen)),
          'Print',
        );
        expect(
          xdgTrigger(
            HotKey(
              key: PhysicalKeyboardKey.keyS,
              modifiers: [HotKeyModifier.meta, HotKeyModifier.alt],
            ),
          ),
          'LOGO+ALT+s',
        );
      });
    },
  );

  group('prettyPortalTrigger (GNOME trigger_description → app label)', () {
    test('strips the localized sentence and orders modifiers', () {
      expect(
        prettyPortalTrigger('Pressione <Shift><Control>1'),
        'Ctrl+Shift+1',
      );
      expect(
        prettyPortalTrigger('Press <Control><Alt>Print'),
        'Ctrl+Alt+PrtSc',
      );
      expect(prettyPortalTrigger('<Super>space'), 'Super+Space');
    });

    test('leaves unrecognized descriptions alone', () {
      expect(prettyPortalTrigger('Ctrl+Shift+1'), 'Ctrl+Shift+1');
      expect(prettyPortalTrigger(''), '');
    });
  });
}
