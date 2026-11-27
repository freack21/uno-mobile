import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:last_card_core/modes.dart';
import 'package:last_card_core/rules.dart';
import 'package:uno_mobile/main.dart';
import 'package:uno_mobile/ui/game_controller.dart';
import 'package:uno_mobile/ui/exact_score_screen.dart';
import 'package:uno_mobile/ui/game_screen.dart';
import 'package:uno_mobile/ui/hold_card_screen.dart';
import 'package:uno_mobile/ui/playing_card.dart';
import 'package:uno_mobile/ui/guide_screen.dart';
import 'package:uno_mobile/ui/mode_screen.dart';
import 'package:uno_mobile/ui/theme.dart';
import 'package:uno_mobile/ui/update_toast.dart';
import 'package:uno_mobile/ui/home_screen.dart';
import 'package:uno_mobile/ui/sfx.dart';
import 'package:uno_mobile/ui/app_update.dart';

bool toastHidden(WidgetTester tester) => tester
    .widget<IgnorePointer>(
      find
          .descendant(
            of: find.byType(UpdateToast),
            matching: find.byType(IgnorePointer),
          )
          .first,
    )
    .ignoring;

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

      if (mode.kind != GameKind.shedding) {
        // Party games are covered by their own tests below.
        await tester.pumpWidget(const SizedBox());
        return;
      }
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

  testWidgets('a banner shows once, not again on later rebuilds', (
    tester,
  ) async {
    var banner = const TableBanner(1, 'SKIP');
    late StateSetter rebuild;
    await tester.pumpWidget(
      wrap(
        StatefulBuilder(
          builder: (context, setState) {
            rebuild = setState;
            return Scaffold(body: TableBannerView(banner: banner));
          },
        ),
      ),
    );
    // First appearance comes with the update that posts the banner.
    rebuild(() => banner = const TableBanner(2, 'SKIP'));
    await tester.pump();
    expect(find.text('SKIP'), findsOneWidget);

    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(milliseconds: 500)); // fade-out
    expect(find.text('SKIP'), findsNothing);

    // Other turns rebuild the table with the same (old) banner.
    for (var i = 0; i < 3; i++) {
      rebuild(() {});
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('SKIP'), findsNothing, reason: 'stale banner re-shown');
    }

    // A genuinely new banner still shows.
    rebuild(() => banner = const TableBanner(3, 'REVERSE'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('REVERSE'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('round opens with shuffle, deal, first card and turn order', (
    tester,
  ) async {
    final c = GameController(
      mode: gameModes.first,
      rules: gameModes.first.rules,
      playerCount: 4,
      difficulty: Difficulty.hard,
    );
    addTearDown(c.dispose);
    final moves = c.game.events.length;

    expect(c.intro, IntroStep.shuffle);
    expect([for (var s = 0; s < 4; s++) c.visibleCards(s)], [0, 0, 0, 0]);

    await tester.pump(const Duration(milliseconds: 1600));
    expect(c.intro, IntroStep.deal);
    // The player after the dealer receives the first card.
    await tester.pump(const Duration(milliseconds: 100));
    expect(c.visibleCards(c.game.nextSeat(c.game.dealer)), 1);

    await tester.pump(const Duration(seconds: 3));
    expect(c.intro, IntroStep.flip);
    expect([for (var s = 0; s < 4; s++) c.visibleCards(s)], [7, 7, 7, 7]);

    await tester.pump(const Duration(milliseconds: 1200));
    expect(c.intro, IntroStep.order);
    expect(c.turnOrder.first, c.game.current);
    expect(c.turnOrder.toSet().length, 4);
    // Nobody may act during the opening.
    expect(c.draw(), isNotNull);
    expect(c.game.events.length, moves);

    await tester.pump(const Duration(milliseconds: 2700));
    expect(c.intro, isNull);
  });

  testWidgets('tapping skips the opening', (tester) async {
    final c = GameController(
      mode: gameModes.first,
      rules: gameModes.first.rules,
      playerCount: 3,
      difficulty: Difficulty.normal,
    );
    addTearDown(c.dispose);
    await tester.pump(const Duration(milliseconds: 1700));
    c.skipIntro();
    expect(c.intro, isNull);
    expect(c.visibleCards(0), 7);
  });

  testWidgets('update toast appears when a new version is ready', (
    tester,
  ) async {
    await phone(tester);
    addTearDown(() => updateReady.value = false);
    var updates = 0;
    await tester.pumpWidget(
      wrap(Scaffold(body: UpdateToast(onUpdate: () => updates++))),
    );
    expect(toastHidden(tester), isTrue);

    updateReady.value = true;
    await tester.pumpAndSettle();
    expect(find.text('Update available'), findsOneWidget);
    expect(toastHidden(tester), isFalse);

    await tester.tap(find.text('Update'));
    await tester.pump();
    expect(updates, 1);
    // Shows progress instead of allowing a second tap.
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('update toast can be postponed', (tester) async {
    await phone(tester);
    addTearDown(() => updateReady.value = false);
    updateReady.value = true;
    await tester.pumpWidget(wrap(const Scaffold(body: UpdateToast())));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Later'));
    await tester.pumpAndSettle();
    expect(toastHidden(tester), isTrue);
  });

  testWidgets('sound button mutes and unmutes', (tester) async {
    addTearDown(() => setSoundOn(true));
    await tester.pumpWidget(wrap(const Scaffold(body: SoundButton())));
    expect(soundOn.value, isTrue);
    expect(find.byIcon(Icons.volume_up_rounded), findsOneWidget);
    await tester.tap(find.byType(SoundButton));
    await tester.pump();
    expect(soundOn.value, isFalse);
    expect(find.byIcon(Icons.volume_off_rounded), findsOneWidget);
    await tester.tap(find.byType(SoundButton));
    await tester.pump();
    expect(soundOn.value, isTrue);
  });

  GameMode party(GameKind kind) => gameModes.firstWhere((m) => m.kind == kind);

  testWidgets('Exact Score plays through the screen', (tester) async {
    await phone(tester);
    await tester.pumpWidget(
      wrap(
        ExactScoreScreen(
          mode: party(GameKind.exactScore),
          players: 3,
          difficulty: Difficulty.hard,
          target: 20,
        ),
      ),
    );
    expect(find.text('TARGET 20'), findsOneWidget);
    var drew = 0;
    for (var i = 0; i < 80; i++) {
      await tester.pump(const Duration(milliseconds: 600));
      if (find.text('Tap to draw').evaluate().isNotEmpty) {
        await tester.tap(find.text('Tap to draw'));
        drew++;
        continue;
      }
      // Wild values and +2 victims are the only choices.
      final choice = find.byWidgetPredicate(
        (w) =>
            w.key is ValueKey<String> &&
            RegExp(r'^(wild|victim)-')
                .hasMatch((w.key! as ValueKey<String>).value),
      );
      if (choice.evaluate().isNotEmpty) await tester.tap(choice.first);
    }
    expect(drew, greaterThan(0));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Hold Card plays through the screen', (tester) async {
    await phone(tester);
    await tester.pumpWidget(
      wrap(
        HoldCardScreen(
          mode: party(GameKind.holdCard),
          players: 4,
          difficulty: Difficulty.normal,
        ),
      ),
    );
    expect(find.text('HOLD CARD'), findsOneWidget);
    var placed = 0;
    for (var i = 0; i < 80; i++) {
      await tester.pump(const Duration(milliseconds: 500));
      if (find.text('1 · Call a number').evaluate().isNotEmpty) {
        await tester.tap(find.text('7').last);
        await tester.pump();
        // The hand is the last row of cards on screen.
        await tester.tap(find.byType(PlayingCard).last, warnIfMissed: false);
        placed++;
      } else if (find.text('MATCH! Press HOLD!').evaluate().isNotEmpty) {
        await tester.tap(find.text('HOLD CARD'));
      }
    }
    expect(placed, greaterThan(0));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('basics guide renders', (tester) async {
    await phone(tester);
    await tester.pumpWidget(wrap(const GuideScreen()));
    expect(find.text('Action cards'), findsOneWidget);
  });
}
