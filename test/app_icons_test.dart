import 'package:flutter_test/flutter_test.dart';
import 'package:shoshot/core/app_icons.dart';

void main() {
  test('every AppIcons getter resolves for both weights', () {
    for (final icons in [AppIcons.regular, AppIcons.boldWeight]) {
      final all = icons.all;
      expect(all, isNotEmpty);
      for (final icon in all) {
        expect(icon.codePoint, greaterThan(0));
      }
    }
  });

  test('bold weight uses a different font family', () {
    expect(
      AppIcons.boldWeight.select.fontFamily,
      isNot(AppIcons.regular.select.fontFamily),
    );
  });
}
