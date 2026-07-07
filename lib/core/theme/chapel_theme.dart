import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Chapel palette.
///
/// Warm, calm, traditional. The base is a soft cream that feels like
/// program paper stock, with a muted navy for authority (title bars,
/// buttons), warm gold for accents (chips, callouts, active states), and
/// a sage green for positive signals like "set apart" or "confirmed".
///
/// Kept in one place so screens never hardcode raw hex values.
class ChapelPalette {
  ChapelPalette._();

  // Primary — muted navy, formal but not cold.
  static const navy = Color(0xFF2E4057);
  static const navyDark = Color(0xFF1F2E3F);
  static const navyLight = Color(0xFF4A6178);

  // Accent — warm brass gold.
  static const gold = Color(0xFFB08A3E);
  static const goldDark = Color(0xFF87682B);
  static const goldLight = Color(0xFFE8D9B0);

  // Positive — sage green (set apart / confirmed / active in service).
  static const sage = Color(0xFF5A7A5A);
  static const sageLight = Color(0xFFCFE0CF);

  // Warning — muted amber (stale in pipeline).
  static const amber = Color(0xFFB07535);
  static const amberLight = Color(0xFFF4E1C7);

  // Error — dignified maroon rather than harsh red.
  static const maroon = Color(0xFF8B3A3A);
  static const maroonLight = Color(0xFFF2D6D6);

  // Neutrals — a warm off-white cream and paper tones.
  static const cream = Color(0xFFFAF6EE);
  static const paper = Color(0xFFF3EEE2);
  static const paperDeep = Color(0xFFE8E0CE);
  static const ink = Color(0xFF2A2620);
  static const inkSoft = Color(0xFF5C554A);
  static const rule = Color(0xFFD9CFB8);
}

/// Builds the ChapelTheme [ThemeData]. Material 3 with a hand-tuned
/// [ColorScheme] and a Merriweather (serif) + Inter (sans) typography
/// pair.
ThemeData buildChapelTheme() {
  const scheme = ColorScheme(
    brightness: Brightness.light,
    primary: ChapelPalette.navy,
    onPrimary: Color(0xFFFFFFFF),
    primaryContainer: Color(0xFFCFD8E3),
    onPrimaryContainer: ChapelPalette.navyDark,
    secondary: ChapelPalette.gold,
    onSecondary: Color(0xFFFFFFFF),
    secondaryContainer: ChapelPalette.goldLight,
    onSecondaryContainer: ChapelPalette.goldDark,
    tertiary: ChapelPalette.sage,
    onTertiary: Color(0xFFFFFFFF),
    tertiaryContainer: ChapelPalette.sageLight,
    onTertiaryContainer: Color(0xFF2E4A2E),
    error: ChapelPalette.maroon,
    onError: Color(0xFFFFFFFF),
    errorContainer: ChapelPalette.maroonLight,
    onErrorContainer: Color(0xFF4D1E1E),
    surface: ChapelPalette.cream,
    onSurface: ChapelPalette.ink,
    onSurfaceVariant: ChapelPalette.inkSoft,
    surfaceContainerLowest: Color(0xFFFFFFFF),
    surfaceContainerLow: ChapelPalette.cream,
    surfaceContainer: ChapelPalette.paper,
    surfaceContainerHigh: ChapelPalette.paper,
    surfaceContainerHighest: ChapelPalette.paperDeep,
    surfaceTint: ChapelPalette.navy,
    outline: ChapelPalette.rule,
    outlineVariant: Color(0xFFEAE1CB),
    inverseSurface: ChapelPalette.navyDark,
    onInverseSurface: ChapelPalette.cream,
    inversePrimary: ChapelPalette.goldLight,
    shadow: Color(0x22000000),
    scrim: Color(0x88000000),
  );

  final serif = GoogleFonts.merriweatherTextTheme();
  final sans = GoogleFonts.interTextTheme();

  // Merriweather for display/headline/title (formal), Inter for body/label
  // (readable at small sizes).
  final textTheme = TextTheme(
    displayLarge: serif.displayLarge?.copyWith(color: ChapelPalette.ink),
    displayMedium: serif.displayMedium?.copyWith(color: ChapelPalette.ink),
    displaySmall: serif.displaySmall?.copyWith(color: ChapelPalette.ink),
    headlineLarge: serif.headlineLarge?.copyWith(
      color: ChapelPalette.ink,
      fontWeight: FontWeight.w700,
    ),
    headlineMedium: serif.headlineMedium?.copyWith(
      color: ChapelPalette.ink,
      fontWeight: FontWeight.w700,
    ),
    headlineSmall: serif.headlineSmall?.copyWith(
      color: ChapelPalette.ink,
      fontWeight: FontWeight.w600,
    ),
    titleLarge: serif.titleLarge?.copyWith(
      color: ChapelPalette.ink,
      fontWeight: FontWeight.w700,
    ),
    titleMedium: serif.titleMedium?.copyWith(
      color: ChapelPalette.ink,
      fontWeight: FontWeight.w600,
    ),
    titleSmall: sans.titleSmall?.copyWith(
      color: ChapelPalette.ink,
      fontWeight: FontWeight.w600,
    ),
    bodyLarge: sans.bodyLarge?.copyWith(color: ChapelPalette.ink),
    bodyMedium: sans.bodyMedium?.copyWith(color: ChapelPalette.ink),
    bodySmall: sans.bodySmall?.copyWith(color: ChapelPalette.inkSoft),
    labelLarge: sans.labelLarge?.copyWith(
      color: ChapelPalette.ink,
      fontWeight: FontWeight.w600,
    ),
    labelMedium: sans.labelMedium?.copyWith(color: ChapelPalette.inkSoft),
    labelSmall: sans.labelSmall?.copyWith(color: ChapelPalette.inkSoft),
  );

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorScheme: scheme,
    scaffoldBackgroundColor: ChapelPalette.cream,
    canvasColor: ChapelPalette.cream,
    textTheme: textTheme,
    primaryTextTheme: textTheme,
    dividerColor: ChapelPalette.rule,
    dividerTheme: const DividerThemeData(
      color: ChapelPalette.rule,
      thickness: 1,
      space: 1,
    ),
    iconTheme: const IconThemeData(color: ChapelPalette.inkSoft),
    primaryIconTheme: const IconThemeData(color: Color(0xFFFFFFFF)),
    appBarTheme: AppBarTheme(
      backgroundColor: ChapelPalette.navy,
      foregroundColor: Colors.white,
      elevation: 0,
      scrolledUnderElevation: 2,
      centerTitle: false,
      shadowColor: const Color(0x33000000),
      surfaceTintColor: Colors.transparent,
      iconTheme: const IconThemeData(color: Colors.white),
      actionsIconTheme: const IconThemeData(color: Colors.white),
      titleTextStyle: serif.titleLarge?.copyWith(
        color: Colors.white,
        fontWeight: FontWeight.w700,
        fontSize: 20,
      ),
      toolbarTextStyle: sans.bodyMedium?.copyWith(color: Colors.white),
    ),
    cardTheme: CardThemeData(
      color: scheme.surfaceContainerLowest,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: ChapelPalette.rule),
      ),
      margin: EdgeInsets.zero,
    ),
    listTileTheme: ListTileThemeData(
      iconColor: ChapelPalette.inkSoft,
      textColor: ChapelPalette.ink,
      titleTextStyle: sans.bodyLarge?.copyWith(
        color: ChapelPalette.ink,
        fontWeight: FontWeight.w600,
      ),
      subtitleTextStyle: sans.bodySmall?.copyWith(color: ChapelPalette.inkSoft),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: scheme.surfaceContainerLowest,
      elevation: 6,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      titleTextStyle: serif.titleLarge?.copyWith(
        color: ChapelPalette.ink,
        fontWeight: FontWeight.w700,
      ),
      contentTextStyle: sans.bodyMedium?.copyWith(color: ChapelPalette.ink),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: ChapelPalette.navyDark,
      contentTextStyle: sans.bodyMedium?.copyWith(color: Colors.white),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerLowest,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 14,
      ),
      hintStyle: sans.bodyMedium?.copyWith(color: ChapelPalette.inkSoft),
      labelStyle: sans.bodyMedium?.copyWith(color: ChapelPalette.inkSoft),
      floatingLabelStyle: sans.bodySmall?.copyWith(
        color: ChapelPalette.navy,
        fontWeight: FontWeight.w600,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: ChapelPalette.rule),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: ChapelPalette.rule),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: ChapelPalette.navy, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: ChapelPalette.maroon),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: ChapelPalette.maroon, width: 1.5),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: ChapelPalette.navy,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        textStyle: sans.labelLarge?.copyWith(fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: ChapelPalette.navy,
        side: const BorderSide(color: ChapelPalette.navy),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        textStyle: sans.labelLarge?.copyWith(fontWeight: FontWeight.w600),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: ChapelPalette.navy,
        textStyle: sans.labelLarge?.copyWith(fontWeight: FontWeight.w600),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: ChapelPalette.gold,
      foregroundColor: Colors.white,
      elevation: 2,
      focusElevation: 3,
      hoverElevation: 3,
      extendedTextStyle: sans.labelLarge?.copyWith(
        color: Colors.white,
        fontWeight: FontWeight.w600,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(28),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: ChapelPalette.navy,
      indicatorColor: ChapelPalette.gold,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return sans.labelSmall?.copyWith(
          color: selected ? Colors.white : const Color(0xFFCFD8E3),
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
        );
      }),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return IconThemeData(
          color: selected ? Colors.white : const Color(0xFFCFD8E3),
          size: 24,
        );
      }),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: scheme.surfaceContainerHighest,
      selectedColor: ChapelPalette.goldLight,
      side: const BorderSide(color: ChapelPalette.rule),
      labelStyle: sans.labelMedium?.copyWith(color: ChapelPalette.ink),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
    ),
    tabBarTheme: TabBarThemeData(
      labelColor: Colors.white,
      unselectedLabelColor: const Color(0xFFCFD8E3),
      indicatorColor: ChapelPalette.gold,
      dividerColor: Colors.transparent,
      labelStyle: sans.labelLarge?.copyWith(fontWeight: FontWeight.w700),
      unselectedLabelStyle: sans.labelLarge?.copyWith(fontWeight: FontWeight.w500),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) {
        if (s.contains(WidgetState.selected)) return ChapelPalette.gold;
        return const Color(0xFFF3EEE2);
      }),
      trackColor: WidgetStateProperty.resolveWith((s) {
        if (s.contains(WidgetState.selected)) return ChapelPalette.goldLight;
        return ChapelPalette.rule;
      }),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: ChapelPalette.navy,
      linearTrackColor: ChapelPalette.paperDeep,
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: ChapelPalette.navyDark,
        borderRadius: BorderRadius.circular(6),
      ),
      textStyle: sans.labelSmall?.copyWith(color: Colors.white),
    ),
  );
}
