import 'dart:math';

import 'cards.dart';
import 'rules.dart';

/// Exact Score: fill your track to the target exactly.
///
/// Each turn draw one card; there is no discarding. A number is crossed off
/// your track if it fits, otherwise it busts and is lost. A Wild adds any
/// 1-9 you choose; Skip skips the next player; Reverse turns the direction;
/// +2 takes two points from an opponent of your choice (lost if nobody has
/// points yet).
enum ScorePhase { draw, decide, over }

class ScorePlayer {
  ScorePlayer(this.seat, this.name, {this.isHuman = false});

  final int seat;
  final String name;
  final bool isHuman;
  int score = 0;
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

  /// An empty game to be filled from a received state (no deck).
  ExactScoreGame.restore({
    required this.players,
    required this.target,
    Random? rng,
  }) : rng = rng ?? Random();

  final List<ScorePlayer> players;
  final int target;
  final Random rng;
  final List<GameCard> drawPile = [];
  final List<GameCard> discardPile = [];

  int current = 0;
  int direction = 1;
  ScorePhase phase = ScorePhase.draw;

  /// Card drawn this turn, waiting to be used (or busting).
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
    _finish(seat);
  }

  /// The drawn card cannot be used (too high, or no +2 target): it is lost.
  void bust(int seat) {
    _require(seat, ScorePhase.decide);
    if (canUse(seat)) throw StateError('This card can be used');
    _finish(seat);
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

/// Bot choice for its drawn card: the value for a Wild, the victim for a
/// +2 (other cards need no choice).
({int? value, int? victim}) decideExactScore(
  ExactScoreGame g,
  int seat,
  Difficulty difficulty,
  Random rng,
) {
  final f = g.drawnFace!;
  final easy = difficulty == Difficulty.easy;
  switch (f.kind) {
    case CardKind.wild || CardKind.wildDraw:
      final values = g.wildValues(seat);
      return (
        value: easy ? values[rng.nextInt(values.length)] : values.last,
        victim: null,
      );
    case CardKind.draw:
      // Hit whoever is closest to winning.
      final victims = g.victims(seat)
        ..sort((a, b) => g.remaining(a).compareTo(g.remaining(b)));
      return (
        value: null,
        victim: easy ? victims[rng.nextInt(victims.length)] : victims.first,
      );
    default:
      return (value: null, victim: null);
  }
}
