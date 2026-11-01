import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../core/settings.dart';

/// Design tokens of the "tty" look: a terminal palette (one instance per
/// [ThemeName], Catppuccin Mocha and Latte by default) and JetBrains Mono
/// everywhere. Widgets read them with [Tty.of]; Material widgets get them
/// through [ttyTheme].
@immutable
class Tty extends ThemeExtension<Tty> {
  const Tty({
    required this.base,
    required this.mantle,
    required this.crust,
    required this.surface,
    required this.panel,
    required this.border,
    required this.track,
    required this.empty,
    required this.text,
    required this.muted,
    required this.green,
    required this.mauve,
    required this.red,
    required this.blue,
    required this.peach,
    required this.teal,
    required this.yellow,
    required this.pink,
    required this.dark,
  });

  final Color base; // page background
  final Color mantle; // side panels
  final Color crust; // player bar
  final Color surface; // cards, inputs
  final Color panel; // stat cards
  final Color border;
  final Color track; // empty part of progress bars
  final Color empty; // empty cells of meters and graphs
  final Color text;
  final Color muted; // secondary text, "// comments"
  final Color green; // prompt, active, play
  final Color mauve; // brand, section titles
  final Color red; // liked
  final Color blue;
  final Color peach;
  final Color teal;
  final Color yellow;
  final Color pink;
  final bool dark;

  // Catppuccin Mocha (MIT), with a few in-between shades of the design.
  static const mocha = Tty(
    base: Color(0xFF1E1E2E),
    mantle: Color(0xFF1A1A28),
    crust: Color(0xFF181825),
    surface: Color(0xFF2A2A3C),
    panel: Color(0xFF232334),
    border: Color(0xFF34344A),
    track: Color(0xFF3A3A50),
    empty: Color(0xFF45475A),
    text: Color(0xFFE2E2EE),
    muted: Color(0xFF9091AB),
    green: Color(0xFFA6E3A1),
    mauve: Color(0xFFCBA6F7),
    red: Color(0xFFF38BA8),
    blue: Color(0xFF89B4FA),
    peach: Color(0xFFFAB387),
    teal: Color(0xFF94E2D5),
    yellow: Color(0xFFF9E2AF),
    pink: Color(0xFFF5A3C7),
    dark: true,
  );

  // Catppuccin Latte (MIT).
  static const latte = Tty(
    base: Color(0xFFEFF1F5),
    mantle: Color(0xFFE6E9EF),
    crust: Color(0xFFDCE0E8),
    surface: Color(0xFFE2E5EC),
    panel: Color(0xFFE6E9EF),
    border: Color(0xFFCCD0DA),
    track: Color(0xFFBCC0CC),
    empty: Color(0xFFACB0BE),
    text: Color(0xFF4C4F69),
    muted: Color(0xFF6C6F85),
    green: Color(0xFF40A02B),
    mauve: Color(0xFF8839EF),
    red: Color(0xFFD20F39),
    blue: Color(0xFF1E66F5),
    peach: Color(0xFFFE640B),
    teal: Color(0xFF179299),
    yellow: Color(0xFFDF8E1D),
    pink: Color(0xFFEA76CB),
    dark: false,
  );

  // Dracula (MIT).
  static const dracula = Tty(
    base: Color(0xFF282A36),
    mantle: Color(0xFF21222C),
    crust: Color(0xFF191A21),
    surface: Color(0xFF343746),
    panel: Color(0xFF2D2F3D),
    border: Color(0xFF44475A),
    track: Color(0xFF44475A),
    empty: Color(0xFF525570),
    text: Color(0xFFF8F8F2),
    muted: Color(0xFF8894B8),
    green: Color(0xFF50FA7B),
    mauve: Color(0xFFBD93F9),
    red: Color(0xFFFF5555),
    blue: Color(0xFF8BE9FD),
    peach: Color(0xFFFFB86C),
    teal: Color(0xFF8BE9FD),
    yellow: Color(0xFFF1FA8C),
    pink: Color(0xFFFF79C6),
    dark: true,
  );

  // Nord (MIT). The comment grey is lifted to stay readable.
  static const nord = Tty(
    base: Color(0xFF2E3440),
    mantle: Color(0xFF2A2F3A),
    crust: Color(0xFF272C36),
    surface: Color(0xFF3B4252),
    panel: Color(0xFF353B49),
    border: Color(0xFF434C5E),
    track: Color(0xFF434C5E),
    empty: Color(0xFF4C566A),
    text: Color(0xFFECEFF4),
    muted: Color(0xFF99A2B3),
    green: Color(0xFFA3BE8C),
    mauve: Color(0xFFB48EAD),
    red: Color(0xFFBF616A),
    blue: Color(0xFF81A1C1),
    peach: Color(0xFFD08770),
    teal: Color(0xFF8FBCBB),
    yellow: Color(0xFFEBCB8B),
    pink: Color(0xFFB48EAD),
    dark: true,
  );

  // Gruvbox dark, bright accents (MIT).
  static const gruvboxDark = Tty(
    base: Color(0xFF282828),
    mantle: Color(0xFF232323),
    crust: Color(0xFF1D2021),
    surface: Color(0xFF3C3836),
    panel: Color(0xFF32302F),
    border: Color(0xFF504945),
    track: Color(0xFF504945),
    empty: Color(0xFF665C54),
    text: Color(0xFFEBDBB2),
    muted: Color(0xFFA89984),
    green: Color(0xFFB8BB26),
    mauve: Color(0xFFD3869B),
    red: Color(0xFFFB4934),
    blue: Color(0xFF83A598),
    peach: Color(0xFFFE8019),
    teal: Color(0xFF8EC07C),
    yellow: Color(0xFFFABD2F),
    pink: Color(0xFFD3869B),
    dark: true,
  );

  // Tokyo Night, "night" variant (MIT).
  static const tokyoNight = Tty(
    base: Color(0xFF1A1B26),
    mantle: Color(0xFF16161E),
    crust: Color(0xFF13131A),
    surface: Color(0xFF292E42),
    panel: Color(0xFF1F2335),
    border: Color(0xFF3B4261),
    track: Color(0xFF3B4261),
    empty: Color(0xFF414868),
    text: Color(0xFFC0CAF5),
    muted: Color(0xFF7F86AE),
    green: Color(0xFF9ECE6A),
    mauve: Color(0xFFBB9AF7),
    red: Color(0xFFF7768E),
    blue: Color(0xFF7AA2F7),
    peach: Color(0xFFFF9E64),
    teal: Color(0xFF73DACA),
    yellow: Color(0xFFE0AF68),
    pink: Color(0xFF9D7CD8),
    dark: true,
  );

  // Rosé Pine (MIT). It has no green: foam plays that part.
  static const rosePine = Tty(
    base: Color(0xFF191724),
    mantle: Color(0xFF16141F),
    crust: Color(0xFF121019),
    surface: Color(0xFF26233A),
    panel: Color(0xFF1F1D2E),
    border: Color(0xFF403D52),
    track: Color(0xFF403D52),
    empty: Color(0xFF524F67),
    text: Color(0xFFE0DEF4),
    muted: Color(0xFF908CAA),
    green: Color(0xFF9CCFD8),
    mauve: Color(0xFFC4A7E7),
    red: Color(0xFFEB6F92),
    blue: Color(0xFF31748F),
    peach: Color(0xFFF6C177),
    teal: Color(0xFF9CCFD8),
    yellow: Color(0xFFF6C177),
    pink: Color(0xFFEBBCBA),
    dark: true,
  );

  // One Dark, from Atom (MIT).
  static const oneDark = Tty(
    base: Color(0xFF282C34),
    mantle: Color(0xFF21252B),
    crust: Color(0xFF1E2227),
    surface: Color(0xFF333842),
    panel: Color(0xFF2C313A),
    border: Color(0xFF3E4451),
    track: Color(0xFF3E4451),
    empty: Color(0xFF4B5263),
    text: Color(0xFFABB2BF),
    muted: Color(0xFF9196A2),
    green: Color(0xFF98C379),
    mauve: Color(0xFFC678DD),
    red: Color(0xFFE06C75),
    blue: Color(0xFF61AFEF),
    peach: Color(0xFFD19A66),
    teal: Color(0xFF56B6C2),
    yellow: Color(0xFFE5C07B),
    pink: Color(0xFFC678DD),
    dark: true,
  );

  // Solarized light (MIT).
  static const solarizedLight = Tty(
    base: Color(0xFFFDF6E3),
    mantle: Color(0xFFF5EFDC),
    crust: Color(0xFFEEE8D5),
    surface: Color(0xFFEEE8D5),
    panel: Color(0xFFF5EFDC),
    border: Color(0xFFE3DDCA),
    track: Color(0xFFD3CDBA),
    empty: Color(0xFF93A1A1),
    text: Color(0xFF073642),
    muted: Color(0xFF586E75),
    green: Color(0xFF859900),
    mauve: Color(0xFF6C71C4),
    red: Color(0xFFDC322F),
    blue: Color(0xFF268BD2),
    peach: Color(0xFFCB4B16),
    teal: Color(0xFF2AA198),
    yellow: Color(0xFFB58900),
    pink: Color(0xFFD33682),
    dark: false,
  );

  // Gruvbox light, faded accents (MIT).
  static const gruvboxLight = Tty(
    base: Color(0xFFFBF1C7),
    mantle: Color(0xFFF2E5BC),
    crust: Color(0xFFEBDBB2),
    surface: Color(0xFFEBDBB2),
    panel: Color(0xFFF2E5BC),
    border: Color(0xFFD5C4A1),
    track: Color(0xFFBDAE93),
    empty: Color(0xFFA89984),
    text: Color(0xFF3C3836),
    muted: Color(0xFF7C6F64),
    green: Color(0xFF79740E),
    mauve: Color(0xFF8F3F71),
    red: Color(0xFF9D0006),
    blue: Color(0xFF076678),
    peach: Color(0xFFAF3A03),
    teal: Color(0xFF427B58),
    yellow: Color(0xFFB57614),
    pink: Color(0xFF8F3F71),
    dark: false,
  );

  // Rosé Pine Dawn (MIT).
  static const rosePineDawn = Tty(
    base: Color(0xFFFAF4ED),
    mantle: Color(0xFFF4EDE8),
    crust: Color(0xFFF2E9E1),
    surface: Color(0xFFF2E9E1),
    panel: Color(0xFFF4EDE8),
    border: Color(0xFFDFDAD9),
    track: Color(0xFFCECACD),
    empty: Color(0xFFB9B5BA),
    text: Color(0xFF575279),
    muted: Color(0xFF797593),
    green: Color(0xFF56949F),
    mauve: Color(0xFF907AA9),
    red: Color(0xFFB4637A),
    blue: Color(0xFF286983),
    peach: Color(0xFFEA9D34),
    teal: Color(0xFF56949F),
    yellow: Color(0xFFEA9D34),
    pink: Color(0xFFD7827E),
    dark: false,
  );

  // One Light, from Atom (MIT).
  static const oneLight = Tty(
    base: Color(0xFFFAFAFA),
    mantle: Color(0xFFF0F0F1),
    crust: Color(0xFFE5E5E6),
    surface: Color(0xFFEAEAEB),
    panel: Color(0xFFF0F0F1),
    border: Color(0xFFDBDBDC),
    track: Color(0xFFD0D0D1),
    empty: Color(0xFFBFBFC1),
    text: Color(0xFF383A42),
    muted: Color(0xFF696C77),
    green: Color(0xFF50A14F),
    mauve: Color(0xFFA626A4),
    red: Color(0xFFE45649),
    blue: Color(0xFF4078F2),
    peach: Color(0xFFC18401),
    teal: Color(0xFF0184BC),
    yellow: Color(0xFF986801),
    pink: Color(0xFFA626A4),
    dark: false,
  );

  static Tty named(ThemeName name) => switch (name) {
    ThemeName.catppuccinMocha => mocha,
    ThemeName.dracula => dracula,
    ThemeName.nord => nord,
    ThemeName.gruvboxDark => gruvboxDark,
    ThemeName.tokyoNight => tokyoNight,
    ThemeName.rosePine => rosePine,
    ThemeName.oneDark => oneDark,
    ThemeName.catppuccinLatte => latte,
    ThemeName.solarizedLight => solarizedLight,
    ThemeName.gruvboxLight => gruvboxLight,
    ThemeName.rosePineDawn => rosePineDawn,
    ThemeName.oneLight => oneLight,
  };

  static Tty of(BuildContext context) => Theme.of(context).extension<Tty>()!;

  /// The dots of the theme picker swatch.
  List<Color> get swatch => [mauve, green, peach, blue, red];

  List<Color> get accents => [blue, mauve, green, teal, peach, yellow, pink];

  /// Background tinted with [c], as behind the coloured tiles of the design.
  Color tint(Color c) => Color.alphaBlend(c.withValues(alpha: dark ? 0.15 : 0.18), base);

  /// A stable accent for an item (album, artist, playlist) from its id.
  Color accentFor(int seed) => accents[seed.abs() % accents.length];

  @override
  Tty copyWith() => this;

  @override
  Tty lerp(ThemeExtension<Tty>? other, double t) => (other is Tty && t >= 0.5) ? other : this;
}

ThemeData ttyTheme(Tty c) {
  // JetBrains Mono, bundled with the app (see pubspec.yaml).
  const family = 'JetBrains Mono';
  final base = ThemeData(
    brightness: c.dark ? Brightness.dark : Brightness.light,
    useMaterial3: true,
    fontFamily: family,
  );
  final text = base.textTheme
      .copyWith(
        bodyLarge: TextStyle(fontSize: 14, height: 1.5, color: c.text),
        bodyMedium: TextStyle(fontSize: 13, height: 1.5, color: c.text),
        bodySmall: TextStyle(fontSize: 12, height: 1.4, color: c.muted),
        titleLarge: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: c.text),
        titleMedium: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: c.text),
        titleSmall: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: c.text),
        labelLarge: TextStyle(fontSize: 13, color: c.text),
        labelMedium: TextStyle(fontSize: 12, color: c.muted),
        labelSmall: TextStyle(fontSize: 11, color: c.muted),
      )
      .apply(fontFamily: family);
  final scheme = ColorScheme(
    brightness: c.dark ? Brightness.dark : Brightness.light,
    primary: c.green,
    onPrimary: c.base,
    primaryContainer: c.tint(c.green),
    onPrimaryContainer: c.green,
    secondary: c.mauve,
    onSecondary: c.base,
    secondaryContainer: c.tint(c.mauve),
    onSecondaryContainer: c.mauve,
    tertiary: c.peach,
    onTertiary: c.base,
    error: c.red,
    onError: c.base,
    errorContainer: c.tint(c.red),
    onErrorContainer: c.red,
    surface: c.base,
    onSurface: c.text,
    onSurfaceVariant: c.muted,
    surfaceContainerLowest: c.base,
    surfaceContainerLow: c.mantle,
    surfaceContainer: c.crust,
    surfaceContainerHigh: c.surface,
    surfaceContainerHighest: c.surface,
    outline: c.border,
    outlineVariant: c.border,
    inverseSurface: c.text,
    onInverseSurface: c.base,
    inversePrimary: c.green,
  );
  return base.copyWith(
    colorScheme: scheme,
    extensions: [c],
    textTheme: text,
    scaffoldBackgroundColor: c.base,
    canvasColor: c.base,
    dividerColor: c.border,
    dividerTheme: DividerThemeData(color: c.border, thickness: 1, space: 1),
    splashFactory: NoSplash.splashFactory,
    highlightColor: c.surface,
    hoverColor: c.surface.withValues(alpha: 0.6),
    visualDensity: VisualDensity.compact,
    appBarTheme: AppBarTheme(
      backgroundColor: c.base,
      foregroundColor: c.text,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleTextStyle: text.titleMedium,
    ),
    listTileTheme: ListTileThemeData(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      iconColor: c.muted,
      textColor: c.text,
      titleTextStyle: text.bodyMedium,
      subtitleTextStyle: text.bodySmall,
      dense: true,
    ),
    iconTheme: IconThemeData(color: c.text, size: 20),
    sliderTheme: SliderThemeData(
      activeTrackColor: c.green,
      inactiveTrackColor: c.track,
      thumbColor: c.green,
      trackHeight: 4,
      overlayShape: SliderComponentShape.noOverlay,
      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: c.green, linearTrackColor: c.track),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: c.surface,
      hintStyle: TextStyle(color: c.muted),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide.none),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: c.green,
        foregroundColor: c.base,
        textStyle: text.labelLarge?.copyWith(fontWeight: FontWeight.w700),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: c.text,
        backgroundColor: c.surface,
        side: BorderSide.none,
        textStyle: text.labelLarge,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: c.muted, textStyle: text.labelLarge),
    ),
    tabBarTheme: TabBarThemeData(
      labelColor: c.green,
      unselectedLabelColor: c.muted,
      indicatorColor: c.green,
      dividerColor: c.border,
      labelStyle: text.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
      unselectedLabelStyle: text.bodyMedium,
      overlayColor: WidgetStatePropertyAll(c.surface),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: c.surface,
      side: BorderSide.none,
      labelStyle: text.bodyMedium,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: c.surface,
      textStyle: text.bodyMedium,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(6),
        side: BorderSide(color: c.border),
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(backgroundColor: c.mantle, modalBackgroundColor: c.mantle),
    dialogTheme: DialogThemeData(backgroundColor: c.mantle, titleTextStyle: text.titleMedium),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: c.surface,
      contentTextStyle: text.bodyMedium,
      behavior: SnackBarBehavior.floating,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? c.base : c.muted),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? c.green : c.surface),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        foregroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? c.green : c.muted),
        backgroundColor: WidgetStatePropertyAll(c.surface),
        side: WidgetStatePropertyAll(BorderSide(color: c.border)),
      ),
    ),
  );
}

/// Authors of the bundled palettes, all under the MIT licence. Shown in
/// « à propos » and in the licence page.
const themeCredits = [
  ('catppuccin', 'Catppuccin'),
  ('dracula', 'Dracula Theme'),
  ('nord', 'Sven Greb (Arctic Ice Studio)'),
  ('gruvbox', 'Pavel Pertsev (morhetz)'),
  ('tokyo night', 'Enkia'),
  ('rosé pine', 'Rosé Pine'),
  ('one dark / one light', 'GitHub Inc. (Atom)'),
  ('solarized', 'Ethan Schoonover'),
];

void registerThemeLicenses() {
  LicenseRegistry.addLicense(() async* {
    for (final (name, author) in themeCredits) {
      yield LicenseEntryWithLineBreaks(['palette $name'], 'Copyright (c) $author\n\n$_mit');
    }
  });
}

const _mit = '''Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.''';
