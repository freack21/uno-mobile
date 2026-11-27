import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'ui/app_update.dart';
import 'ui/home_screen.dart';
import 'ui/theme.dart';
import 'ui/update_toast.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
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

class LastCardApp extends StatelessWidget {
  const LastCardApp({super.key, this.joinCode});

  final String? joinCode;

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
      home: HomeScreen(joinCode: joinCode),
    );
  }
}
