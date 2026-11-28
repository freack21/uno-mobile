import 'dart:math';

import 'cards.dart';
import 'exact_score.dart';
import 'hold_card.dart';
import 'i18n.dart';
import 'rules.dart';
import 'table.dart';

/// How far the drawn card's reveal has got in Exact Score.
enum ExactStage { tease, reveal, choose, bust }

/// Exact Score over time: draw, a teasing face-down beat, the flip, then the
/// points (or a bust). Bots and idle online players are played automatically.
class ExactScoreTable extends TableRuntime {
  ExactScoreTable({
    required this.game,
    required super.humans,
    this.difficulty = Difficulty.normal,
    super.pace,
    super.idleMs,
    Random? rng,
  }) : rng = rng ?? Random();

  ExactScoreGame game;
  final Difficulty difficulty;
  final Random rng;

  /// Reveal stage of the drawn card; null between draws.
  ExactStage? stage;

  /// Bumped per draw so animations replay.
  int turnId = 0;

  /// Points a seat had before its last scoring move (for the tick animation).
  final Map<int, int> fillFrom = {};

  /// Last card resolved.
  GameCard? last;

  @override
  bool get isOver => game.phase == ScorePhase.over;

  @override
  List<List<int>> standings() {
    final w = game.winner;
    final rest = rankBy([
      for (final p in game.players)
        if (p.seat != w) p.seat,
    ], (s) => -game.players[s].score);
    return [
      if (w != null) [w],
      ...rest,
    ];
  }

  @override
  void start() {
    sound('shuffle');
    changed();
    after(1100, _nextTurn);
  }

  @override
  void resume() {
    if (isOver) return;
    if (game.phase == ScorePhase.decide) {
      if (stage == ExactStage.choose) {
        _idleChoice(game.current);
      } else {
        _resolve(game.current);
      }
    } else {
      _nextTurn();
    }
  }

  int _botPace(int ms) {
    final f = switch (difficulty) {
      Difficulty.easy => 1.15,
      Difficulty.normal => 1.0,
      Difficulty.hard => 0.9,
    };
    return (ms * f).round();
  }

  void _nextTurn() {
    if (isOver) return;
    final seat = game.current;
    if (isHuman(seat)) {
      sound('turn', forSeat: seat);
      changed();
      final idle = idleMs;
      if (idle != null) {
        final id = turnId;
        after(idle, () {
          if (game.current == seat &&
              game.phase == ScorePhase.draw &&
              stage == null &&
              turnId == id) {
            _draw(seat);
          }
        });
      }
      return;
    }
    changed();
    after(_botPace(1000 + rng.nextInt(700)), () => _draw(seat));
  }

  /// [seat] draws on their turn. Returns false if it is not allowed now.
  bool draw(int seat) {
    if (seat != game.current ||
        game.phase != ScorePhase.draw ||
        stage != null) {
      return false;
    }
    _draw(seat);
    return true;
  }

  void _draw(int seat) {
    if (game.current != seat || game.phase != ScorePhase.draw) return;
    game.draw(seat);
    turnId++;
    // Only the latest move animates; older points stay crossed off.
    fillFrom.clear();
    stage = ExactStage.tease;
    sound('draw');
    changed();
    after(1150, () {
      stage = ExactStage.reveal;
      sound('flip');
      changed();
      after(750, () => _resolve(seat));
    });
  }

  void _resolve(int seat) {
    final f = game.drawnFace!;
    if (!game.canUse(seat)) {
      stage = ExactStage.bust;
      say(
        Msg('word', s: f.kind == CardKind.number ? 'BUST!' : 'WASTED'),
        subtitle: f.kind == CardKind.number
            ? Msg('bust', p: [seat], n: [game.remaining(seat), f.value])
            : const Msg('nothingToTake'),
        sound: 'nope',
        alert: true,
      );
      changed();
      after(1200, () {
        last = game.drawn;
        game.bust(seat);
        stage = null;
        _afterMove();
      });
      return;
    }
    final needsChoice =
        f.kind == CardKind.wild ||
        f.kind == CardKind.wildDraw ||
        f.kind == CardKind.draw;
    if (needsChoice && isHuman(seat)) {
      stage = ExactStage.choose;
      changed();
      _idleChoice(seat);
      return;
    }
    final c = needsChoice
        ? decideExactScore(game, seat, difficulty, rng)
        : (value: null, victim: null);
    _use(seat, value: c.value, victim: c.victim);
  }

  void _idleChoice(int seat) {
    final idle = idleMs;
    if (idle == null) return;
    final id = turnId;
    after(idle, () {
      if (stage != ExactStage.choose || turnId != id) return;
      final c = decideExactScore(game, seat, Difficulty.normal, rng);
      _use(seat, value: c.value, victim: c.victim);
    });
  }

  bool chooseWild(int seat, int value) {
    if (stage != ExactStage.choose || seat != game.current) return false;
    if (!game.wildValues(seat).contains(value)) return false;
    _use(seat, value: value);
    return true;
  }

  bool chooseVictim(int seat, int victim) {
    if (stage != ExactStage.choose || seat != game.current) return false;
    if (!game.victims(seat).contains(victim)) return false;
    _use(seat, victim: victim);
    return true;
  }

  void _use(int seat, {int? value, int? victim}) {
    final f = game.drawnFace!;
    final card = game.drawn!;
    final p = game.players[seat];
    final before = p.score;
    final victimBefore = victim == null ? 0 : game.players[victim].score;
    game.use(seat, value: value, victim: victim);
    last = card;
    stage = null;
    var wait = 900;
    switch (f.kind) {
      case CardKind.skip:
        sound('skip');
      case CardKind.reverse:
        if (game.players.length > 2) {
          say(
            const Msg('word', s: 'REVERSE'),
            subtitle: const Msg('direction'),
            sound: 'reverse',
          );
        } else {
          sound('reverse');
        }
      case CardKind.draw:
        final v = game.players[victim!];
        fillFrom[victim] = v.score;
        say(
          Msg('minus', n: [victimBefore - v.score]),
          subtitle: Msg('hit', p: [seat, victim]),
          sound: 'penalty',
          alert: true,
        );
      default:
        // Numbers and Wilds: points are crossed off one by one.
        final gained = p.score - before;
        fillFrom[seat] = before;
        say(
          Msg('plus', n: [gained]),
          subtitle: Msg('onScore', p: [seat], n: [p.score, game.target]),
          sound: f.isWild ? 'wild' : null,
          ticks: gained,
        );
        wait = 700 + gained * 110;
    }
    changed();
    after(wait, _afterMove);
  }

  void _afterMove() {
    if (isOver) {
      changed();
      return;
    }
    final skipped = game.lastSkipped;
    if (skipped.isNotEmpty) {
      say(
        const Msg('word', s: 'SKIP'),
        subtitle: Msg('loseTurn', p: skipped),
      );
    }
    changed();
    after(skipped.isEmpty ? 500 : 1200, _nextTurn);
  }
}

/// Hold Card over time: turns, the reveal, HOLD races and their outcome.
class HoldCardTable extends TableRuntime {
  HoldCardTable({
    required this.game,
    required super.humans,
    this.difficulty = Difficulty.normal,
    super.pace,
    super.idleMs,
    Random? rng,
  }) : rng = rng ?? Random() {
    bots = [for (final _ in game.players) HoldBot(difficulty, this.rng)];
  }

  HoldCardGame game;
  final Difficulty difficulty;
  final Random rng;
  late final List<HoldBot> bots;

  /// Bumped for every card put in the box, to replay the flip.
  int playId = 0;

  @override
  bool get isOver => game.phase == HoldPhase.over;

  @override
  List<List<int>> standings() {
    final winners = game.winners;
    return [
      if (winners.isNotEmpty) winners,
      ...rankBy([
        for (final p in game.players)
          if (!winners.contains(p.seat)) p.seat,
      ], (s) => game.players[s].hand.length),
    ];
  }

  @override
  void start() {
    sound('shuffle');
    changed();
    after(1000, _nextTurn);
  }

  @override
  void resume() {
    switch (game.phase) {
      case HoldPhase.call:
        _nextTurn();
      case HoldPhase.race:
        after(600, _settle);
      case HoldPhase.over:
        break;
    }
  }

  void _nextTurn() {
    if (game.phase != HoldPhase.call) return;
    final seat = game.current;
    final id = playId;
    if (isHuman(seat)) {
      sound('turn', forSeat: seat);
      changed();
      final idle = idleMs;
      if (idle != null) {
        after(idle, () {
          if (game.phase == HoldPhase.call &&
              game.current == seat &&
              playId == id) {
            final b = bots[seat];
            _place(seat, b.call(game.guess), b.pick(game.players[seat]));
          }
        });
      }
      return;
    }
    changed();
    final f = switch (difficulty) {
      Difficulty.easy => 1.2,
      Difficulty.normal => 1.0,
      Difficulty.hard => 0.85,
    };
    after(((1000 + rng.nextInt(800)) * f).round(), () {
      if (game.phase != HoldPhase.call || game.current != seat) return;
      final b = bots[seat];
      _place(seat, b.call(game.guess), b.pick(game.players[seat]));
    });
  }

  /// [seat] calls and puts their card at [index] in the box.
  bool place(int seat, HoldCall call, int index) {
    if (game.phase != HoldPhase.call || game.current != seat) return false;
    try {
      _place(seat, call, index);
      return true;
    } on StateError {
      return false;
    }
  }

  void _place(int seat, HoldCall call, int index) {
    final play = game.place(seat, call, index);
    playId++;
    sound('flip');
    if (play.drew > 0) {
      say(
        Msg('plus', n: [play.drew]),
        subtitle: Msg('stockDraw', p: [seat], n: [play.drew]),
        sound: 'penalty',
        alert: true,
      );
    }
    if (play.match) {
      sound('last');
      for (final q in game.players) {
        if (isHuman(q.seat)) continue;
        final t = bots[q.seat].reaction();
        if (t != null) after(t, () => press(q.seat));
      }
      after(2400, _settle);
      changed();
      return;
    }
    final kind = play.card.light.kind;
    if (play.drew == 0 && kind == CardKind.skip) {
      say(
        const Msg('word', s: 'SKIP'),
        subtitle: const Msg('nextLoses'),
        sound: 'skip',
      );
    } else if (play.drew == 0 && kind == CardKind.reverse) {
      say(
        const Msg('word', s: 'REVERSE'),
        subtitle: const Msg('direction'),
        sound: 'reverse',
      );
    }
    // A jumpy bot may slap HOLD on a miss before the next turn starts.
    for (final q in game.players) {
      if (isHuman(q.seat)) continue;
      final t = bots[q.seat].falsePress();
      if (t != null) after(t, () => press(q.seat));
    }
    changed();
    if (!isOver) after(play.drew > 0 ? 1900 : 1400, _nextTurn);
  }

  /// [seat] presses HOLD. Returns false if it changed nothing.
  bool press(int seat) {
    if (isOver) return false;
    if (game.phase == HoldPhase.race && game.presses.contains(seat)) {
      return false;
    }
    if (game.phase == HoldPhase.call && game.box.isEmpty) return false;
    sound('tick');
    final r = game.press(seat);
    changed();
    if (r != null) _resolved(r);
    return true;
  }

  void _settle() {
    if (game.phase != HoldPhase.race) return;
    _resolved(game.settle());
  }

  void _resolved(HoldResult r) {
    cancelTimers();
    final taker = r.taker!;
    say(
      r.falsePress
          ? const Msg('word', s: 'TOO EARLY!')
          : Msg('plus', n: [r.taken]),
      subtitle: r.falsePress
          ? Msg('tooEarly', p: [taker], n: [r.taken])
          : Msg('slowest', p: [taker]),
      sound: 'penalty',
      alert: true,
      forSeat: null,
    );
    changed();
    if (!isOver) after(1900, _nextTurn);
  }
}
