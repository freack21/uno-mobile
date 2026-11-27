import 'package:material_ui/material_ui.dart';

import '../online/browser.dart';
import 'theme.dart';

/// Which look the player picked; [system] follows the device.
enum ThemeChoice { system, light, dark }

/// Holds the light/dark choice and remembers it on this device.
class ThemeSwitch extends ChangeNotifier {
  ThemeSwitch._() {
    final stored = readStored(_key);
    choice = ThemeChoice.values.firstWhere(
      (c) => c.name == stored,
      orElse: () => ThemeChoice.system,
    );
  }

  static final instance = ThemeSwitch._();
  static const _key = 'lastcard.theme';

  late ThemeChoice choice;

  /// Whether the dark table is used, given the device's own setting.
  bool isDark(Brightness device) => switch (choice) {
    ThemeChoice.system => device == Brightness.dark,
    ThemeChoice.light => false,
    ThemeChoice.dark => true,
  };

  void pick(ThemeChoice c) {
    if (c == choice) return;
    choice = c;
    writeStored(_key, c.name);
    notifyListeners();
  }

  /// Applies the look: palette, and the browser around the app.
  static void apply(bool dark) {
    Palette.dark = dark;
    setPageColors(background: dark ? '#14161B' : '#F3EFE6', dark: dark);
  }
}
