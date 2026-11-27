import 'dart:async';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'package:last_card_core/cards.dart';
import 'package:last_card_core/hold_card.dart';
import 'package:last_card_core/modes.dart';
import 'package:last_card_core/rules.dart';

import 'game_controller.dart' show TableBanner, botNames;
import 'game_screen.dart' show TableBannerView;
import 'guide_screen.dart';
import 'party_widgets.dart';
import 'playing_card.dart';
import 'sfx.dart';
import 'theme.dart';

class HoldCardScreen extends StatefulWidget {
  const HoldCardScreen({
    super.key,
    required this.mode,
    required this.players,
    required this.difficulty,
    this.guess = HoldGuess.number,
  });

  final GameMode mode;
  final int players;
  final Difficulty difficulty;
  final HoldGuess guess;

  @override
  State<HoldCardScreen> createState() => _HoldCardScreenState();
}

class _HoldCardScreenState extends State<HoldCardScreen> {
  static const me = 0;
  static const gold = Color(0xFFF4B620);
  final _rng = Random();
  late HoldCardGame g;
  late List<HoldBot?> _bots;
  final _timers = <Timer>[];
  bool _paused = false;
  TableBanner? _banner;
  int _bannerId = 0;

  /// Bumped for every card put in the box, to replay the flip.
  int _playId = 0;

  /// The human's call for this turn, before picking a card.
  HoldCall? _call;

  @override
  void initState() {
    super.initState();
    _newGame();
  }

  @override
  void dispose() {
    _cancelTimers();
    super.dispose();
  }

  // ----------------------------------------------------------------- flow

  void _after(int ms, VoidCallback fn) {
    late final Timer t;
    t = Timer(Duration(milliseconds: ms), () {
      _timers.remove(t);
      if (mounted && !_paused) fn();
    });
    _timers.add(t);
  }

  void _cancelTimers() {
    for (final t in _timers) {
      t.cancel();
    }
    _timers.clear();
  }

  void _newGame() {
    _cancelTimers();
    g = HoldCardGame(
      players: [
        HoldPlayer(me, 'You', isHuman: true),
        for (var i = 1; i < widget.players; i++) HoldPlayer(i, botNames[i - 1]),
      ],
      guess: widget.guess,
      rng: _rng,
    );
    _bots = [
      for (var i = 0; i < widget.players; i++)
        i == me ? null : HoldBot(widget.difficulty, _rng),
    ];
    _banner = null;
    _call = null;
    playSfx(Sfx.shuffle);
    _after(1000, _nextTurn);
  }

  void _nextTurn() {
    if (g.phase != HoldPhase.call) return;
    _call = null;
    setState(() {});
    final seat = g.current;
    if (seat == me) {
      playSfx(Sfx.turn);
      return;
    }
    final bot = _bots[seat]!;
    final pace = switch (widget.difficulty) {
      Difficulty.easy => 1.2,
      Difficulty.normal => 1.0,
      Difficulty.hard => 0.85,
    };
    _after(((1000 + _rng.nextInt(800)) * pace).round(), () {
      if (g.phase != HoldPhase.call || g.current != seat) return;
      _place(seat, bot.call(g.guess), bot.pick(g.players[seat]));
    });
  }

  void _place(int seat, HoldCall call, int index) {
    final play = g.place(seat, call, index);
    _playId++;
    playSfx(Sfx.flip);
    final p = g.players[seat];
    if (play.drew > 0) {
      playSfx(Sfx.penalty);
      _say(
        '+${play.drew}',
        '${p.name} ${p.isHuman ? 'draw' : 'draws'} ${play.drew} from the stock',
        color: Palette.brand,
      );
    }
    if (play.match) {
      playSfx(Sfx.last);
      for (final q in g.players) {
        final t = _bots[q.seat]?.reaction();
        if (t != null) _after(t, () => _press(q.seat));
      }
      _after(2400, _settle);
      setState(() {});
      return;
    }
    final kind = play.card.light.kind;
    if (play.drew == 0 && kind == CardKind.skip) {
      playSfx(Sfx.skip);
      _say('SKIP', 'The next player loses a turn');
    } else if (play.drew == 0 && kind == CardKind.reverse) {
      playSfx(Sfx.reverse);
      _say('REVERSE', 'Play changes direction');
    }
    // A jumpy bot may slap HOLD on a miss before the next turn starts.
    for (final q in g.players) {
      final t = _bots[q.seat]?.falsePress();
      if (t != null) _after(t, () => _press(q.seat));
    }
    setState(() {});
    if (g.phase == HoldPhase.over) {
      _finish();
    } else {
      _after(play.drew > 0 ? 1900 : 1400, _nextTurn);
    }
  }

  void _press(int seat) {
    if (g.phase == HoldPhase.over) return;
    if (g.phase == HoldPhase.race && g.presses.contains(seat)) return;
    if (seat == me) HapticFeedback.heavyImpact();
    playSfx(Sfx.tick);
    final r = g.press(seat);
    setState(() {});
    if (r != null) _resolved(r);
  }

  void _settle() {
    if (g.phase != HoldPhase.race) return;
    _resolved(g.settle());
  }

  void _resolved(HoldResult r) {
    _cancelTimers();
    final taker = g.players[r.taker!];
    final you = taker.isHuman;
    _say(
      r.falsePress ? 'TOO EARLY!' : '+${r.taken}',
      r.falsePress
          ? '${taker.name} pressed without a match: ${r.taken} cards'
          : you
          ? 'Too slow! You take the box'
          : '${taker.name} was slowest and takes the box',
      color: Palette.brand,
    );
    playSfx(you ? Sfx.caught : Sfx.penalty);
    setState(() {});
    if (g.phase == HoldPhase.over) {
      _finish();
    } else {
      _after(1900, _nextTurn);
    }
  }

  void _finish() {
    playSfx(g.winners.contains(me) ? Sfx.win : Sfx.lose);
    setState(() {});
  }

  void _say(String title, String subtitle, {Color? color}) {
    _banner = TableBanner(++_bannerId, title, subtitle: subtitle, color: color);
  }

  Future<void> _menu() async {
    _paused = true;
    _cancelTimers();
    final action = await showPartyMenu(context, widget.mode);
    if (!mounted) return;
    _paused = false;
    switch (action) {
      case 'guide':
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => GuideScreen(mode: widget.mode)),
        );
        if (mounted) _resume();
      case 'restart':
        setState(_newGame);
      case 'quit':
        Navigator.pop(context);
      default:
        _resume();
    }
  }

  void _resume() {
    switch (g.phase) {
      case HoldPhase.call:
        _nextTurn();
      case HoldPhase.race:
        _after(600, _settle);
      case HoldPhase.over:
        break;
    }
  }

  // ------------------------------------------------------------- human

  void _chooseCall(HoldCall call) {
    HapticFeedback.selectionClick();
    playSfx(Sfx.tick);
    setState(() => _call = call);
  }

  void _pickCard(int index) {
    final call = _call;
    if (call == null || g.current != me || g.phase != HoldPhase.call) return;
    HapticFeedback.lightImpact();
    playSfx(Sfx.card);
    _place(me, call, index);
  }

  // ------------------------------------------------------------------- UI

  bool get _myTurn => g.current == me && g.phase == HoldPhase.call;

  String get _status {
    final last = g.last;
    switch (g.phase) {
      case HoldPhase.race:
        final i = g.presses.indexOf(me);
        return i >= 0 ? 'You pressed #${i + 1}' : 'MATCH! Press HOLD!';
      case HoldPhase.over:
        return '';
      case HoldPhase.call:
        if (_myTurn) {
          return _call == null
              ? '1 · Call a ${g.guess.label.toLowerCase()}'
              : '2 · Pick one of your cards (called ${_call!.label})';
        }
        if (last != null && !last.match) {
          return 'No match — the box keeps ${g.box.length}';
        }
        return "${g.players[g.current].name}'s turn…";
    }
  }

  @override
  Widget build(BuildContext context) {
    final race = g.phase == HoldPhase.race;
    return PartyScaffold(
      mode: widget.mode,
      subtitle:
          'Guess the ${g.guess.label.toLowerCase()} · '
          '${widget.difficulty.label}',
      accent: race ? gold : Palette.brand,
      onMenu: _menu,
      child: Stack(
        children: [
          Column(
            children: [
              _opponents(),
              Expanded(child: _table()),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
                child: Text(
                  _status,
                  style: font(
                    15,
                    weight: 600,
                    color: race ? gold : Palette.text,
                  ),
                ),
              ),
              if (_myTurn && _call == null) _callPanel(),
              _holdButton(race),
              _hand(),
            ],
          ),
          if (g.phase == HoldPhase.over) Positioned.fill(child: _results()),
        ],
      ),
    );
  }

  Widget _opponents() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 12, 8, 0),
      child: Row(
        children: [
          for (final p in g.players.where((p) => !p.isHuman))
            Expanded(child: _seat(p)),
        ],
      ),
    );
  }

  Widget _seat(HoldPlayer p) {
    final turn = g.current == p.seat && g.phase == HoldPhase.call;
    final press = g.presses.indexOf(p.seat);
    return Column(
      children: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            SeatAvatar(seat: p.seat, name: p.name, active: turn),
            Positioned(
              right: -6,
              bottom: -2,
              child: _CountBadge(count: p.hand.length),
            ),
            if (turn)
              const Positioned(right: -16, top: -4, child: ThinkingDots()),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          p.name,
          style: font(
            13,
            weight: 600,
            color: turn ? Palette.text : Palette.muted,
          ),
        ),
        const SizedBox(height: 4),
        SizedBox(
          height: 22,
          child: g.phase == HoldPhase.race && press >= 0
              ? PartyChip('#${press + 1}', color: const Color(0xFFE09A00))
              : null,
        ),
      ],
    );
  }

  Widget _table() {
    final last = g.last;
    final race = g.phase == HoldPhase.race;
    return Stack(
      alignment: Alignment.center,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(width: 132, child: _boxPile()),
            const SizedBox(width: 18),
            SizedBox(
              width: 132,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      last == null
                          ? 'No card yet'
                          : '${g.players[last.seat].name} called ${last.call.label}',
                      style: font(14, weight: 650, color: Palette.muted),
                    ),
                  ),
                  const SizedBox(height: 8),
                  last == null
                      ? SizedBox(width: 84, height: 84 * cardAspect)
                      : TweenAnimationBuilder<double>(
                          key: ValueKey(_playId),
                          tween: Tween(begin: 0, end: 1),
                          duration: const Duration(milliseconds: 460),
                          curve: Curves.easeOutBack,
                          builder: (context, v, child) => Transform(
                            alignment: Alignment.center,
                            transform: Matrix4.identity()
                              ..setEntry(3, 2, 0.0015)
                              ..rotateY((1 - v.clamp(0.0, 1.0)) * pi / 2),
                            child: child,
                          ),
                          child: PlayingCard(
                            width: 84,
                            face: last.card.light,
                            glow: race ? gold : null,
                          ),
                        ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 22,
                    child: last == null
                        ? null
                        : PartyChip(
                            last.match ? 'MATCH' : 'NO MATCH',
                            color: last.match
                                ? const Color(0xFFE09A00)
                                : Palette.surfaceHigh,
                          ),
                  ),
                ],
              ),
            ),
          ],
        ),
        Align(
          alignment: const Alignment(0, -0.98),
          child: TableBannerView(banner: _banner),
        ),
      ],
    );
  }

  Widget _boxPile() {
    final n = g.box.length;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Box', style: font(14, weight: 650, color: Palette.muted)),
        const SizedBox(height: 8),
        SizedBox(
          width: 84,
          height: 84 * cardAspect,
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (n == 0)
                Container(
                  width: 70,
                  height: 70 * cardAspect,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: Palette.text.withValues(alpha: 0.18),
                      width: 2,
                    ),
                  ),
                ),
              for (var i = 0; i < min(n, 5); i++)
                Transform.translate(
                  offset: Offset((i - 2) * 2.5, -i * 2.0),
                  child: Transform.rotate(
                    angle: (i.isEven ? -1 : 1) * 0.06 * i,
                    child: const PlayingCard(width: 64),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            '$n card${n == 1 ? '' : 's'} · stock ${g.stock.length}',
            style: font(13, weight: 600, color: Palette.muted),
          ),
        ),
      ],
    );
  }

  Widget _callPanel() {
    Widget chip(String label, Color color, Color fg, HoldCall call) => Padding(
      padding: const EdgeInsets.all(3),
      child: Material(
        color: color,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _chooseCall(call),
          child: SizedBox(
            width: g.guess == HoldGuess.number ? 54 : 76,
            height: 44,
            child: Center(
              child: Text(label, style: font(18, weight: 700, color: fg)),
            ),
          ),
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Wrap(
        alignment: WrapAlignment.center,
        children: g.guess == HoldGuess.number
            ? [
                for (var v = 0; v <= 9; v++)
                  chip(
                    '$v',
                    Palette.surfaceHigh,
                    Palette.text,
                    HoldCall.number(v),
                  ),
              ]
            : [
                for (final c in CardColor.light)
                  chip(
                    c.label,
                    Palette.of(c),
                    Palette.onColor(c),
                    HoldCall.color(c),
                  ),
              ],
      ),
    );
  }

  Widget _holdButton(bool race) {
    final live = race
        ? !g.presses.contains(me)
        : g.phase == HoldPhase.call && g.box.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: _Pulse(
        active: race && live,
        child: SizedBox(
          width: double.infinity,
          height: 60,
          child: FilledButton(
            onPressed: live ? () => _press(me) : null,
            style: FilledButton.styleFrom(
              backgroundColor: race ? Palette.brand : const Color(0xFF5C2520),
              disabledBackgroundColor: Palette.surfaceHigh,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.back_hand_rounded),
                const SizedBox(width: 10),
                Text('HOLD CARD', style: font(20, weight: 700)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Your cards, face down: you never see what you are putting in the box.
  Widget _hand() {
    final n = g.players[me].hand.length;
    final canPick = _myTurn && _call != null;
    return LayoutBuilder(
      builder: (context, box) {
        final w = box.maxWidth;
        const cardW = 58.0;
        const pad = 14.0;
        final step = n > 1
            ? max(18.0, min(cardW * 0.75, (w - pad * 2 - cardW) / (n - 1)))
            : 0.0;
        final total = n == 0 ? 0.0 : cardW + step * (n - 1);
        final scroll = total + pad * 2 > w;
        final start = scroll ? pad : (w - total) / 2;
        final stack = SizedBox(
          width: scroll ? total + pad * 2 : w,
          height: cardW * cardAspect + 16,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              for (var i = 0; i < n; i++)
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 240),
                  curve: Curves.easeOutCubic,
                  left: start + i * step,
                  top: canPick ? 0 : 12,
                  child: GestureDetector(
                    onTap: () => _pickCard(i),
                    child: PlayingCard(
                      width: cardW,
                      glow: canPick
                          ? Colors.white.withValues(alpha: 0.3)
                          : null,
                    ),
                  ),
                ),
            ],
          ),
        );
        return Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: scroll
              ? SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: stack,
                )
              : stack,
        );
      },
    );
  }

  Widget _results() {
    final winners = g.winners;
    final won = winners.contains(me);
    final names = winners.map((s) => g.players[s].name).toList();
    final title = won
        ? (winners.length > 1 ? 'You tie for the win!' : 'You win!')
        : '${names.join(' & ')} ${names.length > 1 ? 'win' : 'wins'}';
    final rows = List.of(g.players)
      ..sort((a, b) => a.hand.length.compareTo(b.hand.length));
    return PartyResults(
      title: title,
      subtitle: 'First to empty their hand',
      won: won,
      rows: [
        for (final p in rows)
          ResultRow(
            p.seat,
            p.name,
            '${p.hand.length} left',
            winner: winners.contains(p.seat),
          ),
      ],
      onAgain: () => setState(_newGame),
      onMenu: () => Navigator.pop(context),
    );
  }
}

class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final hot = count <= 2;
    return Container(
      constraints: const BoxConstraints(minWidth: 24),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: hot ? Palette.brand : Palette.cardWhite,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Palette.ink, width: 2),
      ),
      child: Text(
        '$count',
        textAlign: TextAlign.center,
        style: font(12, weight: 700, color: hot ? Colors.white : Palette.ink),
      ),
    );
  }
}

/// Gently pulses its child while [active].
class _Pulse extends StatefulWidget {
  const _Pulse({required this.active, required this.child});

  final bool active;
  final Widget child;

  @override
  State<_Pulse> createState() => _PulseState();
}

class _PulseState extends State<_Pulse> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );

  @override
  void initState() {
    super.initState();
    if (widget.active) _c.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(_Pulse old) {
    super.didUpdateWidget(old);
    if (widget.active && !_c.isAnimating) {
      _c.repeat(reverse: true);
    } else if (!widget.active && _c.isAnimating) {
      _c
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: Tween(
        begin: 1.0,
        end: 1.05,
      ).animate(CurvedAnimation(parent: _c, curve: Curves.easeInOut)),
      child: widget.child,
    );
  }
}
