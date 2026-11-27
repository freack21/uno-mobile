import 'package:material_ui/material_ui.dart';

import 'package:last_card_core/cards.dart';

/// Design tokens. One dark table palette; card colors carry the brand.
abstract final class Palette {
  static const ink = Color(0xFF14161B);
  static const surface = Color(0xFF1D2027);
  static const surfaceHigh = Color(0xFF272B34);
  static const line = Color(0xFF343944);
  static const text = Color(0xFFF6F3EC);
  static const muted = Color(0xFF9AA1AD);
  static const brand = Color(0xFFE5392C);
  static const cardWhite = Color(0xFFFFFDF7);

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
        brightness: Brightness.dark,
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
        side: const BorderSide(color: Palette.line, width: 1.5),
        textStyle: font(15, weight: 600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Palette.surface,
      showDragHandle: true,
      shape: RoundedRectangleBorder(
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
