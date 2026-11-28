import 'dart:convert';

import 'package:last_card_core/modes.dart';
import 'package:material_ui/material_ui.dart';

import '../online/browser.dart';

/// A badge earned by playing. [check] looks at the stats after a change.
class Achievement {
  const Achievement(this.id, this.icon, this.title, this.detail, this.check);

  final String id;
  final IconData icon;

  /// English; shown through t().
  final String title;
  final String detail;
  final bool Function(Stats s) check;
}

final achievements = <Achievement>[
  Achievement(
    'first_win',
    Icons.emoji_events_rounded,
    'First win',
    'Win any game',
    (s) => s.won >= 1,
  ),
  Achievement(
    'hat_trick',
    Icons.local_fire_department_rounded,
    'Hat-trick',
    'Win 3 games in a row',
    (s) => s.bestStreak >= 3,
  ),
  Achievement(
    'on_fire',
    Icons.whatshot_rounded,
    'Unstoppable',
    'Win 5 games in a row',
    (s) => s.bestStreak >= 5,
  ),
  Achievement(
    'explorer',
    Icons.explore_rounded,
    'Explorer',
    'Play 5 different modes',
    (s) => s.modes.length >= 5,
  ),
  Achievement(
    'collector',
    Icons.collections_bookmark_rounded,
    'Seen it all',
    'Play every mode',
    (s) => gameModes.every((m) => s.modes.containsKey(m.id)),
  ),
  Achievement(
    'catcher',
    Icons.back_hand_rounded,
    'Gotcha!',
    'Catch a player who forgot to call LAST CARD',
    (s) => s.catches >= 1,
  ),
  Achievement(
    'caller',
    Icons.campaign_rounded,
    'Loud and clear',
    'Call LAST CARD 10 times',
    (s) => s.lastCalls >= 10,
  ),
  Achievement(
    'social',
    Icons.public_rounded,
    'Social',
    'Finish an online match',
    (s) => s.onlinePlayed >= 1,
  ),
  Achievement(
    'party',
    Icons.celebration_rounded,
    'Party animal',
    'Win Exact Score or Hold Card',
    (s) => s.wins('exact_score') + s.wins('hold_card') >= 1,
  ),
  Achievement(
    'merciless',
    Icons.whatshot_outlined,
    'Survivor',
    'Win a Merciless game',
    (s) => s.wins('merciless') >= 1,
  ),
  Achievement(
    'daily',
    Icons.today_rounded,
    'Daily player',
    'Finish a daily challenge',
    (s) => s.dailies >= 1,
  ),
  Achievement(
    'veteran',
    Icons.military_tech_rounded,
    'Veteran',
    'Play 50 games',
    (s) => s.played >= 50,
  ),
];

/// What this player has done, kept on the device.
class Stats extends ChangeNotifier {
  Stats._() {
    try {
      final raw = readStored(_key);
      if (raw != null) _load(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      // Unreadable stats start over rather than break the app.
    }
  }

  static final instance = Stats._();
  static const _key = 'lastcard.stats';

  int played = 0;
  int won = 0;
  int streak = 0;
  int bestStreak = 0;
  int onlinePlayed = 0;
  int catches = 0;
  int lastCalls = 0;
  int dailies = 0;

  /// Mode id → (played, won).
  final Map<String, (int, int)> modes = {};
  final Set<String> unlocked = {};

  /// Told about each newly earned achievement.
  void Function(Achievement)? onUnlock;

  int wins(String mode) => modes[mode]?.$2 ?? 0;

  void recordGame({
    required String mode,
    required bool won,
    bool online = false,
  }) {
    played++;
    if (online) onlinePlayed++;
    final (p, w) = modes[mode] ?? (0, 0);
    modes[mode] = (p + 1, w + (won ? 1 : 0));
    if (won) {
      this.won++;
      streak++;
      if (streak > bestStreak) bestStreak = streak;
    } else {
      streak = 0;
    }
    _changed();
  }

  void recordCatch() {
    catches++;
    _changed();
  }

  void recordLastCall() {
    lastCalls++;
    _changed();
  }

  void recordDaily() {
    dailies++;
    _changed();
  }

  void _changed() {
    for (final a in achievements) {
      if (!unlocked.contains(a.id) && a.check(this)) {
        unlocked.add(a.id);
        onUnlock?.call(a);
      }
    }
    writeStored(_key, jsonEncode(_toJson()));
    notifyListeners();
  }

  Map<String, Object?> _toJson() => {
    'played': played,
    'won': won,
    'streak': streak,
    'best': bestStreak,
    'online': onlinePlayed,
    'catches': catches,
    'calls': lastCalls,
    'dailies': dailies,
    'modes': {
      for (final e in modes.entries) e.key: [e.value.$1, e.value.$2],
    },
    'unlocked': unlocked.toList(),
  };

  void _load(Map<String, dynamic> j) {
    played = j['played'] as int? ?? 0;
    won = j['won'] as int? ?? 0;
    streak = j['streak'] as int? ?? 0;
    bestStreak = j['best'] as int? ?? 0;
    onlinePlayed = j['online'] as int? ?? 0;
    catches = j['catches'] as int? ?? 0;
    lastCalls = j['calls'] as int? ?? 0;
    dailies = j['dailies'] as int? ?? 0;
    for (final e in ((j['modes'] as Map?) ?? const {}).entries) {
      final v = e.value as List;
      modes[e.key as String] = (v[0] as int, v[1] as int);
    }
    unlocked.addAll([
      for (final x in (j['unlocked'] as List?) ?? const []) x as String,
    ]);
  }

  /// Starts over (tests).
  @visibleForTesting
  void reset() {
    played = won = streak = bestStreak = onlinePlayed = 0;
    catches = lastCalls = dailies = 0;
    modes.clear();
    unlocked.clear();
  }
}

/// Every Achievement text, for the translation check.
@visibleForTesting
Iterable<String> achievementTexts() => [
  for (final a in achievements) ...[a.title, a.detail],
];
