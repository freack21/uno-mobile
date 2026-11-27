import 'dart:math';

import 'bot.dart';
import 'cards.dart';
import 'game.dart';
import 'rules.dart';
import 'table.dart';

/// Runs a shedding game (Classic and friends) on the server: bot turns,
/// bot Jump-Ins and catches, the Speed clock, idle players, the opening
/// beat of each round and the break between rounds.
class ShedTable extends TableRuntime {
  ShedTable({
    required this.game,
    required super.humans,
    this.difficulty = Difficulty.normal,
    super.pace,
    super.idleMs,
    this.introMs = 8400,
    this.roundBreakMs = 6500,
    Random? rng,
  }) : rng = rng ?? Random() {
    bots = [for (final _ in game.players) Bot(difficulty, this.rng)];
    _seenEvent = game.events.isEmpty ? 0 : game.events.last.id;
  }

  Game game;
  final Difficulty difficulty;
  final Random rng;
  late final List<Bot> bots;

  /// Shuffle-and-deal animation time the clients play before each round.
  final int introMs;

  /// Pause on the round results before the next round (points, elimination).
  final int roundBreakMs;

  /// True while clients play the round opening; moves are refused.
  bool opening = false;

  /// Bot deciding its move, for the "thinking" dots.
  int? thinkingSeat;

  /// When the Speed clock of the person on turn runs out.
  DateTime? turnDeadline;

  /// Seats in the order they were knocked out of the match.
  final List<int> knockouts = [];

  int _seenEvent = 0;
  int _clockSerial = 0;
  int? _clockSeat;

  @override
  bool get isOver => game.isMatchOver;

  @override
  void start() => _openRound();

  @override
  void resume() => _afterChange();

  void _openRound() {
    opening = true;
    thinkingSeat = null;
    turnDeadline = null;
    _clockSeat = null;
    changed();
    after(introMs, () {
      opening = false;
      _afterChange();
    });
  }

  // ------------------------------------------------------------ people

  /// [seat] plays the cards with these ids (out of turn: a Jump-In).
  bool play(
    int seat,
    int cardId, {
    CardColor? color,
    int? swapWith,
    List<int> extra = const [],
  }) {
    if (opening || game.isRoundOver) return false;
    final hand = game.players[seat].hand;
    GameCard? find(int id) {
      for (final c in hand) {
        if (c.id == id) return c;
      }
      return null;
    }

    final card = find(cardId);
    final extras = [for (final id in extra) find(id)];
    if (card == null || extras.contains(null)) return false;
    return _act(seat, () {
      game.play(
        seat,
        card,
        color: color,
        swapWith: swapWith,
        extra: extras.cast<GameCard>(),
      );
      _clockSeat = null;
    });
  }

  bool draw(int seat) => _act(seat, () => game.draw(seat));
  bool pass(int seat) => _act(seat, () => game.pass(seat));
  bool challenge(int seat) => _act(seat, () => game.challengeWild(seat));

  /// The LAST CARD button: call, catch, or a false call that costs 2.
  bool callLast(int seat) {
    if (opening) return false;
    if (game.pressLast(seat) == LastPress.ignored) return false;
    _afterChange();
    return true;
  }

  bool catchPlayer(int seat, int target) {
    if (!game.catchPlayer(seat, target)) return false;
    _afterChange();
    return true;
  }

  bool _act(int seat, void Function() move) {
    if (opening || game.isRoundOver) return false;
    try {
      move();
    } on StateError {
      return false;
    }
    _afterChange();
    return true;
  }

  // --------------------------------------------------------- scheduling

  void _afterChange() {
    _readEvents();
    if (game.isMatchOver) {
      thinkingSeat = null;
      turnDeadline = null;
      changed();
      return;
    }
    if (game.phase == Phase.roundOver) {
      thinkingSeat = null;
      turnDeadline = null;
      changed();
      after(roundBreakMs, () {
        if (game.phase != Phase.roundOver) return;
        game.nextRound();
        _seenEvent = game.events.isEmpty ? 0 : game.events.last.id;
        _openRound();
      });
      return;
    }
    final version = game.version;
    _scheduleJumpIns(version);
    final seat = game.current;
    if (isHuman(seat)) {
      thinkingSeat = null;
      _startClock(seat, version);
      changed();
      return;
    }
    turnDeadline = null;
    _clockSeat = null;
    thinkingSeat = seat;
    final forgot = game.vulnerable;
    final delay =
        bots[seat].thinkTime(game, seat) +
        (_bannerShown ? 900 : 0) +
        // Give a person a fair chance to still call "Last card!".
        (forgot != null && isHuman(forgot) ? 1500 : 0);
    changed();
    after(delay, () {
      if (game.version == version) _autoMove(seat, bots[seat]);
    });
  }

  bool _bannerShown = false;

  void _readEvents() {
    const loud = {
      EventType.skip,
      EventType.reverse,
      EventType.penalty,
      EventType.swap,
      EventType.rotate,
      EventType.flip,
      EventType.discardAll,
      EventType.lastCall,
      EventType.caught,
      EventType.falseCall,
      EventType.challenge,
      EventType.knockout,
      EventType.jumpIn,
    };
    _bannerShown = false;
    for (final e in game.events) {
      if (e.id <= _seenEvent) continue;
      if (loud.contains(e.type)) _bannerShown = true;
      if (e.type == EventType.knockout && e.seat != null) {
        if (!knockouts.contains(e.seat)) knockouts.add(e.seat!);
      }
    }
    if (game.events.isNotEmpty) _seenEvent = game.events.last.id;
  }

  /// The Speed clock and the idle timer for a person on turn. Both restart
  /// when the turn passes to someone else or after the person plays.
  void _startClock(int seat, int version) {
    if (_clockSeat == seat) return;
    _clockSeat = seat;
    final serial = ++_clockSerial;
    final secs = game.rules.turnSeconds;
    turnDeadline = secs == null
        ? null
        : DateTime.now().add(
            Duration(milliseconds: (secs * 1000 * pace).round()),
          );
    if (secs != null) {
      after(secs * 1000, () {
        if (serial != _clockSerial || game.current != seat) return;
        if (game.isRoundOver) return;
        _clockSeat = null;
        game.timeout(seat);
        _afterChange();
      });
    }
    final idle = idleMs;
    if (idle != null) {
      after(idle, () {
        if (serial != _clockSerial || game.current != seat) return;
        if (game.isRoundOver) return;
        _clockSeat = null;
        _autoMove(seat, Bot(Difficulty.normal, rng));
      });
    }
  }

  void _scheduleJumpIns(int version) {
    if (!game.rules.jumpIn) return;
    for (var seat = 0; seat < game.players.length; seat++) {
      if (isHuman(seat) || seat == game.current) continue;
      final card = bots[seat].jumpIn(game, seat);
      if (card == null) continue;
      after(bots[seat].jumpInDelay(), () {
        if (game.version != version || !game.canJumpIn(seat, card)) return;
        game.play(seat, card);
        _afterChange();
      });
    }
  }

  /// A bot (or an idle person) takes the turn.
  void _autoMove(int seat, Bot bot) {
    if (game.isRoundOver || game.current != seat) return;
    final forgot = game.vulnerable;
    if (forgot != null && forgot != seat && bot.catches()) {
      game.catchPlayer(seat, forgot);
      _afterChange();
      return;
    }
    switch (bot.decide(game, seat)) {
      case PlayMove(:final card, :final color, :final swapWith, :final extra):
        if (game.players[seat].hand.length == 2 + extra.length &&
            bot.callsLast()) {
          game.callLast(seat);
        }
        game.play(seat, card, color: color, swapWith: swapWith, extra: extra);
      case DrawMove():
        game.draw(seat);
      case PassMove():
        game.pass(seat);
      case ChallengeMove():
        game.challengeWild(seat);
    }
    _afterChange();
  }

  // ------------------------------------------------------------ results

  @override
  List<List<int>> standings() {
    final g = game;
    final seats = [for (final p in g.players) p.seat];
    final out = knockouts.reversed.toList();
    final alive = [
      for (final s in seats)
        if (!out.contains(s)) s,
    ];
    final winner = g.lastRound?.winner;
    List<List<int>> head;
    if (g.rules.format == MatchFormat.points) {
      head = rankBy(alive, (s) => -g.players[s].score);
    } else if (winner != null && g.rules.teams) {
      final team = [
        for (final s in alive)
          if (s == winner || g.isTeammate(s, winner)) s,
      ];
      final rest = [
        for (final s in alive)
          if (!team.contains(s)) s,
      ];
      head = [team, if (rest.isNotEmpty) rest];
    } else {
      final others = [
        for (final s in alive)
          if (s != winner) s,
      ];
      head = [
        if (winner != null && alive.contains(winner)) [winner],
        ...rankBy(others, (s) => g.handPoints(g.players[s])),
      ];
    }
    return [
      ...head,
      for (final s in out) [s],
    ];
  }
}
