import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:uno_mobile/online/browser.dart';
import 'package:uno_mobile/ui/theme.dart';
import 'package:uno_mobile/ui/theme_switch.dart';

void main() {
  test('the choice follows the device or overrides it, and is remembered', () {
    final t = ThemeSwitch.instance;
    expect(t.choice, ThemeChoice.system);
    expect(t.isDark(Brightness.dark), isTrue);
    expect(t.isDark(Brightness.light), isFalse);

    t.pick(ThemeChoice.light);
    expect(t.isDark(Brightness.dark), isFalse);
    expect(readStored('lastcard.theme'), 'light');

    t.pick(ThemeChoice.dark);
    expect(t.isDark(Brightness.light), isTrue);
    t.pick(ThemeChoice.system);
  });

  test('the palette switches between the dark and light table', () {
    ThemeSwitch.apply(false);
    expect(Palette.ink.computeLuminance(), greaterThan(0.7));
    expect(Palette.text.computeLuminance(), lessThan(0.1));
    ThemeSwitch.apply(true);
    expect(Palette.ink.computeLuminance(), lessThan(0.05));
    expect(Palette.text.computeLuminance(), greaterThan(0.8));
  });
}
