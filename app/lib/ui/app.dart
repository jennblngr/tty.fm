import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app_info.dart';
import '../core/session.dart';
import '../core/settings.dart';
import 'screens/login.dart';
import 'shell.dart';
import 'theme.dart';

// The look lives in theme.dart and the widgets, never in the state or
// playback code. Themes are built once, on first use.
final _themes = <ThemeName, ThemeData>{};
ThemeData _theme(ThemeName name) => _themes.putIfAbsent(name, () => ttyTheme(Tty.named(name)));

class TtyFmApp extends ConsumerWidget {
  const TtyFmApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (follow, dark, light, fixed) = ref.watch(
      settingsProvider.select((s) => (s.followSystem, s.darkTheme, s.lightTheme, s.fixedTheme)),
    );
    final session = ref.watch(sessionProvider);
    final configured = ref.watch(settingsProvider.select((s) => s.configured));
    return MaterialApp(
      title: appDisplayName,
      debugShowCheckedModeBanner: false,
      theme: _theme(follow ? light : fixed),
      darkTheme: _theme(dark),
      themeMode: follow ? ThemeMode.system : ThemeMode.light,
      home: session.when(
        loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
        error: (_, _) => const LoginScreen(),
        data: (token) => token != null && configured ? const AppShell() : const LoginScreen(),
      ),
    );
  }
}
