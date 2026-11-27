import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:uno_mobile/game/cards.dart';
import 'package:uno_mobile/game/exact_score.dart';
import 'package:uno_mobile/game/hold_card.dart';
import 'package:uno_mobile/game/rules.dart';

var _ids = 50000;
GameCard face(CardColor c, CardKind k, {int value = 0, int draw = 0}) =>
    GameCard(_ids++, CardFace(c, k, value: value, draw: draw));
GameCard n(int v, [CardColor c = CardColor.red]) =>
    face(c, CardKind.number, value: v);

ExactScoreGame exact(int players, {int target = 20}) {
  final g = ExactScoreGame(
    players: [
      for (var i = 0; i < players; i++) ScorePlayer(i, 'P$i', isHuman: i == 0),
    ],
    target: target,
    rng: Random(1),
  );
  g.current = 0;
  return g;
}

/// Puts [card] on top of the draw pile.
void stack(ExactScoreGame g, GameCard card) => g.drawPile.add(card);

void main() {
  group('Exact Score', () {
    test('numbers add up and the exact target wins', () {
      final g = exact(2);
      g.players[0].score = 13;
      stack(g, n(7));
      g.draw(0);
      expect(g.canUse(0), isTrue);
      g.use(0);
      expect(g.players[0].score, 20);
      expect(g.winner, 0);
      expect(g.phase, ScorePhase.over);
    });

    test('a number past the target cannot be used', () {
      final g = exact(2);
      g.players[0].score = 19;
      stack(g, n(2));
      g.draw(0);
      expect(g.canUse(0), isFalse);
      expect(() => g.use(0), throwsStateError);
      g.discard(0);
      expect(g.players[0].score, 19);
      expect(g.current, 1);
    });

    test('three discards in a row cost the next turn', () {
      final g = exact(3);
      for (var i = 0; i < 3; i++) {
        g.current = 0;
        g.phase = ScorePhase.draw;
        stack(g, n(5));
        g.draw(0);
        final penalty = g.discard(0);
        expect(penalty, i == 2);
      }
      // Seat 0 is now skipped once: from seat 2, play passes it.
      g.current = 2;
      stack(g, n(1));
      g.draw(2);
      g.use(2);
      expect(g.current, 1);
      expect(g.lastSkipped, [0]);
    });

    test('wild picks a value within the target', () {
      final g = exact(2);
      g.players[0].score = 16;
      stack(g, face(CardColor.wild, CardKind.wild));
      g.draw(0);
      expect(g.wildValues(0), [1, 2, 3, 4]);
      expect(() => g.use(0, value: 5), throwsStateError);
      g.use(0, value: 4);
      expect(g.winner, 0);
    });

    test('skip, reverse and +2', () {
      final g = exact(3);
      stack(g, face(CardColor.red, CardKind.skip));
      g.draw(0);
      g.use(0);
      expect(g.current, 2);

      g.current = 0;
      stack(g, face(CardColor.red, CardKind.reverse));
      g.draw(0);
      g.use(0);
      expect(g.direction, -1);
      expect(g.current, 2);

      g.current = 0;
      g.players[1].score = 9;
      stack(g, face(CardColor.red, CardKind.draw, draw: 2));
      g.draw(0);
      expect(g.victims(0), [1]);
      g.use(0, victim: 1);
      expect(g.players[1].score, 7);
    });

    test('+2 cannot be used when nobody has points', () {
      final g = exact(2);
      stack(g, face(CardColor.red, CardKind.draw, draw: 2));
      g.draw(0);
      expect(g.canUse(0), isFalse);
    });

    test('bots finish games at every target', () {
      for (final target in [20, 30, 40, 50]) {
        for (var seed = 0; seed < 20; seed++) {
          final rng = Random(seed);
          final players = 2 + seed % 5;
          final g = ExactScoreGame(
            players: [for (var i = 0; i < players; i++) ScorePlayer(i, 'B$i')],
            target: target,
            rng: rng,
          );
          var turns = 0;
          while (g.phase != ScorePhase.over) {
            expect(++turns, lessThan(5000));
            final seat = g.current;
            g.draw(seat);
            final move = decideExactScore(
              g,
              seat,
              Difficulty.values[seat % 3],
              rng,
            );
            if (move.use) {
              g.use(seat, value: move.value, victim: move.victim);
            } else {
              g.discard(seat);
            }
            for (final p in g.players) {
              expect(p.score, inInclusiveRange(0, target));
            }
          }
          expect(g.players[g.winner!].score, target);
        }
      }
    });
  });

  group('Hold Card', () {
    HoldCardGame hold(int players) => HoldCardGame(
      players: [
        for (var i = 0; i < players; i++) HoldPlayer(i, 'P$i', isHuman: i == 0),
      ],
      rng: Random(2),
    );

    void setHands(HoldCardGame g, List<List<GameCard>> hands) {
      for (var i = 0; i < hands.length; i++) {
        g.players[i].hand
          ..clear()
          ..addAll(hands[i]);
      }
    }

    test('deals ten number cards each', () {
      final g = hold(6);
      for (final p in g.players) {
        expect(p.hand.length, 10);
        expect(p.hand.every((c) => c.light.kind == CardKind.number), isTrue);
      }
    });

    test('a match: the slowest presser takes the box', () {
      final g = hold(3);
      final a = n(5), b = n(5, CardColor.blue), c = n(2);
      setHands(g, [
        [a, n(1)],
        [b, n(1)],
        [c, n(1)],
      ]);
      g.pick(0, a);
      g.pick(1, b);
      g.pick(2, c);
      g.reveal();
      expect(g.matches, {5});
      expect(g.box.length, 3);
      expect(g.press(2), isNull);
      expect(g.press(0), isNull);
      final r = g.press(1)!;
      expect(r.taker, 1);
      expect(r.taken, 3);
      expect(g.players[1].hand.length, 4);
      expect(g.box, isEmpty);
      expect(g.phase, HoldPhase.choose);
    });

    test('someone who never presses takes the box', () {
      final g = hold(3);
      final a = n(5), b = n(5, CardColor.blue), c = n(2);
      setHands(g, [
        [a, n(1)],
        [b, n(1)],
        [c, n(1)],
      ]);
      g.pick(0, a);
      g.pick(1, b);
      g.pick(2, c);
      g.reveal();
      g.press(1);
      g.press(2);
      final r = g.settle();
      expect(r.taker, 0);
    });

    test('no match: the box carries over; a false press takes it', () {
      final g = hold(2);
      setHands(g, [
        [n(1), n(3), n(9)],
        [n(2), n(4), n(9, CardColor.blue)],
      ]);
      g.pick(0, g.players[0].hand[0]);
      g.pick(1, g.players[1].hand[0]);
      g.reveal();
      expect(g.isMatch, isFalse);
      final r = g.settle();
      expect(r.taker, isNull);
      expect(g.box.length, 2);

      g.pick(0, g.players[0].hand[0]);
      g.pick(1, g.players[1].hand[0]);
      g.reveal();
      final f = g.press(0)!;
      expect(f.falsePress, isTrue);
      expect(f.taker, 0);
      expect(f.taken, 4);
      expect(g.players[0].hand.length, 5);
    });

    test('emptying your hand wins; ties share the win', () {
      final g = hold(2);
      setHands(g, [
        [n(1)],
        [n(2)],
      ]);
      g.pick(0, g.players[0].hand.first);
      g.pick(1, g.players[1].hand.first);
      g.reveal();
      g.settle();
      expect(g.phase, HoldPhase.over);
      expect(g.winners, [0, 1]);
    });

    test('cannot pick twice or out of turn', () {
      final g = hold(2);
      final card = g.players[0].hand.first;
      g.pick(0, card);
      expect(() => g.pick(0, g.players[0].hand.first), throwsStateError);
      expect(() => g.reveal(), throwsStateError);
    });

    test('bots finish games', () {
      for (var seed = 0; seed < 60; seed++) {
        final rng = Random(seed);
        final count = 2 + seed % 5;
        final g = HoldCardGame(
          players: [for (var i = 0; i < count; i++) HoldPlayer(i, 'B$i')],
          rng: rng,
        );
        final bots = [
          for (var i = 0; i < count; i++)
            HoldBot(Difficulty.values[i % 3], rng),
        ];
        final total = count * 10;
        var rounds = 0;
        while (g.phase != HoldPhase.over) {
          expect(++rounds, lessThan(3000));
          for (final p in g.players) {
            g.pick(p.seat, bots[p.seat].pick(p));
          }
          g.reveal();
          if (g.isMatch) {
            // Press in order of reaction time; misses never press.
            final times = [
              for (final p in g.players) (p.seat, bots[p.seat].reaction()),
            ]..removeWhere((t) => t.$2 == null);
            times.sort((a, b) => a.$2!.compareTo(b.$2!));
            HoldResult? r;
            for (final (seat, _) in times) {
              r = g.press(seat) ?? r;
            }
            if (g.phase == HoldPhase.reveal) g.settle();
          } else {
            g.settle();
          }
          final cards =
              g.box.length + g.players.fold(0, (s, p) => s + p.hand.length);
          expect(cards, total, reason: 'cards are conserved');
        }
        expect(g.winners, isNotEmpty);
      }
    });
  });
}
