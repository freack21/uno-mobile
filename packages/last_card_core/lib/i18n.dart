/// Languages of the app and the messages the game produces.
///
/// UI text is written in English and passed through [t]; the Indonesian
/// dictionary maps each English string to its translation (missing entries
/// fall back to English, and a test checks that none are missing).
///
/// What happens at the table is a [Msg]: a key plus the seats, numbers and
/// cards involved. Each player renders it in their own language and from
/// their own seat ("You draw 2" / "Budi draws 2"), so the server never sends
/// finished sentences.
library;

import 'cards.dart';
import 'i18n_id.dart';

enum Lang { en, id }

/// The language the app currently shows. The server keeps English.
Lang lang = Lang.en;

/// [en] in the current language, with `{name}` placeholders filled in.
String t(String en, [Map<String, Object?> args = const {}]) {
  var s = lang == Lang.id ? (indonesian[en] ?? en) : en;
  for (final e in args.entries) {
    s = s.replaceAll('{${e.key}}', '${e.value}');
  }
  return s;
}

/// [one] or [many] by [n] (filled in as `{n}`).
String tn(
  int n,
  String one,
  String many, [
  Map<String, Object?> args = const {},
]) => t(n == 1 ? one : many, {'n': n, ...args});

/// A message about the table: a [key] plus the seats [p], numbers [n],
/// cards [f] and a word [s] it is about.
class Msg {
  const Msg(
    this.key, {
    this.p = const [],
    this.n = const [],
    this.f = const [],
    this.s,
  });

  /// No text (a note that only plays a sound).
  static const none = Msg('');

  final String key;
  final List<int> p;
  final List<int> n;
  final List<CardFace> f;
  final String? s;

  bool get isEmpty => key.isEmpty;

  /// Seats go through [seat] (the viewer's own numbering online).
  Map<String, Object?> toJson(int Function(int) seat) => {
    'k': key,
    if (p.isNotEmpty) 'p': [for (final x in p) seat(x)],
    if (n.isNotEmpty) 'n': n,
    if (f.isNotEmpty)
      'f': [
        for (final x in f) [x.color.index, x.kind.index, x.value, x.draw],
      ],
    if (s != null) 's': s,
  };

  static Msg fromJson(Map<String, dynamic> j) => Msg(
    j['k'] as String,
    p: [for (final x in (j['p'] as List?) ?? const []) x as int],
    n: [for (final x in (j['n'] as List?) ?? const []) x as int],
    f: [
      for (final x in (j['f'] as List?) ?? const [])
        CardFace(
          CardColor.values[(x as List)[0] as int],
          CardKind.values[x[1] as int],
          value: x[2] as int,
          draw: x[3] as int,
        ),
    ],
    s: j['s'] as String?,
  );

  @override
  bool operator ==(Object other) =>
      other is Msg && other.key == key && _same(other);

  bool _same(Msg o) => '${o.p}${o.n}${o.f}${o.s}' == '$p$n$f$s';

  @override
  int get hashCode => Object.hash(key, '$p$n$f$s');
}

/// Who is who for rendering a [Msg].
class Seating {
  const Seating({required this.name, required this.you, this.mate});

  final String Function(int seat) name;

  /// Whether the seat is the reader.
  final bool Function(int seat) you;

  /// Whether the seat is the reader's partner (team play).
  final bool Function(int seat)? mate;
}

/// [m] as a sentence in the current language.
String render(Msg m, Seating who) {
  String name(int i) => who.name(m.p[i]);
  bool you(int i) => who.you(m.p[i]);
  int n(int i) => m.n[i];
  String cards() => m.f.map(faceLabel).join(' + ');
  // "{a} draws 2" / "You draw 2": one key for others, one for the reader.
  String pick(
    String mine,
    String theirs, [
    Map<String, Object?> args = const {},
  ]) => you(0) ? t(mine, args) : t(theirs, {'a': name(0), ...args});

  switch (m.key) {
    case '':
      return '';
    case 'word':
      return t(m.s!);
    case 'plus':
      return '+${n(0)}';
    case 'minus':
      return '−${n(0)}';
    // ---------------------------------------------------- shedding game
    case 'play':
      return pick('You played {cards}', '{a} played {cards}', {
        'cards': cards(),
      });
    case 'jumpIn':
      return pick('You jumped in with {cards}', '{a} jumped in with {cards}', {
        'cards': cards(),
      });
    case 'discardAll':
      return you(0)
          ? tn(
              n(0),
              'You discarded 1 more card',
              'You discarded {n} more cards',
            )
          : tn(
              n(0),
              '{a} discarded 1 more card',
              '{a} discarded {n} more cards',
              {'a': name(0)},
            );
    case 'reversed':
      return t('Direction reversed');
    case 'reversedTimes':
      return t('Reversed {n} times: same direction', {'n': n(0)});
    case 'skipAll':
      return pick('You skipped everyone', '{a} skipped everyone');
    case 'flipped':
      return t(
        m.s == 'dark'
            ? 'Everything flipped to the dark side'
            : 'Everything flipped to the light side',
      );
    case 'dug':
      final color = colorLabel(CardColor.values[n(1)]);
      return you(0)
          ? tn(
              n(0),
              'You dug 1 card for {color}',
              'You dug {n} cards for {color}',
              {'color': color},
            )
          : tn(
              n(0),
              '{a} dug 1 card for {color}',
              '{a} dug {n} cards for {color}',
              {'a': name(0), 'color': color},
            );
    case 'drew':
      return you(0)
          ? tn(n(0), 'You drew 1 card', 'You drew {n} cards')
          : tn(n(0), '{a} drew 1 card', '{a} drew {n} cards', {'a': name(0)});
    case 'challengeWon':
      return pick(
        'Challenge won! You bluffed and draw 4',
        'Challenge won! {a} bluffed and draws 4',
      );
    case 'challengeFailed':
      return pick(
        'Challenge failed! You draw 6',
        'Challenge failed! {a} draws 6',
      );
    case 'lastCall':
      return pick('You: "Last card!"', '{a}: "Last card!"');
    case 'falseCall':
      return pick(
        'Nobody is on one card · you draw 2',
        '{a} called for nothing · draws 2',
      );
    case 'caught':
      if (you(1)) return t('{a} caught you: +2', {'a': name(0)});
      return pick('You caught {b}: +2', '{a} caught {b}: +2', {'b': name(1)});
    case 'timeout':
      return pick('You ran out of time', '{a} ran out of time');
    case 'takes':
      return pick('You take +{n}', '{a} takes +{n}', {'n': n(0)});
    case 'handLimit':
      return pick(
        'You hit {n} cards and are out!',
        '{a} hit {n} cards and is out!',
        {'n': n(0)},
      );
    case 'swap':
      if (you(1)) return t('{a} swapped hands with you', {'a': name(0)});
      return pick('You swapped hands with {b}', '{a} swapped hands with {b}', {
        'b': name(1),
      });
    case 'rotate':
      return t('All hands passed along');
    case 'skipped':
      return pick('You were skipped', '{a} was skipped');
    case 'mostCards':
      return pick(
        'You held the most cards and are out!',
        '{a} held the most cards and is out!',
      );
    case 'teamRound':
      final ours = you(0) || (who.mate?.call(m.p[0]) ?? false);
      return ours
          ? t('Your team wins the round!')
          : t('Team {a} wins the round!', {'a': name(0)});
    case 'round':
      return pick('You win the round!', '{a} wins the round!');
    // ------------------------------------------------------- Exact Score
    case 'bust':
      return pick(
        'You needed {need}, drew {drew}',
        '{a} needed {need}, drew {drew}',
        {'need': n(0), 'drew': n(1)},
      );
    case 'nothingToTake':
      return t('Nobody has points to take yet');
    case 'direction':
      return t('Play changes direction');
    case 'hit':
      if (you(1)) return t('{a} hit you', {'a': name(0)});
      return pick('You hit {b}', '{a} hit {b}', {'b': name(1)});
    case 'onScore':
      return pick('You are on {score}/{target}', '{a} is on {score}/{target}', {
        'score': n(0),
        'target': n(1),
      });
    case 'loseTurn':
      final names = [for (var i = 0; i < m.p.length; i++) name(i)];
      if (m.p.length == 1) {
        return pick('You lose a turn', '{a} loses a turn');
      }
      return t('{names} lose a turn', {'names': names.join(' & ')});
    // --------------------------------------------------------- Hold Card
    case 'stockDraw':
      return pick(
        'You draw {n} from the stock',
        '{a} draws {n} from the stock',
        {'n': n(0)},
      );
    case 'nextLoses':
      return t('The next player loses a turn');
    case 'tooEarly':
      return pick(
        'You pressed without a match: {n} cards',
        '{a} pressed without a match: {n} cards',
        {'n': n(0)},
      );
    case 'slowest':
      return pick(
        'Too slow! You take the box',
        '{a} was slowest and takes the box',
      );
  }
  return m.key;
}

// ---------------------------------------------------------------- labels

String colorLabel(CardColor c) => t(switch (c) {
  CardColor.red => 'Red',
  CardColor.yellow => 'Yellow',
  CardColor.green => 'Green',
  CardColor.blue => 'Blue',
  CardColor.pink => 'Pink',
  CardColor.teal => 'Teal',
  CardColor.orange => 'Orange',
  CardColor.purple => 'Purple',
  CardColor.wild => 'Wild',
});

/// "Red 7", "Wild +4" in the current language.
String faceLabel(CardFace f) {
  final base = switch (f.kind) {
    CardKind.wildDraw => t('Wild +{n}', {'n': f.draw}),
    CardKind.wildReverseDraw => t('Wild Reverse +{n}', {'n': f.draw}),
    CardKind.wildDrawColor => t('Wild Draw Color'),
    CardKind.number => '${f.value}',
    CardKind.draw => '+${f.draw}',
    CardKind.skip => t('Skip'),
    CardKind.reverse => t('Reverse'),
    CardKind.skipAll => t('Skip All'),
    CardKind.discardAll => t('Discard All'),
    CardKind.flip => t('Flip'),
    CardKind.wild => t('Wild'),
  };
  return f.isWild ? base : '${colorLabel(f.color)} $base';
}
