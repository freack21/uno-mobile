import 'cards.dart';

enum MatchFormat {
  /// One round, first player out wins.
  single,

  /// Round winners collect points; first to [RuleSet.targetScore] wins.
  points,

  /// After each round the player holding the most cards is knocked out.
  elimination,
}

enum StackRule {
  off,

  /// +2 on +2, +4 on +4.
  same,

  /// Any draw card of equal or higher value.
  escalating,
}

enum Difficulty {
  easy,
  normal,
  hard;

  String get label => name[0].toUpperCase() + name.substring(1);
}

class RuleSet {
  const RuleSet({
    this.deck = DeckType.classic,
    this.format = MatchFormat.single,
    this.targetScore = 500,
    this.stack = StackRule.off,
    this.sevenZero = false,
    this.jumpIn = false,
    this.drawUntilPlayable = false,
    this.challengeWild4 = false,
    this.teams = false,
    this.turnSeconds,
    this.handLimit,
    this.handSize = 7,
  });

  final DeckType deck;
  final MatchFormat format;
  final int targetScore;
  final StackRule stack;
  final bool sevenZero;
  final bool jumpIn;
  final bool drawUntilPlayable;
  final bool challengeWild4;

  /// 2v2: seats 0 & 2 versus seats 1 & 3.
  final bool teams;

  /// Speed mode: seconds the human has per turn.
  final int? turnSeconds;

  /// Merciless: players reaching this many cards are knocked out.
  final int? handLimit;
  final int handSize;

  RuleSet copyWith({
    DeckType? deck,
    MatchFormat? format,
    int? targetScore,
    StackRule? stack,
    bool? sevenZero,
    bool? jumpIn,
    bool? drawUntilPlayable,
    bool? challengeWild4,
    bool? teams,
    int? Function()? turnSeconds,
    int? Function()? handLimit,
  }) => RuleSet(
    deck: deck ?? this.deck,
    format: format ?? this.format,
    targetScore: targetScore ?? this.targetScore,
    stack: stack ?? this.stack,
    sevenZero: sevenZero ?? this.sevenZero,
    jumpIn: jumpIn ?? this.jumpIn,
    drawUntilPlayable: drawUntilPlayable ?? this.drawUntilPlayable,
    challengeWild4: challengeWild4 ?? this.challengeWild4,
    teams: teams ?? this.teams,
    turnSeconds: turnSeconds != null ? turnSeconds() : this.turnSeconds,
    handLimit: handLimit != null ? handLimit() : this.handLimit,
    handSize: handSize,
  );
}
