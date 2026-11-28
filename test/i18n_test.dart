import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:last_card_core/cards.dart';
import 'package:last_card_core/game.dart';
import 'package:last_card_core/i18n.dart';
import 'package:last_card_core/i18n_id.dart';
import 'package:last_card_core/protocol.dart';
import 'package:last_card_core/rules.dart';
import 'package:uno_mobile/ui/stats.dart';

/// Every English string the app passes through t(), tn() and the message
/// renderer, plus mode texts and server errors, read from the sources.
Set<String> sourceStrings() {
  const s = r"""'((?:[^'\\]|\\.)*)'""";
  final patterns = [
    RegExp(r'(?<![\w.])t\(\s*' + s),
    RegExp(r'(?<![\w.])tn\(\s*[^,]+,\s*' + s + r'\s*,\s*' + s),
    RegExp(r'pick\(\s*' + s + r'\s*,\s*' + s),
    RegExp(r"Msg\('word', s: " + s),
    RegExp(r'tagline: ' + s),
    RegExp(r'tag: ' + s),
    RegExp(r'Card(?:Color|Kind)\.\w+ => ' + s),
    RegExp(r'GuideSection\(\s*' + s),
    RegExp(r'_Toggle\(\s*' + s + r'\s*,\s*' + s),
    RegExp(r'(?:error|Problem)\(\s*(?:const\s+)?' + s),
  ];
  final bullet = RegExp(r'^\s+' + s + r',\s*$', multiLine: true);
  final files =
      [
        ...Directory('lib').listSync(recursive: true),
        ...Directory('packages/last_card_core/lib').listSync(),
        File('server/lib/rooms.dart'),
      ].whereType<File>().where(
        (f) => f.path.endsWith('.dart') && !f.path.endsWith('i18n_id.dart'),
      );
  final found = <String>{};
  String clean(String k) => k.replaceAll(r"\'", "'").replaceAll(r'\$', r'$');
  for (final f in files) {
    final text = f.readAsStringSync();
    for (final p in patterns) {
      for (final m in p.allMatches(text)) {
        for (var i = 1; i <= m.groupCount; i++) {
          final g = m.group(i);
          if (g != null) found.add(clean(g));
        }
      }
    }
    if (f.path.endsWith('modes.dart')) {
      for (final m in bullet.allMatches(text)) {
        if (m.group(1)!.contains(' ')) found.add(clean(m.group(1)!));
      }
    }
  }
  // Interpolated Dart strings ('$value') are values, not text.
  return {
    for (final k in found)
      if (!k.contains(r'$')) k,
  };
}

Set<String> placeholders(String s) => {
  for (final m in RegExp(r'\{(\w+)\}').allMatches(s)) m.group(1)!,
};

void main() {
  tearDown(() => lang = Lang.en);

  test('every English string has an Indonesian translation', () {
    final missing = {
      ...sourceStrings(),
      ...achievementTexts(),
    }.where((k) => !indonesian.containsKey(k));
    expect(missing, isEmpty);
  });

  test('translations keep their placeholders', () {
    for (final e in indonesian.entries) {
      expect(placeholders(e.value), placeholders(e.key), reason: e.key);
    }
  });

  test('t() fills placeholders and falls back to English', () {
    lang = Lang.id;
    expect(t('Round {n}', {'n': 3}), isNot('Round 3'));
    expect(t('Round {n}', {'n': 3}), contains('3'));
    expect(t('not a known string'), 'not a known string');
    lang = Lang.en;
    expect(t('Round {n}', {'n': 3}), 'Round 3');
    expect(tn(1, '1 card', '{n} cards'), '1 card');
    expect(tn(4, '1 card', '{n} cards'), '4 cards');
  });

  test('messages read from the reader’s seat and language', () {
    final who = Seating(name: (s) => ['Ana', 'Budi'][s], you: (s) => s == 0);
    const drew = Msg('drew', p: [1], n: [2]);
    expect(render(drew, who), 'Budi drew 2 cards');
    expect(render(const Msg('drew', p: [0], n: [1]), who), 'You drew 1 card');
    expect(render(const Msg('caught', p: [1, 0]), who), 'Budi caught you: +2');
    lang = Lang.id;
    expect(render(drew, who), allOf(contains('Budi'), contains('2')));
    expect(render(drew, who), isNot('Budi drew 2 cards'));
    final card = render(
      const Msg('play', p: [1], f: [CardFace(CardColor.red, CardKind.skip)]),
      who,
    );
    expect(card, contains(t('Red')));
  });

  test('event messages travel with seats rotated to each viewer', () {
    final g = Game(
      rules: const RuleSet(),
      players: [for (var i = 0; i < 3; i++) Player(i, 'P$i')],
    );
    final mine = g.current;
    g.draw(mine);
    final other = (mine + 1) % 3;
    final view = gameFromView(gameView(g, other));
    final e = view.events.last;
    expect(e.msg.key, 'drew');
    // Seat numbers are the viewer's own: the drawer sits two seats on.
    expect(e.msg.p.single, (mine - other + 3) % 3);
    expect(render(e.msg, view.seating), startsWith('P$mine drew'));
  });
}
