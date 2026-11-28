import 'package:material_ui/material_ui.dart';

import 'package:last_card_core/cards.dart';
import 'package:last_card_core/i18n.dart';
import 'package:last_card_core/modes.dart';
import 'package:last_card_core/rules.dart';

import '../online/online_screens.dart';
import '../online/session.dart';
import 'daily.dart';
import 'game_screen.dart';
import 'guide_screen.dart';
import 'lang_switch.dart';
import 'mode_screen.dart';
import 'playing_card.dart';
import 'sfx.dart';
import 'stats_screen.dart';
import 'theme.dart';
import 'theme_switch.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, this.joinCode});

  /// "ROOM-PASSWORD" from an invite link: opens the online screen right away.
  final String? joinCode;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    // An invite link, or else the room this device was last playing in (the
    // app was closed, reloaded or updated without leaving it).
    final saved = OnlineSession.instance.saved;
    final code =
        widget.joinCode ?? (saved == null ? null : '${saved.$1}-${saved.$2}');
    if (code != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => OnlineHomeScreen(joinCode: code)),
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // The list scrolls all the way to the bottom edge (behind the home
      // indicator); only its end is padded to stay reachable.
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
              sliver: SliverToBoxAdapter(child: _Hero()),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
              sliver: SliverToBoxAdapter(
                child: Text(t('Game modes'), style: font(22, weight: 700)),
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
        const Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [LangButton(), ThemeButton(), SoundButton()],
        ),
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
          t('LAST CARD'),
          textAlign: TextAlign.center,
          style: font(40, weight: 700, height: 1).copyWith(letterSpacing: 1),
        ),
        const SizedBox(height: 6),
        Text(
          t('Match colors, play dirty, empty your hand.'),
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
          label: Text(t('Quick play')),
        ),
        const SizedBox(height: 10),
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF2475D6),
          ),
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const OnlineHomeScreen()),
          ),
          icon: const Icon(Icons.groups_rounded),
          label: Text(t('Play online with friends')),
        ),
        const SizedBox(height: 10),
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFFF4B620),
            foregroundColor: const Color(0xFF2A2210),
          ),
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const DailyScreen()),
          ),
          icon: const Icon(Icons.today_rounded),
          label: Text(t('Daily challenge')),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const GuideScreen()),
                ),
                icon: const Icon(Icons.school_rounded),
                label: Text(t('How to play')),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const StatsScreen()),
                ),
                icon: const Icon(Icons.emoji_events_outlined),
                label: Text(t('Stats')),
              ),
            ),
          ],
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
                              t(mode.tag!),
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
                      t(mode.tagline),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: font(13.5, color: Palette.muted, height: 1.3),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: Palette.muted),
            ],
          ),
        ),
      ),
    );
  }
}

/// Speaker icon that turns sound effects on and off.
class SoundButton extends StatelessWidget {
  const SoundButton({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: soundOn,
      builder: (context, on, _) => IconButton(
        tooltip: on ? t('Mute sounds') : t('Turn sounds on'),
        onPressed: () => setSoundOn(!on),
        icon: Icon(on ? Icons.volume_up_rounded : Icons.volume_off_rounded),
        color: on ? Palette.text : Palette.muted,
      ),
    );
  }
}

/// Light, dark, or the device's own setting.
class ThemeButton extends StatelessWidget {
  const ThemeButton({super.key});

  @override
  Widget build(BuildContext context) {
    final themes = ThemeSwitch.instance;
    return ListenableBuilder(
      listenable: themes,
      builder: (context, _) => PopupMenuButton<ThemeChoice>(
        tooltip: t('Light or dark'),
        initialValue: themes.choice,
        onSelected: themes.pick,
        color: Palette.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        icon: Icon(_icon(themes.choice), color: Palette.text),
        itemBuilder: (context) => [
          for (final c in ThemeChoice.values)
            PopupMenuItem(
              value: c,
              child: Row(
                children: [
                  Icon(_icon(c), size: 20, color: Palette.text),
                  const SizedBox(width: 12),
                  Text(switch (c) {
                    ThemeChoice.system => t('Same as device'),
                    ThemeChoice.light => t('Light'),
                    ThemeChoice.dark => t('Dark'),
                  }, style: font(15, weight: c == themes.choice ? 650 : 500)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  static IconData _icon(ThemeChoice c) => switch (c) {
    ThemeChoice.system => Icons.brightness_auto_rounded,
    ThemeChoice.light => Icons.light_mode_rounded,
    ThemeChoice.dark => Icons.dark_mode_rounded,
  };
}

/// English, Bahasa Indonesia, or the device's language.
class LangButton extends StatelessWidget {
  const LangButton({super.key});

  @override
  Widget build(BuildContext context) {
    final langs = LangSwitch.instance;
    String name(Lang? l) => switch (l) {
      null => t('Same as device'),
      Lang.en => 'English',
      Lang.id => 'Bahasa Indonesia',
    };
    return PopupMenuButton<Lang?>(
      tooltip: t('Language'),
      initialValue: langs.choice,
      onSelected: langs.pick,
      color: Palette.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      icon: Icon(Icons.translate_rounded, color: Palette.text),
      itemBuilder: (context) => [
        for (final l in <Lang?>[null, Lang.id, Lang.en])
          PopupMenuItem(
            value: l,
            child: Text(
              name(l),
              style: font(15, weight: l == langs.choice ? 650 : 500),
            ),
          ),
      ],
    );
  }
}
