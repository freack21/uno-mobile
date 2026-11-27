import 'dart:async';
import 'dart:math';

import 'package:material_ui/material_ui.dart';

import 'package:last_card_core/bot.dart';
import 'package:last_card_core/cards.dart';
import 'package:last_card_core/game.dart';
import 'package:last_card_core/modes.dart';
import 'package:last_card_core/protocol.dart';
import 'package:last_card_core/rules.dart';

import 'sfx.dart';
import 'theme.dart';

const botNames = ['Kira', 'Bimo', 'Sari', 'Dodo', 'Rara'];

/// Steps of the round opening shown before anyone plays.
enum IntroStep { shuffle, deal, flip, order }

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
  }) : send = null {
    _newGame();
  }

  /// A match played on the server: moves go out through [send], and the
  /// state comes back through [applyRemote].
  GameController.online({
    required this.mode,
    required Map<String, dynamic> match,
    required void Function(Map<String, Object?> action) this.send,
  }) : rules = rulesFromJson(
         (match['view'] as Map<String, dynamic>)['rules']
             as Map<String, dynamic>,
       ),
       playerCount = ((match['view'] as Map)['players'] as List).length,
       difficulty = Difficulty.normal {
    applyRemote(match);
  }

  static const human = 0;

  /// Sends a move to the server; null when playing offline.
  final void Function(Map<String, Object?> action)? send;
  bool get online => send != null;

  /// Changes whenever a different game is shown, so views can reset.
  int gameId = 0;
  int? _remoteMatch;
  bool _hasGame = false;

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
  bool _wasMyTurn = false;
  int _seenEvent = 0;

  /// When the human's Speed clock runs out, if running.
  DateTime? turnDeadline;
  TableBanner? banner;

  /// Bot currently "thinking" about its move, for the seat indicator.
  int? thinkingSeat;

  /// Round opening (shuffle, deal, first card, turn order); null once play
  /// has started. The engine has already dealt: this only paces the reveal.
  IntroStep? intro;

  /// Cards handed out so far during [IntroStep.deal].
  int dealt = 0;
  List<int> _dealSeats = const [];
  Timer? _introTimer;

  bool get inIntro => intro != null;

  /// Seats in turn order, starting with the first player.
  List<int> get turnOrder {
    final order = <int>[game.current];
    for (
      var s = game.nextSeat(game.current);
      s != game.current;
      s = game.nextSeat(s)
    ) {
      order.add(s);
    }
    return order;
  }

  /// Seat receiving the [i]-th dealt card.
  int dealSeatAt(int i) => _dealSeats[i];

  /// Cards of [seat] that are on the table already (all of them after the deal).
  int visibleCards(int seat) => switch (intro) {
    IntroStep.shuffle => 0,
    IntroStep.deal => _dealSeats.take(dealt).where((s) => s == seat).length,
    _ => game.players[seat].hand.length,
  };

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
    _hasGame = true;
    gameId++;
    _seenEvent = game.events.isEmpty ? 0 : game.events.last.id;
    banner = null;
    _startIntro();
  }

  /// Applies a match state from the server (online play).
  void applyRemote(Map<String, dynamic> msg) {
    if (_disposed) return;
    final next = gameFromView(msg['view'] as Map<String, dynamic>);
    final id = msg['id'] as int;
    final newMatch = id != _remoteMatch;
    final newRound = newMatch || !_hasGame || next.round != game.round;
    game = next;
    _hasGame = true;
    if (newMatch) {
      _remoteMatch = id;
      gameId++;
      banner = null;
    }
    thinkingSeat = msg['thinking'] as int?;
    final clock = msg['clockMs'] as int?;
    turnDeadline = clock == null
        ? null
        : DateTime.now().add(Duration(milliseconds: clock));
    if (newRound) {
      _seenEvent = game.events.isEmpty ? 0 : game.events.last.id;
      if (msg['opening'] == true) {
        _startIntro();
        return;
      }
    }
    _afterChange();
  }

  void restart() {
    if (online) return;
    _paused = false;
    _newGame();
  }

  /// Freezes bots and the turn clock while a menu or guide is open.
  void pause() {
    if (online) return;
    _paused = true;
    _cancelAll();
  }

  void resume() {
    if (online || !_paused) return;
    _paused = false;
    if (inIntro) {
      _runIntro();
    } else {
      _afterChange();
    }
  }

  void nextRound() {
    if (online || game.phase != Phase.roundOver || humanOut) return;
    game.nextRound();
    _seenEvent = game.events.last.id;
    _startIntro();
  }

  // ----------------------------------------------------------------- intro

  void _startIntro() {
    // Deal round-robin from the player after the dealer, like at a table.
    final seats = [game.nextSeat(game.dealer)];
    for (
      var s = game.nextSeat(seats.first);
      s != seats.first;
      s = game.nextSeat(s)
    ) {
      seats.add(s);
    }
    _dealSeats = [for (var i = 0; i < rules.handSize; i++) ...seats];
    dealt = 0;
    intro = IntroStep.shuffle;
    _wasMyTurn = false;
    playSfx(Sfx.shuffle);
    notifyListeners();
    _runIntro();
  }

  /// Schedules the next intro beat from the current step (also on resume).
  void _runIntro() {
    _introTimer?.cancel();
    if (_disposed || _paused) return;
    switch (intro) {
      case IntroStep.shuffle:
        _introTimer = Timer(const Duration(milliseconds: 1500), () {
          intro = IntroStep.deal;
          notifyListeners();
          _runIntro();
        });
      case IntroStep.deal:
        // About 2.6 s for the whole deal, whatever the table size.
        final ms = (2600 / _dealSeats.length).clamp(55, 110).round();
        _introTimer = Timer.periodic(Duration(milliseconds: ms), (t) {
          dealt++;
          playSfx(Sfx.deal);
          if (dealt >= _dealSeats.length) {
            t.cancel();
            _introTimer = Timer(const Duration(milliseconds: 500), () {
              intro = IntroStep.flip;
              playSfx(Sfx.flip);
              notifyListeners();
              _runIntro();
            });
          }
          notifyListeners();
        });
      case IntroStep.flip:
        _introTimer = Timer(const Duration(milliseconds: 1100), () {
          intro = IntroStep.order;
          playSfx(Sfx.start);
          notifyListeners();
          _runIntro();
        });
      case IntroStep.order:
        _introTimer = Timer(const Duration(milliseconds: 2600), skipIntro);
      case null:
        break;
    }
  }

  /// Ends the opening and starts play. Online, the server holds play for
  /// the whole opening, so taps ([user]) cannot skip it.
  void skipIntro({bool user = false}) {
    if (!inIntro || (user && online)) return;
    _introTimer?.cancel();
    intro = null;
    dealt = _dealSeats.length;
    _afterChange();
  }

  // --------------------------------------------------------- human actions

  /// Returns an error message if the move was no longer legal.
  String? play(
    GameCard card, {
    CardColor? color,
    int? swapWith,
    List<GameCard> extra = const [],
  }) => _human(
    () {
      _humanClockRunning = false;
      game.play(human, card, color: color, swapWith: swapWith, extra: extra);
    },
    {
      'a': 'play',
      'card': card.id,
      'color': color?.index,
      'swap': swapWith,
      'extra': [for (final c in extra) c.id],
    },
  );

  String? draw() => _human(() => game.draw(human), {'a': 'draw'});
  String? pass() => _human(() => game.pass(human), {'a': 'pass'});
  String? challenge() =>
      _human(() => game.challengeWild(human), {'a': 'challenge'});

  /// The LAST CARD button: call, catch or a false call (see
  /// [Game.pressLast]).
  void callLast() {
    if (inIntro) return;
    if (online) return send!({'a': 'last'});
    if (game.pressLast(human) != LastPress.ignored) _afterChange();
  }

  bool catchBot(int seat) {
    if (online) {
      send!({'a': 'catch', 'target': seat});
      return true;
    }
    final ok = game.catchPlayer(human, seat);
    if (ok) _afterChange();
    return ok;
  }

  String? _human(void Function() action, Map<String, Object?> remote) {
    if (inIntro) return 'Wait for the deal to finish';
    if (online) {
      send!(remote);
      return null;
    }
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
    if (!online) thinkingSeat = null;
    final bannerShown = _readEvents();
    if (_paused || inIntro) {
      notifyListeners();
      return;
    }
    if (online) {
      // The server runs bots and clocks; only react to what happened.
      if (isMyTurn && !_wasMyTurn) playSfx(Sfx.turn);
      _wasMyTurn = isMyTurn;
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
    if (isMyTurn && !_wasMyTurn) playSfx(Sfx.turn);
    _wasMyTurn = isMyTurn;
    if (game.current == human) {
      _startClock();
    } else {
      _stopClock();
      final seat = game.current;
      final iForgot = game.vulnerable == human;
      final delay =
          _bots[seat]!.thinkTime(game, seat) +
          // Let a banner (SKIP, +4, SWAP...) land before the next move.
          (bannerShown ? 900 : 0) +
          // Give the human a fair chance to still call "Last card!".
          (iForgot ? 1500 : 0);
      thinkingSeat = seat;
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
      case PlayMove(:final card, :final color, :final swapWith, :final extra):
        if (g.players[seat].hand.length == 2 + extra.length &&
            bot.callsLast()) {
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
    _introTimer?.cancel();
    _botTimer?.cancel();
    _stopClock();
    for (final t in _jumpTimers) {
      t.cancel();
    }
    _jumpTimers.clear();
  }

  // --------------------------------------------------------------- banners

  /// Posts the newest banner; returns whether one was posted.
  bool _readEvents() {
    TableBanner? next;
    final sounds = <Sfx>{};
    for (final e in game.events) {
      if (e.id <= _seenEvent) continue;
      next = _bannerFor(e) ?? next;
      final sound = _soundFor(e);
      if (sound != null) sounds.add(sound);
    }
    sounds.forEach(playSfx);
    if (game.events.isNotEmpty) _seenEvent = game.events.last.id;
    if (next != null) banner = next;
    return next != null;
  }

  Sfx? _soundFor(GameEvent e) {
    final card = e.card;
    return switch (e.type) {
      EventType.play || EventType.jumpIn =>
        card != null && game.face(card).isWild ? Sfx.wild : Sfx.card,
      EventType.draw => Sfx.draw,
      EventType.penalty || EventType.challenge => Sfx.penalty,
      EventType.skip => Sfx.skip,
      EventType.reverse => Sfx.reverse,
      EventType.swap || EventType.rotate || EventType.discardAll => Sfx.swap,
      EventType.flip => Sfx.flip,
      EventType.lastCall => Sfx.last,
      EventType.caught => Sfx.caught,
      EventType.falseCall => Sfx.penalty,
      EventType.knockout => Sfx.knockout,
      EventType.timeout => Sfx.nope,
      EventType.roundEnd =>
        e.seat == human || (e.seat != null && game.isTeammate(human, e.seat!))
            ? Sfx.win
            : Sfx.lose,
    };
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
      EventType.falseCall => TableBanner(
        e.id,
        'WRONG CALL',
        subtitle: you
            ? 'Nobody is on one card · you draw 2'
            : '$who called for nothing · draws 2',
        color: you ? Palette.brand : null,
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
