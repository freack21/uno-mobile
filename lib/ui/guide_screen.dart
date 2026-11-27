import 'package:material_ui/material_ui.dart';

import '../game/cards.dart';
import '../game/modes.dart';
import 'playing_card.dart';
import 'theme.dart';

IconData modeIcon(String id) => switch (id) {
  'classic' => Icons.style_rounded,
  'points' => Icons.emoji_events_rounded,
  'stacking' => Icons.layers_rounded,
  'seven_o' => Icons.swap_horiz_rounded,
  'jump_in' => Icons.bolt_rounded,
  'doubles' => Icons.filter_2_rounded,
  'draw_until' => Icons.all_inclusive_rounded,
  'merciless' => Icons.local_fire_department_rounded,
  'flipside' => Icons.flip_rounded,
  'teams' => Icons.groups_rounded,
  'elimination' => Icons.person_remove_rounded,
  'speed' => Icons.timer_rounded,
  'challenge' => Icons.gavel_rounded,
  _ => Icons.tune_rounded,
};

/// Full-page rules for one mode, or the shared basics when [mode] is null.
class GuideScreen extends StatelessWidget {
  const GuideScreen({super.key, this.mode});

  final GameMode? mode;

  @override
  Widget build(BuildContext context) {
    final m = mode;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Palette.ink,
        surfaceTintColor: Colors.transparent,
        title: Text(
          m == null ? 'How to play' : '${m.name} rules',
          style: font(19, weight: 650),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          if (m != null) ...[
            Text(m.tagline, style: font(17, weight: 500, color: Palette.muted)),
            const SizedBox(height: 20),
            GuideSections(sections: m.guide),
            const SizedBox(height: 8),
            const _BasicsLink(),
          ] else
            const GuideSections(sections: basicsGuide),
        ],
      ),
    );
  }
}

class GuideSections extends StatelessWidget {
  const GuideSections({super.key, required this.sections});

  final List<GuideSection> sections;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [for (final s in sections) _Section(section: s)],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.section});

  final GuideSection section;

  @override
  Widget build(BuildContext context) {
    final s = section;
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(s.title, style: font(18, weight: 650)),
          const SizedBox(height: 10),
          for (final point in s.points)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 8, right: 12),
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      color: Palette.brand,
                      shape: BoxShape.circle,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      point,
                      style: font(15, weight: 420, height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
          if (s.cards.isNotEmpty) ...[
            const SizedBox(height: 6),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final f in s.cards)
                    Padding(
                      padding: const EdgeInsets.only(right: 10),
                      child: PlayingCard(
                        face: f,
                        width: 58,
                        wildColors: _isDarkExample(s)
                            ? CardColor.dark
                            : CardColor.light,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  bool _isDarkExample(GuideSection s) =>
      s.cards.any((f) => CardColor.dark.contains(f.color));
}

class _BasicsLink extends StatelessWidget {
  const _BasicsLink();

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Palette.surface,
      borderRadius: BorderRadius.circular(18),
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        leading: const Icon(Icons.school_rounded, color: Palette.brand),
        title: Text('New to the game?', style: font(16, weight: 600)),
        subtitle: Text(
          'Matching, action cards, Last Card and scoring.',
          style: font(13, color: Palette.muted),
        ),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const GuideScreen()),
        ),
      ),
    );
  }
}
