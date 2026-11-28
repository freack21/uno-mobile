import 'dart:async';

import 'i18n.dart';

/// A short announcement for the players: banner text plus an optional sound.
class TableNote {
  const TableNote(
    this.id,
    this.title, {
    this.subtitle = Msg.none,
    this.sound,
    this.alert = false,
    this.ticks = 0,
    this.forSeat,
  });

  final int id;

  /// Rendered by each reader in their own language (see i18n.dart).
  final Msg title;
  final Msg subtitle;

  /// Name of a sound effect (matches the app's Sfx names).
  final String? sound;

  /// Shown in the warning color.
  final bool alert;

  /// Points crossed off one by one (Exact Score), each with a tick sound.
  final int ticks;

  /// Only for this seat (e.g. "your turn"); null for everyone.
  final int? forSeat;

  Map<String, Object?> toJson(int Function(int) seat) => {
    'id': id,
    'title': title.toJson(seat),
    'subtitle': subtitle.toJson(seat),
    'sound': sound,
    'alert': alert,
    'ticks': ticks,
    'forSeat': forSeat == null ? null : seat(forSeat!),
  };

  factory TableNote.fromJson(Map<String, dynamic> j) => TableNote(
    j['id'] as int,
    Msg.fromJson(j['title'] as Map<String, dynamic>),
    subtitle: Msg.fromJson(j['subtitle'] as Map<String, dynamic>),
    sound: j['sound'] as String?,
    alert: j['alert'] as bool,
    ticks: j['ticks'] as int,
    forSeat: j['forSeat'] as int?,
  );
}

/// Runs a game over time: bot turns, reveal beats, races and timeouts.
///
/// The same runtime drives offline games in the app (one human at seat 0)
/// and online games on the server (any seats can be human).
abstract class TableRuntime {
  TableRuntime({required this.humans, this.pace = 1.0, this.idleMs});

  /// Seats played by people; every other seat is a bot.
  final Set<int> humans;

  /// Multiplies every delay; tests run with a tiny pace.
  final double pace;

  /// Online: a person who does nothing this long on their turn is played
  /// for automatically. Null offline.
  final int? idleMs;

  /// Called after every change.
  void Function()? onChange;

  /// Recent notes, newest last.
  final List<TableNote> notes = [];

  /// The id of the latest note; saved so a restored table numbers on.
  int noteId = 0;

  final _timers = <Timer>[];
  bool _paused = false;
  bool _disposed = false;

  bool get isOver;

  /// Final placement: groups of seats, best first; a group shares a place.
  List<List<int>> standings();

  void start();

  /// Picks up after [pause].
  void resume();

  bool isHuman(int seat) => humans.contains(seat);

  void after(int ms, void Function() fn) {
    if (_disposed) return;
    late final Timer t;
    t = Timer(Duration(milliseconds: (ms * pace).round()), () {
      _timers.remove(t);
      if (!_disposed && !_paused) fn();
    });
    _timers.add(t);
  }

  void cancelTimers() {
    for (final t in _timers) {
      t.cancel();
    }
    _timers.clear();
  }

  void say(
    Msg title, {
    Msg subtitle = Msg.none,
    String? sound,
    bool alert = false,
    int ticks = 0,
    int? forSeat,
  }) {
    notes.add(
      TableNote(
        ++noteId,
        title,
        subtitle: subtitle,
        sound: sound,
        alert: alert,
        ticks: ticks,
        forSeat: forSeat,
      ),
    );
    if (notes.length > 12) notes.removeAt(0);
  }

  /// A sound with no banner.
  void sound(String name, {int? forSeat}) =>
      say(Msg.none, sound: name, forSeat: forSeat);

  void changed() {
    if (!_disposed) onChange?.call();
  }

  void pause() {
    _paused = true;
    cancelTimers();
  }

  void unpause() {
    if (!_paused) return;
    _paused = false;
    resume();
  }

  void dispose() {
    _disposed = true;
    cancelTimers();
  }

  bool get disposed => _disposed;
}

/// Groups seats ranked by [key] (lower is better) into shared places.
List<List<int>> rankBy(Iterable<int> seats, num Function(int) key) {
  final sorted = seats.toList()..sort((a, b) => key(a).compareTo(key(b)));
  final groups = <List<int>>[];
  for (final s in sorted) {
    if (groups.isNotEmpty && key(groups.last.first) == key(s)) {
      groups.last.add(s);
    } else {
      groups.add([s]);
    }
  }
  return groups;
}
