import 'package:flutter/material.dart';

import 'core/app_scope.dart';
import 'core/theme.dart';
import 'ui/editor/editor_screen.dart';
import 'ui/home/home_screen.dart';
import 'ui/overlay/overlay_screen.dart';
import 'ui/settings/settings_screen.dart';

class ShoShotApp extends StatelessWidget {
  const ShoShotApp({super.key, required this.services});

  final AppServices services;

  @override
  Widget build(BuildContext context) {
    return AppScope(
      services: services,
      child: ListenableBuilder(
        listenable: services.settings,
        builder: (context, _) {
          return MaterialApp(
            title: 'Show Shot',
            debugShowCheckedModeBanner: false,
            navigatorKey: services.flow.navigatorKey,
            scaffoldMessengerKey: services.flow.messengerKey,
            theme: AppTheme.dark(),
            themeMode: ThemeMode.dark,
            initialRoute: '/',
            onGenerateRoute: _onGenerateRoute,
          );
        },
      ),
    );
  }

  Route<dynamic> _onGenerateRoute(RouteSettings routeSettings) {
    switch (routeSettings.name) {
      case '/settings':
        return _fade(const SettingsScreen(), routeSettings);
      case '/blank':
        return _instant(const ColoredBox(color: AppColors.bg), routeSettings);
      case '/overlay':
        return _instant(const OverlayScreen(), routeSettings);
      case '/editor':
        return _instant(const EditorScreen(), routeSettings);
      case '/':
      default:
        return _fade(const HomeScreen(), routeSettings);
    }
  }

  PageRoute<void> _fade(Widget page, RouteSettings settings) {
    return PageRouteBuilder<void>(
      settings: settings,
      transitionDuration: const Duration(milliseconds: 180),
      reverseTransitionDuration: const Duration(milliseconds: 120),
      pageBuilder: (_, _, _) => page,
      transitionsBuilder: (_, animation, _, child) =>
          FadeTransition(opacity: animation, child: child),
    );
  }

  /// Overlay/editor must appear fully rendered on the first frame.
  PageRoute<void> _instant(Widget page, RouteSettings settings) {
    return PageRouteBuilder<void>(
      settings: settings,
      transitionDuration: Duration.zero,
      reverseTransitionDuration: Duration.zero,
      pageBuilder: (_, _, _) => page,
    );
  }
}
