import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ttyfm/core/settings.dart';
import 'package:ttyfm/ui/theme.dart';

Future<Settings> _load(Map<String, Object> prefs) async {
  SharedPreferences.setMockInitialValues(prefs);
  final p = await SharedPreferences.getInstance();
  final container = ProviderContainer(overrides: [sharedPrefsProvider.overrideWithValue(p)]);
  addTearDown(container.dispose);
  return container.read(settingsProvider);
}

void main() {
  test('every theme name has a palette of the same brightness', () {
    for (final name in ThemeName.values) {
      expect(Tty.named(name).dark, name.dark, reason: name.label);
    }
    expect(ThemeName.values.where((t) => t.dark), hasLength(7));
    expect(ThemeName.values.where((t) => !t.dark), hasLength(5));
  });

  test('defaults follow the system with mocha and latte', () async {
    final s = await _load({});
    expect(s.followSystem, isTrue);
    expect(s.darkTheme, ThemeName.catppuccinMocha);
    expect(s.lightTheme, ThemeName.catppuccinLatte);
  });

  test('the old light/dark choice becomes a fixed theme', () async {
    final light = await _load({'themeMode': 'light'});
    expect(light.followSystem, isFalse);
    expect(light.fixedTheme, ThemeName.catppuccinLatte);
    final dark = await _load({'themeMode': 'dark'});
    expect(dark.followSystem, isFalse);
    expect(dark.fixedTheme, ThemeName.catppuccinMocha);
  });
}
