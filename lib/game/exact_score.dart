import 'dart:math';

import 'cards.dart';
import 'rules.dart';

/// Exact Score: fill your track to the target exactly.
///
/// Each turn draw one card, then use it or discard it. Numbers add their
/// value but never past the target; a Wild adds any 1-9 you choose; Skip
/// skips the next player; Reverse turns the direction; +2 takes two points
/// from an opponent. Three discards in a row cost your next turn.
enum ScorePhase { draw, decide, over }

class ScorePlayer {
  ScorePlayer(this.seat, this.name, {this.isHuman = false});

  final int seat;
  final String name;
  final bool isHuman;
  int score = 0;

  /// Discards in a row; at [ExactScoreGame.maxDiscards] the next turn is lost.
  int discards = 0;
  bool skipNext = false;
}

class ExactScoreGame {
  ExactScoreGame({required this.players, required this.target, Random? rng})
    : rng = rng ?? Random() {
    if (players.length < 2) throw ArgumentError('Need at least 2 players');
    if (target < 10) throw ArgumentError('Target too small');
    drawPile.addAll(buildDeck(DeckType.classic, this.rng));
    current = this.rng.nextInt(players.length);
  }

  static const maxDiscards = 3;

  final List<ScorePlayer> players;
  final int target;
  final Random rng;
  final List<GameCard> drawPile = [];
  final List<GameCard> discardPile = [];

  int current = 0;
  int direction = 1;
  ScorePhase phase = ScorePhase.draw;

  /// Card drawn this turn, waiting to be used or discarded.
  GameCard? drawn;
  int? winner;

  /// Players whose turn was skipped by the last advance.
  List<int> lastSkipped = const [];

  CardFace? get drawnFace => drawn?.light;
  int remaining(int seat) => target - players[seat].score;

  int nextSeat(int from) {
    final n = players.length;
    return ((from + direction) % n + n) % n;
  }

  GameCard draw(int seat) {
    _require(seat, ScorePhase.draw);
    if (drawPile.isEmpty) {
      drawPile
        ..addAll(discardPile)
        ..shuffle(rng);
      discardPile.clear();
    }
    drawn = drawPile.removeLast();
    phase = ScorePhase.decide;
    return drawn!;
  }

  /// Values a Wild can add for [seat].
  List<int> wildValues(int seat) => [
    for (var v = 1; v <= min(9, remaining(seat)); v++) v,
  ];

  /// Opponents a +2 can hit (they need points to lose).
  List<int> victims(int seat) => [
    for (final p in players)
      if (p.seat != seat && p.score > 0) p.seat,
  ];

  bool canUse(int seat) {
    if (phase != ScorePhase.decide || seat != current) return false;
    final f = drawnFace!;
    return switch (f.kind) {
      CardKind.number => players[seat].score + f.value <= target,
      CardKind.wild || CardKind.wildDraw => wildValues(seat).isNotEmpty,
      CardKind.draw => victims(seat).isNotEmpty,
      _ => true,
    };
  }

  /// Uses the drawn card. A Wild needs [value]; a +2 needs [victim].
  void use(int seat, {int? value, int? victim}) {
    if (!canUse(seat)) throw StateError('Card cannot be used');
    final f = drawnFace!;
    final p = players[seat];
    switch (f.kind) {
      case CardKind.number:
        p.score += f.value;
      case CardKind.wild || CardKind.wildDraw:
        if (value == null || !wildValues(seat).contains(value)) {
          throw StateError('Pick a value from 1 to ${wildValues(seat).last}');
        }
        p.score += value;
      case CardKind.skip:
        players[nextSeat(seat)].skipNext = true;
      case CardKind.reverse:
        if (players.length == 2) {
          players[nextSeat(seat)].skipNext = true;
        } else {
          direction = -direction;
        }
      case CardKind.draw:
        if (victim == null || !victims(seat).contains(victim)) {
          throw StateError('Pick an opponent with points');
        }
        final v = players[victim];
        v.score = max(0, v.score - 2);
      default:
        break;
    }
    p.discards = 0;
    _finish(seat);
  }

  /// Discards the drawn card. The third discard in a row costs a turn.
  /// Returns true if that penalty was triggered.
  bool discard(int seat) {
    _require(seat, ScorePhase.decide);
    final p = players[seat];
    p.discards++;
    final penalty = p.discards >= maxDiscards;
    if (penalty) {
      p.discards = 0;
      p.skipNext = true;
    }
    _finish(seat);
    return penalty;
  }

  void _finish(int seat) {
    discardPile.add(drawn!);
    drawn = null;
    if (players[seat].score == target) {
      winner = seat;
      phase = ScorePhase.over;
      return;
    }
    final skipped = <int>[];
    var s = nextSeat(seat);
    while (players[s].skipNext) {
      players[s].skipNext = false;
      skipped.add(s);
      s = nextSeat(s);
    }
    lastSkipped = skipped;
    current = s;
    phase = ScorePhase.draw;
  }

  void _require(int seat, ScorePhase want) {
    if (phase != want) throw StateError('Not the time for that');
    if (seat != current) throw StateError('Not your turn');
  }
}

class ScoreMove {
  const ScoreMove.use({this.value, this.victim}) : use = true;
  const ScoreMove.discard() : use = false, value = null, victim = null;

  final bool use;
  final int? value;
  final int? victim;
}

/// Bot choice for the drawn card.
ScoreMove decideExactScore(
  ExactScoreGame g,
  int seat,
  Difficulty difficulty,
  Random rng,
) {
  if (!g.canUse(seat)) return const ScoreMove.discard();
  final f = g.drawnFace!;
  final easy = difficulty == Difficulty.easy;
  switch (f.kind) {
    case CardKind.wild || CardKind.wildDraw:
      final values = g.wildValues(seat);
      return ScoreMove.use(
        value: easy ? values[rng.nextInt(values.length)] : values.last,
      );
    case CardKind.draw:
      // Hit whoever is closest to winning.
      final victims = g.victims(seat)
        ..sort((a, b) => g.remaining(a).compareTo(g.remaining(b)));
      return ScoreMove.use(
        victim: easy ? victims[rng.nextInt(victims.length)] : victims.first,
      );
    case CardKind.number:
      // Beginners sometimes hold out for a "better" card.
      if (easy && rng.nextDouble() < 0.12) return const ScoreMove.discard();
      return const ScoreMove.use();
    default:
      return const ScoreMove.use();
  }
}
