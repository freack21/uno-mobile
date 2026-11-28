import 'dart:async';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'package:last_card_core/cards.dart';
import 'package:last_card_core/exact_score.dart';
import 'package:last_card_core/i18n.dart';
import 'package:last_card_core/modes.dart';
import 'package:last_card_core/party_tables.dart';
import 'package:last_card_core/rules.dart';

import '../online/session.dart';
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
    this.players = 4,
    this.difficulty = Difficulty.normal,
    this.target,
    this.table,
  });

  final GameMode mode;
  final int players;
  final Difficulty difficulty;

  /// Fixed target, or null for a random one from 20 to 50.
  final int? target;

  /// An online table mirrored from the server; null plays offline vs bots.
  final ExactScoreTable? table;

  @override
  State<ExactScoreScreen> createState() => _ExactScoreScreenState();
}

class _ExactScoreScreenState extends State<ExactScoreScreen> {
  static const me = 0;
  static const tickMs = 110;
  final _rng = Random();
  late ExactScoreTable table;
  TableBanner? _banner;
  int _seenNote = 0;
  bool _endPlayed = false;
  final _tickTimers = <Timer>[];

  bool get online => widget.table != null;
  ExactScoreGame get g => table.game;

  @override
  void initState() {
    super.initState();
    if (online) {
      table = widget.table!;
      _seenNote = table.notes.isEmpty ? 0 : table.notes.last.id;
      table.onChange = _onChange;
    } else {
      _newGame();
    }
  }

  @override
  void dispose() {
    for (final x in _tickTimers) {
      x.cancel();
    }
    if (online) {
      table.onChange = null;
    } else {
      table.dispose();
    }
    super.dispose();
  }

  void _newGame() {
    final target = widget.target ?? 20 + _rng.nextInt(7) * 5;
    table = ExactScoreTable(
      game: ExactScoreGame(
        players: [
          ScorePlayer(me, t('You'), isHuman: true),
          for (var i = 1; i < widget.players; i++)
            ScorePlayer(i, botNames[i - 1]),
        ],
        target: target,
        rng: _rng,
      ),
      humans: {me},
      difficulty: widget.difficulty,
      rng: _rng,
    )..onChange = _onChange;
    _seenNote = 0;
    _endPlayed = false;
    _banner = null;
    table.start();
  }

  /// Turns new notes into banners and sounds, then repaints.
  void _onChange() {
    if (!mounted) return;
    for (final n in table.notes) {
      if (n.id <= _seenNote) continue;
      if (n.forSeat != null && n.forSeat != me) continue;
      if (!n.title.isEmpty) {
        // Each reader sees names, "you" and the language from their seat.
        final who = Seating(
          name: (s) => g.players[s].name,
          you: (s) => s == me,
        );
        _banner = TableBanner(
          n.id,
          render(n.title, who),
          subtitle: n.subtitle.isEmpty ? null : render(n.subtitle, who),
          color: n.alert ? Palette.brand : null,
        );
      }
      if (n.sound != null) playSfxNamed(n.sound!);
      for (var i = 0; i < n.ticks; i++) {
        _tickTimers.add(
          Timer(
            Duration(milliseconds: tickMs * i + 120),
            () => playSfx(Sfx.tick),
          ),
        );
      }
    }
    if (table.notes.isNotEmpty) _seenNote = table.notes.last.id;
    if (table.isOver && !_endPlayed) {
      _endPlayed = true;
      playSfx(g.winner == me ? Sfx.win : Sfx.lose);
    }
    setState(() {});
  }

  Future<void> _menu() async {
    if (!online) table.pause();
    final action = await showPartyMenu(context, widget.mode, online: online);
    if (!mounted) return;
    switch (action) {
      case 'guide':
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => GuideScreen(mode: widget.mode)),
        );
        if (mounted && !online) table.unpause();
      case 'restart':
        table.dispose();
        setState(_newGame);
      case 'quit':
        Navigator.pop(context);
      default:
        if (!online) table.unpause();
    }
  }

  void _humanDraw() {
    if (g.current != me || g.phase != ScorePhase.draw || table.stage != null) {
      return;
    }
    HapticFeedback.lightImpact();
    table.draw(me);
  }

  void _wild(int v) => table.chooseWild(me, v);
  void _victim(int s) => table.chooseVictim(me, s);

  // ------------------------------------------------------------------- UI

  @override
  Widget build(BuildContext context) {
    final myTurn = g.current == me && g.phase != ScorePhase.over;
    return PartyScaffold(
      mode: widget.mode,
      subtitle:
          '${t('Target {n}', {'n': g.target})} · '
          '${online ? OnlineSession.instance.statusLabel : widget.difficulty.label}',
      accent: table.stage == ExactStage.bust
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
                color: seatColor(p.seat),
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
                  t('TARGET {n}', {'n': g.target}),
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
                          canDraw
                              ? t('Tap to draw')
                              : t('{n} left', {'n': g.drawPile.length}),
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
                            child: drawn != null && table.stage != null
                                ? _Spotlight(
                                    key: ValueKey(table.turnId),
                                    face: drawn.light,
                                    stage: table.stage!,
                                  )
                                : table.last != null
                                ? Opacity(
                                    opacity: 0.4,
                                    child: PlayingCard(
                                      width: 80,
                                      face: table.last!.light,
                                    ),
                                  )
                                : const SizedBox(),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          drawn != null
                              ? (g.current == me
                                    ? t('Your card')
                                    : t('{a} drew', {
                                        'a': g.players[g.current].name,
                                      }))
                              : t('Last card'),
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
    } else if (table.stage == ExactStage.choose) {
      final f = g.drawnFace!;
      if (f.kind == CardKind.draw) {
        text = t('Take 2 points from…');
        for (final s in g.victims(me)) {
          choices.add(_chip('victim-$s', g.players[s].name, () => _victim(s)));
        }
      } else {
        text = t('Wild! Add any value up to {n}', {
          'n': min(9, g.remaining(me)),
        });
        for (final v in g.wildValues(me)) {
          choices.add(_chip('wild-$v', '+$v', () => _wild(v)));
        }
      }
    } else if (table.stage != null) {
      text = p.isHuman ? t('Drawing…') : t('{a} draws…', {'a': p.name});
    } else if (g.current == me) {
      text = t('Your turn — tap the deck to draw');
    } else {
      text = t("{a}'s turn…", {'a': p.name});
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
    final from = table.fillFrom[me] ?? p.score;
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
                  t('Your track'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: font(15, weight: 650),
                ),
              ),
              const Spacer(),
              Text('${p.score} / ${g.target}', style: font(15, weight: 700)),
              const SizedBox(width: 8),
              Text(
                t('need {n}', {'n': g.remaining(me)}),
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
                              key: ValueKey('${table.turnId}-$i'),
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
      title: won ? t('You win!') : t('{a} wins', {'a': g.players[w].name}),
      subtitle: t('First to exactly {n}', {'n': g.target}),
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
      onAgain: online
          ? null
          : () {
              table.dispose();
              setState(_newGame);
            },
      onMenu: () => Navigator.pop(context),
    );
  }
}

/// The drawn card: slides out of the deck face down, wobbles with suspense,
/// then turns over. A bust shakes it in red.
class _Spotlight extends StatefulWidget {
  const _Spotlight({super.key, required this.face, required this.stage});

  final CardFace face;
  final ExactStage stage;

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
    if (widget.stage != ExactStage.tease && !_flip.isCompleted) {
      _wobble.stop();
      _flip.forward();
    }
    if (widget.stage == ExactStage.bust && old.stage != ExactStage.bust) {
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
        final teasing = widget.stage == ExactStage.tease;
        final wobble = teasing ? (_wobble.value - 0.5) * 0.12 : 0.0;
        final flip = _flip.value;
        final faceUp = flip >= 0.5;
        final squash = max(0.06, (cos(flip * pi)).abs());
        final shake = sin(_shake.value * pi * 6) * 8 * (1 - _shake.value);
        final bust = widget.stage == ExactStage.bust;
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
