import 'dart:math';

import 'cards.dart';
import 'rules.dart';

class Player {
  Player(this.seat, this.name, {this.isHuman = false});

  final int seat;
  final String name;
  final bool isHuman;
  final List<GameCard> hand = [];

  /// Match score (points format) or rounds won.
  int score = 0;

  /// Knocked out of the match (elimination / hand limit).
  bool out = false;

  /// Announced "Last card!" for the current single-card hand.
  bool calledLast = false;

  int get team => seat % 2;
}

enum EventType {
  play,
  jumpIn,
  draw,
  penalty,
  skip,
  reverse,
  swap,
  rotate,
  flip,
  discardAll,
  lastCall,
  caught,
  challenge,
  knockout,
  timeout,
  roundEnd,
}

class GameEvent {
  GameEvent(this.id, this.type, this.text, {this.seat, this.card, this.count});

  final int id;
  final EventType type;
  final String text;
  final int? seat;
  final GameCard? card;
  final int? count;

  @override
  String toString() => text;
}

enum Phase { play, afterDraw, roundOver, matchOver }

class PendingChallenge {
  const PendingChallenge(this.offender, this.guilty);

  final int offender;

  /// The offender held a card of the previous color, so the Wild +4 was a bluff.
  final bool guilty;
}

class RoundResult {
  const RoundResult({
    required this.winner,
    required this.points,
    this.knockedOut,
  });

  final int winner;
  final int points;
  final int? knockedOut;
}

/// The complete, UI-independent game engine. Every public mutation validates
/// its input and throws [StateError] on an illegal move.
class Game {
  Game({required this.rules, required this.players, Random? rng})
    : rng = rng ?? Random() {
    if (rules.teams && players.length != 4) {
      throw ArgumentError('Team play needs exactly 4 players');
    }
    if (players.length < 2) throw ArgumentError('Need at least 2 players');
    dealer = players.length - 1;
    startRound();
  }

  final RuleSet rules;
  final List<Player> players;
  final Random rng;

  final List<GameCard> drawPile = [];
  final List<GameCard> discard = [];
  final List<GameEvent> events = [];
  int _eventId = 0;

  Side side = Side.light;
  int current = 0;
  int direction = 1;
  int dealer = 0;
  int round = 0;
  CardColor activeColor = CardColor.red;
  Phase phase = Phase.play;

  /// Accumulated draw penalty waiting on [current].
  int pendingDraw = 0;
  PendingChallenge? challenge;

  /// Card just drawn on this turn; only it may be played (or pass).
  GameCard? drawnCard;

  /// Seat that went down to one card without calling; can be caught.
  int? vulnerable;
  RoundResult? lastRound;

  /// Bumped on every state change so async callers can detect staleness.
  int version = 0;

  // ---------------------------------------------------------------- queries

  GameCard get top => discard.last;
  CardFace get topFace => top.face(side);
  CardFace face(GameCard c) => c.face(side);
  Player get currentPlayer => players[current];
  List<Player> get activePlayers => players.where((p) => !p.out).toList();
  List<CardColor> get sideColors =>
      side == Side.light ? CardColor.light : CardColor.dark;
  bool get isRoundOver => phase == Phase.roundOver || phase == Phase.matchOver;
  bool get isMatchOver => phase == Phase.matchOver;

  int nextSeat(int from, [int steps = 1]) {
    var seat = from;
    for (var i = 0; i < steps; i++) {
      do {
        seat = (seat + direction) % players.length;
        if (seat < 0) seat += players.length;
      } while (players[seat].out && seat != from);
    }
    return seat;
  }

  bool isTeammate(int a, int b) => rules.teams && a != b && a % 2 == b % 2;

  bool canStack(CardFace f) => switch (rules.stack) {
    StackRule.off => false,
    StackRule.same => f.isDrawCard && f.sameSymbol(topFace),
    StackRule.escalating => f.isDrawCard && f.draw >= topFace.draw,
  };

  /// Whether [seat] may play [card] as a normal turn move.
  bool isPlayable(int seat, GameCard card) {
    if (isRoundOver || seat != current) return false;
    if (phase == Phase.afterDraw && card.id != drawnCard?.id) return false;
    final f = face(card);
    if (pendingDraw > 0) return canStack(f);
    if (f.isWild) return true;
    final t = topFace;
    return f.color == activeColor || (!t.isWild && f.sameSymbol(t));
  }

  List<GameCard> playableCards(int seat) =>
      players[seat].hand.where((c) => isPlayable(seat, c)).toList();

  /// Jump-In: an identical card (same color and symbol) may be played out of
  /// turn by anyone except the player whose turn it is.
  bool canJumpIn(int seat, GameCard card) {
    if (!rules.jumpIn || phase != Phase.play || seat == current) return false;
    if (pendingDraw > 0 || challenge != null || players[seat].out) return false;
    final f = face(card);
    final t = topFace;
    return !f.isWild && f.color == t.color && f.sameSymbol(t);
  }

  List<GameCard> jumpInCards(int seat) =>
      players[seat].hand.where((c) => canJumpIn(seat, c)).toList();

  /// The play needs a color choice from the player.
  bool needsColor(GameCard card) =>
      face(card).isWild ||
      (face(card).kind == CardKind.flip && card.face(side.other).isWild);

  /// The play needs a swap target (Seven-O "7").
  bool needsSwapTarget(int seat, GameCard card) {
    final f = face(card);
    return rules.sevenZero &&
        f.kind == CardKind.number &&
        f.value == 7 &&
        players[seat].hand.length > 1;
  }

  /// The player on turn faces a penalty and may resolve it by challenging.
  bool get canChallenge => challenge != null && pendingDraw > 0;

  bool canCallLast(int seat) {
    final p = players[seat];
    if (p.calledLast || p.out || isRoundOver) return false;
    return p.hand.length == 1 || (p.hand.length == 2 && seat == current);
  }

  int handPoints(Player p) => p.hand.fold(0, (s, c) => s + face(c).points);

  // ------------------------------------------------------------- lifecycle

  void startRound() {
    round++;
    side = Side.light;
    direction = 1;
    pendingDraw = 0;
    challenge = null;
    drawnCard = null;
    vulnerable = null;
    lastRound = null;
    discard.clear();
    drawPile
      ..clear()
      ..addAll(buildDeck(rules.deck, rng));
    for (final p in players) {
      p.hand.clear();
      p.calledLast = false;
    }
    dealer = nextSeat(dealer);
    for (var i = 0; i < rules.handSize; i++) {
      for (final p in activePlayers) {
        p.hand.add(drawPile.removeLast());
      }
    }
    // Always start on a number card so nobody is hit before playing.
    while (drawPile.last.light.kind != CardKind.number) {
      drawPile.insert(0, drawPile.removeLast());
    }
    discard.add(drawPile.removeLast());
    activeColor = topFace.color;
    current = nextSeat(dealer);
    phase = Phase.play;
    _changed();
  }

  void nextRound() {
    if (phase != Phase.roundOver) throw StateError('Round is not over');
    startRound();
  }

  // ----------------------------------------------------------------- moves

  /// Plays [card]. If it is not [seat]'s turn this is a Jump-In.
  void play(int seat, GameCard card, {CardColor? color, int? swapWith}) {
    final p = players[seat];
    if (!p.hand.any((c) => c.id == card.id)) {
      throw StateError('Card not in hand');
    }
    final jump = seat != current;
    if (jump ? !canJumpIn(seat, card) : !isPlayable(seat, card)) {
      throw StateError('Illegal play: $card');
    }
    if (needsColor(card) && (color == null || !_validColor(card, color))) {
      throw StateError('A valid color is required');
    }
    _clearVulnerable(seat);
    if (jump) current = seat;

    final f = face(card);
    final prevColor = activeColor;
    p.hand.removeWhere((c) => c.id == card.id);
    discard.add(card);
    drawnCard = null;
    phase = Phase.play;
    challenge = null;
    activeColor = f.isWild ? color! : f.color;
    _log(
      jump ? EventType.jumpIn : EventType.play,
      jump
          ? '${p.name} jumped in with ${f.label}'
          : '${p.name} played ${f.label}',
      seat: seat,
      card: card,
    );

    if (f.kind == CardKind.discardAll) {
      final extra = p.hand.where((c) => face(c).color == f.color).toList();
      if (extra.isNotEmpty) {
        p.hand.removeWhere(extra.contains);
        discard.insertAll(discard.length - 1, extra);
        _log(
          EventType.discardAll,
          '${p.name} discarded ${extra.length} more ${f.color.label} card${extra.length == 1 ? '' : 's'}',
          seat: seat,
          count: extra.length,
        );
      }
    }

    if (p.hand.isEmpty) {
      // A final draw card still counts against the next player.
      if (f.isDrawCard) {
        _drawCards(nextSeat(seat), pendingDraw + f.draw);
        pendingDraw = 0;
      }
      _endRound(seat);
      return;
    }
    if (p.hand.length == 1 && !p.calledLast) vulnerable = seat;

    switch (f.kind) {
      case CardKind.number:
        if (rules.sevenZero && f.value == 7) {
          _swapHands(seat, _validSwapTarget(seat, swapWith));
        } else if (rules.sevenZero && f.value == 0) {
          _rotateHands(seat);
        }
        _advance(1);
      case CardKind.skip:
        _logSkip(nextSeat(seat));
        _advance(2);
      case CardKind.reverse:
        if (activePlayers.length == 2) {
          _logSkip(nextSeat(seat));
          _advance(2);
        } else {
          direction = -direction;
          _log(EventType.reverse, 'Direction reversed', seat: seat);
          _advance(1);
        }
      case CardKind.draw || CardKind.wildDraw:
        pendingDraw += f.draw;
        if (rules.challengeWild4 &&
            f.kind == CardKind.wildDraw &&
            f.draw == 4 &&
            pendingDraw == 4) {
          final guilty = p.hand.any(
            (c) => !face(c).isWild && face(c).color == prevColor,
          );
          challenge = PendingChallenge(seat, guilty);
        }
        _advance(1);
      case CardKind.wildReverseDraw:
        if (activePlayers.length > 2) {
          direction = -direction;
          _log(EventType.reverse, 'Direction reversed', seat: seat);
        }
        pendingDraw += f.draw;
        _advance(1);
      case CardKind.skipAll:
        _log(EventType.skip, '${p.name} skipped everyone', seat: seat);
        _advance(0);
      case CardKind.discardAll || CardKind.wild:
        _advance(1);
      case CardKind.flip:
        side = side.other;
        activeColor = topFace.isWild ? color! : topFace.color;
        _log(
          EventType.flip,
          'Everything flipped to the ${side.name} side',
          seat: seat,
        );
        _advance(1);
      case CardKind.wildDrawColor:
        final victim = nextSeat(seat);
        final drawn = _drawUntilColor(victim, activeColor);
        _log(
          EventType.penalty,
          '${players[victim].name} dug ${drawn.length} card${drawn.length == 1 ? '' : 's'} for ${activeColor.label}',
          seat: victim,
          count: drawn.length,
        );
        if (isRoundOver) return;
        _advance(players[victim].out ? 1 : 2);
    }
  }

  /// Draws on your turn. With a pending penalty this takes the penalty.
  void draw(int seat) {
    _requireTurn(seat);
    if (phase != Phase.play) throw StateError('Already drew this turn');
    _clearVulnerable(seat);
    if (pendingDraw > 0) {
      _takePenalty(seat);
      if (!isRoundOver) _advance(1);
      return;
    }
    final drawn = <GameCard>[];
    final p = players[seat];
    do {
      final got = _drawCards(seat, 1);
      if (got.isEmpty) break;
      drawn.add(got.first);
    } while (rules.drawUntilPlayable &&
        !p.out &&
        !_matchesNormally(drawn.last));
    if (drawn.isNotEmpty) {
      _log(
        EventType.draw,
        '${p.name} drew ${drawn.length} card${drawn.length == 1 ? '' : 's'}',
        seat: seat,
        count: drawn.length,
      );
    }
    if (isRoundOver) return;
    if (p.out) {
      _advance(1);
    } else if (drawn.isNotEmpty && _matchesNormally(drawn.last)) {
      drawnCard = drawn.last;
      phase = Phase.afterDraw;
      _changed();
    } else {
      _advance(1);
    }
  }

  /// Keep the drawn card and end the turn.
  void pass(int seat) {
    _requireTurn(seat);
    if (phase != Phase.afterDraw) throw StateError('Draw first');
    drawnCard = null;
    phase = Phase.play;
    _advance(1);
  }

  /// Challenge a Wild +4. If it was a bluff the offender draws 4 and you play
  /// normally; otherwise you draw 6 and lose your turn.
  void challengeWild(int seat) {
    _requireTurn(seat);
    final ch = challenge;
    if (ch == null || pendingDraw == 0) {
      throw StateError('Nothing to challenge');
    }
    _clearVulnerable(seat);
    challenge = null;
    if (ch.guilty) {
      pendingDraw = 0;
      _drawCards(ch.offender, 4);
      _log(
        EventType.challenge,
        'Challenge won! ${players[ch.offender].name} bluffed and draws 4',
        seat: ch.offender,
        count: 4,
      );
      if (!isRoundOver) _beginTurn();
    } else {
      pendingDraw = 0;
      _drawCards(seat, 6);
      _log(
        EventType.challenge,
        'Challenge failed! ${players[seat].name} draws 6',
        seat: seat,
        count: 6,
      );
      if (!isRoundOver) _advance(1);
    }
  }

  void callLast(int seat) {
    if (!canCallLast(seat)) return;
    players[seat].calledLast = true;
    if (vulnerable == seat) vulnerable = null;
    _log(EventType.lastCall, '${players[seat].name}: "Last card!"', seat: seat);
  }

  /// Returns true if [target] forgot to call and was caught.
  bool catchPlayer(int catcher, int target) {
    if (vulnerable != target || catcher == target || isRoundOver) return false;
    vulnerable = null;
    _drawCards(target, 2);
    _log(
      EventType.caught,
      '${players[catcher].name} caught ${players[target].name}: +2',
      seat: target,
      count: 2,
    );
    if (!isRoundOver && players[current].out) _advance(1);
    return true;
  }

  /// Speed mode: the turn clock ran out.
  void timeout(int seat) {
    _requireTurn(seat);
    _log(
      EventType.timeout,
      "${players[seat].name} ran out of time",
      seat: seat,
    );
    if (phase == Phase.afterDraw) {
      pass(seat);
    } else if (pendingDraw > 0) {
      draw(seat);
    } else {
      _clearVulnerable(seat);
      _drawCards(seat, 2);
      if (!isRoundOver) _advance(1);
    }
  }

  // --------------------------------------------------------------- helpers

  bool _matchesNormally(GameCard c) {
    final f = face(c);
    if (f.isWild) return true;
    final t = topFace;
    return f.color == activeColor || (!t.isWild && f.sameSymbol(t));
  }

  bool _validColor(GameCard card, CardColor color) {
    final f = face(card);
    final colors = f.kind == CardKind.flip
        ? (side.other == Side.light ? CardColor.light : CardColor.dark)
        : sideColors;
    return colors.contains(color);
  }

  int _validSwapTarget(int seat, int? target) {
    if (target != null &&
        target != seat &&
        target >= 0 &&
        target < players.length &&
        !players[target].out) {
      return target;
    }
    final others = activePlayers.where((p) => p.seat != seat).toList()
      ..sort((a, b) => a.hand.length.compareTo(b.hand.length));
    return others.first.seat;
  }

  void _requireTurn(int seat) {
    if (isRoundOver) throw StateError('Round is over');
    if (seat != current) throw StateError('Not your turn');
  }

  void _clearVulnerable(int actor) {
    if (vulnerable != null && vulnerable != actor) vulnerable = null;
  }

  void _advance(int steps) {
    current = nextSeat(current, steps);
    if (players[current].out) current = nextSeat(current);
    _beginTurn();
  }

  /// Resolves penalties the player on turn cannot answer.
  void _beginTurn() {
    phase = Phase.play;
    drawnCard = null;
    var guard = 0;
    while (pendingDraw > 0 && !isRoundOver && guard++ < players.length) {
      final p = players[current];
      final canAnswer =
          challenge != null || p.hand.any((c) => canStack(face(c)));
      if (canAnswer) break;
      _takePenalty(current);
      if (isRoundOver) return;
      current = nextSeat(current);
    }
    _changed();
  }

  void _takePenalty(int seat) {
    final n = pendingDraw;
    pendingDraw = 0;
    challenge = null;
    _drawCards(seat, n);
    _log(
      EventType.penalty,
      '${players[seat].name} takes +$n',
      seat: seat,
      count: n,
    );
  }

  List<GameCard> _drawCards(int seat, int n) {
    final p = players[seat];
    final drawn = <GameCard>[];
    for (var i = 0; i < n && !p.out; i++) {
      if (drawPile.isEmpty) _reshuffle();
      if (drawPile.isEmpty) break;
      final c = drawPile.removeLast();
      p.hand.add(c);
      drawn.add(c);
      _checkHandLimit(seat);
    }
    if (p.hand.length > 1) p.calledLast = false;
    if (vulnerable == seat && p.hand.length != 1) vulnerable = null;
    return drawn;
  }

  List<GameCard> _drawUntilColor(int seat, CardColor color) {
    final p = players[seat];
    final drawn = <GameCard>[];
    while (!p.out) {
      final got = _drawCards(seat, 1);
      if (got.isEmpty) break;
      drawn.add(got.first);
      if (face(got.first).color == color) break;
    }
    return drawn;
  }

  void _reshuffle() {
    if (discard.length <= 1) return;
    final keep = discard.removeLast();
    drawPile
      ..addAll(discard)
      ..shuffle(rng);
    discard
      ..clear()
      ..add(keep);
  }

  void _checkHandLimit(int seat) {
    final limit = rules.handLimit;
    final p = players[seat];
    if (limit == null || p.out || p.hand.length < limit) return;
    p.out = true;
    drawPile.insertAll(0, p.hand);
    p.hand.clear();
    if (vulnerable == seat) vulnerable = null;
    _log(
      EventType.knockout,
      '${p.name} hit $limit cards and is out!',
      seat: seat,
    );
    final remaining = activePlayers;
    if (rules.teams) {
      final teams = remaining.map((p) => p.team).toSet();
      if (teams.length == 1) _endRound(remaining.first.seat);
    } else if (remaining.length == 1) {
      _endRound(remaining.first.seat);
    }
  }

  void _swapHands(int a, int b) {
    final ha = List.of(players[a].hand);
    players[a].hand
      ..clear()
      ..addAll(players[b].hand);
    players[b].hand
      ..clear()
      ..addAll(ha);
    _resetCalls();
    _log(
      EventType.swap,
      '${players[a].name} swapped hands with ${players[b].name}',
      seat: a,
    );
  }

  void _rotateHands(int from) {
    final seats = <int>[from];
    for (var s = nextSeat(from); s != from; s = nextSeat(s)) {
      seats.add(s);
    }
    final hands = [for (final s in seats) List.of(players[s].hand)];
    for (var i = 0; i < seats.length; i++) {
      final target = players[seats[(i + 1) % seats.length]];
      target.hand
        ..clear()
        ..addAll(hands[i]);
    }
    _resetCalls();
    _log(EventType.rotate, 'All hands passed along', seat: from);
  }

  /// After hands move around, single cards count as announced.
  void _resetCalls() {
    vulnerable = null;
    for (final p in players) {
      p.calledLast = p.hand.length == 1;
    }
  }

  void _logSkip(int seat) =>
      _log(EventType.skip, '${players[seat].name} was skipped', seat: seat);

  void _endRound(int winner) {
    if (isRoundOver) return;
    final w = players[winner];
    final losers = activePlayers.where(
      (p) => p.seat != winner && !isTeammate(p.seat, winner),
    );
    final points = losers.fold(0, (s, p) => s + handPoints(p));
    int? knocked;

    switch (rules.format) {
      case MatchFormat.single:
        _award(winner, 1);
        phase = Phase.matchOver;
      case MatchFormat.points:
        _award(winner, points);
        phase = w.score >= rules.targetScore
            ? Phase.matchOver
            : Phase.roundOver;
      case MatchFormat.elimination:
        final candidates = activePlayers.where((p) => p.seat != winner).toList()
          ..shuffle(rng)
          ..sort((a, b) {
            final byCount = b.hand.length.compareTo(a.hand.length);
            return byCount != 0 ? byCount : handPoints(b) - handPoints(a);
          });
        if (candidates.isNotEmpty) {
          final k = candidates.first..out = true;
          knocked = k.seat;
          _log(
            EventType.knockout,
            '${k.name} held the most cards and is out!',
            seat: k.seat,
          );
        }
        w.score++;
        phase = activePlayers.length <= 1 ? Phase.matchOver : Phase.roundOver;
    }
    // Knockouts (elimination or hand limit) can leave a single player.
    if (activePlayers.length <= 1) phase = Phase.matchOver;
    lastRound = RoundResult(
      winner: winner,
      points: points,
      knockedOut: knocked,
    );
    vulnerable = null;
    pendingDraw = 0;
    challenge = null;
    _log(
      EventType.roundEnd,
      rules.teams
          ? 'Team ${w.name} wins the round!'
          : '${w.name} wins the round!',
      seat: winner,
    );
  }

  void _award(int winner, int amount) {
    for (final p in players) {
      if (p.seat == winner || isTeammate(p.seat, winner)) p.score += amount;
    }
  }

  /// Winner of the match: the highest score among players still in.
  Player get matchWinner {
    final pool = activePlayers.isEmpty ? players : activePlayers;
    if (rules.format == MatchFormat.elimination && pool.length == 1) {
      return pool.first;
    }
    final winner = lastRound?.winner;
    if (winner != null && rules.format == MatchFormat.single) {
      return players[winner];
    }
    return pool.reduce((a, b) => b.score > a.score ? b : a);
  }

  void _log(
    EventType type,
    String text, {
    int? seat,
    GameCard? card,
    int? count,
  }) {
    events.add(
      GameEvent(++_eventId, type, text, seat: seat, card: card, count: count),
    );
    if (events.length > 60) events.removeAt(0);
    _changed();
  }

  void _changed() => version++;

  /// Total number of cards in play; constant for a deck (used by tests).
  int get cardCount =>
      drawPile.length +
      discard.length +
      players.fold(0, (s, p) => s + p.hand.length);
}
