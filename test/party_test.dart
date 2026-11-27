import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:last_card_core/cards.dart';
import 'package:last_card_core/exact_score.dart';
import 'package:last_card_core/hold_card.dart';
import 'package:last_card_core/rules.dart';

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

    test('a number past the target busts', () {
      final g = exact(2);
      g.players[0].score = 19;
      stack(g, n(2));
      g.draw(0);
      expect(g.canUse(0), isFalse);
      expect(() => g.use(0), throwsStateError);
      g.bust(0);
      expect(g.players[0].score, 19);
      expect(g.current, 1);
    });

    test('a usable card cannot be thrown away', () {
      final g = exact(2);
      stack(g, n(3));
      g.draw(0);
      expect(() => g.bust(0), throwsStateError);
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
            if (g.canUse(seat)) {
              final c = decideExactScore(
                g,
                seat,
                Difficulty.values[seat % 3],
                rng,
              );
              g.use(seat, value: c.value, victim: c.victim);
            } else {
              g.bust(seat);
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
    HoldCardGame hold(int players, {HoldGuess guess = HoldGuess.number}) {
      final g = HoldCardGame(
        players: [
          for (var i = 0; i < players; i++)
            HoldPlayer(i, 'P$i', isHuman: i == 0),
        ],
        guess: guess,
        rng: Random(2),
      );
      g.current = 0;
      return g;
    }

    void setHands(HoldCardGame g, List<List<GameCard>> hands) {
      for (var i = 0; i < hands.length; i++) {
        g.players[i].hand
          ..clear()
          ..addAll(hands[i]);
      }
    }

    test('deals ten unseen cards each from the full deck', () {
      final g = hold(4);
      for (final p in g.players) {
        expect(p.hand.length, 10);
      }
      expect(g.stock.length, 108 - 40);
    });

    test('a miss stays in the box and the turn moves on', () {
      final g = hold(3);
      setHands(g, [
        [n(3), n(1)],
        [n(2), n(1)],
        [n(4), n(1)],
      ]);
      final play = g.place(0, const HoldCall.number(7), 0);
      expect(play.match, isFalse);
      expect(g.box.length, 1);
      expect(g.phase, HoldPhase.call);
      expect(g.current, 1);
      g.place(1, const HoldCall.number(9), 0);
      expect(g.box.length, 2);
      expect(g.current, 2);
    });

    test('a match starts a race; the slowest takes the box', () {
      final g = hold(3);
      setHands(g, [
        [n(3), n(1)],
        [n(7), n(1)],
        [n(4), n(1)],
      ]);
      g.place(0, const HoldCall.number(5), 0);
      final play = g.place(1, const HoldCall.number(7), 0);
      expect(play.match, isTrue);
      expect(g.phase, HoldPhase.race);
      expect(g.press(1), isNull);
      expect(g.press(0), isNull);
      final r = g.press(2)!;
      expect(r.taker, 2);
      expect(r.taken, 2);
      expect(g.players[2].hand.length, 4);
      expect(g.box, isEmpty);
      expect(g.current, 2, reason: 'play continues after the placer');
    });

    test('someone who never presses takes the box', () {
      final g = hold(3);
      setHands(g, [
        [n(7), n(1)],
        [n(2), n(1)],
        [n(4), n(1)],
      ]);
      g.place(0, const HoldCall.number(7), 0);
      g.press(0);
      g.press(2);
      expect(g.settle().taker, 1);
    });

    test('wilds always match; Wild +4 also costs 4', () {
      final g = hold(2);
      setHands(g, [
        [face(CardColor.wild, CardKind.wildDraw, draw: 4), n(1)],
        [n(2), n(3)],
      ]);
      final play = g.place(0, const HoldCall.number(0), 0);
      expect(play.match, isTrue);
      expect(play.drew, 4);
      expect(g.players[0].hand.length, 5);
    });

    test('number mode: +2 never matches and its owner draws 2', () {
      final g = hold(2);
      setHands(g, [
        [face(CardColor.red, CardKind.draw, draw: 2), n(1)],
        [n(2), n(3)],
      ]);
      final play = g.place(0, const HoldCall.number(2), 0);
      expect(play.match, isFalse);
      expect(play.drew, 2);
      expect(g.players[0].hand.length, 3);
    });

    test('color mode: color decides, +2 still costs 2', () {
      final g = hold(2, guess: HoldGuess.color);
      setHands(g, [
        [face(CardColor.blue, CardKind.draw, draw: 2), n(1)],
        [n(2, CardColor.green), n(3)],
      ]);
      expect(
        () => g.place(0, const HoldCall.number(2), 0),
        throwsStateError,
        reason: 'color mode needs a color call',
      );
      final play = g.place(0, const HoldCall.color(CardColor.blue), 0);
      expect(play.match, isTrue);
      expect(play.drew, 2);
    });

    test('skip and reverse change the turn order', () {
      final g = hold(3);
      setHands(g, [
        [face(CardColor.red, CardKind.skip), n(1)],
        [n(2), n(1)],
        [face(CardColor.red, CardKind.reverse), n(1)],
      ]);
      g.place(0, const HoldCall.number(9), 0);
      expect(g.current, 2);
      g.place(2, const HoldCall.number(9), 0);
      expect(g.direction, -1);
      expect(g.current, 1);
    });

    test('a false press takes the box', () {
      final g = hold(2);
      setHands(g, [
        [n(3), n(1)],
        [n(2), n(1)],
      ]);
      g.place(0, const HoldCall.number(7), 0);
      final r = g.press(1)!;
      expect(r.falsePress, isTrue);
      expect(r.taker, 1);
      expect(g.players[1].hand.length, 3);
    });

    test('the last card wins unless its owner takes the box', () {
      final g = hold(2);
      setHands(g, [
        [n(3)],
        [n(2), n(1)],
      ]);
      g.place(0, const HoldCall.number(7), 0);
      expect(g.phase, HoldPhase.over);
      expect(g.winners, [0]);
    });

    test('bots finish games in both modes', () {
      for (final guess in HoldGuess.values) {
        for (var seed = 0; seed < 40; seed++) {
          final rng = Random(seed);
          final count = 2 + seed % 5;
          final g = HoldCardGame(
            players: [for (var i = 0; i < count; i++) HoldPlayer(i, 'B$i')],
            guess: guess,
            rng: rng,
          );
          final bots = [
            for (var i = 0; i < count; i++)
              HoldBot(Difficulty.values[i % 3], rng),
          ];
          var turns = 0;
          while (g.phase != HoldPhase.over) {
            expect(++turns, lessThan(20000));
            final seat = g.current;
            final p = g.players[seat];
            g.place(seat, bots[seat].call(guess), bots[seat].pick(p));
            if (g.phase == HoldPhase.race) {
              final times = [
                for (final q in g.players) (q.seat, bots[q.seat].reaction()),
              ]..removeWhere((t) => t.$2 == null);
              times.sort((a, b) => a.$2!.compareTo(b.$2!));
              for (final (s, _) in times) {
                g.press(s);
              }
              if (g.phase == HoldPhase.race) g.settle();
            }
            final cards =
                g.stock.length +
                g.box.length +
                g.players.fold(0, (s, p) => s + p.hand.length);
            expect(cards, 108, reason: 'cards are conserved');
          }
          expect(g.winners, isNotEmpty);
        }
      }
    });
  });
}
