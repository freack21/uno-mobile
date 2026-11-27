import 'dart:math';

import 'cards.dart';
import 'game.dart';
import 'rules.dart';

sealed class BotMove {
  const BotMove();
}

class PlayMove extends BotMove {
  const PlayMove(this.card, {this.color, this.swapWith, this.extra = const []});

  final GameCard card;
  final CardColor? color;
  final int? swapWith;

  /// Doubles: more cards with the same symbol, played after [card].
  final List<GameCard> extra;
}

class DrawMove extends BotMove {
  const DrawMove();
}

class PassMove extends BotMove {
  const PassMove();
}

class ChallengeMove extends BotMove {
  const ChallengeMove();
}

/// Heuristic computer opponent. Bots only use public information plus their
/// own hand: they never peek at other hands or the draw pile.
class Bot {
  Bot(this.difficulty, [Random? rng]) : rng = rng ?? Random();

  final Difficulty difficulty;
  final Random rng;

  bool get _easy => difficulty == Difficulty.easy;
  bool get _hard => difficulty == Difficulty.hard;

  BotMove decide(Game g, int seat) {
    if (g.phase == Phase.afterDraw) {
      final c = g.drawnCard!;
      if (_easy && rng.nextDouble() < 0.3) return const PassMove();
      if (_hard && _isBluff(g, seat, c) && !_threatened(g, seat)) {
        return const PassMove();
      }
      return _play(g, seat, c);
    }

    if (g.canChallenge && _shouldChallenge(g)) return const ChallengeMove();

    final options = g.playableCards(seat);
    if (options.isEmpty) return const DrawMove();
    if (g.pendingDraw > 0) {
      // Pass the penalty on whenever possible; the cheapest stack first.
      options.sort((a, b) => g.face(a).draw.compareTo(g.face(b).draw));
      if (_easy && rng.nextDouble() < 0.3) return const DrawMove();
      return _play(g, seat, options.first);
    }
    if (_easy) return _play(g, seat, options[rng.nextInt(options.length)]);

    options.sort((a, b) => _score(g, seat, b).compareTo(_score(g, seat, a)));
    return _play(g, seat, options.first);
  }

  /// Picks a card for Jump-In, or null to stay quiet.
  GameCard? jumpIn(Game g, int seat) {
    final cards = g.jumpInCards(seat);
    if (cards.isEmpty) return null;
    final chance = switch (difficulty) {
      Difficulty.easy => 0.35,
      Difficulty.normal => 0.7,
      Difficulty.hard => 0.95,
    };
    return rng.nextDouble() < chance ? cards.first : null;
  }

  /// Milliseconds a bot needs to notice a Jump-In chance. Always slower than
  /// a human reacting to the glow, but fast enough to beat a slow turn.
  int jumpInDelay() =>
      switch (difficulty) {
        Difficulty.easy => 2300,
        Difficulty.normal => 1700,
        Difficulty.hard => 1200,
      } +
      rng.nextInt(600);

  /// How long the bot "thinks" before acting, in milliseconds. Like a person:
  /// quick when there is nothing to decide, slower with many options, a
  /// threatening penalty or a big hand to sort through.
  int thinkTime(Game g, int seat) {
    final hand = g.players[seat].hand.length;
    final int base;
    if (g.phase == Phase.afterDraw) {
      base = 900 + rng.nextInt(600); // look at the drawn card
    } else if (g.canChallenge || g.pendingDraw > 0) {
      base = 1500 + rng.nextInt(900); // stack, challenge or take it?
    } else {
      final options = g.playableCards(seat).length;
      base = options == 0
          ? 1000 +
                rng.nextInt(600) // nothing fits: reach for the deck
          : 1300 +
                min(options, 6) * 150 +
                min(hand, 12) * 25 +
                rng.nextInt(900);
    }
    final pace = switch (difficulty) {
      Difficulty.easy => 1.15,
      Difficulty.normal => 1.0,
      Difficulty.hard => 0.9,
    };
    return (base * pace).round();
  }

  bool callsLast() =>
      rng.nextDouble() <
      switch (difficulty) {
        Difficulty.easy => 0.7,
        Difficulty.normal => 0.88,
        Difficulty.hard => 0.97,
      };

  bool catches() =>
      rng.nextDouble() <
      switch (difficulty) {
        Difficulty.easy => 0.45,
        Difficulty.normal => 0.75,
        Difficulty.hard => 0.95,
      };

  PlayMove _play(Game g, int seat, GameCard card) {
    final extra = _combo(g, seat, card);
    final last = extra.isEmpty ? card : extra.last;
    return PlayMove(
      card,
      extra: extra,
      color: g.needsColor(last) ? _bestColor(g, seat, last) : null,
      swapWith: g.needsSwapTarget(seat, card, extra: extra.length)
          ? _swapTarget(g, seat)
          : null,
    );
  }

  /// Same-symbol cards to throw along with [card] (Doubles).
  List<GameCard> _combo(Game g, int seat, GameCard card) {
    final partners = g.comboPartners(seat, card);
    if (partners.isEmpty) return const [];
    if (_easy) {
      // Beginners don't always spot the combo.
      return rng.nextBool() ? const [] : [partners.first];
    }
    final next = g.nextSeat(seat);
    final f = g.face(card);
    final attacks = f.kind == CardKind.skip || f.isDrawCard;
    // Don't pile extra Skips or draws on a teammate.
    if (attacks && g.isTeammate(seat, next)) return const [];
    // End on the color the bot holds most of, so the next turn is easy.
    final rest = g.players[seat].hand
        .where((c) => c.id != card.id && !partners.contains(c))
        .toList();
    int held(GameCard c) =>
        rest.where((r) => g.face(r).color == g.face(c).color).length;
    return List.of(partners)..sort((a, b) => held(a).compareTo(held(b)));
  }

  int _score(Game g, int seat, GameCard card) {
    final f = g.face(card);
    final next = g.nextSeat(seat);
    final nextIsFriend = g.isTeammate(seat, next);
    final nextCards = g.players[next].hand.length;
    final hand = g.players[seat].hand;
    var s = 0;

    // Dump high-value cards first, keep wilds as a safety net.
    s += f.points ~/ 5;
    if (f.isWild) s -= 30;
    if (f.color == g.activeColor) s += 6;
    s += hand.where((c) => g.face(c).color == f.color).length * 2;

    final attacks =
        f.kind == CardKind.skip ||
        f.kind == CardKind.skipAll ||
        f.isDrawCard ||
        f.kind == CardKind.wildDrawColor;
    if (attacks) {
      if (nextIsFriend) {
        s -= 40;
      } else if (nextCards <= 2) {
        s += 60;
      } else if (_hard) {
        s += 8;
      }
    }
    if (f.kind == CardKind.discardAll) {
      s += hand.where((c) => g.face(c).color == f.color).length * 8;
    }
    if (g.rules.sevenZero && f.kind == CardKind.number) {
      final fewest = g.activePlayers
          .where((p) => p.seat != seat)
          .map((p) => p.hand.length)
          .fold(999, min);
      if (f.value == 7 && fewest < hand.length - 1) s += 35;
      if (f.value == 0 && _hard && g.players[next].hand.length < hand.length) {
        s += 15;
      }
    }
    if (f.kind == CardKind.flip) {
      final darkGood = hand.where((c) => !c.face(g.side.other).isWild).length;
      s += _hard ? darkGood - hand.length ~/ 2 : 0;
    }
    if (_isBluff(g, seat, card)) s -= _threatened(g, seat) ? 0 : 50;
    return s;
  }

  /// Playing this Wild +4 would lose a challenge.
  bool _isBluff(Game g, int seat, GameCard card) {
    final f = g.face(card);
    if (!g.rules.challengeWild4 || f.kind != CardKind.wildDraw || f.draw != 4) {
      return false;
    }
    return g.players[seat].hand.any(
      (c) =>
          c.id != card.id &&
          !g.face(c).isWild &&
          g.face(c).color == g.activeColor,
    );
  }

  bool _threatened(Game g, int seat) {
    final next = g.nextSeat(seat);
    return !g.isTeammate(seat, next) && g.players[next].hand.length <= 2;
  }

  bool _shouldChallenge(Game g) {
    final offender = g.players[g.challenge!.offender];
    return switch (difficulty) {
      Difficulty.easy => rng.nextDouble() < 0.2,
      Difficulty.normal => rng.nextDouble() < 0.35,
      // More cards in hand means more likely to have held the old color.
      Difficulty.hard =>
        rng.nextDouble() < (offender.hand.length >= 5 ? 0.65 : 0.25),
    };
  }

  CardColor _bestColor(Game g, int seat, GameCard played) {
    // A Flip card turns every hand over, so count the other side.
    final flip = g.face(played).kind == CardKind.flip;
    final side = flip ? g.side.other : g.side;
    final colors = side == Side.light ? CardColor.light : CardColor.dark;
    if (_easy) return colors[rng.nextInt(colors.length)];
    final counts = {for (final c in colors) c: 0};
    for (final c in g.players[seat].hand) {
      if (c.id == played.id) continue;
      final f = c.face(side);
      if (!f.isWild) counts[f.color] = counts[f.color]! + 1;
    }
    final best = counts.values.fold(0, max);
    final top = counts.keys.where((c) => counts[c] == best).toList();
    return top[rng.nextInt(top.length)];
  }

  int _swapTarget(Game g, int seat) {
    final others = g.activePlayers.where((p) => p.seat != seat).toList();
    if (_easy) return others[rng.nextInt(others.length)].seat;
    others.sort((a, b) {
      // Never take a teammate's good hand; prefer opponents with few cards.
      final ta = g.isTeammate(seat, a.seat) ? 1 : 0;
      final tb = g.isTeammate(seat, b.seat) ? 1 : 0;
      return ta != tb ? ta - tb : a.hand.length.compareTo(b.hand.length);
    });
    return others.first.seat;
  }
}
