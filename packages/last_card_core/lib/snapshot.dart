/// Complete saves of running tables, so a server can stop and pick a match
/// up again where it was. Unlike the views in protocol.dart nothing is
/// hidden: every hand and the order of every pile is kept.
library;

import 'dart:math';

import 'cards.dart';
import 'game.dart';
import 'hold_card.dart';
import 'party_tables.dart';
import 'protocol.dart';
import 'rules.dart';
import 'shed_table.dart';
import 'table.dart';

List<Object?> _cards(Iterable<GameCard> cards) => [
  for (final c in cards) cardToJson(c),
];

List<GameCard> _cardsFrom(Object? j) => [
  for (final c in j as List) cardFromJson(c as List),
];

/// Everything needed to rebuild [t] with [loadTable].
Map<String, Object?> saveTable(TableRuntime t) {
  final base = {'humans': t.humans.toList(), 'notes': t.noteId};
  switch (t) {
    case ShedTable():
      final g = t.game;
      return {
        ...base,
        'kind': 'shed',
        'game': {
          ...gameView(g, 0),
          'humanFlags': [for (final p in g.players) p.isHuman],
          'hands': [for (final p in g.players) _cards(p.hand)],
          'pile': _cards(g.drawPile),
          'guilty': g.challenge?.guilty,
          'drawnCard': g.drawnCard == null ? null : cardToJson(g.drawnCard!),
        },
        'opening': t.opening,
        'knockouts': t.knockouts,
      };
    case ExactScoreTable():
      final g = t.game;
      return {
        ...base,
        'kind': 'exact',
        'game': {
          ...exactView(g, 0),
          'humanFlags': [for (final p in g.players) p.isHuman],
          'pile': _cards(g.drawPile),
          'discardPile': _cards(g.discardPile),
        },
        'stage': t.stage?.index,
        'turnId': t.turnId,
        'last': t.last == null ? null : cardToJson(t.last!),
      };
    case HoldCardTable():
      final g = t.game;
      return {
        ...base,
        'kind': 'hold',
        'game': {
          ...holdView(g, 0),
          'humanFlags': [for (final p in g.players) p.isHuman],
          'hands': [for (final p in g.players) _cards(p.hand)],
          'stockCards': _cards(g.stock),
          'boxCards': _cards(g.box),
          'handSize': g.handSize,
        },
        'playId': t.playId,
      };
    default:
      throw ArgumentError('Unknown table ${t.runtimeType}');
  }
}

/// Rebuilds a table saved by [saveTable]. It is idle until [resumeTable].
TableRuntime loadTable(
  Map<String, dynamic> j, {
  Difficulty difficulty = Difficulty.normal,
  double pace = 1.0,
  int? idleMs,
  int introMs = 8400,
  Random? rng,
}) {
  final humans = {for (final s in j['humans'] as List) s as int};
  final gj = j['game'] as Map<String, dynamic>;
  final flags = [for (final f in gj['humanFlags'] as List) f as bool];
  final TableRuntime t;
  switch (j['kind']) {
    case 'shed':
      final g = gameFromView(gj, humans: flags);
      final hands = gj['hands'] as List;
      for (var i = 0; i < g.players.length; i++) {
        g.players[i].hand
          ..clear()
          ..addAll(_cardsFrom(hands[i]));
      }
      g.drawPile
        ..clear()
        ..addAll(_cardsFrom(gj['pile']));
      final offender = gj['challenger'] as int?;
      g.challenge = offender == null
          ? null
          : PendingChallenge(offender, gj['guilty'] as bool);
      final drawn = gj['drawnCard'] as List?;
      g.drawnCard = drawn == null ? null : cardFromJson(drawn);
      t =
          ShedTable(
              game: g,
              humans: humans,
              difficulty: difficulty,
              pace: pace,
              idleMs: idleMs,
              introMs: introMs,
              rng: rng,
            )
            ..opening = j['opening'] as bool
            ..knockouts.addAll([
              for (final s in j['knockouts'] as List) s as int,
            ]);
    case 'exact':
      final g = exactFromView(gj, humans: flags);
      g.drawPile
        ..clear()
        ..addAll(_cardsFrom(gj['pile']));
      g.discardPile.addAll(_cardsFrom(gj['discardPile']));
      final stage = j['stage'] as int?;
      final last = j['last'] as List?;
      t =
          ExactScoreTable(
              game: g,
              humans: humans,
              difficulty: difficulty,
              pace: pace,
              idleMs: idleMs,
              rng: rng,
            )
            ..stage = stage == null ? null : ExactStage.values[stage]
            ..turnId = j['turnId'] as int
            ..last = last == null ? null : cardFromJson(last);
    case 'hold':
      final view = holdFromView(gj, humans: flags);
      // Same state with the real cards and hand size.
      final g = HoldCardGame.restore(
        players: view.players,
        guess: view.guess,
        rng: rng,
        handSize: gj['handSize'] as int,
      );
      final hands = gj['hands'] as List;
      for (var i = 0; i < g.players.length; i++) {
        g.players[i].hand
          ..clear()
          ..addAll(_cardsFrom(hands[i]));
      }
      g.stock.addAll(_cardsFrom(gj['stockCards']));
      g.box.addAll(_cardsFrom(gj['boxCards']));
      g.current = view.current;
      g.direction = view.direction;
      g.phase = view.phase;
      g.last = view.last;
      g.presses.addAll(view.presses);
      g.winners = view.winners;
      t = HoldCardTable(
        game: g,
        humans: humans,
        difficulty: difficulty,
        pace: pace,
        idleMs: idleMs,
        rng: rng,
      )..playId = j['playId'] as int;
    default:
      throw ArgumentError('Unknown table kind ${j['kind']}');
  }
  t.noteId = j['notes'] as int;
  return t;
}

/// Starts a loaded table's clocks again: a round opening plays again, any
/// other moment carries on (bots move, idle players are played for).
void resumeTable(TableRuntime t) {
  if (t is ShedTable && t.opening) {
    t.start();
  } else {
    t.resume();
  }
}
