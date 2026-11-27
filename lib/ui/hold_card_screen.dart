import 'dart:async';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../game/cards.dart';
import '../game/hold_card.dart';
import '../game/modes.dart';
import '../game/rules.dart';
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
  });

  final GameMode mode;
  final int players;
  final Difficulty difficulty;

  @override
  State<HoldCardScreen> createState() => _HoldCardScreenState();
}

class _HoldCardScreenState extends State<HoldCardScreen> {
  static const me = 0;
  final _rng = Random();
  late HoldCardGame g;
  late List<HoldBot?> _bots;
  final _timers = <Timer>[];
  bool _paused = false;

  /// The reveal row is shown from the reveal until the next round starts.
  bool _showReveal = false;
  TableBanner? _banner;
  int _bannerId = 0;

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
      rng: _rng,
    );
    _bots = [
      for (var i = 0; i < widget.players; i++)
        i == me ? null : HoldBot(widget.difficulty, _rng),
    ];
    _banner = null;
    playSfx(Sfx.shuffle);
    _startRound();
  }

  void _startRound() {
    setState(() => _showReveal = false);
    for (final p in g.players) {
      if (p.isHuman || g.picks.containsKey(p.seat)) continue;
      _after(500 + _rng.nextInt(1200), () {
        if (g.phase != HoldPhase.choose || g.picks.containsKey(p.seat)) return;
        g.pick(p.seat, _bots[p.seat]!.pick(p));
        playSfx(Sfx.deal);
        setState(() {});
        _maybeReveal();
      });
    }
  }

  void _pick(GameCard card) {
    if (g.phase != HoldPhase.choose || g.picks.containsKey(me)) return;
    HapticFeedback.lightImpact();
    playSfx(Sfx.card);
    setState(() => g.pick(me, card));
    _maybeReveal();
  }

  void _maybeReveal() {
    if (!g.allPicked) return;
    _after(550, () {
      setState(() {
        g.reveal();
        _showReveal = true;
      });
      playSfx(Sfx.flip);
      if (g.isMatch) {
        playSfx(Sfx.last);
        for (final p in g.players) {
          final t = _bots[p.seat]?.reaction();
          if (t != null) _after(t, () => _press(p.seat));
        }
        _after(2400, _settle);
      } else {
        for (final p in g.players) {
          final t = _bots[p.seat]?.falsePress();
          if (t != null) _after(t, () => _press(p.seat));
        }
        _after(1500, _settle);
      }
    });
  }

  void _press(int seat) {
    if (g.phase != HoldPhase.reveal || g.presses.contains(seat)) return;
    if (seat == me) HapticFeedback.heavyImpact();
    playSfx(Sfx.tick);
    final r = g.press(seat);
    setState(() {});
    if (r != null) _resolved(r);
  }

  void _settle() {
    if (g.phase != HoldPhase.reveal) return;
    _resolved(g.settle());
  }

  void _resolved(HoldResult r) {
    _cancelTimers();
    final taker = r.taker;
    if (taker == null) {
      _say('No match', 'The box keeps ${g.box.length} cards');
    } else {
      final name = g.players[taker].name;
      final you = taker == me;
      _say(
        r.falsePress ? 'TOO EARLY!' : '+${r.taken}',
        r.falsePress
            ? '$name ${you ? 'take' : 'takes'} the box: ${r.taken} cards'
            : you
            ? 'Too slow! You take the box'
            : '$name was slowest and takes the box',
        color: Palette.brand,
      );
      playSfx(you ? Sfx.caught : Sfx.penalty);
    }
    if (g.phase == HoldPhase.over) {
      playSfx(g.winners.contains(me) ? Sfx.win : Sfx.lose);
      setState(() {});
      return;
    }
    setState(() {});
    _after(1900, _startRound);
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

  /// Picks up where the game was paused.
  void _resume() {
    switch (g.phase) {
      case HoldPhase.choose:
        _startRound();
        _maybeReveal();
      case HoldPhase.reveal:
        _after(600, _settle);
      case HoldPhase.over:
        break;
    }
  }

  // ------------------------------------------------------------------- UI

  String get _status {
    switch (g.phase) {
      case HoldPhase.choose:
        return g.picks.containsKey(me)
            ? 'Waiting for the others…'
            : 'Pick a card to put in the box';
      case HoldPhase.reveal:
        if (!g.isMatch) return 'No match… don\'t press!';
        final i = g.presses.indexOf(me);
        return i >= 0 ? 'You pressed #${i + 1}' : 'Same number! Press HOLD!';
      case HoldPhase.over:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final match = g.phase == HoldPhase.reveal && g.isMatch;
    return PartyScaffold(
      mode: widget.mode,
      subtitle: 'Round ${g.round} · ${widget.difficulty.label}',
      accent: match ? const Color(0xFFF4B620) : Palette.brand,
      onMenu: _menu,
      child: Stack(
        children: [
          Column(
            children: [
              _opponents(),
              Expanded(child: _table()),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Text(
                  _status,
                  style: font(
                    15,
                    weight: 600,
                    color: match ? const Color(0xFFF4B620) : Palette.text,
                  ),
                ),
              ),
              _holdButton(match),
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
    final picked = g.picks.containsKey(p.seat);
    final press = g.presses.indexOf(p.seat);
    Widget status;
    if (g.phase == HoldPhase.choose) {
      status = picked
          ? const PartyChip('READY', color: Color(0xFF2EA358))
          : const ThinkingDots();
    } else if (g.phase == HoldPhase.reveal && press >= 0) {
      status = PartyChip('#${press + 1}', color: const Color(0xFFE09A00));
    } else {
      status = const SizedBox(height: 20);
    }
    return Column(
      children: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            SeatAvatar(seat: p.seat, name: p.name),
            Positioned(
              right: -6,
              bottom: -2,
              child: _CountBadge(count: p.hand.length),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(p.name, style: font(13, weight: 600, color: Palette.muted)),
        const SizedBox(height: 4),
        SizedBox(height: 24, child: Center(child: status)),
      ],
    );
  }

  Widget _table() {
    return LayoutBuilder(
      builder: (context, box) {
        final cardW = min(
          56.0,
          (box.maxWidth - 32) / max(4, g.players.length) - 8,
        );
        return Stack(
          alignment: Alignment.center,
          children: [
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _boxPile(),
                const SizedBox(height: 18),
                SizedBox(
                  // Card + lift for matches + seat avatar underneath.
                  height: cardW * cardAspect + 44,
                  child: _showReveal ? _revealRow(cardW) : _pickedRow(cardW),
                ),
              ],
            ),
            Align(
              alignment: const Alignment(0, -0.95),
              child: TableBannerView(banner: _banner),
            ),
          ],
        );
      },
    );
  }

  Widget _boxPile() {
    final n = g.box.length;
    return Column(
      children: [
        SizedBox(
          width: 96,
          height: 96 * cardAspect * 0.62,
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (n == 0)
                Container(
                  width: 70,
                  height: 70 * cardAspect * 0.62,
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
                  offset: Offset((i - 2) * 3.0, -i * 2.0),
                  child: Transform.rotate(
                    angle: (i.isEven ? -1 : 1) * 0.08 * i,
                    child: const PlayingCard(width: 46),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Text(
          n == 0 ? 'Box is empty' : 'Box · $n card${n == 1 ? '' : 's'}',
          style: font(14, weight: 650, color: Palette.muted),
        ),
      ],
    );
  }

  Widget _slot(int seat, double w, Widget card) {
    final p = g.players[seat];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          card,
          const SizedBox(height: 6),
          SeatAvatar(seat: seat, name: p.name, size: 18),
        ],
      ),
    );
  }

  /// Face-down cards of whoever has already picked this round.
  Widget _pickedRow(double w) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (final p in g.players)
          _slot(
            p.seat,
            w,
            g.picks.containsKey(p.seat)
                ? PlayingCard(width: w)
                : SizedBox(width: w, height: w * cardAspect),
          ),
      ],
    );
  }

  Widget _revealRow(double w) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (final (seat, card) in g.revealed)
          _slot(
            seat,
            w,
            TweenAnimationBuilder<double>(
              key: ValueKey('${g.round}-$seat'),
              tween: Tween(begin: 0, end: 1),
              duration: Duration(milliseconds: 380 + seat * 60),
              curve: Curves.easeOutBack,
              builder: (context, v, child) => Transform(
                alignment: Alignment.center,
                transform: Matrix4.identity()
                  ..setEntry(3, 2, 0.0015)
                  ..rotateY((1 - v.clamp(0.0, 1.0)) * pi / 2),
                child: child,
              ),
              child: Transform.translate(
                offset: Offset(
                  0,
                  g.matches.contains(card.light.value) ? -8 : 0,
                ),
                child: PlayingCard(
                  width: w,
                  face: card.light,
                  glow: g.matches.contains(card.light.value)
                      ? const Color(0xFFF4B620)
                      : null,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _holdButton(bool match) {
    final live = g.phase == HoldPhase.reveal && !g.presses.contains(me);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: _Pulse(
        active: match && live,
        child: SizedBox(
          width: double.infinity,
          height: 62,
          child: FilledButton(
            onPressed: live ? () => _press(me) : null,
            style: FilledButton.styleFrom(
              backgroundColor: match ? Palette.brand : const Color(0xFF9B2A21),
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

  Widget _hand() {
    final hand = List.of(g.players[me].hand)
      ..sort((a, b) => a.light.value.compareTo(b.light.value));
    final canPick = g.phase == HoldPhase.choose && !g.picks.containsKey(me);
    return LayoutBuilder(
      builder: (context, box) {
        final w = box.maxWidth;
        const cardW = 64.0;
        const pad = 14.0;
        final n = hand.length;
        final step = n > 1
            ? max(26.0, min(cardW * 0.8, (w - pad * 2 - cardW) / (n - 1)))
            : 0.0;
        final total = n == 0 ? 0.0 : cardW + step * (n - 1);
        final scroll = total + pad * 2 > w;
        final start = scroll ? pad : (w - total) / 2;
        final stack = SizedBox(
          width: scroll ? total + pad * 2 : w,
          height: cardW * cardAspect + 18,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              for (var i = 0; i < n; i++)
                AnimatedPositioned(
                  key: ValueKey(hand[i].id),
                  duration: const Duration(milliseconds: 240),
                  curve: Curves.easeOutCubic,
                  left: start + i * step,
                  top: canPick ? 0 : 14,
                  child: GestureDetector(
                    onTap: () => _pick(hand[i]),
                    child: PlayingCard(
                      width: cardW,
                      face: hand[i].light,
                      dimmed: !canPick,
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
      subtitle: 'Round ${g.round} · first to empty their hand',
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
