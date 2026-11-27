import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:uno_mobile/game/modes.dart';
import 'package:uno_mobile/game/rules.dart';
import 'package:uno_mobile/main.dart';
import 'package:uno_mobile/ui/game_screen.dart';
import 'package:uno_mobile/ui/guide_screen.dart';
import 'package:uno_mobile/ui/mode_screen.dart';
import 'package:uno_mobile/ui/theme.dart';

Widget wrap(Widget child) => MaterialApp(theme: buildTheme(), home: child);

Future<void> phone(WidgetTester tester) async {
  tester.view.physicalSize = const Size(390 * 3, 844 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

void main() {
  testWidgets('home lists every mode', (tester) async {
    // A tall viewport builds every tile of the lazy list at once.
    tester.view.physicalSize = const Size(390, 3200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const LastCardApp());
    expect(find.text('LAST CARD'), findsOneWidget);
    for (final m in gameModes) {
      expect(find.text(m.tagline), findsOneWidget, reason: m.id);
    }
  });

  for (final mode in gameModes) {
    testWidgets('${mode.name}: setup, guide and a few turns', (tester) async {
      await phone(tester);
      final old = FlutterError.onError;
      FlutterError.onError = (d) {
        debugPrint('DETAILS: ${d.toString()}');
        old?.call(d);
      };
      addTearDown(() => FlutterError.onError = old);
      await tester.pumpWidget(wrap(ModeScreen(mode: mode)));
      expect(find.text('Play ${mode.name}'), findsOneWidget);

      await tester.pumpWidget(wrap(GuideScreen(mode: mode)));
      expect(find.text(mode.guide.first.title), findsOneWidget);

      await tester.pumpWidget(
        wrap(
          GameScreen(
            mode: mode,
            rules: mode.rules,
            players: mode.defaultPlayers,
            difficulty: Difficulty.hard,
          ),
        ),
      );
      // Act only through the draw pile / buttons so no picker is needed.
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 700));
        for (final label in ['Keep', 'Draw']) {
          final f = find.text(label);
          if (f.evaluate().isNotEmpty) {
            await tester.tap(f.first, warnIfMissed: false);
            break;
          }
        }
        final take = find.textContaining('Take +');
        if (take.evaluate().isNotEmpty) {
          await tester.tap(take.first, warnIfMissed: false);
        }
      }
      await tester.pump(const Duration(seconds: 2));
      expect(tester.takeException(), isNull);
      // Unmount to cancel the controller's timers.
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('basics guide renders', (tester) async {
    await phone(tester);
    await tester.pumpWidget(wrap(const GuideScreen()));
    expect(find.text('Action cards'), findsOneWidget);
  });
}
