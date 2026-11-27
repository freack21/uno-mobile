import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:last_card_core/exact_score.dart';
import 'package:last_card_core/game.dart';
import 'package:last_card_core/hold_card.dart';
import 'package:last_card_core/modes.dart';
import 'package:last_card_core/party_tables.dart';
import 'package:last_card_core/rules.dart';
import 'package:last_card_core/shed_table.dart';
import 'package:last_card_core/snapshot.dart';
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

  test('Exact Score only animates the latest gain', () async {
    final t = ExactScoreTable(
      game: ExactScoreGame(
        players: [for (var i = 0; i < 3; i++) ScorePlayer(i, 'P$i')],
        target: 30,
        rng: Random(5),
      ),
      humans: {},
      pace: pace,
      rng: Random(5),
    );
    var gains = 0;
    var draws = 0;
    final done = Completer<void>();
    t.onChange = () {
      if (t.fillFrom.isNotEmpty) gains++;
      if (t.stage == ExactStage.tease) {
        draws++;
        // A fresh draw must not replay anyone's earlier crossing-off.
        expect(t.fillFrom, isEmpty);
      }
      if (t.isOver && !done.isCompleted) done.complete();
    };
    t.start();
    await done.future.timeout(const Duration(seconds: 60));
    t.dispose();
    expect(draws, greaterThan(1));
    expect(gains, greaterThan(0));
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

  group('saved tables pick up where they stopped', () {
    /// Runs [t] for [steps] changes, saves it, throws it away, loads the
    /// save and plays that to the end.
    Future<TableRuntime> roundTrip(TableRuntime t, int steps) async {
      final saved = Completer<Map<String, dynamic>>();
      var n = 0;
      t.onChange = () {
        if (++n == steps && !saved.isCompleted && !t.isOver) {
          // Through JSON, as on disk.
          saved.complete(jsonDecode(jsonEncode(saveTable(t))));
        }
      };
      t.start();
      final j = await saved.future.timeout(const Duration(seconds: 30));
      t.dispose();
      final loaded = loadTable(j, pace: pace, idleMs: idle, introMs: 0);
      expect(
        jsonEncode(saveTable(loaded)),
        jsonEncode(j),
        reason: 'a loaded table saves the same state',
      );
      final done = Completer<void>();
      loaded.onChange = () {
        if (loaded.isOver && !done.isCompleted) done.complete();
      };
      resumeTable(loaded);
      await done.future.timeout(const Duration(seconds: 60));
      loaded.dispose();
      return loaded;
    }

    for (final mode in gameModes.where(
      (m) => m.kind == GameKind.shedding && !m.isCustom,
    )) {
      test(mode.name, () async {
        final count = mode.rules.teams ? 4 : max(mode.minPlayers, 3);
        final g = Game(
          rules: mode.rules,
          players: [for (var i = 0; i < count; i++) Player(i, 'P$i')],
          rng: Random(11),
        );
        final total = [
          ...g.drawPile,
          ...g.discard,
          for (final p in g.players) ...p.hand,
        ].length;
        final t = ShedTable(
          game: g,
          humans: {0, 1},
          pace: pace,
          idleMs: idle,
          introMs: 0,
          rng: Random(11),
        );
        final after = await roundTrip(t, 8) as ShedTable;
        final lg = after.game;
        expect(lg.isMatchOver, isTrue);
        expect(
          [
            ...lg.drawPile,
            ...lg.discard,
            for (final p in lg.players) ...p.hand,
          ].length,
          total,
          reason: 'no card lost or made up',
        );
        expectStandings(after, count);
      });
    }

    for (final steps in [2, 25, 60, 120]) {
      test('Point Race saved after $steps changes', () async {
        final mode = gameModes.firstWhere((m) => m.id == 'points');
        final t = ShedTable(
          game: Game(
            rules: mode.rules.copyWith(targetScore: 250),
            players: [for (var i = 0; i < 3; i++) Player(i, 'P$i')],
            rng: Random(steps),
          ),
          humans: {0},
          pace: pace,
          idleMs: idle,
          introMs: 0,
          roundBreakMs: 0,
          rng: Random(steps),
        );
        final after = await roundTrip(t, steps) as ShedTable;
        expect(after.game.isMatchOver, isTrue);
        expectStandings(after, 3);
      });
    }

    for (final steps in [3, 9, 20]) {
      test('Exact Score saved after $steps changes', () async {
        final t = ExactScoreTable(
          game: ExactScoreGame(
            players: [for (var i = 0; i < 3; i++) ScorePlayer(i, 'P$i')],
            target: 25,
            rng: Random(4),
          ),
          humans: {0},
          pace: pace,
          idleMs: idle,
          rng: Random(4),
        );
        final after = await roundTrip(t, steps) as ExactScoreTable;
        expect(after.game.winner, isNotNull);
        expectStandings(after, 3);
      });
    }

    for (final steps in [4, 12, 30]) {
      test('Hold Card saved after $steps changes', () async {
        final t = HoldCardTable(
          game: HoldCardGame(
            players: [for (var i = 0; i < 3; i++) HoldPlayer(i, 'P$i')],
            guess: HoldGuess.color,
            rng: Random(6),
          ),
          humans: {0},
          pace: pace,
          idleMs: idle,
          rng: Random(6),
        );
        final after = await roundTrip(t, steps) as HoldCardTable;
        expect(after.game.winners, isNotEmpty);
        expectStandings(after, 3);
      });
    }
  });

  test('rankBy shares places on ties', () {
    expect(rankBy([0, 1, 2, 3], (s) => [3, 1, 3, 0][s]), [
      [3],
      [1],
      [0, 2],
    ]);
  });
}
