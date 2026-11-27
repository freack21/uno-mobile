import 'dart:math';

import 'cards.dart';
import 'rules.dart';

/// Hold Card: everyone secretly picks a number card, all are revealed into
/// the box together. If two or more show the same number, everyone races to
/// press HOLD; the slowest (or anyone who never presses) takes the whole box.
/// Pressing when nothing matches takes the box too. Empty your hand to win.
enum HoldPhase { choose, reveal, over }

class HoldPlayer {
  HoldPlayer(this.seat, this.name, {this.isHuman = false});

  final int seat;
  final String name;
  final bool isHuman;
  final List<GameCard> hand = [];
}

class HoldResult {
  const HoldResult({this.taker, this.taken = 0, this.falsePress = false});

  /// Who took the box; null when nothing matched and the box stays.
  final int? taker;
  final int taken;

  /// The taker pressed HOLD although nothing matched.
  final bool falsePress;
}

class HoldCardGame {
  HoldCardGame({required this.players, Random? rng, this.handSize = 10})
    : rng = rng ?? Random() {
    if (players.length < 2) throw ArgumentError('Need at least 2 players');
    // Number cards only: 76 in a classic deck, enough for 6 x 10.
    final deck = buildDeck(
      DeckType.classic,
      this.rng,
    ).where((c) => c.light.kind == CardKind.number).toList();
    for (var i = 0; i < handSize; i++) {
      for (final p in players) {
        p.hand.add(deck.removeLast());
      }
    }
  }

  final List<HoldPlayer> players;
  final Random rng;
  final int handSize;

  /// Cards waiting for someone to take them.
  final List<GameCard> box = [];

  /// Cards picked this round (seat -> card), face down until the reveal.
  final Map<int, GameCard> picks = {};

  /// Cards revealed in the last reveal, in seat order.
  List<(int, GameCard)> revealed = const [];

  /// Numbers that showed up more than once in the last reveal.
  Set<int> matches = const {};

  /// Seats in the order they pressed HOLD this reveal.
  final List<int> presses = [];

  HoldPhase phase = HoldPhase.choose;
  int round = 1;
  List<int> winners = const [];

  bool get isMatch => matches.isNotEmpty;
  bool get allPicked => picks.length == players.length;

  void pick(int seat, GameCard card) {
    if (phase != HoldPhase.choose) throw StateError('Not picking now');
    if (picks.containsKey(seat)) throw StateError('Already picked');
    final hand = players[seat].hand;
    if (!hand.any((c) => c.id == card.id)) throw StateError('Not in hand');
    hand.removeWhere((c) => c.id == card.id);
    picks[seat] = card;
  }

  void reveal() {
    if (phase != HoldPhase.choose || !allPicked) {
      throw StateError('Everyone must pick first');
    }
    revealed = [for (final p in players) (p.seat, picks[p.seat]!)];
    picks.clear();
    box.addAll(revealed.map((r) => r.$2));
    final counts = <int, int>{};
    for (final (_, c) in revealed) {
      counts[c.light.value] = (counts[c.light.value] ?? 0) + 1;
    }
    matches = {
      for (final e in counts.entries)
        if (e.value > 1) e.key,
    };
    presses.clear();
    phase = HoldPhase.reveal;
  }

  /// [seat] presses HOLD. Without a match this is a false press: they take
  /// the box at once. Returns the result when the reveal is settled.
  HoldResult? press(int seat) {
    if (phase != HoldPhase.reveal || presses.contains(seat)) return null;
    if (!isMatch) return _settle(seat, falsePress: true);
    presses.add(seat);
    return presses.length == players.length ? settle() : null;
  }

  /// Ends the reveal: with a match, the slowest presser (or one of those who
  /// never pressed) takes the box; without one the box carries over.
  HoldResult settle() {
    if (phase != HoldPhase.reveal) throw StateError('Nothing to settle');
    if (!isMatch) return _settle(null);
    final missed = [
      for (final p in players)
        if (!presses.contains(p.seat)) p.seat,
    ];
    final taker = missed.isEmpty
        ? presses.last
        : missed[rng.nextInt(missed.length)];
    return _settle(taker);
  }

  HoldResult _settle(int? taker, {bool falsePress = false}) {
    final taken = taker == null ? 0 : box.length;
    if (taker != null) {
      players[taker].hand.addAll(box);
      box.clear();
    }
    final empty = [
      for (final p in players)
        if (p.hand.isEmpty) p.seat,
    ];
    if (empty.isNotEmpty) {
      winners = empty;
      phase = HoldPhase.over;
    } else {
      round++;
      phase = HoldPhase.choose;
    }
    return HoldResult(taker: taker, taken: taken, falsePress: falsePress);
  }
}

/// Bot timing and habits for Hold Card.
class HoldBot {
  HoldBot(this.difficulty, this.rng);

  final Difficulty difficulty;
  final Random rng;

  GameCard pick(HoldPlayer p) => p.hand[rng.nextInt(p.hand.length)];

  /// Milliseconds to slap HOLD after a match, or null if it misses it.
  int? reaction() {
    final (base, spread, miss) = switch (difficulty) {
      Difficulty.easy => (950, 700, 0.12),
      Difficulty.normal => (620, 500, 0.04),
      Difficulty.hard => (380, 380, 0.0),
    };
    if (rng.nextDouble() < miss) return null;
    return base + rng.nextInt(spread);
  }

  /// Milliseconds until a jumpy false press when nothing matched, or null.
  int? falsePress() {
    final chance = switch (difficulty) {
      Difficulty.easy => 0.07,
      Difficulty.normal => 0.02,
      Difficulty.hard => 0.0,
    };
    return rng.nextDouble() < chance ? 400 + rng.nextInt(600) : null;
  }
}
