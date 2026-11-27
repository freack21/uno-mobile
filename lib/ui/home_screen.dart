import 'package:material_ui/material_ui.dart';

import '../game/cards.dart';
import '../game/modes.dart';
import '../game/rules.dart';
import 'game_screen.dart';
import 'guide_screen.dart';
import 'mode_screen.dart';
import 'playing_card.dart';
import 'theme.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
      // The list scrolls all the way to the bottom edge (behind the home
      // indicator); only its end is padded to stay reachable.
        child: CustomScrollView(
        bottom: false,
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
              sliver: SliverToBoxAdapter(child: _Hero()),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
              sliver: SliverToBoxAdapter(
                child: Text('Game modes', style: font(22, weight: 700)),
              ),
            ),
            SliverPadding(
              padding: EdgeInsets.fromLTRB(
                16,
                0,
                16,
                32 + MediaQuery.paddingOf(context).bottom,
              ),
              sliver: SliverList.separated(
                itemCount: gameModes.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (context, i) => _ModeTile(mode: gameModes[i]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 150,
          child: Stack(
            alignment: Alignment.bottomCenter,
            children: [
              for (final (i, face) in const [
                CardFace(CardColor.blue, CardKind.draw, draw: 2),
                CardFace(CardColor.yellow, CardKind.number, value: 7),
                CardFace(CardColor.wild, CardKind.wild),
                CardFace(CardColor.red, CardKind.skip),
              ].indexed)
                Transform.translate(
                  offset: Offset((i - 1.5) * 46, (i == 1 || i == 2) ? -10 : 0),
                  child: Transform.rotate(
                    angle: (i - 1.5) * 0.2,
                    alignment: Alignment.bottomCenter,
                    child: PlayingCard(face: face, width: 78),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 22),
        Text(
          'LAST CARD',
          textAlign: TextAlign.center,
          style: font(40, weight: 700, height: 1).copyWith(letterSpacing: 1),
        ),
        const SizedBox(height: 6),
        Text(
          'Match colors, play dirty, empty your hand.',
          textAlign: TextAlign.center,
          style: font(15, color: Palette.muted),
        ),
        const SizedBox(height: 22),
        FilledButton.icon(
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => GameScreen(
                mode: gameModes.first,
                rules: gameModes.first.rules,
                players: 4,
                difficulty: Difficulty.normal,
              ),
            ),
          ),
          icon: const Icon(Icons.play_arrow_rounded),
          label: const Text('Quick play'),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const GuideScreen()),
          ),
          icon: const Icon(Icons.school_rounded),
          label: const Text('How to play'),
        ),
      ],
    );
  }
}

class _ModeTile extends StatelessWidget {
  const _ModeTile({required this.mode});

  final GameMode mode;

  @override
  Widget build(BuildContext context) {
    final accent = Palette.of(mode.accent);
    return Material(
      color: Palette.surface,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => ModeScreen(mode: mode)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: BorderRadius.circular(14),
                  border: mode.accent == CardColor.wild
                      ? Border.all(color: Palette.line, width: 1.5)
                      : null,
                ),
                child: Icon(modeIcon(mode.id), color: Colors.white, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(mode.name, style: font(17, weight: 650)),
                        ),
                        if (mode.tag != null) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Palette.surfaceHigh,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              mode.tag!,
                              style: font(
                                11,
                                weight: 600,
                                color: Palette.muted,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      mode.tagline,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: font(13.5, color: Palette.muted, height: 1.3),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: Palette.muted),
            ],
          ),
        ),
      ),
    );
  }
}
