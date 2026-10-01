import 'dart:io';

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
        listenable: Listenable.merge([services.settings, services.systemTheme]),
        builder: (context, _) {
          final accent = services.systemTheme.accent.color;
          return MaterialApp(
            title: 'Show Shot',
            debugShowCheckedModeBanner: false,
            navigatorKey: services.flow.navigatorKey,
            scaffoldMessengerKey: services.flow.messengerKey,
            theme: AppTheme.build(brightness: Brightness.light, accent: accent),
            darkTheme: AppTheme.build(
              brightness: Brightness.dark,
              accent: accent,
            ),
            // Follows the OS setting — Flutter's engine already detects this
            // on macOS/Windows/Linux, no native code of our own needed.
            themeMode: ThemeMode.system,
            initialRoute: '/',
            onGenerateRoute: _onGenerateRoute,
            builder: Platform.isLinux ? _roundCorners : null,
          );
        },
      ),
    );
  }

  /// Linux: macOS and Windows 11 round windows at the OS level; on GNOME
  /// that's up to the app — GTK draws the rounded frame and shadow (see
  /// linux/runner/my_application.cc) and the content has to be clipped to
  /// the same 12px radius, except when maximized / full screen / tiled.
  Widget _roundCorners(BuildContext context, Widget? child) {
    return ValueListenableBuilder<bool>(
      valueListenable: services.native.windowRounded,
      builder: (context, rounded, child) => rounded
          ? ClipRRect(borderRadius: BorderRadius.circular(12), child: child)
          : child!,
      child: child,
    );
  }

  Route<dynamic> _onGenerateRoute(RouteSettings routeSettings) {
    switch (routeSettings.name) {
      case '/settings':
        return _fade(const SettingsScreen(), routeSettings);
      case '/blank':
        return _instant(
          Builder(
            builder: (context) =>
                ColoredBox(color: Theme.of(context).scaffoldBackgroundColor),
          ),
          routeSettings,
        );
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
