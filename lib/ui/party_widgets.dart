import 'dart:async';
import 'dart:math';

import 'package:material_ui/material_ui.dart';

import 'package:last_card_core/modes.dart';

import 'guide_screen.dart';
import 'sfx.dart';
import 'theme.dart';

/// Building blocks shared by the party game screens (Exact Score, Hold Card).

const partySeatColors = [
  Palette.brand,
  Color(0xFF2475D6),
  Color(0xFF2EA358),
  Color(0xFFF4B620),
  Color(0xFF7A4AD0),
  Color(0xFFF07A1C),
];

class SeatAvatar extends StatelessWidget {
  const SeatAvatar({
    super.key,
    required this.seat,
    required this.name,
    this.size = 44,
    this.active = false,
  });

  final int seat;
  final String name;
  final double size;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: active ? Palette.text : Colors.transparent,
          width: 2.5,
        ),
      ),
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: partySeatColors[seat % partySeatColors.length],
          shape: BoxShape.circle,
        ),
        child: Text(
          name[0],
          style: font(size * 0.46, weight: 700, color: Colors.white),
        ),
      ),
    );
  }
}

class PartyChip extends StatelessWidget {
  const PartyChip(this.label, {super.key, this.color = Palette.surfaceHigh});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(label, style: font(11, weight: 700, color: Colors.white)),
    );
  }
}

/// Three bouncing dots while a bot decides.
class ThinkingDots extends StatefulWidget {
  const ThinkingDots({super.key});

  @override
  State<ThinkingDots> createState() => _ThinkingDotsState();
}

class _ThinkingDotsState extends State<ThinkingDots>
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
    return Container(
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
    );
  }
}

/// Table background tinted with [accent], plus the top bar.
class PartyScaffold extends StatelessWidget {
  const PartyScaffold({
    super.key,
    required this.mode,
    required this.subtitle,
    required this.accent,
    required this.onMenu,
    required this.child,
  });

  final GameMode mode;
  final String subtitle;
  final Color accent;
  final VoidCallback onMenu;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) onMenu();
      },
      child: Scaffold(
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
                    (color ?? accent).withValues(alpha: 0.24),
                    const Color(0xFF1A1D23),
                  ),
                  Palette.ink,
                ],
              ),
            ),
            child: child,
          ),
          child: SafeArea(
            child: Column(
              children: [
                Padding(
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
                            Text(mode.name, style: font(17, weight: 650)),
                            Text(
                              subtitle,
                              style: font(12, color: Palette.muted),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'How to play',
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => GuideScreen(mode: mode),
                          ),
                        ),
                        icon: const Icon(Icons.help_outline_rounded),
                      ),
                    ],
                  ),
                ),
                Expanded(child: child),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Pause menu; returns 'guide', 'restart', 'quit' or null (resume).
Future<String?> showPartyMenu(
  BuildContext context,
  GameMode mode, {
  bool online = false,
}) {
  return showModalBottomSheet<String>(
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
              label: Text('How to play ${mode.name}'),
            ),
            if (!online) ...[
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () => Navigator.pop(context, 'restart'),
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Restart'),
              ),
            ],
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () => Navigator.pop(context, 'quit'),
              icon: const Icon(Icons.logout_rounded),
              label: Text(online ? 'Back to lobby' : 'Quit to menu'),
            ),
          ],
        ),
      ),
    ),
  );
}

class ResultRow {
  const ResultRow(this.seat, this.name, this.detail, {this.winner = false});

  final int seat;
  final String name;
  final String detail;
  final bool winner;
}

/// End-of-game overlay; fades in after a short beat.
class PartyResults extends StatefulWidget {
  const PartyResults({
    super.key,
    required this.title,
    required this.subtitle,
    required this.won,
    required this.rows,
    required this.onAgain,
    required this.onMenu,
  });

  final String title;
  final String subtitle;
  final bool won;
  final List<ResultRow> rows;

  /// Null online: the next match is started from the lobby.
  final VoidCallback? onAgain;
  final VoidCallback onMenu;

  @override
  State<PartyResults> createState() => _PartyResultsState();
}

class _PartyResultsState extends State<PartyResults> {
  bool _visible = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(const Duration(milliseconds: 1200), () {
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
                    widget.won
                        ? Icons.emoji_events_rounded
                        : Icons.style_rounded,
                    size: 44,
                    color: widget.won ? const Color(0xFFF4B620) : Palette.muted,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    widget.title,
                    textAlign: TextAlign.center,
                    style: font(26, weight: 700),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.subtitle,
                    textAlign: TextAlign.center,
                    style: font(14, color: Palette.muted),
                  ),
                  const SizedBox(height: 18),
                  for (final r in widget.rows)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      child: Row(
                        children: [
                          SeatAvatar(seat: r.seat, name: r.name, size: 30),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              r.name,
                              style: font(15, weight: r.winner ? 700 : 500),
                            ),
                          ),
                          if (r.winner) ...[
                            const Icon(
                              Icons.emoji_events_rounded,
                              size: 18,
                              color: Color(0xFFF4B620),
                            ),
                            const SizedBox(width: 6),
                          ],
                          Text(r.detail, style: font(15, weight: 650)),
                        ],
                      ),
                    ),
                  const SizedBox(height: 18),
                  if (widget.onAgain != null) ...[
                    FilledButton(
                      onPressed: widget.onAgain,
                      child: const Text('Play again'),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton(
                      onPressed: widget.onMenu,
                      child: const Text('Menu'),
                    ),
                  ] else
                    FilledButton(
                      onPressed: widget.onMenu,
                      child: const Text('Back to lobby'),
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
