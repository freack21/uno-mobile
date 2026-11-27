/// Wire format shared by the multiplayer server and the app.
///
/// Game states are sent per viewer: seats are rotated so the viewer is
/// always seat 0 (the app's screens assume that), and cards the viewer may
/// not see are replaced by dummies with negative ids.
library;

import 'cards.dart';
import 'exact_score.dart';
import 'game.dart';
import 'hold_card.dart';
import 'rules.dart';

// ------------------------------------------------------------------- cards

List<int> faceToJson(CardFace f) => [
  f.color.index,
  f.kind.index,
  f.value,
  f.draw,
];

CardFace faceFromJson(List<dynamic> j) => CardFace(
  CardColor.values[j[0] as int],
  CardKind.values[j[1] as int],
  value: j[2] as int,
  draw: j[3] as int,
);

List<Object> cardToJson(GameCard c) => [
  c.id,
  faceToJson(c.light),
  if (c.dark != null) faceToJson(c.dark!),
];

GameCard cardFromJson(List<dynamic> j) => GameCard(
  j[0] as int,
  faceFromJson(j[1] as List<dynamic>),
  j.length > 2 ? faceFromJson(j[2] as List<dynamic>) : null,
);

const _hidden = CardFace(CardColor.wild, CardKind.wild);

/// Stand-in for a card the viewer cannot see.
GameCard dummyCard(int id) => GameCard(id, _hidden);

// ------------------------------------------------------------------- rules

Map<String, Object?> rulesToJson(RuleSet r) => {
  'deck': r.deck.index,
  'format': r.format.index,
  'target': r.targetScore,
  'stack': r.stack.index,
  'sevenZero': r.sevenZero,
  'jumpIn': r.jumpIn,
  'drawUntil': r.drawUntilPlayable,
  'challenge': r.challengeWild4,
  'combos': r.combos,
  'teams': r.teams,
  'turnSeconds': r.turnSeconds,
  'handLimit': r.handLimit,
};

RuleSet rulesFromJson(Map<String, dynamic> j) => RuleSet(
  deck: DeckType.values[j['deck'] as int],
  format: MatchFormat.values[j['format'] as int],
  targetScore: j['target'] as int,
  stack: StackRule.values[j['stack'] as int],
  sevenZero: j['sevenZero'] as bool,
  jumpIn: j['jumpIn'] as bool,
  drawUntilPlayable: j['drawUntil'] as bool,
  challengeWild4: j['challenge'] as bool,
  combos: j['combos'] as bool,
  teams: j['teams'] as bool,
  turnSeconds: j['turnSeconds'] as int?,
  handLimit: j['handLimit'] as int?,
);

// ------------------------------------------------------------ seat rotation

/// Maps real seats to the viewer's local seats (viewer = 0) and back.
class Seats {
  const Seats(this.viewer, this.count);

  final int viewer;
  final int count;

  int toLocal(int seat) => (seat - viewer + count) % count;
  int toReal(int local) => (local + viewer) % count;
  int? toLocalOrNull(int? seat) => seat == null ? null : toLocal(seat);
}

// --------------------------------------------------------- shedding game

/// The state of [g] as seen from [viewer]'s seat.
Map<String, Object?> gameView(Game g, int viewer) {
  final s = Seats(viewer, g.players.length);
  var hiddenId = -1;
  GameCard hide(GameCard c) {
    // Flipside backs show the other face; everything else is unknown.
    if (g.rules.deck != DeckType.flipside) return dummyCard(hiddenId--);
    return g.side == Side.light
        ? GameCard(hiddenId--, _hidden, c.dark)
        : GameCard(hiddenId--, c.light, _hidden);
  }

  final local = [
    for (var i = 0; i < g.players.length; i++) g.players[s.toReal(i)],
  ];
  return {
    'rules': rulesToJson(g.rules),
    'players': [
      for (final p in local)
        {
          'name': p.name,
          'score': p.score,
          'out': p.out,
          'called': p.calledLast,
          'hand': [
            for (final c in p.hand) cardToJson(p.seat == viewer ? c : hide(c)),
          ],
        },
    ],
    'draw': g.drawPile.length,
    'drawTop': g.drawPile.isEmpty ? null : cardToJson(hide(g.drawPile.last)),
    'discard': [for (final c in g.discard) cardToJson(c)],
    'side': g.side.index,
    'current': s.toLocal(g.current),
    'direction': g.direction,
    'dealer': s.toLocal(g.dealer),
    'round': g.round,
    'color': g.activeColor.index,
    'phase': g.phase.index,
    'pending': g.pendingDraw,
    // Whether the bluff was real stays on the server.
    'challenger': s.toLocalOrNull(g.challenge?.offender),
    'drawn': g.drawnCard != null && g.current == viewer
        ? cardToJson(g.drawnCard!)
        : null,
    'vulnerable': s.toLocalOrNull(g.vulnerable),
    'lastRound': g.lastRound == null
        ? null
        : {
            'winner': s.toLocal(g.lastRound!.winner),
            'points': g.lastRound!.points,
            'out': s.toLocalOrNull(g.lastRound!.knockedOut),
          },
    'events': [
      for (final e in g.events)
        {
          'id': e.id,
          'type': e.type.index,
          'text': e.text,
          'seat': s.toLocalOrNull(e.seat),
          'card': e.card == null ? null : cardToJson(e.card!),
          'count': e.count,
        },
    ],
    'version': g.version,
  };
}

/// Rebuilds a game from [gameView] output; seat 0 is the viewer.
Game gameFromView(Map<String, dynamic> j) {
  final pj = (j['players'] as List).cast<Map<String, dynamic>>();
  final players = [
    for (var i = 0; i < pj.length; i++)
      Player(i, pj[i]['name'] as String, isHuman: i == 0)
        ..score = pj[i]['score'] as int
        ..out = pj[i]['out'] as bool
        ..calledLast = pj[i]['called'] as bool
        ..hand.addAll([
          for (final c in pj[i]['hand'] as List) cardFromJson(c as List),
        ]),
  ];
  final g = Game.restore(
    rules: rulesFromJson(j['rules'] as Map<String, dynamic>),
    players: players,
  );
  final drawCount = j['draw'] as int;
  final top = j['drawTop'] as List?;
  for (var i = 0; i < drawCount; i++) {
    final last = i == drawCount - 1 && top != null;
    g.drawPile.add(last ? cardFromJson(top) : dummyCard(-10000 - i));
  }
  g.discard.addAll([
    for (final c in j['discard'] as List) cardFromJson(c as List),
  ]);
  g.side = Side.values[j['side'] as int];
  g.current = j['current'] as int;
  g.direction = j['direction'] as int;
  g.dealer = j['dealer'] as int;
  g.round = j['round'] as int;
  g.activeColor = CardColor.values[j['color'] as int];
  g.phase = Phase.values[j['phase'] as int];
  g.pendingDraw = j['pending'] as int;
  final challenger = j['challenger'] as int?;
  g.challenge = challenger == null ? null : PendingChallenge(challenger, false);
  final drawn = j['drawn'] as List?;
  g.drawnCard = drawn == null ? null : cardFromJson(drawn);
  g.vulnerable = j['vulnerable'] as int?;
  final lr = j['lastRound'] as Map<String, dynamic>?;
  g.lastRound = lr == null
      ? null
      : RoundResult(
          winner: lr['winner'] as int,
          points: lr['points'] as int,
          knockedOut: lr['out'] as int?,
        );
  for (final e in (j['events'] as List).cast<Map<String, dynamic>>()) {
    final card = e['card'] as List?;
    g.events.add(
      GameEvent(
        e['id'] as int,
        EventType.values[e['type'] as int],
        e['text'] as String,
        seat: e['seat'] as int?,
        card: card == null ? null : cardFromJson(card),
        count: e['count'] as int?,
      ),
    );
  }
  g.version = j['version'] as int;
  return g;
}

/// Seat indices of a shedding move from the viewer's side to the server's.
int realSeat(int viewer, int count, int local) =>
    Seats(viewer, count).toReal(local);

// --------------------------------------------------------------- party games

Map<String, Object?> exactView(ExactScoreGame g, int viewer) {
  final s = Seats(viewer, g.players.length);
  return {
    'target': g.target,
    'players': [
      for (var i = 0; i < g.players.length; i++)
        {
          'name': g.players[s.toReal(i)].name,
          'score': g.players[s.toReal(i)].score,
          'skip': g.players[s.toReal(i)].skipNext,
        },
    ],
    'draw': g.drawPile.length,
    'current': s.toLocal(g.current),
    'direction': g.direction,
    'phase': g.phase.index,
    // The drawn card is turned over in the middle of the table for everyone.
    'drawn': g.drawn == null ? null : cardToJson(g.drawn!),
    'winner': s.toLocalOrNull(g.winner),
    'skipped': [for (final x in g.lastSkipped) s.toLocal(x)],
  };
}

ExactScoreGame exactFromView(Map<String, dynamic> j) {
  final pj = (j['players'] as List).cast<Map<String, dynamic>>();
  final g = ExactScoreGame.restore(
    players: [
      for (var i = 0; i < pj.length; i++)
        ScorePlayer(i, pj[i]['name'] as String, isHuman: i == 0)
          ..score = pj[i]['score'] as int
          ..skipNext = pj[i]['skip'] as bool,
    ],
    target: j['target'] as int,
  );
  for (var i = 0; i < (j['draw'] as int); i++) {
    g.drawPile.add(dummyCard(-1 - i));
  }
  g.current = j['current'] as int;
  g.direction = j['direction'] as int;
  g.phase = ScorePhase.values[j['phase'] as int];
  final drawn = j['drawn'] as List?;
  g.drawn = drawn == null ? null : cardFromJson(drawn);
  g.winner = j['winner'] as int?;
  g.lastSkipped = [for (final x in j['skipped'] as List) x as int];
  return g;
}

Map<String, Object?> holdView(HoldCardGame g, int viewer) {
  final s = Seats(viewer, g.players.length);
  final last = g.last;
  return {
    'guess': g.guess.index,
    'players': [
      for (var i = 0; i < g.players.length; i++)
        {
          'name': g.players[s.toReal(i)].name,
          // Nobody sees any hand, not even its owner.
          'cards': g.players[s.toReal(i)].hand.length,
        },
    ],
    'stock': g.stock.length,
    'box': g.box.length,
    'current': s.toLocal(g.current),
    'direction': g.direction,
    'phase': g.phase.index,
    'last': last == null
        ? null
        : {
            'seat': s.toLocal(last.seat),
            'number': last.call.number,
            'color': last.call.color?.index,
            'card': cardToJson(last.card),
            'match': last.match,
            'drew': last.drew,
          },
    'presses': [for (final x in g.presses) s.toLocal(x)],
    'winners': [for (final x in g.winners) s.toLocal(x)],
  };
}

HoldCardGame holdFromView(Map<String, dynamic> j) {
  final pj = (j['players'] as List).cast<Map<String, dynamic>>();
  var id = -1;
  final g = HoldCardGame.restore(
    players: [
      for (var i = 0; i < pj.length; i++)
        HoldPlayer(i, pj[i]['name'] as String, isHuman: i == 0)
          ..hand.addAll([
            for (var k = 0; k < (pj[i]['cards'] as int); k++) dummyCard(id--),
          ]),
    ],
    guess: HoldGuess.values[j['guess'] as int],
  );
  for (var i = 0; i < (j['stock'] as int); i++) {
    g.stock.add(dummyCard(id--));
  }
  for (var i = 0; i < (j['box'] as int); i++) {
    g.box.add(dummyCard(id--));
  }
  g.current = j['current'] as int;
  g.direction = j['direction'] as int;
  g.phase = HoldPhase.values[j['phase'] as int];
  final last = j['last'] as Map<String, dynamic>?;
  if (last != null) {
    final number = last['number'] as int?;
    g.last = HoldPlay(
      seat: last['seat'] as int,
      call: number != null
          ? HoldCall.number(number)
          : HoldCall.color(CardColor.values[last['color'] as int]),
      card: cardFromJson(last['card'] as List),
      match: last['match'] as bool,
      drew: last['drew'] as int,
    );
  }
  g.presses.addAll([for (final x in j['presses'] as List) x as int]);
  g.winners = [for (final x in j['winners'] as List) x as int];
  return g;
}
