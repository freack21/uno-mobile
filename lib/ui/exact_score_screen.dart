import 'dart:async';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../game/cards.dart';
import '../game/exact_score.dart';
import '../game/modes.dart';
import '../game/rules.dart';
import 'game_controller.dart' show TableBanner, botNames;
import 'game_screen.dart' show TableBannerView;
import 'guide_screen.dart';
import 'party_widgets.dart';
import 'playing_card.dart';
import 'sfx.dart';
import 'theme.dart';

class ExactScoreScreen extends StatefulWidget {
  const ExactScoreScreen({
    super.key,
    required this.mode,
    required this.players,
    required this.difficulty,
    this.target,
  });

  final GameMode mode;
  final int players;
  final Difficulty difficulty;

  /// Fixed target, or null for a random one from 20 to 50.
  final int? target;

  @override
  State<ExactScoreScreen> createState() => _ExactScoreScreenState();
}

class _ExactScoreScreenState extends State<ExactScoreScreen> {
  static const me = 0;
  final _rng = Random();
  late ExactScoreGame g;
  final _timers = <Timer>[];
  bool _paused = false;
  TableBanner? _banner;
  int _bannerId = 0;

  /// Last card played or discarded, shown on the table.
  GameCard? _last;

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
    final target = widget.target ?? 20 + _rng.nextInt(7) * 5;
    g = ExactScoreGame(
      players: [
        ScorePlayer(me, 'You', isHuman: true),
        for (var i = 1; i < widget.players; i++)
          ScorePlayer(i, botNames[i - 1]),
      ],
      target: target,
      rng: _rng,
    );
    _banner = null;
    _last = null;
    playSfx(Sfx.shuffle);
    _after(900, _nextTurn);
  }

  void _nextTurn() {
    if (g.phase == ScorePhase.over) return;
    setState(() {});
    if (g.current == me) {
      playSfx(Sfx.turn);
      return;
    }
    final seat = g.current;
    _after(_think(900), () {
      g.draw(seat);
      playSfx(Sfx.draw);
      setState(() {});
      _after(_think(1000), () {
        final move = decideExactScore(g, seat, widget.difficulty, _rng);
        if (move.use) {
          _use(seat, value: move.value, victim: move.victim);
        } else {
          _discard(seat);
        }
      });
    });
  }

  int _think(int base) {
    final pace = switch (widget.difficulty) {
      Difficulty.easy => 1.2,
      Difficulty.normal => 1.0,
      Difficulty.hard => 0.85,
    };
    return ((base + _rng.nextInt(600)) * pace).round();
  }

  void _draw() {
    if (g.current != me || g.phase != ScorePhase.draw) return;
    HapticFeedback.lightImpact();
    g.draw(me);
    playSfx(Sfx.draw);
    setState(() {});
  }

  void _use(int seat, {int? value, int? victim}) {
    final f = g.drawnFace!;
    final card = g.drawn!;
    final name = g.players[seat].name;
    g.use(seat, value: value, victim: victim);
    _last = card;
    switch (f.kind) {
      case CardKind.skip:
        playSfx(Sfx.skip);
      case CardKind.reverse:
        playSfx(Sfx.reverse);
        if (g.players.length > 2) _say('REVERSE', 'Play changes direction');
      case CardKind.draw:
        playSfx(Sfx.penalty);
        final v = g.players[victim!];
        _say('−2', '$name hit ${v.isHuman ? 'you' : v.name}');
      case CardKind.wild || CardKind.wildDraw:
        playSfx(Sfx.wild);
        _say('+$value', '$name used a Wild');
      default:
        playSfx(Sfx.card);
    }
    _afterMove();
  }

  void _discard(int seat) {
    final card = g.drawn!;
    final p = g.players[seat];
    final penalty = g.discard(seat);
    _last = card;
    playSfx(Sfx.tick);
    if (penalty) {
      playSfx(Sfx.nope);
      _say(
        '3 DISCARDS',
        '${p.name} ${p.isHuman ? 'lose' : 'loses'} the next turn',
        color: Palette.brand,
      );
    }
    _afterMove();
  }

  void _afterMove() {
    if (g.phase == ScorePhase.over) {
      playSfx(g.winner == me ? Sfx.win : Sfx.lose);
      setState(() {});
      return;
    }
    final skipped = g.lastSkipped;
    if (skipped.isNotEmpty) {
      final names = skipped.map((s) => g.players[s].name).join(' & ');
      _say(
        'SKIP',
        '$names ${skipped.length == 1 && skipped.first != me ? 'loses' : 'lose'} a turn',
      );
    }
    setState(() {});
    _after(skipped.isEmpty ? 500 : 1100, _nextTurn);
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
    if (g.phase == ScorePhase.over || g.current == me) return;
    // A bot holding a drawn card decides now; otherwise its turn restarts.
    if (g.phase == ScorePhase.decide) {
      final seat = g.current;
      _after(600, () {
        final move = decideExactScore(g, seat, widget.difficulty, _rng);
        move.use
            ? _use(seat, value: move.value, victim: move.victim)
            : _discard(seat);
      });
    } else {
      _nextTurn();
    }
  }

  // ------------------------------------------------------------------- UI

  @override
  Widget build(BuildContext context) {
    final myTurn = g.current == me && g.phase != ScorePhase.over;
    return PartyScaffold(
      mode: widget.mode,
      subtitle: 'Target ${g.target} · ${widget.difficulty.label}',
      accent: myTurn ? const Color(0xFF2475D6) : const Color(0xFF7A4AD0),
      onMenu: _menu,
      child: Stack(
        children: [
          Column(
            children: [
              _opponents(),
              Expanded(child: _table()),
              _panel(),
              _track(),
            ],
          ),
          if (g.phase == ScorePhase.over) Positioned.fill(child: _results()),
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

  Widget _seat(ScorePlayer p) {
    final active = g.current == p.seat && g.phase != ScorePhase.over;
    return Column(
      children: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            SeatAvatar(seat: p.seat, name: p.name, active: active),
            if (active && g.phase == ScorePhase.draw)
              const Positioned(right: -16, top: -4, child: ThinkingDots()),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          p.name,
          style: font(
            13,
            weight: 600,
            color: active ? Palette.text : Palette.muted,
          ),
        ),
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: TweenAnimationBuilder<double>(
              tween: Tween(end: p.score / g.target),
              duration: const Duration(milliseconds: 500),
              builder: (context, v, _) => LinearProgressIndicator(
                value: v,
                minHeight: 6,
                backgroundColor: Palette.surfaceHigh,
                color: partySeatColors[p.seat % partySeatColors.length],
              ),
            ),
          ),
        ),
        const SizedBox(height: 3),
        Text(
          '${p.score}/${g.target}',
          style: font(12, weight: 650, color: Palette.text),
        ),
        _Dots(count: p.discards),
      ],
    );
  }

  Widget _table() {
    final drawn = g.drawn;
    final canDraw = g.current == me && g.phase == ScorePhase.draw;
    return Stack(
      alignment: Alignment.center,
      children: [
        Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              decoration: BoxDecoration(
                color: Palette.surface.withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Palette.line),
              ),
              child: Text(
                'TARGET ${g.target}',
                style: font(16, weight: 700).copyWith(letterSpacing: 1),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                GestureDetector(
                  onTap: _draw,
                  child: Column(
                    children: [
                      PlayingCard(
                        width: 80,
                        glow: canDraw
                            ? Colors.white.withValues(alpha: 0.55)
                            : null,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        canDraw ? 'Draw' : '${g.drawPile.length} left',
                        style: font(
                          14,
                          weight: 650,
                          color: canDraw ? Palette.text : Palette.muted,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 34),
                Column(
                  children: [
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      transitionBuilder: (child, anim) => ScaleTransition(
                        scale: Tween(begin: 0.7, end: 1.0).animate(
                          CurvedAnimation(
                            parent: anim,
                            curve: Curves.easeOutBack,
                          ),
                        ),
                        child: FadeTransition(opacity: anim, child: child),
                      ),
                      child: drawn != null
                          ? PlayingCard(
                              key: ValueKey('drawn-${drawn.id}'),
                              width: 80,
                              face: drawn.light,
                              glow: const Color(0xFFF4B620),
                            )
                          : _last != null
                          ? Opacity(
                              key: ValueKey('last-${_last!.id}'),
                              opacity: 0.55,
                              child: PlayingCard(width: 80, face: _last!.light),
                            )
                          : SizedBox(
                              key: const ValueKey('empty'),
                              width: 80,
                              height: 80 * cardAspect,
                            ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      drawn != null
                          ? (g.current == me
                                ? 'Your card'
                                : '${g.players[g.current].name} drew')
                          : 'Last card',
                      style: font(14, weight: 650, color: Palette.muted),
                    ),
                  ],
                ),
              ],
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

  /// The decision for the human's drawn card.
  Widget _panel() {
    final myDecision = g.current == me && g.phase == ScorePhase.decide;
    final String text;
    final actions = <Widget>[];
    if (g.phase == ScorePhase.over) {
      text = '';
    } else if (g.current != me) {
      text = "${g.players[g.current].name}'s turn…";
    } else if (!myDecision) {
      text = 'Your turn — draw a card';
    } else {
      final f = g.drawnFace!;
      final need = g.remaining(me);
      final usable = g.canUse(me);
      switch (f.kind) {
        case CardKind.number:
          text = usable
              ? 'Use +${f.value}? You need $need.'
              : 'Too high — you need $need.';
          if (usable) {
            actions.add(_action('Use +${f.value}', () => _use(me)));
          }
        case CardKind.wild || CardKind.wildDraw:
          text = 'Wild: add any value up to ${min(9, need)}';
          for (final v in g.wildValues(me)) {
            actions.add(_chip('+$v', () => _use(me, value: v)));
          }
        case CardKind.draw:
          if (usable) {
            text = 'Take 2 points from…';
            for (final s in g.victims(me)) {
              actions.add(_chip(g.players[s].name, () => _use(me, victim: s)));
            }
          } else {
            text = 'Nobody has points to take yet.';
          }
        case CardKind.skip:
          text = 'Skip the next player?';
          actions.add(_action('Use Skip', () => _use(me)));
        default:
          text = g.players.length == 2
              ? 'Reverse works like Skip with two players.'
              : 'Reverse the direction?';
          actions.add(_action('Use Reverse', () => _use(me)));
      }
      final left = ExactScoreGame.maxDiscards - g.players[me].discards;
      actions.add(
        _action(
          left == 1 ? 'Discard (lose a turn)' : 'Discard',
          () => _discard(me),
          primary: false,
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            text,
            style: font(
              15,
              weight: 600,
              color: g.current == me ? Palette.text : Palette.muted,
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final a in actions)
                  Padding(padding: const EdgeInsets.only(right: 8), child: a),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _action(String label, VoidCallback onTap, {bool primary = true}) {
    return FilledButton(
      onPressed: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      style: FilledButton.styleFrom(
        backgroundColor: primary ? Palette.brand : Palette.surfaceHigh,
        minimumSize: const Size(0, 46),
        padding: const EdgeInsets.symmetric(horizontal: 18),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      child: Text(label, style: font(15, weight: 650, color: Colors.white)),
    );
  }

  Widget _chip(String label, VoidCallback onTap) {
    return FilledButton(
      onPressed: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      style: FilledButton.styleFrom(
        backgroundColor: const Color(0xFF2475D6),
        minimumSize: const Size(52, 46),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      child: Text(label, style: font(16, weight: 700, color: Colors.white)),
    );
  }

  /// Your track: one line per point, crossed off as you score.
  Widget _track() {
    final p = g.players[me];
    final perRow = 10;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: Palette.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: g.current == me ? const Color(0xFF2475D6) : Palette.line,
          width: 1.5,
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Flexible(
                child: Text(
                  'Your track',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: font(15, weight: 650),
                ),
              ),
              const SizedBox(width: 8),
              _Dots(count: p.discards),
              const Spacer(),
              Text('${p.score} / ${g.target}', style: font(15, weight: 700)),
              const SizedBox(width: 8),
              Text(
                'need ${g.remaining(me)}',
                style: font(13, color: Palette.muted),
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (var row = 0; row * perRow < g.target; row++)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  for (var i = row * perRow; i < (row + 1) * perRow; i++)
                    Expanded(
                      child: i < g.target
                          ? _Tick(filled: i < p.score)
                          : const SizedBox(),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _results() {
    final w = g.winner!;
    final won = w == me;
    final rows = List.of(g.players)..sort((a, b) => b.score.compareTo(a.score));
    return PartyResults(
      title: won ? 'You win!' : '${g.players[w].name} wins',
      subtitle: 'First to exactly ${g.target}',
      won: won,
      rows: [
        for (final p in rows)
          ResultRow(
            p.seat,
            p.name,
            '${p.score}/${g.target}',
            winner: p.seat == w,
          ),
      ],
      onAgain: () => setState(_newGame),
      onMenu: () => Navigator.pop(context),
    );
  }
}

/// One point on the track: a line that gets crossed off.
class _Tick extends StatelessWidget {
  const _Tick({required this.filled});

  final bool filled;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      height: 16,
      margin: const EdgeInsets.symmetric(horizontal: 2),
      decoration: BoxDecoration(
        color: filled ? Palette.brand : Palette.surfaceHigh,
        borderRadius: BorderRadius.circular(4),
      ),
      child: filled
          ? const Icon(Icons.close_rounded, size: 13, color: Colors.white)
          : null,
    );
  }
}

/// Discards in a row, out of three.
class _Dots extends StatelessWidget {
  const _Dots({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < ExactScoreGame.maxDiscards; i++)
          Container(
            width: 6,
            height: 6,
            margin: const EdgeInsets.symmetric(horizontal: 1.5, vertical: 3),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: i < count ? Palette.brand : Palette.surfaceHigh,
            ),
          ),
      ],
    );
  }
}
