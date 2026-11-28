/// The daily challenge leaderboard: one score per device per day, kept for
/// a week.
library;

/// Days follow Indonesian time (WIB, UTC+7), like the app.
String dailyDate(DateTime now) {
  final d = now.toUtc().add(const Duration(hours: 7));
  String two(int x) => x.toString().padLeft(2, '0');
  return '${d.year}-${two(d.month)}-${two(d.day)}';
}

class DailyEntry {
  DailyEntry(this.name, this.score, this.at);

  final String name;
  final int score;
  final int at;

  List<Object> toJson() => [name, score, at];

  static DailyEntry fromJson(List j) =>
      DailyEntry(j[0] as String, j[1] as int, j[2] as int);
}

class DailyBoard {
  /// Date → device id → entry.
  final Map<String, Map<String, DailyEntry>> days = {};

  static const maxScore = 5000;
  static const keepDays = 7;

  /// Error text, or null when the score was taken (or was already in).
  String? submit({
    required String date,
    required String device,
    required String name,
    required int score,
    required DateTime now,
  }) {
    final today = dailyDate(now);
    final yesterday = dailyDate(now.subtract(const Duration(days: 1)));
    if (date != today && date != yesterday) return 'That day is over';
    final nick = name.trim();
    if (nick.isEmpty || nick.length > 16) {
      return 'Nickname is at most 16 characters';
    }
    if (device.length < 8 || device.length > 64) return 'Unknown device';
    if (score < 0 || score > maxScore) return 'Invalid score';
    // One try a day: the first result stays.
    days
        .putIfAbsent(date, () => {})
        .putIfAbsent(
          device,
          () => DailyEntry(nick, score, now.millisecondsSinceEpoch),
        );
    return null;
  }

  /// The top of [date], best first (earlier wins ties), and [device]'s rank.
  Map<String, Object?> view(String date, String? device, {int top = 20}) {
    final entries = (days[date] ?? const {}).entries.toList()
      ..sort((a, b) {
        final c = b.value.score.compareTo(a.value.score);
        return c != 0 ? c : a.value.at.compareTo(b.value.at);
      });
    final rank = entries.indexWhere((e) => e.key == device);
    return {
      't': 'daily',
      'date': date,
      'players': entries.length,
      'top': [
        for (final e in entries.take(top))
          {'name': e.value.name, 'score': e.value.score},
      ],
      'rank': rank < 0 ? null : rank + 1,
    };
  }

  /// Forgets days older than a week.
  void prune(DateTime now) {
    final keep = {
      for (var i = 0; i < keepDays; i++)
        dailyDate(now.subtract(Duration(days: i))),
    };
    days.removeWhere((d, _) => !keep.contains(d));
  }

  Map<String, Object?> toJson() => {
    for (final d in days.entries)
      d.key: {for (final e in d.value.entries) e.key: e.value.toJson()},
  };

  void load(Map<String, dynamic> j) {
    for (final d in j.entries) {
      days[d.key] = {
        for (final e in (d.value as Map<String, dynamic>).entries)
          e.key: DailyEntry.fromJson(e.value as List),
      };
    }
  }
}
