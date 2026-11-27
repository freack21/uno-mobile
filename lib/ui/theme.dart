import 'package:material_ui/material_ui.dart';

import 'package:last_card_core/cards.dart';

/// Design tokens for the dark table and the light one. The card colors
/// carry the brand and stay the same in both.
abstract final class Palette {
  /// The current look; set by [ThemeSwitch] before the app rebuilds.
  static bool dark = true;

  static Color get ink =>
      dark ? const Color(0xFF14161B) : const Color(0xFFF3EFE6);
  static Color get surface =>
      dark ? const Color(0xFF1D2027) : const Color(0xFFFFFDF8);
  static Color get surfaceHigh =>
      dark ? const Color(0xFF272B34) : const Color(0xFFE9E3D7);
  static Color get line =>
      dark ? const Color(0xFF343944) : const Color(0xFFDAD3C4);
  static Color get text =>
      dark ? const Color(0xFFF6F3EC) : const Color(0xFF1D1F25);
  static Color get muted =>
      dark ? const Color(0xFF9AA1AD) : const Color(0xFF6A6F79);

  /// Middle of the table, under the glow of the active color.
  static Color get felt =>
      dark ? const Color(0xFF1A1D23) : const Color(0xFFFFFCF5);

  /// Soft warning text (hints, errors).
  static Color get warn =>
      dark ? const Color(0xFFFFB4A8) : const Color(0xFFB3261E);

  static const brand = Color(0xFFE5392C);
  static const cardWhite = Color(0xFFFFFDF7);

  /// Text and marks on white pieces (badges, banners, cards).
  static const cardInk = Color(0xFF14161B);

  static Color of(CardColor c) => switch (c) {
    CardColor.red => const Color(0xFFE5392C),
    CardColor.yellow => const Color(0xFFF4B620),
    CardColor.green => const Color(0xFF2EA358),
    CardColor.blue => const Color(0xFF2475D6),
    CardColor.pink => const Color(0xFFE8448C),
    CardColor.teal => const Color(0xFF119E9E),
    CardColor.orange => const Color(0xFFF07A1C),
    CardColor.purple => const Color(0xFF7A4AD0),
    CardColor.wild => const Color(0xFF1B1C21),
  };

  /// Readable foreground on a card color.
  static Color onColor(CardColor c) =>
      c == CardColor.yellow ? const Color(0xFF2A2210) : Colors.white;
}

/// Fredoka is a variable font, so weight is set through its axis.
TextStyle font(
  double size, {
  double weight = 500,
  Color? color,
  double? height,
}) => TextStyle(
  fontFamily: 'Fredoka',
  fontSize: size,
  fontWeight: FontWeight.values[((weight / 100).round() - 1).clamp(0, 8)],
  fontVariations: [FontVariation.weight(weight)],
  color: color ?? Palette.text,
  height: height,
);

ThemeData buildTheme() {
  final scheme =
      ColorScheme.fromSeed(
        seedColor: Palette.brand,
        brightness: Palette.dark ? Brightness.dark : Brightness.light,
      ).copyWith(
        primary: Palette.brand,
        onPrimary: Colors.white,
        surface: Palette.surface,
        onSurface: Palette.text,
        surfaceContainerHighest: Palette.surfaceHigh,
        outline: Palette.line,
      );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: Palette.ink,
    fontFamily: 'Fredoka',
    splashFactory: InkSparkle.splashFactory,
    textTheme: TextTheme(
      headlineMedium: font(28, weight: 700),
      titleLarge: font(20, weight: 650),
      titleMedium: font(16, weight: 600),
      bodyLarge: font(16, weight: 450, color: Palette.text),
      bodyMedium: font(14, weight: 450, color: Palette.text),
      labelLarge: font(15, weight: 600),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(64, 52),
        textStyle: font(17, weight: 650),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(64, 48),
        foregroundColor: Palette.text,
        side: BorderSide(color: Palette.line, width: 1.5),
        textStyle: font(15, weight: 600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: Palette.surface,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: Palette.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: Palette.surfaceHigh,
      contentTextStyle: font(14, weight: 500),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? Colors.white : Palette.muted,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected)
            ? Palette.brand
            : Palette.surfaceHigh,
      ),
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
    ),
  );
}
