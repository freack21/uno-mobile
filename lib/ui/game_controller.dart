import 'dart:async';
import 'dart:math';

import 'package:material_ui/material_ui.dart';

import '../game/bot.dart';
import '../game/cards.dart';
import '../game/game.dart';
import '../game/modes.dart';
import '../game/rules.dart';
import 'theme.dart';

const botNames = ['Kira', 'Bimo', 'Sari', 'Dodo', 'Rara'];

/// A short, loud announcement shown over the table.
class TableBanner {
  const TableBanner(this.id, this.title, {this.subtitle, this.color});

  final int id;
  final String title;
  final String? subtitle;
  final Color? color;
}

/// Drives a [Game] for one human (seat 0) against bots: schedules bot turns,
/// Jump-Ins, catches and the Speed turn clock.
class GameController extends ChangeNotifier {
  GameController({
    required this.mode,
    required this.rules,
    required this.playerCount,
    required this.difficulty,
  }) {
    _newGame();
  }

  static const human = 0;

  final GameMode mode;
  final RuleSet rules;
  final int playerCount;
  final Difficulty difficulty;

  final _rng = Random();
  late Game game;
  late List<Bot?> _bots;

  Timer? _botTimer;
  Timer? _clock;
  final _jumpTimers = <Timer>[];
  bool _disposed = false;
  bool _paused = false;
  bool _humanClockRunning = false;
  int _seenEvent = 0;

  /// When the human's Speed clock runs out, if running.
  DateTime? turnDeadline;
  TableBanner? banner;

  Player get me => game.players[human];
  bool get isMyTurn => game.current == human && !game.isRoundOver && !me.out;

  /// The human is out of the match (knocked out), so their game is over.
  bool get humanOut => me.out;
  bool get showResults => game.isRoundOver || humanOut;

  void _newGame() {
    _cancelAll();
    final players = [
      Player(human, 'You', isHuman: true),
      for (var i = 1; i < playerCount; i++) Player(i, botNames[i - 1]),
    ];
    _bots = [
      for (var i = 0; i < playerCount; i++)
        i == human ? null : Bot(difficulty, _rng),
    ];
    game = Game(rules: rules, players: players, rng: _rng);
    _seenEvent = game.events.isEmpty ? 0 : game.events.last.id;
    banner = null;
    _afterChange();
  }

  void restart() {
    _paused = false;
    _newGame();
  }

  /// Freezes bots and the turn clock while a menu or guide is open.
  void pause() {
    _paused = true;
    _cancelAll();
  }

  void resume() {
    if (!_paused) return;
    _paused = false;
    _afterChange();
  }

  void nextRound() {
    if (game.phase != Phase.roundOver || humanOut) return;
    game.nextRound();
    _seenEvent = game.events.last.id;
    _afterChange();
  }

  // --------------------------------------------------------- human actions

  /// Returns an error message if the move was no longer legal.
  String? play(GameCard card, {CardColor? color, int? swapWith}) => _human(() {
    _humanClockRunning = false;
    game.play(human, card, color: color, swapWith: swapWith);
  });

  String? draw() => _human(() => game.draw(human));
  String? pass() => _human(() => game.pass(human));
  String? challenge() => _human(() => game.challengeWild(human));

  void callLast() {
    game.callLast(human);
    _afterChange();
  }

  bool catchBot(int seat) {
    final ok = game.catchPlayer(human, seat);
    if (ok) _afterChange();
    return ok;
  }

  String? _human(void Function() action) {
    try {
      action();
    } on StateError {
      notifyListeners();
      return 'Too late — the table moved on.';
    }
    _afterChange();
    return null;
  }

  // ------------------------------------------------------------ scheduling

  void _afterChange() {
    if (_disposed) return;
    _readEvents();
    if (_paused) {
      notifyListeners();
      return;
    }
    _botTimer?.cancel();
    for (final t in _jumpTimers) {
      t.cancel();
    }
    _jumpTimers.clear();

    if (showResults) {
      _stopClock();
      notifyListeners();
      return;
    }
    _scheduleJumpIns();
    if (game.current == human) {
      _startClock();
    } else {
      _stopClock();
      final iForgot = game.vulnerable == human;
      final delay = 750 + _rng.nextInt(450) + (iForgot ? 1400 : 0);
      _botTimer = Timer(Duration(milliseconds: delay), _botTurn);
    }
    notifyListeners();
  }

  void _botTurn() {
    if (_disposed || _paused || showResults) return;
    final g = game;
    final seat = g.current;
    final bot = _bots[seat];
    if (bot == null) return;

    final forgot = g.vulnerable;
    if (forgot != null && forgot != seat && bot.catches()) {
      g.catchPlayer(seat, forgot);
      _afterChange();
      return;
    }
    switch (bot.decide(g, seat)) {
      case PlayMove(:final card, :final color, :final swapWith):
        if (g.players[seat].hand.length == 2 && bot.callsLast()) {
          g.callLast(seat);
        }
        g.play(seat, card, color: color, swapWith: swapWith);
      case DrawMove():
        g.draw(seat);
      case PassMove():
        g.pass(seat);
      case ChallengeMove():
        g.challengeWild(seat);
    }
    _afterChange();
  }

  void _scheduleJumpIns() {
    if (!rules.jumpIn) return;
    final version = game.version;
    for (var seat = 1; seat < playerCount; seat++) {
      final bot = _bots[seat]!;
      final card = bot.jumpIn(game, seat);
      if (card == null) continue;
      _jumpTimers.add(
        Timer(Duration(milliseconds: bot.jumpInDelay()), () {
          if (_disposed || _paused || game.version != version) return;
          if (!game.canJumpIn(seat, card)) return;
          game.play(seat, card);
          _afterChange();
        }),
      );
    }
  }

  void _startClock() {
    final secs = rules.turnSeconds;
    if (secs == null || _humanClockRunning) return;
    _humanClockRunning = true;
    turnDeadline = DateTime.now().add(Duration(seconds: secs));
    _clock?.cancel();
    _clock = Timer(Duration(seconds: secs), () {
      if (_disposed || _paused || !isMyTurn) return;
      _humanClockRunning = false;
      game.timeout(human);
      _afterChange();
    });
  }

  void _stopClock() {
    _clock?.cancel();
    _humanClockRunning = false;
    turnDeadline = null;
  }

  void _cancelAll() {
    _botTimer?.cancel();
    _stopClock();
    for (final t in _jumpTimers) {
      t.cancel();
    }
    _jumpTimers.clear();
  }

  // --------------------------------------------------------------- banners

  void _readEvents() {
    TableBanner? next;
    for (final e in game.events) {
      if (e.id <= _seenEvent) continue;
      next = _bannerFor(e) ?? next;
    }
    if (game.events.isNotEmpty) _seenEvent = game.events.last.id;
    if (next != null) banner = next;
  }

  TableBanner? _bannerFor(GameEvent e) {
    final who = e.seat == null ? '' : game.players[e.seat!].name;
    final you = e.seat == human;
    return switch (e.type) {
      EventType.play when e.card != null && game.face(e.card!).isWild =>
        TableBanner(
          e.id,
          game.activeColor.label.toUpperCase(),
          subtitle: '$who picked a color',
          color: Palette.of(game.activeColor),
        ),
      EventType.jumpIn => TableBanner(e.id, 'JUMP IN!', subtitle: who),
      EventType.penalty => TableBanner(
        e.id,
        e.count == null ? 'DRAW' : '+${e.count}',
        subtitle: you ? 'You draw' : '$who draws',
        color: you ? Palette.brand : null,
      ),
      EventType.skip => TableBanner(e.id, 'SKIP', subtitle: e.text),
      EventType.reverse => TableBanner(e.id, 'REVERSE'),
      EventType.swap => TableBanner(e.id, 'SWAP!', subtitle: e.text),
      EventType.rotate => TableBanner(e.id, 'PASS IT ON', subtitle: e.text),
      EventType.flip => TableBanner(
        e.id,
        'FLIP!',
        subtitle: e.text,
        color: game.side == Side.dark ? Palette.of(CardColor.purple) : null,
      ),
      EventType.discardAll => TableBanner(
        e.id,
        'DISCARD ALL',
        subtitle: e.text,
      ),
      EventType.lastCall => TableBanner(
        e.id,
        'LAST CARD!',
        subtitle: who,
        color: Palette.brand,
      ),
      EventType.caught => TableBanner(
        e.id,
        'CAUGHT!',
        subtitle: e.text,
        color: Palette.brand,
      ),
      EventType.challenge => TableBanner(e.id, 'CHALLENGE', subtitle: e.text),
      EventType.knockout => TableBanner(
        e.id,
        'OUT!',
        subtitle: e.text,
        color: Palette.brand,
      ),
      EventType.timeout => TableBanner(e.id, 'TIME!', subtitle: e.text),
      _ => null,
    };
  }

  @override
  void dispose() {
    _disposed = true;
    _cancelAll();
    super.dispose();
  }
}
