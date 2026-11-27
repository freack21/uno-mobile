import 'dart:async';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:last_card_core/exact_score.dart';
import 'package:last_card_core/game.dart';
import 'package:last_card_core/hold_card.dart';
import 'package:last_card_core/modes.dart';
import 'package:last_card_core/party_tables.dart';
import 'package:last_card_core/rules.dart';
import 'package:last_card_core/shed_table.dart';
import 'package:last_card_core/table.dart';

/// Waits until [t] reports the end of its match.
Future<void> finish(TableRuntime t) async {
  final done = Completer<void>();
  t.onChange = () {
    if (t.isOver && !done.isCompleted) done.complete();
  };
  t.start();
  await done.future.timeout(const Duration(seconds: 60));
  t.dispose();
}

void expectStandings(TableRuntime t, int players) {
  final seats = t.standings().expand((g) => g).toList();
  expect(seats.toSet().length, players, reason: 'every seat placed once');
  expect(seats.length, players);
}

void main() {
  // Two "people" who never act (played for them after idleMs) plus bots.
  const pace = 0.0002;
  const idle = 30;

  for (final mode in gameModes.where((m) => m.kind == GameKind.shedding)) {
    test('${mode.name}: table plays a full match', () async {
      final count = mode.rules.teams ? 4 : max(mode.minPlayers, 3);
      final t = ShedTable(
        game: Game(
          rules: mode.rules,
          players: [for (var i = 0; i < count; i++) Player(i, 'P$i')],
          rng: Random(7),
        ),
        humans: {0, 1},
        pace: pace,
        idleMs: idle,
        rng: Random(7),
      );
      await finish(t);
      expectStandings(t, count);
    });
  }

  test('Exact Score table plays a full match', () async {
    final t = ExactScoreTable(
      game: ExactScoreGame(
        players: [for (var i = 0; i < 4; i++) ScorePlayer(i, 'P$i')],
        target: 20,
        rng: Random(3),
      ),
      humans: {0, 1},
      pace: pace,
      idleMs: idle,
      rng: Random(3),
    );
    await finish(t);
    expect(t.standings().first.single, t.game.winner);
    expectStandings(t, 4);
  });

  test('Hold Card table plays a full match', () async {
    final t = HoldCardTable(
      game: HoldCardGame(
        players: [for (var i = 0; i < 4; i++) HoldPlayer(i, 'P$i')],
        rng: Random(4),
      ),
      humans: {0, 1},
      pace: pace,
      idleMs: idle,
      rng: Random(4),
    );
    await finish(t);
    expect(t.standings().first, t.game.winners);
    expectStandings(t, 4);
  });

  test('people act through the table; illegal moves are refused', () async {
    final t = ShedTable(
      game: Game(
        rules: const RuleSet(),
        players: [for (var i = 0; i < 3; i++) Player(i, 'P$i')],
        rng: Random(1),
      ),
      humans: {0, 1, 2},
      pace: pace,
      introMs: 0,
    );
    t.start();
    expect(t.opening, isTrue);
    expect(t.draw(t.game.current), isFalse, reason: 'still opening');
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(t.opening, isFalse);
    final seat = t.game.current;
    final other = (seat + 1) % 3;
    expect(t.draw(other), isFalse, reason: 'not their turn');
    expect(t.play(seat, -5), isFalse, reason: 'card not in hand');
    expect(t.draw(seat), isTrue);
    t.dispose();
  });

  test('rankBy shares places on ties', () {
    expect(rankBy([0, 1, 2, 3], (s) => [3, 1, 3, 0][s]), [
      [3],
      [1],
      [0, 2],
    ]);
  });
}
