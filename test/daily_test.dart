import 'package:flutter_test/flutter_test.dart';
import 'package:last_card_core/modes.dart';
import 'package:last_card_core/rules.dart';
import 'package:uno_mobile/ui/daily.dart';
import 'package:uno_mobile/ui/game_controller.dart';

GameController deal(int seed) => GameController(
  mode: gameModes.first,
  rules: const RuleSet(),
  playerCount: 4,
  difficulty: Difficulty.normal,
  seed: seed,
);

void main() {
  test('the day turns at midnight Indonesian time', () {
    expect(dailyToday(DateTime.utc(2026, 11, 28, 16, 59)), '2026-11-28');
    expect(dailyToday(DateTime.utc(2026, 11, 28, 17, 0)), '2026-11-29');
    expect(dailySeed('2026-11-28'), 20261128);
  });

  test('everyone gets the same deal on the same day', () {
    final a = deal(dailySeed('2026-11-28'));
    final b = deal(dailySeed('2026-11-28'));
    final c = deal(dailySeed('2026-11-29'));
    String hands(GameController x) => [
      for (final p in x.game.players) p.hand.map((c) => c.light).join(','),
      x.game.top.light,
      x.game.dealer,
    ].join('|');
    expect(hands(a), hands(b));
    expect(hands(a), isNot(hands(c)));
    expect(a.daily, isTrue);
    // One try: no restarting the daily deal.
    final before = hands(a);
    a.restart();
    expect(hands(a), before);
    for (final x in [a, b, c]) {
      x.dispose();
    }
  });
}
