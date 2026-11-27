import 'dart:async';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../game/cards.dart';
import '../game/game.dart';
import '../game/modes.dart';
import '../game/rules.dart';
import 'game_controller.dart';
import 'guide_screen.dart';
import 'playing_card.dart';
import 'theme.dart';

const _seatColors = [
  Palette.brand,
  Color(0xFF2475D6),
  Color(0xFF2EA358),
  Color(0xFFF4B620),
  Color(0xFF7A4AD0),
  Color(0xFFF07A1C),
];

class GameScreen extends StatefulWidget {
  const GameScreen({
    super.key,
    required this.mode,
    required this.rules,
    required this.players,
    required this.difficulty,
  });

  final GameMode mode;
  final RuleSet rules;
  final int players;
  final Difficulty difficulty;

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  late final GameController c = GameController(
    mode: widget.mode,
    rules: widget.rules,
    playerCount: widget.players,
    difficulty: widget.difficulty,
  );

  String? _hint;
  Timer? _hintTimer;
  bool _busy = false;

  @override
  void dispose() {
    _hintTimer?.cancel();
    c.dispose();
    super.dispose();
  }

  Game get g => c.game;

  void _flash(String text) {
    _hintTimer?.cancel();
    setState(() => _hint = text);
    _hintTimer = Timer(const Duration(milliseconds: 1600), () {
      if (mounted) setState(() => _hint = null);
    });
  }

  Future<void> _onCardTap(GameCard card) async {
    if (_busy || c.showResults) return;
    final jump = !c.isMyTurn && g.canJumpIn(GameController.human, card);
    if (!jump && !g.isPlayable(GameController.human, card)) {
      HapticFeedback.selectionClick();
      _flash(c.isMyTurn ? _whyNot(card) : 'Wait for your turn');
      return;
    }
    CardColor? color;
    int? swapWith;
    _busy = true;
    try {
      if (g.needsColor(card)) {
        final flipping = g.face(card).kind == CardKind.flip;
        color = await _pickColor(
          flipping
              ? (g.side.other == Side.light ? CardColor.light : CardColor.dark)
              : g.sideColors,
          flipping ? g.side.other : g.side,
        );
        if (color == null) return;
      }
      if (g.needsSwapTarget(GameController.human, card)) {
        swapWith = await _pickSwap();
        if (swapWith == null) return;
      }
    } finally {
      _busy = false;
    }
    HapticFeedback.lightImpact();
    final err = c.play(card, color: color, swapWith: swapWith);
    if (err != null) _flash(err);
  }

  String _whyNot(GameCard card) {
    if (g.pendingDraw > 0) return 'Stack a draw card or take +${g.pendingDraw}';
    if (g.phase == Phase.afterDraw) return 'Only the drawn card can be played';
    return "Doesn't match ${g.activeColor.label} or ${g.topFace.symbol}";
  }

  void _onDraw() {
    if (!c.isMyTurn || g.phase != Phase.play) return;
    HapticFeedback.lightImpact();
    final err = c.draw();
    if (err != null) _flash(err);
  }

  Future<CardColor?> _pickColor(List<CardColor> colors, Side side) {
    return showModalBottomSheet<CardColor>(
      context: context,
      builder: (context) => _ColorPicker(colors: colors),
    );
  }

  Future<int?> _pickSwap() {
    final others = g.activePlayers.where((p) => !p.isHuman).toList();
    return showModalBottomSheet<int>(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Swap hands with…', style: font(22, weight: 650)),
              const SizedBox(height: 4),
              Text(
                'You give your hand and take theirs.',
                style: font(14, color: Palette.muted),
              ),
              const SizedBox(height: 16),
              for (final p in others)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Material(
                    color: Palette.surfaceHigh,
                    borderRadius: BorderRadius.circular(16),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () => Navigator.pop(context, p.seat),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            _Avatar(player: p, size: 40),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Text(p.name, style: font(17, weight: 600)),
                            ),
                            Text(
                              '${p.hand.length} card${p.hand.length == 1 ? '' : 's'}',
                              style: font(
                                15,
                                weight: 600,
                                color: Palette.muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openMenu() async {
    c.pause();
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Paused', style: font(24, weight: 700)),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Resume'),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () => Navigator.pop(context, 'guide'),
                icon: const Icon(Icons.menu_book_rounded),
                label: Text('How to play ${widget.mode.name}'),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () => Navigator.pop(context, 'restart'),
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Restart match'),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () => Navigator.pop(context, 'quit'),
                icon: const Icon(Icons.logout_rounded),
                label: const Text('Quit to menu'),
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted) return;
    switch (action) {
      case 'guide':
        await _openGuide();
      case 'restart':
        c.restart();
      case 'quit':
        Navigator.pop(context);
      default:
        c.resume();
    }
  }

  Future<void> _openGuide() async {
    c.pause();
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => GuideScreen(mode: widget.mode)),
    );
    if (mounted) c.resume();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _openMenu();
      },
      child: ListenableBuilder(
        listenable: c,
        builder: (context, _) {
          final accent = Palette.of(g.activeColor);
          return Scaffold(
            body: TweenAnimationBuilder<Color?>(
              tween: ColorTween(end: accent),
              duration: const Duration(milliseconds: 600),
              builder: (context, color, child) => DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(0, -0.12),
                    radius: 1.05,
                    colors: [
                      Color.alphaBlend(
                        (color ?? accent).withValues(alpha: 0.26),
                        const Color(0xFF1A1D23),
                      ),
                      Palette.ink,
                    ],
                  ),
                ),
                child: child,
              ),
              child: SafeArea(
                child: Stack(
                  children: [
                    Column(
                      children: [
                        _TopBar(
                          title: widget.mode.name,
                          subtitle: _subtitle(),
                          onMenu: _openMenu,
                          onGuide: _openGuide,
                        ),
                        _Opponents(controller: c),
                        Expanded(
                          child: _Table(controller: c, onDraw: _onDraw),
                        ),
                        _StatusBar(controller: c, hint: _hint),
                        _Hand(controller: c, onTap: _onCardTap),
                      ],
                    ),
                    if (c.showResults)
                      Positioned.fill(
                        child: _Results(
                          controller: c,
                          onMenu: () => Navigator.pop(context),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  String _subtitle() {
    final parts = <String>[];
    if (widget.rules.format != MatchFormat.single) {
      parts.add('Round ${g.round}');
    }
    if (widget.rules.format == MatchFormat.points) {
      parts.add('to ${widget.rules.targetScore}');
    }
    if (widget.rules.deck == DeckType.flipside) {
      parts.add(g.side == Side.light ? 'Light side' : 'Dark side');
    }
    parts.add(widget.difficulty.label);
    return parts.join(' · ');
  }
}

// ------------------------------------------------------------------ top bar

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.title,
    required this.subtitle,
    required this.onMenu,
    required this.onGuide,
  });

  final String title;
  final String subtitle;
  final VoidCallback onMenu;
  final VoidCallback onGuide;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Menu',
            onPressed: onMenu,
            icon: const Icon(Icons.pause_rounded),
          ),
          Expanded(
            child: Column(
              children: [
                Text(title, style: font(17, weight: 650)),
                Text(subtitle, style: font(12, color: Palette.muted)),
              ],
            ),
          ),
          IconButton(
            tooltip: 'How to play',
            onPressed: onGuide,
            icon: const Icon(Icons.help_outline_rounded),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- opponents

class _Opponents extends StatelessWidget {
  const _Opponents({required this.controller});

  final GameController controller;

  @override
  Widget build(BuildContext context) {
    final g = controller.game;
    final bots = g.players.where((p) => !p.isHuman).toList();
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 12, 8, 0),
      child: Row(
        children: [
          for (final p in bots)
            Expanded(
              child: _Seat(
                player: p,
                game: g,
                thinking: controller.thinkingSeat == p.seat,
                onCatch: () => controller.catchBot(p.seat),
              ),
            ),
        ],
      ),
    );
  }
}

class _Seat extends StatelessWidget {
  const _Seat({
    required this.player,
    required this.game,
    required this.thinking,
    required this.onCatch,
  });

  final Player player;
  final Game game;
  final bool thinking;
  final VoidCallback onCatch;

  @override
  Widget build(BuildContext context) {
    final p = player;
    final active = game.current == p.seat && !game.isRoundOver && !p.out;
    final partner = game.isTeammate(0, p.seat);
    final canCatch = game.vulnerable == p.seat;
    final flip = game.rules.deck == DeckType.flipside;
    final shown = min(p.hand.length, 6);

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 300),
      opacity: p.out ? 0.35 : 1,
      child: Column(
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: active ? Palette.text : Colors.transparent,
                    width: 2.5,
                  ),
                ),
                child: _Avatar(player: p, size: 44),
              ),
              Positioned(
                right: -6,
                bottom: -2,
                child: _CountBadge(
                  count: p.hand.length,
                  hot: p.hand.length <= 2 && !p.out,
                ),
              ),
              Positioned(
                right: -16,
                top: -4,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: thinking
                      ? const _ThinkingBubble()
                      : const SizedBox.shrink(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            p.out ? 'OUT' : p.name,
            style: font(
              13,
              weight: 600,
              color: active ? Palette.text : Palette.muted,
            ),
          ),
          SizedBox(
            height: 26,
            child: Center(
              child: canCatch
                  ? _Chip(label: 'CATCH!', color: Palette.brand, onTap: onCatch)
                  : partner
                  ? const _Chip(label: 'PARTNER', color: Color(0xFF2475D6))
                  : p.calledLast && p.hand.length == 1
                  ? const _Chip(label: 'LAST', color: Color(0xFFF4B620))
                  : SizedBox(
                      width: 14.0 + shown * 7,
                      height: 22,
                      child: Stack(
                        children: [
                          for (var i = 0; i < shown; i++)
                            Positioned(
                              left: i * 7.0,
                              child: PlayingCard(
                                width: 15,
                                face: flip
                                    ? p.hand[i].face(game.side.other)
                                    : null,
                                wildColors: game.side.other == Side.light
                                    ? CardColor.light
                                    : CardColor.dark,
                              ),
                            ),
                        ],
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.player, required this.size});

  final Player player;
  final double size;

  @override
  Widget build(BuildContext context) {
    final color = _seatColors[player.seat % _seatColors.length];
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Text(
        player.name[0],
        style: font(size * 0.46, weight: 700, color: Colors.white),
      ),
    );
  }
}

/// Three bouncing dots: the bot is deciding its move.
class _ThinkingBubble extends StatefulWidget {
  const _ThinkingBubble();

  @override
  State<_ThinkingBubble> createState() => _ThinkingBubbleState();
}

class _ThinkingBubbleState extends State<_ThinkingBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Thinking',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
        decoration: BoxDecoration(
          color: Palette.cardWhite,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Palette.ink, width: 2),
        ),
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) => Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < 3; i++)
                Padding(
                  padding: EdgeInsets.only(left: i == 0 ? 0 : 3),
                  child: Transform.translate(
                    offset: Offset(
                      0,
                      -2.5 * max(0, sin((_c.value * 2 - i * 0.22) * pi)),
                    ),
                    child: Container(
                      width: 5,
                      height: 5,
                      decoration: const BoxDecoration(
                        color: Palette.ink,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count, required this.hot});

  final int count;
  final bool hot;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
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

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.color, this.onTap});

  final String label;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          child: Text(label, style: font(11, weight: 700, color: Colors.white)),
        ),
      ),
    );
  }
}

// -------------------------------------------------------------------- table

class _Table extends StatelessWidget {
  const _Table({required this.controller, required this.onDraw});

  final GameController controller;
  final VoidCallback onDraw;

  @override
  Widget build(BuildContext context) {
    final g = controller.game;
    final canDraw = controller.isMyTurn && g.phase == Phase.play;
    return LayoutBuilder(
      builder: (context, box) {
        final cardW = min(92.0, min(box.maxWidth / 4.2, box.maxHeight / 2.3));
        return Stack(
          alignment: Alignment.center,
          children: [
            _DirectionRing(
              size: min(box.maxWidth * 0.82, box.maxHeight * 0.95),
              clockwise: g.direction == 1,
              color: Palette.of(g.activeColor),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _DrawPile(
                  game: g,
                  width: cardW,
                  enabled: canDraw,
                  onTap: onDraw,
                ),
                SizedBox(width: cardW * 0.42),
                _DiscardPile(game: g, width: cardW),
              ],
            ),
            Positioned(bottom: 6, child: _ColorPill(color: g.activeColor)),
            Align(
              alignment: const Alignment(0, -0.88),
              child: _BannerView(banner: controller.banner),
            ),
          ],
        );
      },
    );
  }
}

class _DrawPile extends StatelessWidget {
  const _DrawPile({
    required this.game,
    required this.width,
    required this.enabled,
    required this.onTap,
  });

  final Game game;
  final double width;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final flip = game.rules.deck == DeckType.flipside;
    final top = game.drawPile.isEmpty ? null : game.drawPile.last;
    final pending = game.pendingDraw;
    final label = !enabled
        ? '${game.drawPile.length} left'
        : pending > 0
        ? 'Take +$pending'
        : 'Draw';
    return Semantics(
      button: true,
      label: 'Draw pile',
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: width + 6,
              height: width * cardAspect + 6,
              child: Stack(
                children: [
                  for (var i = 2; i >= 0; i--)
                    Positioned(
                      left: i * 2.0,
                      top: i * 2.0,
                      child: PlayingCard(
                        width: width,
                        face: flip && i == 0 && top != null
                            ? top.face(game.side.other)
                            : null,
                        wildColors: game.side.other == Side.light
                            ? CardColor.light
                            : CardColor.dark,
                        glow: enabled && i == 0
                            ? Colors.white.withValues(alpha: 0.55)
                            : null,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 200),
              style: font(
                14,
                weight: 650,
                color: enabled
                    ? (pending > 0 ? Palette.brand : Palette.text)
                    : Palette.muted,
              ),
              child: Text(label),
            ),
          ],
        ),
      ),
    );
  }
}

class _DiscardPile extends StatelessWidget {
  const _DiscardPile({required this.game, required this.width});

  final Game game;
  final double width;

  double _tilt(GameCard c) => ((c.id * 7919) % 17 - 8) * 0.018;

  @override
  Widget build(BuildContext context) {
    final pile = game.discard;
    final under = pile.length > 1
        ? pile.sublist(max(0, pile.length - 3), pile.length - 1)
        : <GameCard>[];
    final top = pile.last;
    final lastPlay = game.events.lastWhere(
      (e) => e.card?.id == top.id,
      orElse: () => GameEvent(0, EventType.play, ''),
    );
    final fromBelow = lastPlay.seat == GameController.human;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: width * 1.25,
          height: width * cardAspect + 6,
          child: Stack(
            alignment: Alignment.center,
            children: [
              for (final c in under)
                Transform.rotate(
                  angle: _tilt(c),
                  child: PlayingCard(
                    width: width,
                    face: game.face(c),
                    wildColors: game.sideColors,
                  ),
                ),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 420),
                switchInCurve: Curves.easeOutBack,
                transitionBuilder: (child, anim) {
                  final slide = Tween(
                    begin: Offset(0, fromBelow ? 1.6 : -1.4),
                    end: Offset.zero,
                  ).animate(anim);
                  return SlideTransition(
                    position: slide,
                    child: ScaleTransition(
                      scale: Tween(begin: 0.8, end: 1.0).animate(anim),
                      child: child,
                    ),
                  );
                },
                layoutBuilder: (current, previous) =>
                    Stack(alignment: Alignment.center, children: [?current]),
                child: Transform.rotate(
                  key: ValueKey('${top.id}-${game.side.name}'),
                  angle: _tilt(top),
                  child: PlayingCard(
                    width: width,
                    face: game.topFace,
                    wildColors: game.sideColors,
                  ),
                ),
              ),
            ],
          ),
        ),
        // Matches the draw pile label so both piles stay aligned.
        const SizedBox(height: 26),
      ],
    );
  }
}

class _ColorPill extends StatelessWidget {
  const _ColorPill({required this.color});

  final CardColor color;

  @override
  Widget build(BuildContext context) {
    final c = Palette.of(color);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.fromLTRB(8, 5, 12, 5),
      decoration: BoxDecoration(
        color: Palette.surface.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.withValues(alpha: 0.7), width: 1.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            width: 14,
            height: 14,
            decoration: BoxDecoration(color: c, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Text(color.label, style: font(13, weight: 600)),
        ],
      ),
    );
  }
}

/// Slowly turning arrows around the piles showing the direction of play.
class _DirectionRing extends StatefulWidget {
  const _DirectionRing({
    required this.size,
    required this.clockwise,
    required this.color,
  });

  final double size;
  final bool clockwise;
  final Color color;

  @override
  State<_DirectionRing> createState() => _DirectionRingState();
}

class _DirectionRingState extends State<_DirectionRing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 14),
  )..repeat();

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _spin,
      builder: (context, _) => Transform.rotate(
        angle: (widget.clockwise ? 1 : -1) * _spin.value * 2 * pi,
        child: CustomPaint(
          size: Size.square(widget.size),
          painter: _RingPainter(widget.color, widget.clockwise),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.color, this.clockwise);

  final Color color;
  final bool clockwise;

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.width / 2;
    final center = size.center(Offset.zero);
    final paint = Paint()
      ..color = color.withValues(alpha: 0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    final rect = Rect.fromCircle(center: center, radius: r - 8);
    const arcs = 3;
    for (var i = 0; i < arcs; i++) {
      final start = i * 2 * pi / arcs;
      const sweep = 2 * pi / arcs - 0.5;
      canvas.drawArc(rect, start, sweep, false, paint);
      final end = clockwise ? start + sweep : start;
      final tip = center + Offset(cos(end), sin(end)) * (r - 8);
      final tangent = clockwise ? end + pi / 2 : end - pi / 2;
      final back = tip - Offset(cos(tangent), sin(tangent)) * 10;
      final normal = Offset(cos(end), sin(end)) * 6;
      final path = Path()
        ..moveTo(tip.dx, tip.dy)
        ..lineTo(back.dx + normal.dx, back.dy + normal.dy)
        ..lineTo(back.dx - normal.dx, back.dy - normal.dy)
        ..close();
      canvas.drawPath(path, Paint()..color = color.withValues(alpha: 0.42));
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.color != color || old.clockwise != clockwise;
}

/// Pops a big label for a moment whenever the controller posts a banner.
class _BannerView extends StatefulWidget {
  const _BannerView({required this.banner});

  final TableBanner? banner;

  @override
  State<_BannerView> createState() => _BannerViewState();
}

class _BannerViewState extends State<_BannerView> {
  TableBanner? _shown;
  Timer? _timer;

  @override
  void didUpdateWidget(_BannerView old) {
    super.didUpdateWidget(old);
    final b = widget.banner;
    if (b != null && b.id != _shown?.id) {
      _shown = b;
      _timer?.cancel();
      _timer = Timer(const Duration(milliseconds: 1700), () {
        if (mounted) setState(() => _shown = null);
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final b = _shown;
    return IgnorePointer(
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        transitionBuilder: (child, anim) => FadeTransition(
          opacity: anim,
          child: ScaleTransition(
            scale: Tween(
              begin: 0.7,
              end: 1.0,
            ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutBack)),
            child: child,
          ),
        ),
        child: b == null
            ? const SizedBox.shrink()
            : Container(
                key: ValueKey(b.id),
                padding: const EdgeInsets.symmetric(
                  horizontal: 22,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: b.color ?? Palette.cardWhite,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.4),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      b.title,
                      style: font(
                        30,
                        weight: 700,
                        color: b.color == null ? Palette.ink : Colors.white,
                        height: 1.05,
                      ),
                    ),
                    if (b.subtitle != null)
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 240),
                        child: Text(
                          b.subtitle!,
                          textAlign: TextAlign.center,
                          style: font(
                            13,
                            weight: 550,
                            color: b.color == null
                                ? Palette.ink.withValues(alpha: 0.7)
                                : Colors.white.withValues(alpha: 0.9),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
      ),
    );
  }
}

// --------------------------------------------------------------- status bar

class _StatusBar extends StatelessWidget {
  const _StatusBar({required this.controller, required this.hint});

  final GameController controller;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final g = c.game;
    final me = c.me;
    final myTurn = c.isMyTurn;
    final canLast = g.canCallLast(GameController.human);
    final urgentLast =
        canLast &&
        (g.vulnerable == GameController.human ||
            (myTurn && me.hand.length == 2 && g.playableCards(0).isNotEmpty));

    final text = hint ?? _status(c);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: Column(
        children: [
          if (c.turnDeadline != null) _TurnClock(deadline: c.turnDeadline!),
          SizedBox(
            height: 52,
            child: Row(
              children: [
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    child: Align(
                      key: ValueKey(text),
                      alignment: Alignment.centerLeft,
                      child: Text(
                        text,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: font(
                          15,
                          weight: 600,
                          color: hint != null
                              ? const Color(0xFFFFB4A8)
                              : myTurn
                              ? Palette.text
                              : Palette.muted,
                        ),
                      ),
                    ),
                  ),
                ),
                if (myTurn && g.canChallenge) ...[
                  _ActionButton(
                    label: 'Challenge',
                    color: const Color(0xFF2EA358),
                    onTap: c.challenge,
                  ),
                  const SizedBox(width: 8),
                ],
                if (myTurn && g.phase == Phase.afterDraw) ...[
                  _ActionButton(
                    label: 'Keep',
                    color: Palette.surfaceHigh,
                    onTap: c.pass,
                  ),
                  const SizedBox(width: 8),
                ],
                _LastButton(
                  enabled: canLast,
                  urgent: urgentLast,
                  onTap: () {
                    HapticFeedback.mediumImpact();
                    c.callLast();
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _status(GameController c) {
    final g = c.game;
    if (c.humanOut) return 'You are out of this match';
    if (g.isRoundOver) return '';
    if (!c.isMyTurn) {
      final jump = g.jumpInCards(GameController.human).isNotEmpty;
      if (jump) return 'Jump in now!';
      return "${g.currentPlayer.name}'s turn…";
    }
    if (g.canChallenge) return 'Wild +4! Challenge, or take +${g.pendingDraw}';
    if (g.pendingDraw > 0) return 'Stack a draw card or take +${g.pendingDraw}';
    if (g.phase == Phase.afterDraw) return 'Play the card you drew or keep it';
    if (g.playableCards(GameController.human).isEmpty) {
      return 'No match — draw a card';
    }
    return 'Your turn';
  }
}

class _TurnClock extends StatelessWidget {
  const _TurnClock({required this.deadline});

  final DateTime deadline;

  @override
  Widget build(BuildContext context) {
    final left = deadline.difference(DateTime.now());
    final total = left.inMilliseconds.clamp(1, 1 << 30);
    return TweenAnimationBuilder<double>(
      key: ValueKey(deadline),
      tween: Tween(begin: 1, end: 0),
      duration: Duration(milliseconds: total),
      builder: (context, v, _) => ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: LinearProgressIndicator(
          value: v,
          minHeight: 6,
          backgroundColor: Palette.surfaceHigh,
          color: v < 0.3 ? Palette.brand : Palette.text,
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.color,
    required this.onTap,
  });

  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          child: Text(label, style: font(14, weight: 650, color: Colors.white)),
        ),
      ),
    );
  }
}

class _LastButton extends StatefulWidget {
  const _LastButton({
    required this.enabled,
    required this.urgent,
    required this.onTap,
  });

  final bool enabled;
  final bool urgent;
  final VoidCallback onTap;

  @override
  State<_LastButton> createState() => _LastButtonState();
}

class _LastButtonState extends State<_LastButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  );

  @override
  void didUpdateWidget(_LastButton old) {
    super.didUpdateWidget(old);
    if (widget.urgent && !_pulse.isAnimating) {
      _pulse.repeat(reverse: true);
    } else if (!widget.urgent && _pulse.isAnimating) {
      _pulse
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final on = widget.enabled;
    return ScaleTransition(
      scale: Tween(
        begin: 1.0,
        end: 1.08,
      ).animate(CurvedAnimation(parent: _pulse, curve: Curves.easeInOut)),
      child: Material(
        color: on ? Palette.brand : Palette.surfaceHigh,
        borderRadius: BorderRadius.circular(14),
        elevation: on ? 4 : 0,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: on ? widget.onTap : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            child: Text(
              'LAST CARD',
              style: font(
                14,
                weight: 700,
                color: on ? Colors.white : Palette.muted,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// --------------------------------------------------------------------- hand

class _Hand extends StatelessWidget {
  const _Hand({required this.controller, required this.onTap});

  final GameController controller;
  final ValueChanged<GameCard> onTap;

  int _order(Game g, GameCard c) {
    final f = g.face(c);
    final colorIndex = f.isWild ? 9 : g.sideColors.indexOf(f.color);
    return colorIndex * 1000 + f.kind.index * 20 + f.value + f.draw;
  }

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final g = c.game;
    final hand = List.of(c.me.hand)
      ..sort((a, b) => _order(g, a).compareTo(_order(g, b)));
    final myTurn = c.isMyTurn;
    final jumps = g.jumpInCards(GameController.human).map((c) => c.id).toSet();
    final flip = g.rules.deck == DeckType.flipside;

    return LayoutBuilder(
      builder: (context, box) {
        final w = box.maxWidth;
        final cardW = min(86.0, w / 4.6);
        final cardH = cardW * cardAspect;
        const lift = 16.0;
        const pad = 14.0;
        final n = hand.length;
        final maxStep = cardW * 0.7;
        final fitStep = n > 1 ? (w - pad * 2 - cardW) / (n - 1) : maxStep;
        final step = max(cardW * 0.36, min(maxStep, fitStep));
        final total = n == 0 ? 0.0 : cardW + step * (n - 1);
        final scroll = total + pad * 2 > w;
        final start = scroll ? pad : (w - total) / 2;
        final height = cardH + lift + (flip ? 30 : 18);

        final stack = SizedBox(
          width: scroll ? total + pad * 2 : w,
          height: height,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              for (var i = 0; i < n; i++)
                _handCard(
                  g,
                  hand[i],
                  left: start + i * step,
                  width: cardW,
                  lift: lift,
                  playable:
                      myTurn && g.isPlayable(GameController.human, hand[i]),
                  jump: jumps.contains(hand[i].id),
                  dim: myTurn && !g.isPlayable(GameController.human, hand[i]),
                  flip: flip,
                ),
            ],
          ),
        );
        return Padding(
          padding: const EdgeInsets.only(top: 4),
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

  Widget _handCard(
    Game g,
    GameCard card, {
    required double left,
    required double width,
    required double lift,
    required bool playable,
    required bool jump,
    required bool dim,
    required bool flip,
  }) {
    final up = playable || jump;
    return AnimatedPositioned(
      key: ValueKey(card.id),
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      left: left,
      top: up ? 0 : lift,
      child: GestureDetector(
        onTap: () => onTap(card),
        child: Column(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                PlayingCard(
                  width: width,
                  face: g.face(card),
                  dimmed: dim && !jump,
                  wildColors: g.sideColors,
                  glow: jump
                      ? const Color(0xFFF4B620)
                      : playable
                      ? Colors.white.withValues(alpha: 0.35)
                      : null,
                ),
                if (jump)
                  const Positioned(
                    top: -8,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: _Chip(label: 'JUMP', color: Color(0xFFE09A00)),
                    ),
                  ),
              ],
            ),
            if (flip)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Opacity(
                  opacity: 0.75,
                  child: PlayingCard(
                    width: 18,
                    face: card.face(g.side.other),
                    wildColors: g.side.other == Side.light
                        ? CardColor.light
                        : CardColor.dark,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------------- color picker

class _ColorPicker extends StatelessWidget {
  const _ColorPicker({required this.colors});

  final List<CardColor> colors;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Pick a color', style: font(22, weight: 650)),
            const SizedBox(height: 16),
            GridView.count(
              shrinkWrap: true,
              crossAxisCount: 2,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 2.1,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                for (final color in colors)
                  Material(
                    color: Palette.of(color),
                    borderRadius: BorderRadius.circular(18),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(18),
                      onTap: () => Navigator.pop(context, color),
                      child: Center(
                        child: Text(
                          color.label,
                          style: font(
                            20,
                            weight: 700,
                            color: Palette.onColor(color),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------ results

class _Results extends StatefulWidget {
  const _Results({required this.controller, required this.onMenu});

  final GameController controller;
  final VoidCallback onMenu;

  @override
  State<_Results> createState() => _ResultsState();
}

class _ResultsState extends State<_Results> {
  bool _visible = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    // Let the final card land before covering the table.
    _timer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() => _visible = true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final g = c.game;
    final rules = g.rules;
    final matchOver = g.isMatchOver || c.humanOut;
    final winnerSeat = g.lastRound?.winner;
    final iWon = g.isMatchOver
        ? (g.matchWinner.isHuman ||
              (rules.teams && g.isTeammate(0, g.matchWinner.seat)))
        : winnerSeat == 0 ||
              (winnerSeat != null && g.isTeammate(0, winnerSeat));

    final String title;
    if (c.humanOut && !g.isMatchOver) {
      title = 'You\'re out';
    } else if (g.isMatchOver) {
      title = iWon
          ? (rules.teams ? 'Your team wins!' : 'You win!')
          : '${g.matchWinner.name} ${rules.teams ? '& partner win' : 'wins'}';
    } else {
      title = iWon
          ? 'Round won!'
          : '${g.players[winnerSeat!].name} won the round';
    }
    final subtitle = switch (rules.format) {
      MatchFormat.points when g.lastRound != null =>
        '+${g.lastRound!.points} points · first to ${rules.targetScore}',
      MatchFormat.elimination when g.lastRound?.knockedOut != null =>
        '${g.players[g.lastRound!.knockedOut!].name} was eliminated',
      _ => matchOver ? 'Match over' : 'Round ${g.round}',
    };

    final rows = List.of(g.players)
      ..sort((a, b) {
        if (a.out != b.out) return a.out ? 1 : -1;
        final s = b.score.compareTo(a.score);
        return s != 0 ? s : a.hand.length.compareTo(b.hand.length);
      });

    return AnimatedOpacity(
      opacity: _visible ? 1 : 0,
      duration: const Duration(milliseconds: 260),
      child: IgnorePointer(
        ignoring: !_visible,
        child: ColoredBox(
          color: Colors.black.withValues(alpha: 0.62),
          child: Center(
            child: Container(
              margin: const EdgeInsets.all(20),
              padding: const EdgeInsets.fromLTRB(22, 26, 22, 20),
              constraints: const BoxConstraints(maxWidth: 420),
              decoration: BoxDecoration(
                color: Palette.surface,
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: Palette.line),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(
                    iWon ? Icons.emoji_events_rounded : Icons.style_rounded,
                    size: 44,
                    color: iWon ? const Color(0xFFF4B620) : Palette.muted,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: font(26, weight: 700),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    textAlign: TextAlign.center,
                    style: font(14, color: Palette.muted),
                  ),
                  const SizedBox(height: 18),
                  for (final p in rows) _ResultRow(player: p, game: g),
                  const SizedBox(height: 18),
                  if (!matchOver)
                    FilledButton(
                      onPressed: c.nextRound,
                      child: const Text('Next round'),
                    )
                  else
                    FilledButton(
                      onPressed: c.restart,
                      child: const Text('Play again'),
                    ),
                  const SizedBox(height: 10),
                  OutlinedButton(
                    onPressed: widget.onMenu,
                    child: const Text('Menu'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ResultRow extends StatelessWidget {
  const _ResultRow({required this.player, required this.game});

  final Player player;
  final Game game;

  @override
  Widget build(BuildContext context) {
    final p = player;
    final rules = game.rules;
    final right = switch (rules.format) {
      MatchFormat.points => '${p.score} pts',
      MatchFormat.elimination => p.out ? 'Out' : '${p.score} won',
      MatchFormat.single => p.out ? 'Out' : '${p.hand.length} left',
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          _Avatar(player: p, size: 30),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              rules.teams
                  ? '${p.name} · ${p.team == 0 ? 'Your team' : 'Rivals'}'
                  : p.name,
              style: font(15, weight: p.isHuman ? 650 : 500),
            ),
          ),
          if (rules.format == MatchFormat.points)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Text(
                '${p.hand.length} left',
                style: font(13, color: Palette.muted),
              ),
            ),
          Text(right, style: font(15, weight: 650)),
        ],
      ),
    );
  }
}
