import 'package:material_ui/material_ui.dart';

import 'package:last_card_core/i18n.dart';

import '../online/browser.dart';

/// Which language the player picked; null follows the device.
class LangSwitch extends ChangeNotifier {
  LangSwitch._() {
    final stored = readStored(_key);
    choice = Lang.values.where((l) => l.name == stored).firstOrNull;
  }

  static final instance = LangSwitch._();
  static const _key = 'lastcard.lang';

  Lang? choice;

  /// The language to show, given the device's own languages.
  Lang resolve(List<Locale> device) =>
      choice ??
      (device.isNotEmpty && device.first.languageCode == 'id'
          ? Lang.id
          : Lang.en);

  void pick(Lang? l) {
    if (l == choice) return;
    choice = l;
    writeStored(_key, l?.name);
    notifyListeners();
  }
}
