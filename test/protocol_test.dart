import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:last_card_core/cards.dart';
import 'package:last_card_core/exact_score.dart';
import 'package:last_card_core/game.dart';
import 'package:last_card_core/hold_card.dart';
import 'package:last_card_core/protocol.dart';
import 'package:last_card_core/rules.dart';

/// Sends a view through real JSON, like the socket does.
Map<String, dynamic> wire(Map<String, Object?> view) =>
    jsonDecode(jsonEncode(view)) as Map<String, dynamic>;

Game newGame(RuleSet rules, int players, int seed) => Game(
  rules: rules,
  players: [for (var i = 0; i < players; i++) Player(i, 'P$i')],
  rng: Random(seed),
);

void main() {
  test('rules survive the round trip', () {
    const r = RuleSet(
      deck: DeckType.flipside,
      format: MatchFormat.points,
      targetScore: 250,
      stack: StackRule.escalating,
      sevenZero: true,
      jumpIn: true,
      drawUntilPlayable: true,
      challengeWild4: true,
      combos: true,
      turnSeconds: 8,
      handLimit: 25,
    );
    final back = rulesFromJson(
      jsonDecode(jsonEncode(rulesToJson(r))) as Map<String, dynamic>,
    );
    expect(rulesToJson(back), rulesToJson(r));
  });

  test('viewer sees only their own hand, rotated to seat 0', () {
    final g = newGame(const RuleSet(), 4, 3);
    for (var viewer = 0; viewer < 4; viewer++) {
      final v = gameFromView(wire(gameView(g, viewer)));
      expect(v.players[0].name, 'P$viewer');
      expect(v.players[0].isHuman, isTrue);
      expect(
        v.players[0].hand.map((c) => c.id),
        g.players[viewer].hand.map((c) => c.id),
      );
      for (var i = 1; i < 4; i++) {
        final real = g.players[(i + viewer) % 4];
        expect(v.players[i].name, real.name);
        expect(v.players[i].hand.length, real.hand.length);
        expect(v.players[i].hand.every((c) => c.id < 0), isTrue);
      }
      expect(v.current, (g.current - viewer + 4) % 4);
      expect(v.top.id, g.top.id);
      expect(v.activeColor, g.activeColor);
      expect(v.drawPile.length, g.drawPile.length);
    }
  });

  test('no hidden card id leaks into another view', () {
    final g = newGame(const RuleSet(), 3, 5);
    final v = wire(gameView(g, 0));
    final seen = <int>{
      for (final p in v['players'] as List)
        for (final c in p['hand'] as List) (c as List)[0] as int,
      for (final c in v['discard'] as List) (c as List)[0] as int,
      if (v['drawTop'] != null) (v['drawTop'] as List)[0] as int,
    };
    for (final c in [...g.players[1].hand, ...g.players[2].hand]) {
      expect(seen.contains(c.id), isFalse, reason: 'card ${c.id}');
    }
  });

  test('playability matches the server for the viewer', () {
    for (var seed = 0; seed < 20; seed++) {
      final g = newGame(
        const RuleSet(stack: StackRule.same, combos: true),
        3,
        seed,
      );
      final viewer = g.current;
      final v = gameFromView(wire(gameView(g, viewer)));
      for (final c in g.players[viewer].hand) {
        expect(v.isPlayable(0, c), g.isPlayable(viewer, c));
        expect(v.comboPartners(0, c).length, g.comboPartners(viewer, c).length);
      }
    }
  });

  test('the drawn card is private; a bluff stays secret', () {
    final g = newGame(const RuleSet(challengeWild4: true), 3, 1);
    g.drawnCard = g.players[g.current].hand.first;
    g.phase = Phase.afterDraw;
    g.challenge = PendingChallenge(g.current, true);
    final owner = gameFromView(wire(gameView(g, g.current)));
    final other = gameFromView(wire(gameView(g, (g.current + 1) % 3)));
    expect(owner.drawnCard?.id, g.drawnCard!.id);
    expect(other.drawnCard, isNull);
    expect(other.challenge!.guilty, isFalse);
    expect(other.challenge!.offender, 2);
  });

  test('flipside opponents show only their other side', () {
    final g = newGame(const RuleSet(deck: DeckType.flipside), 2, 2);
    final v = gameFromView(wire(gameView(g, 0)));
    for (var i = 0; i < g.players[1].hand.length; i++) {
      final real = g.players[1].hand[i];
      final seen = v.players[1].hand[i];
      expect(seen.face(Side.dark).label, real.face(Side.dark).label);
      expect(seen.face(Side.light).label, 'Wild');
    }
    expect(
      v.drawPile.last.face(Side.dark).label,
      g.drawPile.last.face(Side.dark).label,
    );
  });

  test('events keep their seats rotated', () {
    final g = newGame(const RuleSet(), 3, 4);
    final seat = g.current;
    g.draw(seat);
    final v = gameFromView(wire(gameView(g, (seat + 1) % 3)));
    final e = v.events.lastWhere((e) => e.type == EventType.draw);
    expect(e.seat, 2);
  });

  test('exact score view round trip', () {
    final g = ExactScoreGame(
      players: [for (var i = 0; i < 3; i++) ScorePlayer(i, 'P$i')],
      target: 30,
      rng: Random(1),
    );
    g.players[2].score = 12;
    g.current = 2;
    g.draw(2);
    final v = exactFromView(wire(exactView(g, 2)));
    expect(v.players[0].score, 12);
    expect(v.current, 0);
    expect(v.drawn!.id, g.drawn!.id);
    expect(v.canUse(0), g.canUse(2));
    expect(v.target, 30);
  });

  test('hold card view never reveals hands', () {
    final g = HoldCardGame(
      players: [for (var i = 0; i < 3; i++) HoldPlayer(i, 'P$i')],
      rng: Random(1),
    );
    g.current = 1;
    g.place(1, const HoldCall.number(4), 0);
    // Only the last card put in the box is ever sent.
    final view = wire(holdView(g, 1));
    expect((view['players'] as List).every((p) => p['cards'] is int), isTrue);
    expect(((view['last'] as Map)['card'] as List)[0], g.last!.card.id);
    final v = holdFromView(wire(holdView(g, 1)));
    expect(v.players[0].hand.length, g.players[1].hand.length);
    expect(v.last!.seat, 0);
    expect(v.last!.call.number, 4);
    expect(v.box.length, g.box.length);
    expect(v.current, (g.current - 1 + 3) % 3);
  });
}
