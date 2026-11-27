import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'online/browser.dart';
import 'ui/app_update.dart';
import 'ui/home_screen.dart';
import 'ui/theme.dart';
import 'ui/theme_switch.dart';
import 'ui/update_toast.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initStorage();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  watchForUpdates();
  // Invite links look like https://host/#join=ROOMID-1234.
  final fragment = Uri.base.fragment;
  runApp(
    LastCardApp(
      joinCode: fragment.startsWith('join=') ? fragment.substring(5) : null,
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
  late bool _dark = _resolve();

  bool _resolve() => _theme.isDark(
    WidgetsBinding.instance.platformDispatcher.platformBrightness,
  );

  @override
  void initState() {
    super.initState();
    ThemeSwitch.apply(_dark);
    WidgetsBinding.instance.addObserver(this);
    _theme.addListener(_update);
  }

  @override
  void dispose() {
    _theme.removeListener(_update);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangePlatformBrightness() => _update();

  void _update() {
    final dark = _resolve();
    if (dark == _dark || !mounted) return;
    _dark = dark;
    ThemeSwitch.apply(dark);
    setState(() {});
    // Colors are read straight from Palette, so every screen (games in
    // progress included) is rebuilt in place, keeping its state.
    void rebuild(Element e) {
      e.markNeedsBuild();
      e.visitChildren(rebuild);
    }

    (context as Element).visitChildren(rebuild);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
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
