import 'dart:async';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'package:last_card_core/cards.dart';
import 'package:last_card_core/exact_score.dart';
import 'package:last_card_core/modes.dart';
import 'package:last_card_core/rules.dart';

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

/// How far the drawn card's reveal has got.
enum _Stage { tease, reveal, choose, bust }

class _ExactScoreScreenState extends State<ExactScoreScreen> {
  static const me = 0;
  static const tickMs = 110;
  final _rng = Random();
  late ExactScoreGame g;
  final _timers = <Timer>[];
  bool _paused = false;
  TableBanner? _banner;
  int _bannerId = 0;

  /// Reveal stage of the drawn card; null between draws.
  _Stage? _stage;

  /// Bumped per draw so card and track animations replay.
  int _turnId = 0;

  /// Points before the last scoring move, per seat: those ticks animate in.
  final _fillFrom = <int, int>{};

  /// Last card resolved, shown faded on the table.
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
    _stage = null;
    _fillFrom.clear();
    playSfx(Sfx.shuffle);
    _after(1100, _nextTurn);
  }

  int _pace(int ms) {
    final f = switch (widget.difficulty) {
      Difficulty.easy => 1.15,
      Difficulty.normal => 1.0,
      Difficulty.hard => 0.9,
    };
    return (ms * f).round();
  }

  void _nextTurn() {
    if (g.phase == ScorePhase.over) return;
    setState(() {});
    if (g.current == me) {
      playSfx(Sfx.turn);
      return;
    }
    final seat = g.current;
    _after(_pace(1000 + _rng.nextInt(700)), () => _draw(seat));
  }

  /// Draws for [seat] and plays the reveal: tease, flip, resolve.
  void _draw(int seat) {
    if (g.current != seat || g.phase != ScorePhase.draw) return;
    g.draw(seat);
    _turnId++;
    _stage = _Stage.tease;
    playSfx(Sfx.draw);
    setState(() {});
    _after(1150, () {
      _stage = _Stage.reveal;
      playSfx(Sfx.flip);
      setState(() {});
      _after(750, () => _resolve(seat));
    });
  }

  void _resolve(int seat) {
    final f = g.drawnFace!;
    final p = g.players[seat];
    if (!g.canUse(seat)) {
      _stage = _Stage.bust;
      playSfx(Sfx.nope);
      _say(
        f.kind == CardKind.number ? 'BUST!' : 'WASTED',
        f.kind == CardKind.number
            ? '${p.name} needed ${g.remaining(seat)}, drew ${f.value}'
            : 'Nobody has points to take yet',
        color: Palette.brand,
      );
      setState(() {});
      _after(1200, () {
        _last = g.drawn;
        g.bust(seat);
        _stage = null;
        _afterMove();
      });
      return;
    }
    final needsChoice =
        f.kind == CardKind.wild ||
        f.kind == CardKind.wildDraw ||
        f.kind == CardKind.draw;
    if (needsChoice && seat == me) {
      setState(() => _stage = _Stage.choose);
      return;
    }
    final choice = needsChoice
        ? decideExactScore(g, seat, widget.difficulty, _rng)
        : (value: null, victim: null);
    _use(seat, value: choice.value, victim: choice.victim);
  }

  void _use(int seat, {int? value, int? victim}) {
    final f = g.drawnFace!;
    final card = g.drawn!;
    final p = g.players[seat];
    final before = p.score;
    final victimScore = victim == null ? 0 : g.players[victim].score;
    g.use(seat, value: value, victim: victim);
    _last = card;
    _stage = null;
    var wait = 900;
    switch (f.kind) {
      case CardKind.skip:
        playSfx(Sfx.skip);
      case CardKind.reverse:
        playSfx(Sfx.reverse);
        if (g.players.length > 2) _say('REVERSE', 'Play changes direction');
      case CardKind.draw:
        playSfx(Sfx.penalty);
        final v = g.players[victim!];
        _fillFrom[victim] = v.score;
        _say(
          '−${victimScore - v.score}',
          '${p.name} hit ${v.isHuman ? 'you' : v.name}',
          color: Palette.brand,
        );
      default:
        // Numbers and Wilds: cross the points off one by one.
        final gained = p.score - before;
        _fillFrom[seat] = before;
        if (f.isWild) playSfx(Sfx.wild);
        for (var i = 0; i < gained; i++) {
          _after(tickMs * i + 120, () => playSfx(Sfx.tick));
        }
        _say(
          '+$gained',
          '${p.name} ${p.isHuman ? 'are' : 'is'} on ${p.score}/${g.target}',
        );
        wait = 700 + gained * tickMs;
    }
    setState(() {});
    _after(wait, _afterMove);
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
    _after(skipped.isEmpty ? 500 : 1200, _nextTurn);
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
    if (g.phase == ScorePhase.over) return;
    if (g.phase == ScorePhase.decide) {
      // Waiting for the human's choice needs nothing; anything else resolves.
      if (_stage != _Stage.choose) _resolve(g.current);
    } else {
      _nextTurn();
    }
  }

  void _humanDraw() {
    if (g.current != me || g.phase != ScorePhase.draw) return;
    HapticFeedback.lightImpact();
    _draw(me);
  }

  // ------------------------------------------------------------------- UI

  @override
  Widget build(BuildContext context) {
    final myTurn = g.current == me && g.phase != ScorePhase.over;
    return PartyScaffold(
      mode: widget.mode,
      subtitle: 'Target ${g.target} · ${widget.difficulty.label}',
      accent: _stage == _Stage.bust
          ? Palette.brand
          : myTurn
          ? const Color(0xFF2475D6)
          : const Color(0xFF7A4AD0),
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
              duration: const Duration(milliseconds: 700),
              curve: Curves.easeOutCubic,
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
      ],
    );
  }

  Widget _table() {
    final canDraw = g.current == me && g.phase == ScorePhase.draw;
    final drawn = g.drawn;
    return Stack(
      alignment: Alignment.center,
      children: [
        // Shrinks when the choice panel below takes room.
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 6,
                ),
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
                    onTap: _humanDraw,
                    child: Column(
                      children: [
                        _Glow(
                          active: canDraw,
                          child: const PlayingCard(width: 80),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          canDraw ? 'Tap to draw' : '${g.drawPile.length} left',
                          style: font(
                            14,
                            weight: 650,
                            color: canDraw ? Palette.text : Palette.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 30),
                  SizedBox(
                    width: 110,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          height: 92 * cardAspect,
                          child: Center(
                            child: drawn != null && _stage != null
                                ? _Spotlight(
                                    key: ValueKey(_turnId),
                                    face: drawn.light,
                                    stage: _stage!,
                                  )
                                : _last != null
                                ? Opacity(
                                    opacity: 0.4,
                                    child: PlayingCard(
                                      width: 80,
                                      face: _last!.light,
                                    ),
                                  )
                                : const SizedBox(),
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
                  ),
                ],
              ),
            ],
          ),
        ),
        Align(
          alignment: const Alignment(0, -0.98),
          child: TableBannerView(banner: _banner),
        ),
      ],
    );
  }

  /// Status line, plus the Wild / +2 choice when it is the human's card.
  Widget _panel() {
    final String text;
    final choices = <Widget>[];
    final p = g.players[g.current];
    if (g.phase == ScorePhase.over) {
      text = '';
    } else if (_stage == _Stage.choose) {
      final f = g.drawnFace!;
      if (f.kind == CardKind.draw) {
        text = 'Take 2 points from…';
        for (final s in g.victims(me)) {
          choices.add(
            _chip('victim-$s', g.players[s].name, () => _use(me, victim: s)),
          );
        }
      } else {
        text = 'Wild! Add any value up to ${min(9, g.remaining(me))}';
        for (final v in g.wildValues(me)) {
          choices.add(_chip('wild-$v', '+$v', () => _use(me, value: v)));
        }
      }
    } else if (_stage != null) {
      text = p.isHuman ? 'Drawing…' : '${p.name} draws…';
    } else if (g.current == me) {
      text = 'Your turn — tap the deck to draw';
    } else {
      text = "${p.name}'s turn…";
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
          if (choices.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: choices),
          ],
        ],
      ),
    );
  }

  Widget _chip(String key, String label, VoidCallback onTap) {
    return FilledButton(
      key: ValueKey(key),
      onPressed: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      style: FilledButton.styleFrom(
        backgroundColor: const Color(0xFF2475D6),
        minimumSize: const Size(52, 44),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      child: Text(label, style: font(16, weight: 700, color: Colors.white)),
    );
  }

  /// Your track: one line per point, crossed off as you score.
  Widget _track() {
    final p = g.players[me];
    const perRow = 10;
    final from = _fillFrom[me] ?? p.score;
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
                      child: i >= g.target
                          ? const SizedBox()
                          : i >= from && i < p.score
                          // Newly scored: cross off one after another.
                          ? _Tick(
                              key: ValueKey('$_turnId-$i'),
                              filled: true,
                              delay: (i - from) * tickMs + 120,
                            )
                          : _Tick(filled: i < p.score),
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

/// The drawn card: slides out of the deck face down, wobbles with suspense,
/// then turns over. A bust shakes it in red.
class _Spotlight extends StatefulWidget {
  const _Spotlight({super.key, required this.face, required this.stage});

  final CardFace face;
  final _Stage stage;

  @override
  State<_Spotlight> createState() => _SpotlightState();
}

class _SpotlightState extends State<_Spotlight> with TickerProviderStateMixin {
  late final AnimationController _enter = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  )..forward();
  late final AnimationController _wobble = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
  )..repeat(reverse: true);
  late final AnimationController _flip = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );
  late final AnimationController _shake = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 500),
  );

  @override
  void didUpdateWidget(_Spotlight old) {
    super.didUpdateWidget(old);
    if (widget.stage != _Stage.tease && !_flip.isCompleted) {
      _wobble.stop();
      _flip.forward();
    }
    if (widget.stage == _Stage.bust && old.stage != _Stage.bust) {
      _shake.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _enter.dispose();
    _wobble.dispose();
    _flip.dispose();
    _shake.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_enter, _wobble, _flip, _shake]),
      builder: (context, _) {
        final enter = Curves.easeOutBack.transform(_enter.value);
        final teasing = widget.stage == _Stage.tease;
        final wobble = teasing ? (_wobble.value - 0.5) * 0.12 : 0.0;
        final flip = _flip.value;
        final faceUp = flip >= 0.5;
        final squash = max(0.06, (cos(flip * pi)).abs());
        final shake = sin(_shake.value * pi * 6) * 8 * (1 - _shake.value);
        final bust = widget.stage == _Stage.bust;
        return Transform.translate(
          // Out of the deck on the left, into the spotlight.
          offset: Offset(-110 * (1 - enter) + shake, -10 * sin(enter * pi)),
          child: Transform.rotate(
            angle: wobble + (1 - enter) * -0.4,
            child: Transform.scale(
              scale: 0.85 + 0.25 * enter + (teasing ? _wobble.value * 0.03 : 0),
              child: Transform(
                alignment: Alignment.center,
                transform: Matrix4.diagonal3Values(squash, 1, 1),
                child: PlayingCard(
                  width: 80,
                  face: faceUp ? widget.face : null,
                  glow: bust
                      ? Palette.brand
                      : faceUp
                      ? const Color(0xFFF4B620)
                      : Colors.white.withValues(alpha: 0.35),
                  dimmed: bust && _shake.isCompleted,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// One point on the track: a line that gets crossed off.
class _Tick extends StatelessWidget {
  const _Tick({super.key, required this.filled, this.delay = 0});

  final bool filled;

  /// Milliseconds before this tick crosses off (0: already crossed).
  final int delay;

  @override
  Widget build(BuildContext context) {
    final total = delay + 220;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: delay == 0 ? 1 : 0, end: 1),
      duration: Duration(milliseconds: delay == 0 ? 1 : total),
      curve: Interval(delay / total, 1, curve: Curves.easeOutBack),
      builder: (context, v, _) {
        final on = filled && v > 0;
        return Container(
          height: 16,
          margin: const EdgeInsets.symmetric(horizontal: 2),
          decoration: BoxDecoration(
            color: on
                ? Color.lerp(Palette.surfaceHigh, Palette.brand, v.clamp(0, 1))
                : Palette.surfaceHigh,
            borderRadius: BorderRadius.circular(4),
          ),
          child: on
              ? Transform.scale(
                  scale: 0.6 + 0.4 * v,
                  child: const Icon(
                    Icons.close_rounded,
                    size: 13,
                    color: Colors.white,
                  ),
                )
              : null,
        );
      },
    );
  }
}

/// Soft pulsing glow around the deck while it waits for a tap.
class _Glow extends StatefulWidget {
  const _Glow({required this.active, required this.child});

  final bool active;
  final Widget child;

  @override
  State<_Glow> createState() => _GlowState();
}

class _GlowState extends State<_Glow> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 800),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.active) return widget.child;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) => Transform.scale(
        scale: 1 + _c.value * 0.04,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.white.withValues(alpha: 0.15 + 0.25 * _c.value),
                blurRadius: 18 + 10 * _c.value,
              ),
            ],
          ),
          child: child,
        ),
      ),
      child: widget.child,
    );
  }
}
