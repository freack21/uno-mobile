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
  runApp(const LastCardApp());
}

class LastCardApp extends StatelessWidget {
  const LastCardApp({super.key});

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
      home: const HomeScreen(),
    );
  }
}
