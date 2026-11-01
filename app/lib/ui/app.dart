import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app_info.dart';
import '../core/session.dart';
import '../core/settings.dart';
import 'screens/login.dart';
import 'shell.dart';
import 'theme.dart';

// The look lives in theme.dart and the widgets, never in the state or
// playback code.
final _dark = ttyTheme(Tty.mocha);
final _light = ttyTheme(Tty.latte);

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
      theme: _light,
      darkTheme: _dark,
      themeMode: themeMode,
      home: session.when(
        loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
        error: (_, _) => const LoginScreen(),
        data: (token) => token != null && configured ? const AppShell() : const LoginScreen(),
      ),
    );
  }
}
