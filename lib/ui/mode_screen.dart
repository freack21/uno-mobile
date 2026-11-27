import 'package:material_ui/material_ui.dart';

import 'package:last_card_core/cards.dart';
import 'package:last_card_core/hold_card.dart';
import 'package:last_card_core/modes.dart';
import 'package:last_card_core/rules.dart';

import 'exact_score_screen.dart';
import 'game_screen.dart';
import 'hold_card_screen.dart';
import 'guide_screen.dart';
import 'theme.dart';

/// Mode details: match setup on top, the full guide below, Start pinned.
class ModeScreen extends StatefulWidget {
  const ModeScreen({super.key, required this.mode});

  final GameMode mode;

  @override
  State<ModeScreen> createState() => _ModeScreenState();
}

class _ModeScreenState extends State<ModeScreen> {
  late GameMode m = widget.mode;
  late int players = m.defaultPlayers;
  Difficulty difficulty = Difficulty.normal;

  /// Exact Score target; 0 means random (20-50).
  int target = 0;

  /// Hold Card: guess numbers or colors.
  HoldGuess guess = HoldGuess.number;
  late RuleSet rules = m.rules;

  int get minPlayers => rules.teams
      ? 4
      : rules.format == MatchFormat.elimination
      ? 3
      : m.minPlayers;
  int get maxPlayers => rules.teams ? 4 : m.maxPlayers;

  void _setRules(RuleSet r) => setState(() {
    rules = r;
    players = players.clamp(minPlayers, maxPlayers);
  });

  void _start() {
    final count = players.clamp(minPlayers, maxPlayers);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => switch (m.kind) {
          GameKind.exactScore => ExactScoreScreen(
            mode: m,
            players: count,
            difficulty: difficulty,
            target: target == 0 ? null : target,
          ),
          GameKind.holdCard => HoldCardScreen(
            mode: m,
            players: count,
            difficulty: difficulty,
            guess: guess,
          ),
          GameKind.shedding => GameScreen(
            mode: m,
            rules: rules,
            players: count,
            difficulty: difficulty,
          ),
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final accent = Palette.of(m.accent);
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Palette.ink,
        surfaceTintColor: Colors.transparent,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 120),
        children: [
          Row(
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: BorderRadius.circular(18),
                  border: m.accent == CardColor.wild
                      ? Border.all(color: Palette.line, width: 1.5)
                      : null,
                ),
                child: Icon(modeIcon(m.id), color: Colors.white, size: 30),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(m.name, style: font(28, weight: 700)),
                    Text(
                      m.tagline,
                      style: font(14, color: Palette.muted, height: 1.3),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          _Panel(
            children: [
              _Row(
                label: 'Opponents',
                child: _Stepper(
                  value: players - 1,
                  min: minPlayers - 1,
                  max: maxPlayers - 1,
                  onChanged: (v) => setState(() => players = v + 1),
                ),
              ),
              _Row(
                label: 'Bots',
                child: _Segments<Difficulty>(
                  values: Difficulty.values,
                  selected: difficulty,
                  label: (d) => d.label,
                  onChanged: (d) => setState(() => difficulty = d),
                ),
              ),
              if (m.kind == GameKind.exactScore)
                _Row(
                  label: 'Target',
                  child: _Segments<int>(
                    values: const [0, 20, 30, 40, 50],
                    selected: target,
                    label: (v) => v == 0 ? 'Random' : '$v',
                    onChanged: (v) => setState(() => target = v),
                  ),
                ),
              if (m.kind == GameKind.holdCard)
                _Row(
                  label: 'Guess',
                  child: _Segments<HoldGuess>(
                    values: HoldGuess.values,
                    selected: guess,
                    label: (g) => g.label,
                    onChanged: (g) => setState(() => guess = g),
                  ),
                ),
              if (rules.format == MatchFormat.points)
                _Row(
                  label: 'Target',
                  child: _Segments<int>(
                    values: const [250, 500, 1000],
                    selected: rules.targetScore,
                    label: (v) => '$v',
                    onChanged: (v) => _setRules(rules.copyWith(targetScore: v)),
                  ),
                ),
              if (m.isCustom) ...customRuleRows(rules, _setRules),
            ],
          ),
          const SizedBox(height: 28),
          Text('How to play', style: font(22, weight: 700)),
          const SizedBox(height: 14),
          GuideSections(sections: m.guide),
          Material(
            color: Palette.surface,
            borderRadius: BorderRadius.circular(18),
            child: ListTile(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
              leading: const Icon(Icons.school_rounded, color: Palette.brand),
              title: Text('Basic rules', style: font(16, weight: 600)),
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
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
          child: FilledButton.icon(
            onPressed: _start,
            icon: const Icon(Icons.play_arrow_rounded),
            label: Text('Play ${m.name}'),
          ),
        ),
      ),
    );
  }
}

/// The rule editor for Custom mode; read-only when [onChanged] is null.
List<Widget> customRuleRows(RuleSet r, ValueChanged<RuleSet>? onChanged) {
  void set(RuleSet next) => onChanged?.call(next);
  return [
    _Row(
      label: 'Deck',
      child: _Segments<DeckType>(
        values: DeckType.values,
        selected: r.deck,
        label: (d) => d.label,
        onChanged: (d) => set(r.copyWith(deck: d)),
      ),
    ),
    _Row(
      label: 'Format',
      child: _Segments<MatchFormat>(
        values: r.teams
            ? const [MatchFormat.single, MatchFormat.points]
            : MatchFormat.values,
        selected: r.format,
        label: (f) => switch (f) {
          MatchFormat.single => 'Single',
          MatchFormat.points => 'Points',
          MatchFormat.elimination => 'Elim.',
        },
        onChanged: (f) => set(r.copyWith(format: f)),
      ),
    ),
    _Row(
      label: 'Stacking',
      child: _Segments<StackRule>(
        values: StackRule.values,
        selected: r.stack,
        label: (s) => switch (s) {
          StackRule.off => 'Off',
          StackRule.same => 'Same',
          StackRule.escalating => 'Higher',
        },
        onChanged: (s) => set(r.copyWith(stack: s)),
      ),
    ),
    _Toggle(
      'Seven-O',
      '7 swaps hands, 0 passes them on',
      r.sevenZero,
      (v) => set(r.copyWith(sevenZero: v)),
    ),
    _Toggle(
      'Jump-In',
      'Play an identical card out of turn',
      r.jumpIn,
      (v) => set(r.copyWith(jumpIn: v)),
    ),
    _Toggle(
      'Doubles',
      'Play same-number cards together',
      r.combos,
      (v) => set(r.copyWith(combos: v)),
    ),
    _Toggle(
      'Draw until playable',
      'Keep drawing until a card fits',
      r.drawUntilPlayable,
      (v) => set(r.copyWith(drawUntilPlayable: v)),
    ),
    _Toggle(
      'Challenge Wild +4',
      'Call out bluffs: 4 for them or 6 for you',
      r.challengeWild4,
      (v) => set(r.copyWith(challengeWild4: v)),
    ),
    _Toggle(
      'Turn timer',
      '8 seconds per turn, or draw 2',
      r.turnSeconds != null,
      (v) => set(r.copyWith(turnSeconds: () => v ? 8 : null)),
    ),
    _Toggle(
      '25-card knockout',
      'Reach 25 cards and you are out',
      r.handLimit != null,
      (v) => set(r.copyWith(handLimit: () => v ? 25 : null)),
    ),
    _Toggle(
      'Teams 2v2',
      'Partners sit opposite and share the win',
      r.teams,
      (v) => set(
        r.copyWith(
          teams: v,
          format: v && r.format == MatchFormat.elimination
              ? MatchFormat.single
              : null,
        ),
      ),
    ),
  ];
}

class _Panel extends StatelessWidget {
  const _Panel({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: Palette.surface,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const Divider(height: 1, color: Palette.line),
            children[i],
          ],
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          SizedBox(width: 82, child: Text(label, style: font(15, weight: 600))),
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              // Shrinks wide segment groups on narrow phones.
              child: FittedBox(fit: BoxFit.scaleDown, child: child),
            ),
          ),
        ],
      ),
    );
  }
}

class _Toggle extends StatelessWidget {
  const _Toggle(this.title, this.subtitle, this.value, this.onChanged);

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final change = onChanged;
    return InkWell(
      onTap: change == null ? null : () => change(!value),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: font(15, weight: 600)),
                  Text(subtitle, style: font(13, color: Palette.muted)),
                ],
              ),
            ),
            Switch(value: value, onChanged: onChanged),
          ],
        ),
      ),
    );
  }
}

class _Segments<T> extends StatelessWidget {
  const _Segments({
    required this.values,
    required this.selected,
    required this.label,
    required this.onChanged,
  });

  final List<T> values;
  final T selected;
  final String Function(T) label;
  final ValueChanged<T>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Palette.ink,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final v in values)
            GestureDetector(
              onTap: onChanged == null ? null : () => onChanged!(v),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(
                  horizontal: 11,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: v == selected
                      ? Palette.surfaceHigh
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Text(
                  label(v),
                  style: font(
                    13.5,
                    weight: 600,
                    color: v == selected ? Palette.text : Palette.muted,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Stepper extends StatelessWidget {
  const _Stepper({
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget btn(IconData icon, int? next) => IconButton.filledTonal(
      style: IconButton.styleFrom(backgroundColor: Palette.surfaceHigh),
      onPressed: next == null ? null : () => onChanged(next),
      icon: Icon(icon, size: 20),
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        btn(Icons.remove_rounded, value > min ? value - 1 : null),
        SizedBox(
          width: 36,
          child: Text(
            '$value',
            textAlign: TextAlign.center,
            style: font(18, weight: 700),
          ),
        ),
        btn(Icons.add_rounded, value < max ? value + 1 : null),
      ],
    );
  }
}
