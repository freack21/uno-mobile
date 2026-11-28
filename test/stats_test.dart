import 'package:flutter_test/flutter_test.dart';
import 'package:uno_mobile/ui/stats.dart';

void main() {
  late Stats s;
  late List<String> unlocked;

  setUp(() {
    s = Stats.instance..reset();
    unlocked = [];
    s.onUnlock = (a) => unlocked.add(a.id);
  });

  test('wins, streaks and per-mode results add up', () {
    s.recordGame(mode: 'classic', won: true);
    s.recordGame(mode: 'classic', won: true);
    s.recordGame(mode: 'speed', won: false);
    s.recordGame(mode: 'speed', won: true, online: true);
    expect(s.played, 4);
    expect(s.won, 3);
    expect(s.streak, 1);
    expect(s.bestStreak, 2);
    expect(s.onlinePlayed, 1);
    expect(s.modes['classic'], (2, 2));
    expect(s.modes['speed'], (2, 1));
  });

  test('achievements unlock once, when earned', () {
    s.recordGame(mode: 'classic', won: true);
    expect(unlocked, ['first_win']);
    s.recordGame(mode: 'classic', won: true);
    s.recordGame(mode: 'classic', won: true);
    expect(unlocked, ['first_win', 'hat_trick']);
    s.recordCatch();
    s.recordCatch();
    expect(unlocked.where((a) => a == 'catcher'), hasLength(1));
    for (var i = 0; i < 10; i++) {
      s.recordLastCall();
    }
    expect(unlocked, contains('caller'));
    s.recordGame(mode: 'exact_score', won: true, online: true);
    expect(unlocked, containsAll(['party', 'social']));
  });
}
