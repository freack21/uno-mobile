import 'dart:async';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'package:last_card_core/cards.dart';
import 'package:last_card_core/game.dart';
import 'package:last_card_core/modes.dart';
import 'package:last_card_core/rules.dart';

import 'game_controller.dart';
import 'guide_screen.dart';
import 'playing_card.dart';
import 'sfx.dart';
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

  // Positions cards fly between: seats, the deck, the discard pile and
  // every card in the player's hand.
  final _stackKey = GlobalKey();
  final _deckKey = GlobalKey();
  final _pileKey = GlobalKey();
  final _handKey = GlobalKey();
  late final _seatKeys = {
    for (var s = 1; s < widget.players; s++) s: GlobalKey(),
  };
  final _cardKeys = <int, GlobalKey>{};
  GlobalKey _cardKey(int id) => _cardKeys.putIfAbsent(id, GlobalKey.new);

  // Cards in the air, and played cards the discard pile hides until they land.
  final _flights = <_Flight>[];
  final _inFlight = <int>{};
  var _flightId = 0;
  Game? _watched;
  var _seenEvent = 0;
  var _seenDealt = 0;

  @override
  void initState() {
    super.initState();
    c.addListener(_onGameChanged);
    _onGameChanged();
  }

  @override
  void dispose() {
    c.removeListener(_onGameChanged);
    _hintTimer?.cancel();
    c.dispose();
    super.dispose();
  }

  /// Turns new game events into card flights. Runs right after the change,
  /// before the rebuild, so played cards are still laid out in the hand.
  void _onGameChanged() {
    if (!identical(_watched, g)) {
      _watched = g;
      _seenEvent = g.events.isEmpty ? 0 : g.events.last.id;
      _seenDealt = 0;
      _flights.clear();
      _inFlight.clear();
    }
    final added = <_Flight>[];
    // Cards drawn in the same step (a +2 hitting someone) leave the deck
    // only once the played card has landed.
    var landed = 0;
    for (final e in g.events) {
      if (e.id <= _seenEvent) continue;
      switch (e.type) {
        case EventType.play || EventType.jumpIn:
          final plays = _playFlights(e);
          added.addAll(plays);
          for (final f in plays) {
            landed = max(landed, f.delay + f.duration);
          }
        case EventType.draw ||
            EventType.penalty ||
            EventType.caught ||
            EventType.challenge:
          if (e.seat != null && (e.count ?? 0) > 0) {
            added.addAll(_drawFlights(e.seat!, e.count!, after: landed));
          }
        default:
          break;
      }
    }
    if (g.events.isNotEmpty) _seenEvent = g.events.last.id;

    if (c.intro == IntroStep.shuffle) _seenDealt = 0;
    if (c.intro == IntroStep.deal) {
      for (; _seenDealt < c.dealt; _seenDealt++) {
        added.addAll(_drawFlights(c.dealSeatAt(_seenDealt), 1, deal: true));
      }
    }
    _cardKeys.removeWhere((id, _) => !c.me.hand.any((card) => card.id == id));
    if (added.isNotEmpty && mounted) setState(() => _flights.addAll(added));
  }

  Rect? _rectOf(GlobalKey? key) {
    final box = key?.currentContext?.findRenderObject() as RenderBox?;
    final root = _stackKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || root == null || !box.hasSize || !root.hasSize) {
      return null;
    }
    if (!box.attached || !root.attached) return null;
    return box.localToGlobal(Offset.zero, ancestor: root) & box.size;
  }

  /// A card-sized rect centered in [area].
  Rect _cardIn(Rect area, double width) => Rect.fromCenter(
    center: area.center,
    width: width,
    height: width * cardAspect,
  );

  List<_Flight> _playFlights(GameEvent e) {
    final last = e.card;
    final seat = e.seat;
    final pile = _rectOf(_pileKey);
    if (last == null || seat == null || pile == null) return const [];
    // The combo (or single card) sits on top of the pile, in play order.
    final symbol = g.face(last);
    final cards = <GameCard>[];
    for (final card in g.discard.reversed) {
      if (cards.length == (e.count ?? 1)) break;
      if (g.face(card).sameSymbol(symbol)) cards.insert(0, card);
    }
    final to = _cardIn(pile, pile.width / 1.25);
    final avatar = _rectOf(_seatKeys[seat]);
    final flights = <_Flight>[];
    for (final (i, card) in cards.indexed) {
      final fromHand = seat == GameController.human
          ? _rectOf(_cardKeys[card.id])
          : null;
      final from = fromHand ?? (avatar != null ? _cardIn(avatar, 30) : null);
      if (from == null) continue;
      _inFlight.add(card.id);
      flights.add(
        _Flight(
          id: ++_flightId,
          from: from,
          to: to,
          face: g.face(card),
          wildColors: g.sideColors,
          reveal: fromHand == null,
          delay: i * 120,
          duration: 430,
          arc: fromHand == null ? 24 : 40,
          startAngle: fromHand == null ? -0.5 : 0,
          endAngle: _cardTilt(card),
          landing: card.id,
        ),
      );
    }
    return flights;
  }

  List<_Flight> _drawFlights(
    int seat,
    int count, {
    bool deal = false,
    int after = 0,
  }) {
    final deck = _rectOf(_deckKey);
    final target = seat == GameController.human
        ? _rectOf(_handKey)
        : _rectOf(_seatKeys[seat]);
    if (deck == null || target == null) return const [];
    final from = _cardIn(deck, deck.width - 6);
    final to = seat == GameController.human
        ? _cardIn(target, 62)
        : _cardIn(target, 22);
    return [
      for (var i = 0; i < min(count, 6); i++)
        _Flight(
          id: ++_flightId,
          from: from,
          to: to,
          delay: after + i * 80,
          duration: deal ? 380 : 400,
          arc: 46,
          startAngle: 0,
          endAngle: deal ? pi * 0.9 : 0.25,
        ),
    ];
  }

  void _land(_Flight f) {
    if (!mounted) return;
    setState(() {
      _flights.remove(f);
      if (f.landing != null) _inFlight.remove(f.landing);
    });
  }

  Game get g => c.game;

  void _flash(String text) {
    _hintTimer?.cancel();
    setState(() => _hint = text);
    _hintTimer = Timer(const Duration(milliseconds: 1600), () {
      if (mounted) setState(() => _hint = null);
    });
  }

  /// Doubles: cards picked for a combo, in play order (first = lead card).
  List<GameCard> _combo = [];

  bool get _comboValid {
    if (_combo.isEmpty || !c.isMyTurn || c.inIntro) return false;
    final lead = _combo.first;
    final hand = c.me.hand.map((x) => x.id).toSet();
    return _combo.every((x) => hand.contains(x.id)) &&
        g.isPlayable(GameController.human, lead) &&
        g.canCombo(GameController.human, lead, _combo.sublist(1));
  }

  Future<void> _onCardTap(GameCard card) async {
    if (_busy || c.showResults || c.inIntro) return;
    if (_comboValid) {
      final i = _combo.indexWhere((x) => x.id == card.id);
      HapticFeedback.selectionClick();
      playSfx(Sfx.tick);
      if (i == 0) {
        setState(() => _combo = []);
      } else if (i > 0) {
        setState(() => _combo.removeAt(i));
      } else if (g
          .comboPartners(GameController.human, _combo.first)
          .any((x) => x.id == card.id)) {
        setState(() => _combo.add(card));
      } else {
        _flash('Only ${g.face(_combo.first).symbol} cards join this combo');
      }
      return;
    }
    final jump = !c.isMyTurn && g.canJumpIn(GameController.human, card);
    if (!jump && !g.isPlayable(GameController.human, card)) {
      HapticFeedback.selectionClick();
      playSfx(Sfx.nope);
      _flash(c.isMyTurn ? _whyNot(card) : 'Wait for your turn');
      return;
    }
    if (!jump && g.comboPartners(GameController.human, card).isNotEmpty) {
      HapticFeedback.selectionClick();
      playSfx(Sfx.tick);
      setState(() => _combo = [card]);
      return;
    }
    await _commit(card, const []);
  }

  Future<void> _playCombo() async {
    if (!_comboValid) return;
    final cards = List.of(_combo);
    setState(() => _combo = []);
    await _commit(cards.first, cards.sublist(1));
  }

  Future<void> _commit(GameCard card, List<GameCard> extra) async {
    final last = extra.isEmpty ? card : extra.last;
    CardColor? color;
    int? swapWith;
    _busy = true;
    try {
      if (g.needsColor(last)) {
        final flipping = g.face(last).kind == CardKind.flip;
        color = await _pickColor(
          flipping
              ? (g.side.other == Side.light ? CardColor.light : CardColor.dark)
              : g.sideColors,
          flipping ? g.side.other : g.side,
        );
        if (color == null) return;
      }
      if (g.needsSwapTarget(GameController.human, card, extra: extra.length)) {
        swapWith = await _pickSwap();
        if (swapWith == null) return;
      }
    } finally {
      _busy = false;
    }
    HapticFeedback.lightImpact();
    final err = c.play(card, color: color, swapWith: swapWith, extra: extra);
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
              const SizedBox(height: 8),
              ValueListenableBuilder<bool>(
                valueListenable: soundOn,
                builder: (context, on, _) => SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('Sound effects', style: font(16, weight: 600)),
                  secondary: Icon(
                    on ? Icons.volume_up_rounded : Icons.volume_off_rounded,
                  ),
                  value: on,
                  onChanged: setSoundOn,
                ),
              ),
              const SizedBox(height: 8),
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
                  key: _stackKey,
                  children: [
                    Column(
                      children: [
                        _TopBar(
                          title: widget.mode.name,
                          subtitle: _subtitle(),
                          onMenu: _openMenu,
                          onGuide: _openGuide,
                        ),
                        _Opponents(controller: c, seatKeys: _seatKeys),
                        Expanded(
                          child: _Table(
                            controller: c,
                            onDraw: _onDraw,
                            deckKey: _deckKey,
                            pileKey: _pileKey,
                            inFlight: _inFlight,
                          ),
                        ),
                        _StatusBar(
                          controller: c,
                          hint: _hint,
                          combo: _comboValid ? _combo : const [],
                          onPlayCombo: _playCombo,
                          onCancelCombo: () => setState(() => _combo = []),
                        ),
                        KeyedSubtree(
                          key: _handKey,
                          child: _Hand(
                            controller: c,
                            onTap: _onCardTap,
                            combo: _comboValid ? _combo : const [],
                            cardKey: _cardKey,
                          ),
                        ),
                      ],
                    ),
                    if (c.inIntro) ...[
                      // Tap anywhere to skip the opening.
                      Positioned.fill(
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: c.skipIntro,
                        ),
                      ),
                      if (c.intro == IntroStep.order)
                        Positioned.fill(child: _TurnOrderPanel(controller: c)),
                    ],
                    Positioned.fill(
                      child: IgnorePointer(
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            for (final f in _flights)
                              _FlightView(
                                key: ValueKey(f.id),
                                flight: f,
                                onDone: () => _land(f),
                              ),
                          ],
                        ),
                      ),
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
  const _Opponents({required this.controller, required this.seatKeys});

  final GameController controller;
  final Map<int, GlobalKey> seatKeys;

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
                avatarKey: seatKeys[p.seat],
                count: controller.visibleCards(p.seat),
                intro: controller.intro,
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
    required this.avatarKey,
    required this.count,
    required this.intro,
    required this.thinking,
    required this.onCatch,
  });

  final Player player;
  final Game game;
  final GlobalKey? avatarKey;

  /// Cards visible on the table (grows during the deal).
  final int count;
  final IntroStep? intro;
  final bool thinking;
  final VoidCallback onCatch;

  @override
  Widget build(BuildContext context) {
    final p = player;
    final active =
        intro == null && game.current == p.seat && !game.isRoundOver && !p.out;
    final dealer =
        (intro == IntroStep.shuffle || intro == IntroStep.deal) &&
        game.dealer == p.seat;
    final partner = game.isTeammate(0, p.seat);
    final canCatch = game.vulnerable == p.seat;
    final flip = game.rules.deck == DeckType.flipside;
    final shown = min(count, 6);

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
                child: _Avatar(key: avatarKey, player: p, size: 44),
              ),
              Positioned(
                right: -6,
                bottom: -2,
                child: _CountBadge(
                  count: count,
                  hot: intro == null && count <= 2 && !p.out,
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
              child: dealer
                  ? const _Chip(label: 'DEALER', color: Color(0xFF7A4AD0))
                  : canCatch
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
  const _Avatar({super.key, required this.player, required this.size});

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
  const _Table({
    required this.controller,
    required this.onDraw,
    required this.deckKey,
    required this.pileKey,
    required this.inFlight,
  });

  final GameController controller;
  final VoidCallback onDraw;
  final GlobalKey deckKey;
  final GlobalKey pileKey;

  /// Played cards still flying towards the pile.
  final Set<int> inFlight;

  @override
  Widget build(BuildContext context) {
    final g = controller.game;
    final canDraw =
        !controller.inIntro && controller.isMyTurn && g.phase == Phase.play;
    final intro = controller.intro;
    final cardsOut = intro != IntroStep.shuffle && intro != IntroStep.deal;
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
                  deckKey: deckKey,
                  intro: intro,
                ),
                SizedBox(width: cardW * 0.42),
                if (!cardsOut)
                  _EmptySlot(width: cardW)
                else if (intro == IntroStep.flip)
                  _FlipIn(
                    child: _DiscardPile(
                      game: g,
                      width: cardW,
                      pileKey: pileKey,
                      hidden: inFlight,
                    ),
                  )
                else
                  _DiscardPile(
                    game: g,
                    width: cardW,
                    pileKey: pileKey,
                    hidden: inFlight,
                  ),
              ],
            ),
            if (cardsOut)
              Positioned(bottom: 6, child: _ColorPill(color: g.activeColor)),
            Align(
              alignment: const Alignment(0, -0.88),
              child: TableBannerView(banner: controller.banner),
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
    required this.deckKey,
    required this.intro,
  });

  final Game game;
  final double width;
  final bool enabled;
  final VoidCallback onTap;
  final GlobalKey deckKey;
  final IntroStep? intro;

  @override
  Widget build(BuildContext context) {
    final flip = game.rules.deck == DeckType.flipside;
    final top = game.drawPile.isEmpty ? null : game.drawPile.last;
    final pending = game.pendingDraw;
    final label = intro == IntroStep.shuffle
        ? 'Shuffling'
        : intro == IntroStep.deal
        ? 'Dealing'
        : !enabled
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
              key: deckKey,
              width: width + 6,
              height: width * cardAspect + 6,
              child: intro == IntroStep.shuffle
                  ? _ShuffleDeck(width: width)
                  : Stack(
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

/// Resting angle of a card on the discard pile (stable per card).
double _cardTilt(GameCard c) => ((c.id * 7919) % 17 - 8) * 0.018;

class _DiscardPile extends StatelessWidget {
  const _DiscardPile({
    required this.game,
    required this.width,
    required this.pileKey,
    required this.hidden,
  });

  final Game game;
  final double width;
  final GlobalKey pileKey;

  /// Cards still flying in; shown once they land.
  final Set<int> hidden;

  @override
  Widget build(BuildContext context) {
    final pile = game.discard.where((c) => !hidden.contains(c.id)).toList();
    final shown = pile.sublist(max(0, pile.length - 3));
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          key: pileKey,
          width: width * 1.25,
          height: width * cardAspect + 6,
          child: Stack(
            alignment: Alignment.center,
            children: [
              for (final c in shown)
                Transform.rotate(
                  key: ValueKey('${c.id}-${game.side.name}'),
                  angle: _cardTilt(c),
                  child: PlayingCard(
                    width: width,
                    face: game.face(c),
                    wildColors: game.sideColors,
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
class TableBannerView extends StatefulWidget {
  const TableBannerView({super.key, required this.banner});

  final TableBanner? banner;

  @override
  State<TableBannerView> createState() => _TableBannerViewState();
}

class _TableBannerViewState extends State<TableBannerView> {
  TableBanner? _shown;
  Timer? _timer;

  /// Last banner already announced. The controller keeps its latest banner
  /// until a new one arrives, so every later rebuild passes the same one.
  int? _lastId;

  @override
  void initState() {
    super.initState();
    _lastId = widget.banner?.id;
  }

  @override
  void didUpdateWidget(TableBannerView old) {
    super.didUpdateWidget(old);
    final b = widget.banner;
    if (b != null && b.id != _lastId) {
      _lastId = b.id;
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
  const _StatusBar({
    required this.controller,
    required this.hint,
    required this.combo,
    required this.onPlayCombo,
    required this.onCancelCombo,
  });

  final List<GameCard> combo;
  final VoidCallback onPlayCombo;
  final VoidCallback onCancelCombo;

  final GameController controller;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final g = c.game;
    final me = c.me;
    final myTurn = c.isMyTurn;
    final canLast = !c.inIntro && g.canCallLast(GameController.human);
    final urgentLast =
        canLast &&
        (g.vulnerable == GameController.human ||
            (myTurn && me.hand.length == 2 && g.playableCards(0).isNotEmpty));

    final text =
        hint ??
        (combo.isEmpty
            ? _status(c)
            : combo.length == 1
            ? 'Tap more ${g.face(combo.first).symbol}s to add'
            : 'Last card sets the color');
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
                if (combo.isNotEmpty) ...[
                  IconButton(
                    tooltip: 'Cancel combo',
                    onPressed: onCancelCombo,
                    icon: const Icon(Icons.close_rounded),
                    color: Palette.muted,
                  ),
                  _ActionButton(
                    label: 'Play ${combo.length}',
                    color: Palette.brand,
                    onTap: onPlayCombo,
                  ),
                  const SizedBox(width: 8),
                ],
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
    final dealer = g.players[g.dealer];
    final dealerName = dealer.isHuman ? 'You' : dealer.name;
    switch (c.intro) {
      case IntroStep.shuffle:
        return '$dealerName ${dealer.isHuman ? 'shuffle' : 'shuffles'} the deck… · tap to skip';
      case IntroStep.deal:
        return '$dealerName ${dealer.isHuman ? 'deal' : 'deals'} ${g.rules.handSize} cards each… · tap to skip';
      case IntroStep.flip:
        return 'First card: ${g.topFace.label}';
      case IntroStep.order:
        return 'Get ready…';
      case null:
        break;
    }
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
  const _Hand({
    required this.controller,
    required this.onTap,
    required this.combo,
    required this.cardKey,
  });

  /// Key per card so a played card's position is known when it flies off.
  final GlobalKey Function(int id) cardKey;

  /// Cards picked for a Doubles combo, in play order.
  final List<GameCard> combo;

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
    // While dealing, cards arrive one by one in deal order; once play starts
    // they slide into sorted order.
    final hand = c.inIntro
        ? c.me.hand.take(c.visibleCards(GameController.human)).toList()
        : (List.of(c.me.hand)
            ..sort((a, b) => _order(g, a).compareTo(_order(g, b))));
    final myTurn = c.isMyTurn && !c.inIntro;
    final jumps = c.inIntro
        ? const <int>{}
        : g.jumpInCards(GameController.human).map((c) => c.id).toSet();
    final flip = g.rules.deck == DeckType.flipside;
    final partners = combo.isEmpty
        ? const <int>{}
        : g
              .comboPartners(GameController.human, combo.first)
              .map((c) => c.id)
              .toSet();

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
                  look: _look(g, hand[i], myTurn, jumps, partners),
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

  _CardLook _look(
    Game g,
    GameCard card,
    bool myTurn,
    Set<int> jumps,
    Set<int> partners,
  ) {
    const gold = Color(0xFFF4B620);
    if (combo.isNotEmpty) {
      final order = combo.indexWhere((c) => c.id == card.id);
      if (order >= 0) {
        return _CardLook(
          up: true,
          glow: Palette.brand,
          badge: '${order + 1}',
          badgeColor: Palette.brand,
        );
      }
      if (partners.contains(card.id)) {
        return const _CardLook(
          up: true,
          glow: gold,
          badge: '+',
          badgeColor: Color(0xFFE09A00),
        );
      }
      return const _CardLook(dim: true);
    }
    if (jumps.contains(card.id)) {
      return const _CardLook(
        up: true,
        glow: gold,
        badge: 'JUMP',
        badgeColor: Color(0xFFE09A00),
      );
    }
    if (!myTurn) return const _CardLook();
    if (!g.isPlayable(GameController.human, card)) {
      return const _CardLook(dim: true);
    }
    final extra = g.comboPartners(GameController.human, card).length;
    return _CardLook(
      up: true,
      glow: Colors.white.withValues(alpha: 0.35),
      badge: extra > 0 ? '×${extra + 1}' : null,
      badgeColor: Palette.surfaceHigh,
    );
  }

  Widget _handCard(
    Game g,
    GameCard card, {
    required double left,
    required double width,
    required double lift,
    required _CardLook look,
    required bool flip,
  }) {
    return AnimatedPositioned(
      key: ValueKey(card.id),
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      left: left,
      top: look.up ? 0 : lift,
      child: GestureDetector(
        onTap: () => onTap(card),
        child: Column(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                PlayingCard(
                  key: cardKey(card.id),
                  width: width,
                  face: g.face(card),
                  dimmed: look.dim,
                  wildColors: g.sideColors,
                  glow: look.glow,
                ),
                if (look.badge != null)
                  Positioned(
                    top: -8,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: _Chip(label: look.badge!, color: look.badgeColor),
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

// -------------------------------------------------------------- round intro

/// Empty discard spot shown until the first card is turned over.
class _EmptySlot extends StatelessWidget {
  const _EmptySlot({required this.width});

  final double width;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: width * 1.25,
          height: width * cardAspect + 6,
          child: Center(
            child: Container(
              width: width,
              height: width * cardAspect,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(width * 0.13),
                border: Border.all(
                  color: Palette.text.withValues(alpha: 0.18),
                  width: 2,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 26),
      ],
    );
  }
}

/// Turns its child over like a card being flipped face up.
class _FlipIn extends StatelessWidget {
  const _FlipIn({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 520),
      curve: Curves.easeOutBack,
      builder: (context, v, child) => Transform(
        alignment: Alignment.center,
        transform: Matrix4.identity()
          ..setEntry(3, 2, 0.0015)
          ..rotateY((1 - v.clamp(0.0, 1.0)) * pi / 2),
        child: child,
      ),
      child: child,
    );
  }
}

/// The deck riffled in two halves.
class _ShuffleDeck extends StatefulWidget {
  const _ShuffleDeck({required this.width});

  final double width;

  @override
  State<_ShuffleDeck> createState() => _ShuffleDeckState();
}

class _ShuffleDeckState extends State<_ShuffleDeck>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 650),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final w = widget.width;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = _c.value;
        final spread = sin(t * pi) * w * 0.48;
        final tilt = sin(t * pi) * 0.14;
        Widget half(double dir, int i) => Positioned(
          left: 3 - i * 1.5,
          top: 3 - i * 1.5,
          child: Transform.translate(
            offset: Offset(dir * spread, -sin(t * pi) * 6),
            child: Transform.rotate(
              angle: dir * tilt,
              child: PlayingCard(width: w),
            ),
          ),
        );
        // The right half drops on top in the second half of each riffle.
        final left = [for (var i = 0; i < 3; i++) half(-1, i)];
        final right = [for (var i = 0; i < 3; i++) half(1, i)];
        return Stack(
          clipBehavior: Clip.none,
          children: t < 0.5 ? [...right, ...left] : [...left, ...right],
        );
      },
    );
  }
}

/// One card moving across the table.
class _Flight {
  _Flight({
    required this.id,
    required this.from,
    required this.to,
    required this.delay,
    required this.duration,
    required this.arc,
    required this.startAngle,
    required this.endAngle,
    this.face,
    this.wildColors = CardColor.light,
    this.reveal = false,
    this.landing,
  });

  final int id;
  final Rect from;
  final Rect to;
  final int delay;
  final int duration;

  /// How high the card lifts mid-flight, in logical pixels.
  final double arc;
  final double startAngle;
  final double endAngle;

  /// Face shown (null: card back).
  final CardFace? face;
  final List<CardColor> wildColors;

  /// Starts face down and turns face up halfway (cards played by bots).
  final bool reveal;

  /// Discard card revealed on the pile when this flight lands.
  final int? landing;
}

class _FlightView extends StatelessWidget {
  const _FlightView({super.key, required this.flight, required this.onDone});

  final _Flight flight;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final f = flight;
    final total = f.delay + f.duration;
    final start = f.delay / total;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: total),
      onEnd: onDone,
      builder: (context, raw, _) {
        if (raw < start) return const SizedBox.shrink();
        final t = Curves.easeOutCubic.transform(
          ((raw - start) / (1 - start)).clamp(0.0, 1.0),
        );
        final rect = Rect.lerp(f.from, f.to, t)!;
        final lift = f.arc * sin(t * pi);
        final angle = f.startAngle + (f.endAngle - f.startAngle) * t;
        // Turning over: squash to the edge, then open on the face side.
        final showFace = f.face != null && (!f.reveal || t >= 0.5);
        final squash = f.reveal ? max(0.06, (cos(t * pi)).abs()) : 1.0;
        return Positioned(
          left: rect.left,
          top: rect.top - lift,
          child: Transform.rotate(
            angle: angle,
            child: Transform(
              alignment: Alignment.center,
              transform: Matrix4.diagonal3Values(squash, 1, 1),
              child: PlayingCard(
                width: rect.width,
                face: showFace ? f.face : null,
                wildColors: f.wildColors,
              ),
            ),
          ),
        );
      },
    );
  }
}

/// "Kira starts": who opens the round and the order around the table.
class _TurnOrderPanel extends StatelessWidget {
  const _TurnOrderPanel({required this.controller});

  final GameController controller;

  @override
  Widget build(BuildContext context) {
    final g = controller.game;
    final order = controller.turnOrder;
    final first = g.players[order.first];
    return IgnorePointer(
      child: ColoredBox(
        color: Colors.black.withValues(alpha: 0.45),
        child: Center(
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 380),
            curve: Curves.easeOutBack,
            builder: (context, v, child) => Opacity(
              opacity: v.clamp(0.0, 1.0),
              child: Transform.scale(scale: 0.85 + 0.15 * v, child: child),
            ),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 20),
              padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
              constraints: const BoxConstraints(maxWidth: 420),
              decoration: BoxDecoration(
                color: Palette.surface,
                borderRadius: BorderRadius.circular(26),
                border: Border.all(color: Palette.line),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.4),
                    blurRadius: 24,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    first.isHuman ? 'You start!' : '${first.name} starts',
                    style: font(26, weight: 700),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${g.players[g.dealer].isHuman ? 'You' : g.players[g.dealer].name} dealt · '
                    'first card ${g.topFace.label}',
                    textAlign: TextAlign.center,
                    style: font(13.5, color: Palette.muted),
                  ),
                  const SizedBox(height: 18),
                  Wrap(
                    alignment: WrapAlignment.center,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    runSpacing: 10,
                    children: [
                      for (var i = 0; i < order.length; i++) ...[
                        if (i > 0)
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 4),
                            child: Icon(
                              Icons.chevron_right_rounded,
                              color: Palette.muted,
                              size: 20,
                            ),
                          ),
                        _OrderSeat(player: g.players[order[i]], first: i == 0),
                      ],
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    g.direction == 1
                        ? 'Play goes clockwise'
                        : 'Play goes counter-clockwise',
                    style: font(13, weight: 550, color: Palette.muted),
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

class _OrderSeat extends StatelessWidget {
  const _OrderSeat({required this.player, required this.first});

  final Player player;
  final bool first;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(2.5),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: first ? Palette.text : Colors.transparent,
              width: 2.5,
            ),
          ),
          child: _Avatar(player: player, size: 36),
        ),
        const SizedBox(height: 4),
        Text(
          player.name,
          style: font(
            12,
            weight: first ? 650 : 500,
            color: first ? Palette.text : Palette.muted,
          ),
        ),
      ],
    );
  }
}

/// How a card in the hand is drawn: lifted, dimmed, glowing, badged.
class _CardLook {
  const _CardLook({
    this.up = false,
    this.dim = false,
    this.glow,
    this.badge,
    this.badgeColor = Palette.surfaceHigh,
  });

  final bool up;
  final bool dim;
  final Color? glow;
  final String? badge;
  final Color badgeColor;
}
