import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:uno_mobile/game/bot.dart';
import 'package:uno_mobile/game/cards.dart';
import 'package:uno_mobile/game/game.dart';
import 'package:uno_mobile/game/modes.dart';
import 'package:uno_mobile/game/rules.dart';

List<Player> seats(int n) => [
  for (var i = 0; i < n; i++) Player(i, 'P$i', isHuman: i == 0),
];

var _ids = 10000;
GameCard card(CardColor c, CardKind k, {int value = 0, int draw = 0}) =>
    GameCard(_ids++, CardFace(c, k, value: value, draw: draw));
GameCard num(CardColor c, int v) => card(c, CardKind.number, value: v);

/// Builds a game and replaces hands / top card with a controlled setup.
Game setup(
  RuleSet rules,
  List<List<GameCard>> hands, {
  required GameCard top,
  int current = 0,
}) {
  final g = Game(rules: rules, players: seats(hands.length), rng: Random(1));
  for (var i = 0; i < hands.length; i++) {
    g.players[i].hand
      ..clear()
      ..addAll(hands[i]);
  }
  g.discard
    ..clear()
    ..add(top);
  g.activeColor = top.light.color;
  g.current = current;
  g.direction = 1;
  return g;
}

int runBotMatch(RuleSet rules, int players, int seed) {
  final rng = Random(seed);
  final g = Game(
    rules: rules,
    players: [for (var i = 0; i < players; i++) Player(i, 'B$i')],
    rng: rng,
  );
  final bots = [
    for (var i = 0; i < players; i++) Bot(Difficulty.values[i % 3], rng),
  ];
  final total = g.cardCount;
  var moves = 0;
  while (!g.isMatchOver) {
    if (g.phase == Phase.roundOver) {
      g.nextRound();
      continue;
    }
    expect(++moves, lessThan(20000), reason: 'match did not finish');
    // Random Jump-Ins and catches exercise the out-of-turn paths.
    for (var s = 0; s < players && rules.jumpIn; s++) {
      final j = bots[s].jumpIn(g, s);
      if (j != null && rng.nextBool()) {
        g.play(s, j);
        break;
      }
    }
    if (g.isRoundOver) continue;
    final v = g.vulnerable;
    if (v != null && rng.nextBool()) g.catchPlayer((v + 1) % players, v);
    if (g.isRoundOver) continue;
    final seat = g.current;
    switch (bots[seat].decide(g, seat)) {
      case PlayMove(:final card, :final color, :final swapWith, :final extra):
        if (g.players[seat].hand.length == 2 + extra.length &&
            bots[seat].callsLast()) {
          g.callLast(seat);
        }
        g.play(seat, card, color: color, swapWith: swapWith, extra: extra);
      case DrawMove():
        g.draw(seat);
      case PassMove():
        g.pass(seat);
      case ChallengeMove():
        g.challengeWild(seat);
    }
    if (rules.handLimit == null) {
      expect(g.cardCount, total, reason: 'cards must be conserved');
    }
  }
  return moves;
}

void main() {
  group('decks', () {
    test('sizes', () {
      expect(buildDeck(DeckType.classic, Random(0)).length, 108);
      expect(buildDeck(DeckType.merciless, Random(0)).length, 164);
      final flip = buildDeck(DeckType.flipside, Random(0));
      expect(flip.length, 112);
      expect(flip.every((c) => c.dark != null), isTrue);
      expect(
        flip.where((c) => c.dark!.color == CardColor.wild).length,
        8,
        reason: 'dark side has 8 wilds',
      );
    });

    test('rounds start on a number card with 7 cards each', () {
      for (var seed = 0; seed < 30; seed++) {
        final g = Game(
          rules: const RuleSet(),
          players: seats(4),
          rng: Random(seed),
        );
        expect(g.topFace.kind, CardKind.number);
        expect(g.players.every((p) => p.hand.length == 7), isTrue);
        expect(g.cardCount, 108);
      }
    });
  });

  group('matching', () {
    test('color, symbol and wild', () {
      final r5 = num(CardColor.red, 5);
      final b5 = num(CardColor.blue, 5);
      final b6 = num(CardColor.blue, 6);
      final w = card(CardColor.wild, CardKind.wild);
      final g = setup(const RuleSet(), [
        [r5, b5, b6, w],
        [num(CardColor.red, 1)],
      ], top: num(CardColor.red, 9));
      expect(g.isPlayable(0, r5), isTrue);
      expect(g.isPlayable(0, b5), isFalse);
      expect(g.isPlayable(0, w), isTrue);
      expect(
        g.isPlayable(1, g.players[1].hand.first),
        isFalse,
        reason: 'not turn',
      );
      g.discard.add(num(CardColor.green, 5));
      g.activeColor = CardColor.green;
      expect(g.isPlayable(0, b5), isTrue);
      expect(g.isPlayable(0, b6), isFalse);
    });

    test('wild sets color and requires one', () {
      final w = card(CardColor.wild, CardKind.wild);
      final g = setup(const RuleSet(), [
        [w, num(CardColor.red, 1)],
        [num(CardColor.red, 1), num(CardColor.red, 2)],
      ], top: num(CardColor.blue, 3));
      expect(() => g.play(0, w), throwsStateError);
      g.play(0, w, color: CardColor.green);
      expect(g.activeColor, CardColor.green);
      expect(g.current, 1);
    });
  });

  group('actions', () {
    test('skip, reverse, reverse with two players', () {
      final skip = card(CardColor.red, CardKind.skip);
      final g = setup(const RuleSet(), [
        [skip, num(CardColor.red, 1)],
        [num(CardColor.red, 1)],
        [num(CardColor.red, 1)],
      ], top: num(CardColor.red, 9));
      g.play(0, skip);
      expect(g.current, 2);

      final rev = card(CardColor.red, CardKind.reverse);
      final g3 = setup(const RuleSet(), [
        [rev, num(CardColor.red, 1)],
        [num(CardColor.red, 1)],
        [num(CardColor.red, 1)],
      ], top: num(CardColor.red, 9));
      g3.play(0, rev);
      expect(g3.direction, -1);
      expect(g3.current, 2);

      final rev2 = card(CardColor.red, CardKind.reverse);
      final g2 = setup(const RuleSet(), [
        [rev2, num(CardColor.red, 1)],
        [num(CardColor.red, 1)],
      ], top: num(CardColor.red, 9));
      g2.play(0, rev2);
      expect(g2.current, 0, reason: 'reverse acts as skip with 2 players');
    });

    test('+2 without stacking hits immediately', () {
      final d2 = card(CardColor.red, CardKind.draw, draw: 2);
      final g = setup(const RuleSet(), [
        [d2, num(CardColor.red, 1)],
        [card(CardColor.blue, CardKind.draw, draw: 2)],
        [num(CardColor.red, 1)],
      ], top: num(CardColor.red, 9));
      g.play(0, d2);
      expect(g.players[1].hand.length, 3);
      expect(g.current, 2);
      expect(g.pendingDraw, 0);
    });

    test('last card draw penalty still applies', () {
      final d2 = card(CardColor.red, CardKind.draw, draw: 2);
      final g = setup(const RuleSet(format: MatchFormat.points), [
        [d2],
        [num(CardColor.blue, 3)],
      ], top: num(CardColor.red, 9));
      g.play(0, d2);
      expect(g.players[1].hand.length, 3);
      expect(g.phase, Phase.roundOver);
      expect(g.players[0].score, greaterThan(3));
    });
  });

  group('stacking', () {
    test('same: +2 on +2 then taker draws total', () {
      final a = card(CardColor.red, CardKind.draw, draw: 2);
      final b = card(CardColor.blue, CardKind.draw, draw: 2);
      final w4 = card(CardColor.wild, CardKind.wildDraw, draw: 4);
      final g = setup(const RuleSet(stack: StackRule.same), [
        [a, num(CardColor.red, 1)],
        [b, num(CardColor.red, 1)],
        [w4, num(CardColor.green, 1)],
      ], top: num(CardColor.red, 9));
      g.play(0, a);
      expect(g.current, 1);
      expect(g.pendingDraw, 2);
      expect(g.isPlayable(1, g.players[1].hand[1]), isFalse);
      g.play(1, b);
      // Player 2 only has a +4, which cannot answer a +2: auto-penalty.
      expect(g.players[2].hand.length, 6);
      expect(g.current, 0);
      expect(g.pendingDraw, 0);
    });

    test('escalating allows bigger draws', () {
      final d2 = card(CardColor.red, CardKind.draw, draw: 2);
      final w10 = card(CardColor.wild, CardKind.wildDraw, draw: 10);
      final g = setup(const RuleSet(stack: StackRule.escalating), [
        [d2, num(CardColor.red, 1)],
        [w10, num(CardColor.red, 1)],
      ], top: num(CardColor.red, 9));
      g.play(0, d2);
      expect(g.isPlayable(1, w10), isTrue);
      g.play(1, w10, color: CardColor.blue);
      expect(g.players[0].hand.length, 13);
    });

    test('player can accept by drawing', () {
      final a = card(CardColor.red, CardKind.draw, draw: 2);
      final b = card(CardColor.blue, CardKind.draw, draw: 2);
      final g = setup(const RuleSet(stack: StackRule.same), [
        [a, num(CardColor.red, 1)],
        [b, num(CardColor.red, 1)],
      ], top: num(CardColor.red, 9));
      g.play(0, a);
      g.draw(1);
      expect(g.players[1].hand.length, 4);
      expect(g.current, 0);
    });
  });

  group('seven-o', () {
    test('7 swaps with target', () {
      final seven = num(CardColor.red, 7);
      final g = setup(const RuleSet(sevenZero: true), [
        [seven, num(CardColor.red, 1), num(CardColor.red, 2)],
        [num(CardColor.blue, 1)],
        [num(CardColor.blue, 2), num(CardColor.blue, 3)],
      ], top: num(CardColor.red, 9));
      expect(g.needsSwapTarget(0, seven), isTrue);
      g.play(0, seven, swapWith: 1);
      expect(g.players[0].hand.length, 1);
      expect(g.players[1].hand.length, 2);
      expect(g.players[0].calledLast, isTrue);
    });

    test('0 rotates hands in play direction', () {
      final zero = num(CardColor.red, 0);
      final h1 = [num(CardColor.blue, 1)];
      final h2 = [num(CardColor.blue, 2), num(CardColor.blue, 3)];
      final g = setup(const RuleSet(sevenZero: true), [
        [zero, num(CardColor.green, 5), num(CardColor.green, 6)],
        h1,
        h2,
      ], top: num(CardColor.red, 9));
      g.play(0, zero);
      expect(g.players[1].hand.map((c) => c.light.value), [5, 6]);
      expect(g.players[2].hand.map((c) => c.light.value), [1]);
      expect(g.players[0].hand.map((c) => c.light.value), [2, 3]);
    });
  });

  group('jump-in', () {
    test('identical card plays out of turn and continues from jumper', () {
      final top = num(CardColor.blue, 5);
      final twin = num(CardColor.blue, 5);
      final g = setup(const RuleSet(jumpIn: true), [
        [num(CardColor.red, 1), num(CardColor.red, 2)],
        [num(CardColor.red, 3), num(CardColor.red, 4)],
        [twin, num(CardColor.red, 6)],
      ], top: top);
      expect(g.canJumpIn(2, twin), isTrue);
      expect(g.canJumpIn(2, g.players[2].hand[1]), isFalse);
      g.play(2, twin);
      expect(g.current, 0);
      expect(g.top.id, twin.id);
    });

    test('not allowed when the rule is off', () {
      final twin = num(CardColor.blue, 5);
      final g = setup(const RuleSet(), [
        [num(CardColor.red, 1)],
        [twin, num(CardColor.red, 1)],
      ], top: num(CardColor.blue, 5));
      expect(g.canJumpIn(1, twin), isFalse);
      expect(() => g.play(1, twin), throwsStateError);
    });
  });

  group('drawing', () {
    test('drawn playable card can be played or kept', () {
      final g = setup(const RuleSet(), [
        [num(CardColor.green, 1), num(CardColor.green, 2)],
        [num(CardColor.green, 3)],
      ], top: num(CardColor.red, 9));
      g.drawPile
        ..clear()
        ..add(num(CardColor.red, 4));
      g.draw(0);
      expect(g.phase, Phase.afterDraw);
      expect(g.isPlayable(0, g.players[0].hand[0]), isFalse);
      g.pass(0);
      expect(g.current, 1);
    });

    test('draw until playable', () {
      final g = setup(const RuleSet(drawUntilPlayable: true), [
        [num(CardColor.green, 1), num(CardColor.green, 2)],
        [num(CardColor.green, 3)],
      ], top: num(CardColor.red, 9));
      g.drawPile
        ..clear()
        ..addAll([
          num(CardColor.red, 4),
          num(CardColor.blue, 1),
          num(CardColor.yellow, 1),
        ]);
      g.draw(0);
      expect(g.players[0].hand.length, 5);
      expect(g.drawnCard!.light.color, CardColor.red);
    });
  });

  group('challenge', () {
    test('bluff caught: offender draws 4, challenger keeps turn', () {
      final w4 = card(CardColor.wild, CardKind.wildDraw, draw: 4);
      final g = setup(const RuleSet(challengeWild4: true), [
        [w4, num(CardColor.red, 1), num(CardColor.blue, 1)],
        [num(CardColor.green, 3), num(CardColor.green, 4)],
      ], top: num(CardColor.red, 9));
      g.play(0, w4, color: CardColor.green);
      expect(g.canChallenge, isTrue);
      g.challengeWild(1);
      expect(g.players[0].hand.length, 6);
      expect(g.players[1].hand.length, 2);
      expect(g.current, 1);
    });

    test('honest play: challenger draws 6', () {
      final w4 = card(CardColor.wild, CardKind.wildDraw, draw: 4);
      final g = setup(const RuleSet(challengeWild4: true), [
        [w4, num(CardColor.blue, 1), num(CardColor.blue, 2)],
        [num(CardColor.green, 3), num(CardColor.green, 4)],
      ], top: num(CardColor.red, 9));
      g.play(0, w4, color: CardColor.green);
      g.challengeWild(1);
      expect(g.players[1].hand.length, 8);
      expect(g.current, 0);
    });
  });

  group('last card', () {
    test('forgetting can be caught; calling is safe', () {
      final g = setup(const RuleSet(), [
        [num(CardColor.red, 1), num(CardColor.red, 2)],
        [num(CardColor.red, 3), num(CardColor.red, 4)],
      ], top: num(CardColor.red, 9));
      g.play(0, g.players[0].hand.first);
      expect(g.vulnerable, 0);
      expect(g.catchPlayer(1, 0), isTrue);
      expect(g.players[0].hand.length, 3);

      final g2 = setup(const RuleSet(), [
        [num(CardColor.red, 1), num(CardColor.red, 2)],
        [num(CardColor.red, 3), num(CardColor.red, 4)],
      ], top: num(CardColor.red, 9));
      g2.callLast(0);
      g2.play(0, g2.players[0].hand.first);
      expect(g2.vulnerable, isNull);
      expect(g2.catchPlayer(1, 0), isFalse);
    });
  });

  group('merciless', () {
    test('skip all keeps the turn', () {
      final sa = card(CardColor.red, CardKind.skipAll);
      final g = setup(const RuleSet(deck: DeckType.merciless), [
        [sa, num(CardColor.red, 1)],
        [num(CardColor.red, 3)],
        [num(CardColor.red, 4)],
      ], top: num(CardColor.red, 9));
      g.play(0, sa);
      expect(g.current, 0);
    });

    test('discard all removes the color', () {
      final da = card(CardColor.red, CardKind.discardAll);
      final g = setup(const RuleSet(deck: DeckType.merciless), [
        [
          da,
          num(CardColor.red, 1),
          num(CardColor.red, 5),
          num(CardColor.blue, 2),
        ],
        [num(CardColor.red, 3)],
      ], top: num(CardColor.red, 9));
      g.play(0, da);
      expect(g.players[0].hand.length, 1);
      expect(g.top.id, da.id);
    });

    test('hand limit knocks a player out', () {
      final d = card(CardColor.wild, CardKind.wildDraw, draw: 10);
      final g = setup(const RuleSet(deck: DeckType.merciless, handLimit: 25), [
        [d, num(CardColor.red, 1)],
        [for (var i = 0; i < 20; i++) num(CardColor.blue, 1)],
        [num(CardColor.green, 1), num(CardColor.green, 2)],
      ], top: num(CardColor.red, 9));
      g.play(0, d, color: CardColor.red);
      expect(g.players[1].out, isTrue);
      expect(g.players[1].hand, isEmpty);
      expect(g.current, 2);
    });

    test('wild draw color digs until the color', () {
      final wc = card(CardColor.wild, CardKind.wildDrawColor);
      final g = setup(const RuleSet(deck: DeckType.merciless), [
        [wc, num(CardColor.red, 1)],
        [num(CardColor.red, 3)],
        [num(CardColor.red, 4)],
      ], top: num(CardColor.red, 9));
      g.drawPile
        ..clear()
        ..addAll([
          num(CardColor.blue, 1),
          num(CardColor.green, 1),
          num(CardColor.yellow, 1),
        ]);
      g.play(0, wc, color: CardColor.green);
      expect(g.players[1].hand.length, 3);
      expect(g.current, 2);
    });
  });

  group('flipside', () {
    test('flip switches side and active color', () {
      final flip = GameCard(
        _ids++,
        const CardFace(CardColor.red, CardKind.flip),
        const CardFace(CardColor.teal, CardKind.number, value: 4),
      );
      final other = GameCard(
        _ids++,
        const CardFace(CardColor.blue, CardKind.number, value: 1),
        const CardFace(CardColor.pink, CardKind.draw, draw: 5),
      );
      final g = setup(const RuleSet(deck: DeckType.flipside), [
        [flip, other],
        [num(CardColor.red, 3)],
      ], top: num(CardColor.red, 9));
      g.play(0, flip);
      expect(g.side, Side.dark);
      expect(g.activeColor, CardColor.teal);
      expect(g.face(other).draw, 5);
    });
  });

  group('teams and elimination', () {
    test('team wins when partner goes out', () {
      final last = num(CardColor.red, 1);
      final g = setup(
        const RuleSet(teams: true),
        [
          [num(CardColor.blue, 1), num(CardColor.blue, 2)],
          [num(CardColor.blue, 3)],
          [last],
          [num(CardColor.blue, 4)],
        ],
        top: num(CardColor.red, 9),
        current: 2,
      );
      g.play(2, last);
      expect(g.isMatchOver, isTrue);
      expect(g.players[0].score, 1);
      expect(g.players[2].score, 1);
      expect(g.players[1].score, 0);
    });

    test('most cards is knocked out', () {
      final last = num(CardColor.red, 1);
      final g = setup(const RuleSet(format: MatchFormat.elimination), [
        [last],
        [
          num(CardColor.blue, 3),
          num(CardColor.blue, 4),
          num(CardColor.blue, 5),
        ],
        [num(CardColor.blue, 4)],
      ], top: num(CardColor.red, 9));
      g.play(0, last);
      expect(g.players[1].out, isTrue);
      expect(g.phase, Phase.roundOver);
    });
  });

  group('doubles', () {
    const doubles = RuleSet(combos: true);

    test('same number in any color plays together; last sets the color', () {
      final y6 = num(CardColor.yellow, 6);
      final r6 = num(CardColor.red, 6);
      final g = setup(doubles, [
        [y6, r6, num(CardColor.blue, 1)],
        [num(CardColor.red, 3)],
      ], top: num(CardColor.yellow, 9));
      expect(g.comboPartners(0, y6).map((c) => c.id), [r6.id]);
      g.play(0, y6, extra: [r6]);
      expect(g.players[0].hand.length, 1);
      expect(g.top.id, r6.id);
      expect(g.activeColor, CardColor.red);
      expect(g.current, 1);
    });

    test('rejected when the rule is off or symbols differ', () {
      final y6 = num(CardColor.yellow, 6);
      final r6 = num(CardColor.red, 6);
      final r7 = num(CardColor.red, 7);
      final off = setup(const RuleSet(), [
        [y6, r6, r7],
        [num(CardColor.red, 3)],
      ], top: num(CardColor.yellow, 9));
      expect(() => off.play(0, y6, extra: [r6]), throwsStateError);
      final on = setup(doubles, [
        [y6, r6, r7],
        [num(CardColor.red, 3)],
      ], top: num(CardColor.yellow, 9));
      expect(() => on.play(0, y6, extra: [r7]), throwsStateError);
      expect(() => on.play(0, y6, extra: [r6, r6]), throwsStateError);
      expect(on.players[0].hand.length, 3, reason: 'nothing played');
    });

    test('two skips skip two players', () {
      final a = card(CardColor.red, CardKind.skip);
      final b = card(CardColor.blue, CardKind.skip);
      final g = setup(doubles, [
        [a, b, num(CardColor.red, 1)],
        [num(CardColor.red, 2)],
        [num(CardColor.red, 3)],
        [num(CardColor.red, 4)],
      ], top: num(CardColor.red, 9));
      g.play(0, a, extra: [b]);
      expect(g.current, 3);
    });

    test('two +2s make the next player draw 4', () {
      final a = card(CardColor.red, CardKind.draw, draw: 2);
      final b = card(CardColor.green, CardKind.draw, draw: 2);
      final g = setup(doubles, [
        [a, b, num(CardColor.red, 1)],
        [num(CardColor.blue, 2)],
        [num(CardColor.red, 3)],
      ], top: num(CardColor.red, 9));
      g.play(0, a, extra: [b]);
      expect(g.players[1].hand.length, 5);
      expect(g.current, 2);
    });

    test('two reverses keep the direction', () {
      final a = card(CardColor.red, CardKind.reverse);
      final b = card(CardColor.blue, CardKind.reverse);
      final g = setup(doubles, [
        [a, b, num(CardColor.red, 1)],
        [num(CardColor.red, 2)],
        [num(CardColor.red, 3)],
      ], top: num(CardColor.red, 9));
      g.play(0, a, extra: [b]);
      expect(g.direction, 1);
      expect(g.current, 1);
    });

    test('wild +4 pair adds up and cannot be challenged', () {
      final a = card(CardColor.wild, CardKind.wildDraw, draw: 4);
      final b = card(CardColor.wild, CardKind.wildDraw, draw: 4);
      final g = setup(const RuleSet(combos: true, challengeWild4: true), [
        [a, b, num(CardColor.red, 1)],
        [num(CardColor.blue, 2)],
        [num(CardColor.red, 3)],
      ], top: num(CardColor.red, 9));
      g.play(0, a, extra: [b], color: CardColor.green);
      expect(g.players[1].hand.length, 9);
      expect(g.activeColor, CardColor.green);
    });

    test('Seven-O: two 7s swap hands once', () {
      final a = num(CardColor.red, 7);
      final b = num(CardColor.blue, 7);
      final g = setup(const RuleSet(combos: true, sevenZero: true), [
        [a, b, num(CardColor.red, 1)],
        [num(CardColor.blue, 2), num(CardColor.blue, 3)],
        [num(CardColor.red, 3)],
      ], top: num(CardColor.red, 9));
      expect(g.needsSwapTarget(0, a, extra: 1), isTrue);
      g.play(0, a, extra: [b], swapWith: 1);
      expect(g.players[0].hand.length, 2);
      expect(g.players[1].hand.length, 1);
    });

    test('a combo can win, and Last Card can be called before it', () {
      final a = num(CardColor.red, 5);
      final b = num(CardColor.blue, 5);
      final c5 = num(CardColor.green, 5);
      final g = setup(doubles, [
        [a, b, c5],
        [num(CardColor.blue, 2)],
      ], top: num(CardColor.red, 9));
      expect(g.canCallLast(0), isFalse, reason: 'combo empties the hand');
      g.play(0, a, extra: [b, c5]);
      expect(g.isMatchOver, isTrue);

      final g2 = setup(doubles, [
        [a, b, num(CardColor.green, 1)],
        [num(CardColor.blue, 2)],
      ], top: num(CardColor.red, 9));
      expect(g2.canCallLast(0), isTrue);
      g2.callLast(0);
      g2.play(0, a, extra: [b]);
      expect(g2.vulnerable, isNull);
    });

    test('jump-ins and flips stay single cards', () {
      final twin = num(CardColor.blue, 5);
      final other = num(CardColor.red, 5);
      final g = setup(const RuleSet(combos: true, jumpIn: true), [
        [num(CardColor.green, 1)],
        [twin, other, num(CardColor.red, 1)],
      ], top: num(CardColor.blue, 5));
      expect(() => g.play(1, twin, extra: [other]), throwsStateError);
      final flip = card(CardColor.red, CardKind.flip);
      final g2 = setup(const RuleSet(combos: true, deck: DeckType.flipside), [
        [flip, card(CardColor.blue, CardKind.flip)],
        [num(CardColor.blue, 2)],
      ], top: num(CardColor.red, 9));
      expect(g2.comboPartners(0, flip), isEmpty);
    });

    test('bots throw their pairs', () {
      final y6 = num(CardColor.yellow, 6);
      final r6 = num(CardColor.red, 6);
      final g = setup(doubles, [
        [y6, r6, num(CardColor.red, 1), num(CardColor.red, 2)],
        [num(CardColor.blue, 3)],
      ], top: num(CardColor.yellow, 9));
      final move = Bot(Difficulty.hard, Random(1)).decide(g, 0) as PlayMove;
      expect(move.card.id, y6.id);
      // Ends on red, the color it still holds.
      expect(move.extra.map((c) => c.id), [r6.id]);
    });
  });

  group('bot pacing', () {
    int avg(Difficulty d, Game g, int seat) {
      final bot = Bot(d, Random(7));
      var total = 0;
      for (var i = 0; i < 200; i++) {
        total += bot.thinkTime(g, seat);
      }
      return total ~/ 200;
    }

    test('think time is human-like and situational', () {
      final stuck = setup(const RuleSet(), [
        [num(CardColor.blue, 1), num(CardColor.blue, 2)],
        [num(CardColor.red, 1)],
      ], top: num(CardColor.red, 9));
      final options = setup(const RuleSet(), [
        [for (var v = 1; v <= 6; v++) num(CardColor.red, v)],
        [num(CardColor.red, 1)],
      ], top: num(CardColor.red, 9));

      for (final g in [stuck, options]) {
        for (final d in Difficulty.values) {
          final bot = Bot(d, Random(3));
          for (var i = 0; i < 100; i++) {
            final t = bot.thinkTime(g, 0);
            expect(t, inInclusiveRange(800, 4500));
          }
        }
      }
      // Deciding between many cards takes longer than reaching for the deck.
      expect(
        avg(Difficulty.normal, options, 0),
        greaterThan(avg(Difficulty.normal, stuck, 0)),
      );
      // Harder bots are a bit quicker.
      expect(
        avg(Difficulty.hard, options, 0),
        lessThan(avg(Difficulty.easy, options, 0)),
      );
    });

    test('jump-in reaction stays slower than a second', () {
      for (final d in Difficulty.values) {
        final bot = Bot(d, Random(1));
        for (var i = 0; i < 50; i++) {
          expect(bot.jumpInDelay(), greaterThanOrEqualTo(1200));
        }
      }
    });
  });

  group('bot simulation', () {
    for (final mode in gameModes) {
      test('${mode.name} matches finish', () {
        for (var seed = 0; seed < 25; seed++) {
          final players = mode.rules.teams ? 4 : 2 + seed % 5;
          runBotMatch(
            mode.rules,
            players.clamp(mode.minPlayers, mode.maxPlayers),
            seed,
          );
        }
      });
    }

    test('everything combined', () {
      const rules = RuleSet(
        deck: DeckType.flipside,
        format: MatchFormat.points,
        stack: StackRule.escalating,
        sevenZero: true,
        jumpIn: true,
        drawUntilPlayable: true,
        challengeWild4: true,
        combos: true,
        handLimit: 25,
      );
      for (var seed = 0; seed < 20; seed++) {
        runBotMatch(rules, 3 + seed % 3, seed);
      }
    });
  });
}
