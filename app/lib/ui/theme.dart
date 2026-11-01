import 'package:flutter/material.dart';

/// Design tokens of the "tty" look: a terminal palette (Catppuccin Mocha in
/// dark, Latte in light) and JetBrains Mono everywhere. Widgets read them
/// with [Tty.of]; Material widgets get them through [ttyTheme].
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

  static const mocha = Tty(
    base: Color(0xFF1E1E2E),
    mantle: Color(0xFF1A1A28),
    crust: Color(0xFF181825),
    surface: Color(0xFF2A2A3C),
    panel: Color(0xFF232334),
    border: Color(0xFF34344A),
    track: Color(0xFF3A3A50),
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

  static const latte = Tty(
    base: Color(0xFFEFF1F5),
    mantle: Color(0xFFE6E9EF),
    crust: Color(0xFFDCE0E8),
    surface: Color(0xFFE2E5EC),
    panel: Color(0xFFE6E9EF),
    border: Color(0xFFCCD0DA),
    track: Color(0xFFBCC0CC),
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

  static Tty of(BuildContext context) => Theme.of(context).extension<Tty>()!;

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
