import 'dart:math';

import 'cards.dart';
import 'rules.dart';

/// Hold Card: every player holds face-down cards they cannot see.
///
/// On your turn you call a number (or a color), then put one of your unseen
/// cards into the box, face up. If it matches the call, everyone races to
/// press HOLD and the slowest takes the whole box. Otherwise the card stays
/// in the box and play moves on. Wilds always match. In number mode +2 never
/// matches and its owner draws 2 from the stock; a Wild +4 matches but its
/// owner draws 4. Skip and Reverse keep their usual effect on turn order.
/// Pressing HOLD without a match takes the box. Empty your hand to win.
enum HoldGuess {
  number,
  color;

  String get label => this == number ? 'Number' : 'Color';
}

enum HoldPhase { call, race, over }

class HoldPlayer {
  HoldPlayer(this.seat, this.name, {this.isHuman = false});

  final int seat;
  final String name;
  final bool isHuman;

  /// Face-down cards; nobody can see them, not even their owner.
  final List<GameCard> hand = [];
}

/// What the player on turn called: a number (0-9) or a color.
class HoldCall {
  const HoldCall.number(int this.number) : color = null;
  const HoldCall.color(CardColor this.color) : number = null;

  final int? number;
  final CardColor? color;

  String get label => number != null ? '$number' : color!.label;
}

/// The result of putting a card in the box.
class HoldPlay {
  const HoldPlay({
    required this.seat,
    required this.call,
    required this.card,
    required this.match,
    this.drew = 0,
  });

  final int seat;
  final HoldCall call;
  final GameCard card;
  final bool match;

  /// Penalty cards the player drew from the stock (+2 / Wild +4).
  final int drew;
}

class HoldResult {
  const HoldResult({this.taker, this.taken = 0, this.falsePress = false});

  final int? taker;
  final int taken;

  /// The taker pressed HOLD when nothing matched.
  final bool falsePress;
}

class HoldCardGame {
  HoldCardGame({
    required this.players,
    this.guess = HoldGuess.number,
    Random? rng,
    this.handSize = 10,
  }) : rng = rng ?? Random() {
    if (players.length < 2) throw ArgumentError('Need at least 2 players');
    stock.addAll(buildDeck(DeckType.classic, this.rng));
    for (var i = 0; i < handSize; i++) {
      for (final p in players) {
        p.hand.add(stock.removeLast());
      }
    }
    current = this.rng.nextInt(players.length);
  }

  /// An empty game to be filled from a received state (no deal).
  HoldCardGame.restore({
    required this.players,
    required this.guess,
    Random? rng,
    this.handSize = 10,
  }) : rng = rng ?? Random();

  final List<HoldPlayer> players;
  final HoldGuess guess;
  final Random rng;
  final int handSize;

  /// Undealt cards; penalties are drawn from here.
  final List<GameCard> stock = [];

  /// Cards waiting for someone to take them, newest last.
  final List<GameCard> box = [];

  int current = 0;
  int direction = 1;
  HoldPhase phase = HoldPhase.call;

  /// The latest card put in the box and what was called for it.
  HoldPlay? last;

  /// Seats in the order they pressed HOLD during a race.
  final List<int> presses = [];
  List<int> winners = const [];

  int nextSeat(int from) {
    final n = players.length;
    return ((from + direction) % n + n) % n;
  }

  /// Whether [face] answers [call].
  bool matches(CardFace face, HoldCall call) {
    if (face.isWild) return true;
    if (call.number != null) {
      return face.kind == CardKind.number && face.value == call.number;
    }
    return face.color == call.color;
  }

  /// [seat] calls [call] and puts the card at [index] of their hand in the box.
  HoldPlay place(int seat, HoldCall call, int index) {
    if (phase != HoldPhase.call) throw StateError('Not the time to play');
    if (seat != current) throw StateError('Not your turn');
    if ((call.number != null) != (guess == HoldGuess.number)) {
      throw StateError('Call a ${guess.label.toLowerCase()}');
    }
    if (call.number != null && (call.number! < 0 || call.number! > 9)) {
      throw StateError('Call a number from 0 to 9');
    }
    final p = players[seat];
    if (index < 0 || index >= p.hand.length) throw StateError('No such card');
    final card = p.hand.removeAt(index);
    box.add(card);
    final f = card.light;
    final match = matches(f, call);
    // +2 / Wild +4 cost their owner cards from the stock in both modes.
    final penalty = switch (f.kind) {
      CardKind.draw || CardKind.wildDraw => f.draw,
      _ => 0,
    };
    var drew = 0;
    for (var i = 0; i < penalty && stock.isNotEmpty; i++) {
      p.hand.add(stock.removeLast());
      drew++;
    }
    final play = HoldPlay(
      seat: seat,
      call: call,
      card: card,
      match: match,
      drew: drew,
    );
    last = play;
    presses.clear();
    if (match) {
      phase = HoldPhase.race;
    } else {
      _endTurn();
    }
    return play;
  }

  /// [seat] presses HOLD. During a race this counts their reaction; at any
  /// other time it is a false press and they take the box at once.
  /// Returns the result when the box changes hands.
  HoldResult? press(int seat) {
    if (phase == HoldPhase.over) return null;
    if (phase == HoldPhase.call) {
      if (box.isEmpty) return null;
      final taken = _give(seat);
      _checkWinners();
      return HoldResult(taker: seat, taken: taken, falsePress: true);
    }
    if (presses.contains(seat)) return null;
    presses.add(seat);
    return presses.length == players.length ? settle() : null;
  }

  /// Ends a race: the slowest presser takes the box, or one of those who
  /// never pressed.
  HoldResult settle() {
    if (phase != HoldPhase.race) throw StateError('No race to settle');
    final missed = [
      for (final p in players)
        if (!presses.contains(p.seat)) p.seat,
    ];
    final taker = missed.isEmpty
        ? presses.last
        : missed[rng.nextInt(missed.length)];
    final taken = _give(taker);
    _endTurn();
    return HoldResult(taker: taker, taken: taken);
  }

  int _give(int seat) {
    final n = box.length;
    players[seat].hand.addAll(box);
    box.clear();
    return n;
  }

  /// Applies Skip / Reverse of the last card and passes the turn.
  void _endTurn() {
    phase = HoldPhase.call;
    if (_checkWinners()) return;
    final played = last!;
    final kind = played.card.light.kind;
    var steps = 1;
    if (kind == CardKind.skip) {
      steps = 2;
    } else if (kind == CardKind.reverse) {
      if (players.length == 2) {
        steps = 2;
      } else {
        direction = -direction;
      }
    }
    var s = played.seat;
    for (var i = 0; i < steps; i++) {
      s = nextSeat(s);
    }
    current = s;
  }

  bool _checkWinners() {
    final empty = [
      for (final p in players)
        if (p.hand.isEmpty) p.seat,
    ];
    if (empty.isEmpty) return false;
    winners = empty;
    phase = HoldPhase.over;
    return true;
  }
}

/// Bot habits for Hold Card.
class HoldBot {
  HoldBot(this.difficulty, this.rng);

  final Difficulty difficulty;
  final Random rng;

  /// Cards are unseen, so any call is a guess.
  HoldCall call(HoldGuess guess) => guess == HoldGuess.number
      ? HoldCall.number(rng.nextInt(10))
      : HoldCall.color(CardColor.light[rng.nextInt(4)]);

  int pick(HoldPlayer p) => rng.nextInt(p.hand.length);

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

  /// Milliseconds until a jumpy false press after a miss, or null.
  int? falsePress() {
    final chance = switch (difficulty) {
      Difficulty.easy => 0.07,
      Difficulty.normal => 0.02,
      Difficulty.hard => 0.0,
    };
    return rng.nextDouble() < chance ? 400 + rng.nextInt(600) : null;
  }
}
