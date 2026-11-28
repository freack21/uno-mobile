import 'dart:async';
import 'dart:ui' show PlatformDispatcher;

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'package:last_card_core/i18n.dart';

import 'online/browser.dart';
import 'online/links.dart';
import 'online/online_screens.dart';
import 'ui/app_update.dart';
import 'ui/home_screen.dart';
import 'ui/lang_switch.dart';
import 'ui/sfx.dart';
import 'ui/stats.dart';
import 'ui/theme.dart';
import 'ui/theme_switch.dart';
import 'ui/update_toast.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initStorage();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  watchForUpdates();
  // Opened from an invite link: the page address on the web, the link that
  // launched the app on Android.
  final link = kIsWeb ? Uri.base : await AppLinks().getInitialLink();
  runApp(LastCardApp(joinCode: link == null ? null : joinCodeOf(link)));
}

/// Lets an invite opened while the app runs bring up its room.
final navigatorKey = GlobalKey<NavigatorState>();

/// Shows "achievement unlocked" over whatever screen is open.
final messengerKey = GlobalKey<ScaffoldMessengerState>();

void _celebrate(Achievement a) {
  playSfx(Sfx.win);
  messengerKey.currentState?.showSnackBar(
    SnackBar(
      content: Row(
        children: [
          Icon(a.icon, color: const Color(0xFFF4B620)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              t('Achievement unlocked: {name}', {'name': t(a.title)}),
            ),
          ),
        ],
      ),
    ),
  );
}

class LastCardApp extends StatefulWidget {
  const LastCardApp({super.key, this.joinCode});

  final String? joinCode;

  @override
  State<LastCardApp> createState() => _LastCardAppState();
}

class _LastCardAppState extends State<LastCardApp> with WidgetsBindingObserver {
  final _theme = ThemeSwitch.instance;
  final _lang = LangSwitch.instance;
  late bool _dark = _resolveDark();

  static PlatformDispatcher get _device =>
      WidgetsBinding.instance.platformDispatcher;

  bool _resolveDark() => _theme.isDark(_device.platformBrightness);

  @override
  void initState() {
    super.initState();
    ThemeSwitch.apply(_dark);
    lang = _lang.resolve(_device.locales);
    WidgetsBinding.instance.addObserver(this);
    _theme.addListener(_update);
    _lang.addListener(_update);
    Stats.instance.onUnlock = _celebrate;
    if (!kIsWeb) {
      _links = AppLinks().uriLinkStream.listen((link) {
        final code = joinCodeOf(link);
        if (code == null) return;
        navigatorKey.currentState?.push(
          MaterialPageRoute(builder: (_) => OnlineHomeScreen(joinCode: code)),
        );
      });
    }
  }

  StreamSubscription<Uri>? _links;

  @override
  void dispose() {
    _links?.cancel();
    _theme.removeListener(_update);
    _lang.removeListener(_update);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangePlatformBrightness() => _update();

  @override
  void didChangeLocales(List<Locale>? locales) => _update();

  void _update() {
    final dark = _resolveDark();
    final language = _lang.resolve(_device.locales);
    if ((dark == _dark && language == lang) || !mounted) return;
    _dark = dark;
    lang = language;
    ThemeSwitch.apply(dark);
    setState(() {});
    // Colors and words are read straight from Palette and t(), so every
    // screen (games in progress included) is rebuilt in place, keeping its
    // state.
    void rebuild(Element e) {
      e.markNeedsBuild();
      e.visitChildren(rebuild);
    }

    (context as Element).visitChildren(rebuild);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      scaffoldMessengerKey: messengerKey,
      title: 'Last Card',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      // On tablets and desktop browsers keep the phone-shaped layout centered.
      builder: (context, child) => ColoredBox(
        color: Palette.ink,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Stack(
              children: [
                ?child,
                const Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: UpdateToast(),
                ),
              ],
            ),
          ),
        ),
      ),
      home: HomeScreen(joinCode: widget.joinCode),
    );
  }
}
