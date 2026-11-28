import 'package:last_card_core/i18n.dart';
import 'package:last_card_core/modes.dart';
import 'package:material_ui/material_ui.dart';

import 'guide_screen.dart';
import 'stats.dart';
import 'theme.dart';

/// Totals, results per mode and the achievements board.
class StatsScreen extends StatelessWidget {
  const StatsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = Stats.instance;
    final rate = s.played == 0 ? 0 : (100 * s.won / s.played).round();
    final played = [
      for (final m in gameModes)
        if (s.modes.containsKey(m.id)) m,
    ];
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Palette.ink,
        surfaceTintColor: Colors.transparent,
        title: Text(t('Stats & achievements'), style: font(19, weight: 650)),
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          16,
          4,
          16,
          24 + MediaQuery.paddingOf(context).bottom,
        ),
        children: [
          Row(
            children: [
              _Number('${s.played}', t('Played')),
              _Number('${s.won}', t('Wins')),
              _Number('$rate%', t('Win rate')),
              _Number('${s.bestStreak}', t('Best streak')),
            ],
          ),
          const SizedBox(height: 22),
          Text(
            t('Achievements {n}/{max}', {
              'n': s.unlocked.length,
              'max': achievements.length,
            }),
            style: font(20, weight: 700),
          ),
          const SizedBox(height: 10),
          for (final a in achievements) _Badge(a, s.unlocked.contains(a.id)),
          if (played.isNotEmpty) ...[
            const SizedBox(height: 22),
            Text(t('By mode'), style: font(20, weight: 700)),
            const SizedBox(height: 10),
            for (final m in played)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: Palette.of(m.accent),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        modeIcon(m.id),
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: Text(m.name, style: font(15, weight: 600))),
                    Text(
                      t('{won} of {played} won', {
                        'won': s.modes[m.id]!.$2,
                        'played': s.modes[m.id]!.$1,
                      }),
                      style: font(14, color: Palette.muted),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _Number extends StatelessWidget {
  const _Number(this.value, this.label);

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 3),
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: Palette.surface,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            Text(value, style: font(22, weight: 700)),
            const SizedBox(height: 2),
            Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 2,
              style: font(12, color: Palette.muted),
            ),
          ],
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge(this.a, this.done);

  final Achievement a;
  final bool done;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Palette.surface,
        borderRadius: BorderRadius.circular(16),
        border: done
            ? Border.all(color: const Color(0xFFF4B620), width: 1.5)
            : null,
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: done ? const Color(0xFFF4B620) : Palette.surfaceHigh,
              shape: BoxShape.circle,
            ),
            child: Icon(
              done ? a.icon : Icons.lock_rounded,
              color: done ? Colors.white : Palette.muted,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t(a.title),
                  style: font(
                    15,
                    weight: 650,
                    color: done ? Palette.text : Palette.muted,
                  ),
                ),
                Text(t(a.detail), style: font(13, color: Palette.muted)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
