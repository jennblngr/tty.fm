import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app_info.dart';
import '../core/session.dart';
import '../core/settings.dart';
import 'screens/login.dart';
import 'shell.dart';

/// Theme lives here only, so a redesign touches this file and the widgets,
/// never the state or playback code.
ThemeData _theme(Brightness b) => ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF5B6EF5), brightness: b),
      useMaterial3: true,
      visualDensity: VisualDensity.adaptivePlatformDensity,
      listTileTheme: const ListTileThemeData(contentPadding: EdgeInsets.symmetric(horizontal: 16)),
    );

class SelfstreamApp extends ConsumerWidget {
  const SelfstreamApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(settingsProvider.select((s) => s.themeMode));
    final session = ref.watch(sessionProvider);
    final configured = ref.watch(settingsProvider.select((s) => s.configured));
    return MaterialApp(
      title: appDisplayName,
      debugShowCheckedModeBanner: false,
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      themeMode: themeMode,
      home: session.when(
        loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
        error: (_, _) => const LoginScreen(),
        data: (token) => token != null && configured ? const AppShell() : const LoginScreen(),
      ),
    );
  }
}
