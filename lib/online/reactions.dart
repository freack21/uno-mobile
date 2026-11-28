import 'package:last_card_core/i18n.dart';

/// Quick reactions online: a fixed set (no free text), sent as an index so
/// each player reads phrases in their own language. Must stay within the
/// server's reactionCount.
const reactionCount = 12;

String reactionText(int r) => switch (r) {
  0 => '👍',
  1 => '😂',
  2 => '😮',
  3 => '😡',
  4 => '🔥',
  5 => '👏',
  6 => t('Nice one!'),
  7 => t('Hurry up!'),
  8 => t('GG!'),
  9 => t('Oops!'),
  10 => t('So close!'),
  _ => t('Not again…'),
};

/// A reaction someone sent, shown for a few seconds.
class Reaction {
  const Reaction(this.id, this.from, this.pick);

  final int id;

  /// Member id of the sender.
  final String from;
  final int pick;
}
