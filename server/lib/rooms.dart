import 'dart:async';
import 'dart:math';

import 'package:last_card_core/cards.dart';
import 'package:last_card_core/exact_score.dart';
import 'package:last_card_core/game.dart';
import 'package:last_card_core/hold_card.dart';
import 'package:last_card_core/modes.dart';
import 'package:last_card_core/party_tables.dart';
import 'package:last_card_core/protocol.dart';
import 'package:last_card_core/rules.dart';
import 'package:last_card_core/shed_table.dart';
import 'package:last_card_core/table.dart';

/// One open connection; [send] delivers a JSON message.
abstract class Connection {
  void send(Map<String, Object?> message);
  void close();
}

/// Settings that tests shrink to run matches in milliseconds.
class ServerConfig {
  const ServerConfig({
    this.pace = 1.0,
    this.idleMs = 25000,
    this.introMs = 8400,
    this.emptyRoomTtl = const Duration(minutes: 30),
  });

  final double pace;

  /// A person who does nothing this long on their turn is played for.
  final int idleMs;
  final int introMs;
  final Duration emptyRoomTtl;
}

const maxMembers = 6;
const _codeChars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
const _botNames = ['Kira', 'Bimo', 'Sari', 'Dodo', 'Rara'];
const _adjectives = [
  'Brave',
  'Lucky',
  'Sneaky',
  'Swift',
  'Jolly',
  'Mighty',
  'Clever',
  'Wild',
  'Sunny',
  'Cosmic',
  'Fuzzy',
  'Spicy',
  'Rapid',
  'Chill',
  'Bold',
  'Witty',
];
const _animals = [
  'Otter',
  'Panda',
  'Tiger',
  'Koala',
  'Falcon',
  'Gecko',
  'Lynx',
  'Badger',
  'Orca',
  'Rhino',
  'Kitten',
  'Llama',
  'Moose',
  'Cobra',
  'Bison',
  'Hippo',
];

/// Points per finishing place in every match.
int pointsForPlace(int place) => switch (place) {
  1 => 10,
  2 => 6,
  3 => 3,
  _ => 1,
};

class Member {
  Member(this.id, this.token, this.name, this.color);

  final String id;
  final String token;
  String name;

  /// Avatar color index, kept for as long as the member stays in the room.
  final int color;
  Connection? connection;
  int points = 0;
  bool get online => connection != null;

  Map<String, Object?> toJson() => {
    'id': id,
    'token': token,
    'name': name,
    'color': color,
    'points': points,
  };

  static Member fromJson(Map<String, dynamic> j) => Member(
    j['id'] as String,
    j['token'] as String,
    j['name'] as String,
    j['color'] as int,
  )..points = j['points'] as int;
}

class Setup {
  String modeId = 'classic';
  int bots = 0;
  Difficulty difficulty = Difficulty.normal;
  int target = 0;
  HoldGuess guess = HoldGuess.number;
  RuleSet custom = const RuleSet();

  GameMode get mode => gameModes.firstWhere(
    (m) => m.id == modeId,
    orElse: () => gameModes.first,
  );
  RuleSet get rules => mode.isCustom ? custom : mode.rules;

  Map<String, Object?> toJson() => {
    'mode': modeId,
    'bots': bots,
    'difficulty': difficulty.index,
    'target': target,
    'guess': guess.index,
    'custom': rulesToJson(custom),
  };

  void restore(Map<String, dynamic> j) {
    modeId = j['mode'] as String;
    bots = j['bots'] as int;
    difficulty = Difficulty.values[j['difficulty'] as int];
    target = j['target'] as int;
    guess = HoldGuess.values[j['guess'] as int];
    custom = rulesFromJson(j['custom'] as Map<String, dynamic>);
  }
}

/// A running match: who sits where and the table that runs it.
class Match {
  Match(this.id, this.mode, this.seats, this.table);

  final int id;
  final GameMode mode;

  /// Member id per seat; null for bots.
  final List<String?> seats;
  final TableRuntime table;
  final List<String> names = [];

  /// Avatar color index per seat.
  final List<int> colors = [];
  bool recorded = false;

  int? seatOf(String memberId) {
    final i = seats.indexOf(memberId);
    return i < 0 ? null : i;
  }
}

class MatchRecord {
  MatchRecord(this.mode, this.ranks);

  static MatchRecord fromJson(Map<String, dynamic> j) =>
      MatchRecord(j['mode'] as String, [
        for (final r in j['ranks'] as List)
          (
            name: r['name'] as String,
            place: r['place'] as int,
            points: r['points'] as int,
            bot: r['bot'] as bool,
          ),
      ]);

  final String mode;
  final List<({String name, int place, int points, bool bot})> ranks;

  Map<String, Object?> toJson() => {
    'mode': mode,
    'ranks': [
      for (final r in ranks)
        {'name': r.name, 'place': r.place, 'points': r.points, 'bot': r.bot},
    ],
  };
}

class Room {
  Room(this.id, this.password, this.config, this.rng);

  final String id;
  final String password;
  final ServerConfig config;
  final Random rng;
  final List<Member> members = [];
  final Setup setup = Setup();
  final List<MatchRecord> history = [];
  String? hostId;
  Match? match;
  int _matchSerial = 0;
  bool finished = false;
  DateTime lastActive = DateTime.now();

  /// The mode of a match the server dropped while restarting, until the
  /// next match starts.
  String? interrupted;

  /// Everything needed to bring the room back after a restart. A running
  /// match cannot be resumed; it is reported as interrupted instead.
  Map<String, Object?> toJson() {
    final m = match;
    return {
      'id': id,
      'pass': password,
      'host': hostId,
      'members': [for (final x in members) x.toJson()],
      'setup': setup.toJson(),
      'history': [for (final h in history) h.toJson()],
      'serial': _matchSerial,
      'finished': finished,
      'interrupted': m != null && !m.table.isOver ? m.mode.name : interrupted,
    };
  }

  static Room fromJson(
    Map<String, dynamic> j,
    ServerConfig config,
    Random rng,
  ) {
    final r = Room(j['id'] as String, j['pass'] as String, config, rng)
      ..hostId = j['host'] as String?
      .._matchSerial = j['serial'] as int
      ..finished = j['finished'] as bool
      ..interrupted = j['interrupted'] as String?;
    r.members.addAll([
      for (final x in j['members'] as List)
        Member.fromJson(x as Map<String, dynamic>),
    ]);
    r.setup.restore(j['setup'] as Map<String, dynamic>);
    r.history.addAll([
      for (final h in j['history'] as List)
        MatchRecord.fromJson(h as Map<String, dynamic>),
    ]);
    return r;
  }

  Member? member(String id) {
    for (final m in members) {
      if (m.id == id) return m;
    }
    return null;
  }

  bool get anyoneOnline => members.any((m) => m.online);

  String randomName() {
    for (var i = 0; i < 200; i++) {
      final name =
          '${_adjectives[rng.nextInt(_adjectives.length)]} '
          '${_animals[rng.nextInt(_animals.length)]}';
      if (!members.any((m) => m.name == name)) return name;
    }
    return 'Player ${members.length + 1}';
  }

  /// Error text, or null if [name] can be used by [who].
  String? checkName(String name, Member who) {
    if (name.isEmpty) return 'Nickname cannot be empty';
    if (name.length > 16) return 'Nickname is at most 16 characters';
    if (members.any((m) => m != who && m.name == name)) {
      return '"$name" is already taken in this room';
    }
    return null;
  }

  // -------------------------------------------------------------- views

  Map<String, Object?> view(Member you) {
    final m = match;
    return {
      't': 'room',
      'id': id,
      'pass': password,
      'you': you.id,
      'host': hostId,
      'members': [
        for (final x in members)
          {
            'id': x.id,
            'name': x.name,
            'online': x.online,
            'color': x.color,
            'points': x.points,
            'playing': m != null && !m.table.isOver && m.seatOf(x.id) != null,
          },
      ],
      'setup': setup.toJson(),
      'playing': m != null && !m.table.isOver,
      'matchId': m?.id,
      'matchMode': m?.mode.id,
      'finished': finished,
      'interrupted': interrupted,
      'history': [for (final h in history) h.toJson()],
    };
  }

  void broadcastRoom() {
    for (final x in members) {
      x.connection?.send(view(x));
    }
  }

  /// The match as seen from [seat].
  Map<String, Object?> matchView(Match m, int seat) {
    final s = Seats(seat, m.seats.length);
    final t = m.table;
    final notes = [for (final n in t.notes) n.toJson(s.toLocal)];
    final base = <String, Object?>{
      't': 'match',
      'id': m.id,
      'mode': m.mode.id,
      'over': t.isOver,
      'notes': notes,
      'colors': [for (var i = 0; i < s.count; i++) m.colors[s.toReal(i)]],
    };
    switch (t) {
      case ShedTable():
        final deadline = t.turnDeadline;
        return {
          ...base,
          'kind': 'shed',
          'view': gameView(t.game, seat),
          'opening': t.opening,
          'thinking': s.toLocalOrNull(t.thinkingSeat),
          'clockMs': deadline == null
              ? null
              : max(0, deadline.difference(DateTime.now()).inMilliseconds),
        };
      case ExactScoreTable():
        return {
          ...base,
          'kind': 'exact',
          'view': exactView(t.game, seat),
          'stage': t.stage?.index,
          'turnId': t.turnId,
          'fillFrom': {
            for (final e in t.fillFrom.entries) '${s.toLocal(e.key)}': e.value,
          },
          'last': t.last == null ? null : cardToJson(t.last!),
        };
      case HoldCardTable():
        return {
          ...base,
          'kind': 'hold',
          'view': holdView(t.game, seat),
          'playId': t.playId,
        };
      default:
        throw StateError('Unknown table');
    }
  }

  void broadcastMatch() {
    final m = match;
    if (m == null) return;
    for (var seat = 0; seat < m.seats.length; seat++) {
      final id = m.seats[seat];
      if (id == null) continue;
      member(id)?.connection?.send(matchView(m, seat));
    }
  }

  // ------------------------------------------------------------ matches

  /// Starts a match with everyone in the room plus the configured bots.
  /// Returns an error message, or null on success.
  String? start() {
    if (match != null && !match!.table.isOver) return 'A match is running';
    final mode = setup.mode;
    final people = [
      for (final m in members)
        if (m.online) m,
    ];
    final total = people.length + setup.bots;
    final rules = setup.rules;
    final min = rules.teams
        ? 4
        : (rules.format == MatchFormat.elimination ? 3 : 2);
    final maxPlayers = rules.teams ? 4 : 6;
    if (total < min) {
      return '${mode.name} needs at least $min players: add bots or invite friends';
    }
    if (total > maxPlayers) {
      return '${mode.name} allows at most $maxPlayers players: remove bots';
    }
    final seats = <String?>[
      for (final p in people) p.id,
      for (var i = 0; i < setup.bots; i++) null,
    ];
    final names = <String>[
      for (final p in people) p.name,
      for (var i = 0; i < setup.bots; i++) '${_botNames[i]} (bot)',
    ];
    final humans = {for (var i = 0; i < people.length; i++) i};
    // People keep their lobby color; bots take the free ones.
    final free = [
      for (var i = 0; i < maxMembers; i++)
        if (!people.any((p) => p.color == i)) i,
    ];
    final colors = [
      for (final p in people) p.color,
      for (var i = 0; i < setup.bots; i++) free[i % free.length],
    ];
    final TableRuntime table;
    switch (mode.kind) {
      case GameKind.shedding:
        table = ShedTable(
          game: Game(
            rules: rules,
            players: [for (var i = 0; i < total; i++) Player(i, names[i])],
            rng: rng,
          ),
          humans: humans,
          difficulty: setup.difficulty,
          pace: config.pace,
          idleMs: config.idleMs,
          introMs: config.introMs,
          rng: rng,
        );
      case GameKind.exactScore:
        table = ExactScoreTable(
          game: ExactScoreGame(
            players: [for (var i = 0; i < total; i++) ScorePlayer(i, names[i])],
            target: setup.target == 0 ? 20 + rng.nextInt(7) * 5 : setup.target,
            rng: rng,
          ),
          humans: humans,
          difficulty: setup.difficulty,
          pace: config.pace,
          idleMs: config.idleMs,
          rng: rng,
        );
      case GameKind.holdCard:
        table = HoldCardTable(
          game: HoldCardGame(
            players: [for (var i = 0; i < total; i++) HoldPlayer(i, names[i])],
            guess: setup.guess,
            rng: rng,
          ),
          humans: humans,
          difficulty: setup.difficulty,
          pace: config.pace,
          idleMs: config.idleMs,
          rng: rng,
        );
    }
    final m = Match(++_matchSerial, mode, seats, table)
      ..names.addAll(names)
      ..colors.addAll(colors);
    match = m;
    finished = false;
    interrupted = null;
    table.onChange = () => _onMatchChange(m);
    table.start();
    broadcastRoom();
    return null;
  }

  void _onMatchChange(Match m) {
    if (match != m) return;
    lastActive = DateTime.now();
    broadcastMatch();
    if (m.table.isOver && !m.recorded) {
      m.recorded = true;
      _record(m);
      broadcastRoom();
    }
  }

  void _record(Match m) {
    final ranks = <({String name, int place, int points, bool bot})>[];
    var place = 1;
    for (final group in m.table.standings()) {
      for (final seat in group) {
        final points = pointsForPlace(place);
        final id = m.seats[seat];
        ranks.add((
          name: m.names[seat],
          place: place,
          points: points,
          bot: id == null,
        ));
        if (id != null) member(id)?.points += points;
      }
      place += group.length;
    }
    history.add(MatchRecord(m.mode.name, ranks));
  }

  /// Routes a move from [who] to the running match.
  bool act(Member who, Map<String, dynamic> msg) {
    final m = match;
    if (m == null || m.table.isOver) return false;
    final seat = m.seatOf(who.id);
    if (seat == null) return false;
    final s = Seats(seat, m.seats.length);
    int real(Object? local) => s.toReal(local as int);
    final a = msg['a'];
    final t = m.table;
    switch (t) {
      case ShedTable():
        return switch (a) {
          'play' => t.play(
            seat,
            msg['card'] as int,
            color: msg['color'] == null
                ? null
                : CardColor.values[msg['color'] as int],
            swapWith: msg['swap'] == null ? null : real(msg['swap']),
            extra: [for (final x in (msg['extra'] as List? ?? [])) x as int],
          ),
          'draw' => t.draw(seat),
          'pass' => t.pass(seat),
          'challenge' => t.challenge(seat),
          'last' => t.callLast(seat),
          'catch' => t.catchPlayer(seat, real(msg['target'])),
          _ => false,
        };
      case ExactScoreTable():
        return switch (a) {
          'draw' => t.draw(seat),
          'wild' => t.chooseWild(seat, msg['value'] as int),
          'victim' => t.chooseVictim(seat, real(msg['target'])),
          _ => false,
        };
      case HoldCardTable():
        return switch (a) {
          'place' => t.place(
            seat,
            msg['number'] != null
                ? HoldCall.number(msg['number'] as int)
                : HoldCall.color(CardColor.values[msg['color'] as int]),
            msg['index'] as int,
          ),
          'press' => t.press(seat),
          _ => false,
        };
      default:
        return false;
    }
  }

  /// A member left for good: hand their seat to a bot and drop them.
  void remove(Member who) {
    final m = match;
    final seat = m?.seatOf(who.id);
    if (m != null && seat != null && !m.table.isOver) {
      m.table.humans.remove(seat);
      m.table.resume();
    }
    members.remove(who);
    if (hostId == who.id) {
      hostId = members.isEmpty ? null : members.first.id;
    }
    broadcastRoom();
  }

  void dispose() => match?.table.dispose();
}

/// All rooms on this server and the message handling for connections.
class Lobby {
  Lobby({this.config = const ServerConfig(), Random? rng})
    : rng = rng ?? Random.secure() {
    _sweeper = Timer.periodic(const Duration(minutes: 1), (_) => sweep());
  }

  final ServerConfig config;
  final Random rng;
  final Map<String, Room> rooms = {};
  late final Timer _sweeper;

  String _code(int length, String chars) =>
      List.generate(length, (_) => chars[rng.nextInt(chars.length)]).join();

  /// Drops rooms nobody has been connected to for a while.
  void sweep() {
    final now = DateTime.now();
    rooms.removeWhere((_, r) {
      final stale =
          !r.anyoneOnline && now.difference(r.lastActive) > config.emptyRoomTtl;
      if (stale) r.dispose();
      return stale;
    });
  }

  /// All rooms, for saving across restarts.
  Map<String, Object?> snapshot() => {
    'version': 1,
    'rooms': [for (final r in rooms.values) r.toJson()],
  };

  /// Brings back rooms from [snapshot]; returns how many. Members reconnect
  /// with their saved tokens.
  int restore(Map<String, dynamic> snapshot) {
    if (snapshot['version'] != 1) return 0;
    var count = 0;
    for (final j in snapshot['rooms'] as List) {
      try {
        final r = Room.fromJson(j as Map<String, dynamic>, config, rng);
        rooms[r.id] = r;
        count++;
      } catch (_) {
        // A room that cannot be read is dropped; the rest still load.
      }
    }
    return count;
  }

  void close() {
    _sweeper.cancel();
    for (final r in rooms.values) {
      r.dispose();
    }
    rooms.clear();
  }

  /// A new connection: returns the handler for its messages and its close.
  ({void Function(Map<String, dynamic>) onMessage, void Function() onClose})
  connect(Connection c) {
    Room? room;
    Member? me;

    void error(String text) => c.send({'t': 'error', 'msg': text});

    void attach(Room r, Member m) {
      // A newer connection for the same member replaces the old one.
      final old = m.connection;
      if (old != null && old != c) {
        old.send({'t': 'error', 'msg': 'Opened in another tab', 'fatal': true});
        old.close();
      }
      m.connection = c;
      room = r;
      me = m;
      r.lastActive = DateTime.now();
      c.send({
        't': 'welcome',
        'room': r.id,
        'pass': r.password,
        'token': m.token,
      });
      r.broadcastRoom();
      final match = r.match;
      final seat = match?.seatOf(m.id);
      if (match != null && seat != null) c.send(r.matchView(match, seat));
    }

    Member newMember(Room r) => Member(
      _code(10, _codeChars),
      _code(24, _codeChars),
      r.randomName(),
      // The first color nobody in the room is using.
      List.generate(maxMembers, (i) => i).firstWhere(
        (i) => !r.members.any((x) => x.color == i),
        orElse: () => r.members.length % maxMembers,
      ),
    );

    void onMessage(Map<String, dynamic> msg) {
      final r = room;
      final m = me;
      switch (msg['t']) {
        case 'ping':
          c.send({'t': 'pong'});
        case 'create':
          String id;
          do {
            id = _code(6, _codeChars);
          } while (rooms.containsKey(id));
          final created = Room(id, _code(4, '0123456789'), config, rng);
          rooms[id] = created;
          final host = newMember(created);
          created.members.add(host);
          created.hostId = host.id;
          attach(created, host);
        case 'join':
          final target = rooms['${msg['room'] ?? ''}'.toUpperCase().trim()];
          if (target == null ||
              target.password != '${msg['pass'] ?? ''}'.trim()) {
            return error('Wrong room ID or password');
          }
          final token = msg['token'] as String?;
          final back = token == null
              ? null
              : target.members.where((x) => x.token == token).firstOrNull;
          if (back != null) return attach(target, back);
          if (target.members.length >= maxMembers) {
            return error('This room is full ($maxMembers players)');
          }
          final joined = newMember(target);
          target.members.add(joined);
          target.hostId ??= joined.id;
          attach(target, joined);
        case 'leave':
          if (r == null || m == null) return;
          r.remove(m);
          m.connection = null;
          room = null;
          me = null;
          if (r.members.isEmpty) {
            r.dispose();
            rooms.remove(r.id);
          }
          c.send({'t': 'left'});
        default:
          if (r == null || m == null) return error('Join a room first');
          r.lastActive = DateTime.now();
          _inRoom(r, m, msg, error);
      }
    }

    void onClose() {
      final r = room;
      final m = me;
      if (r == null || m == null || m.connection != c) return;
      m.connection = null;
      r.lastActive = DateTime.now();
      r.broadcastRoom();
    }

    return (onMessage: onMessage, onClose: onClose);
  }

  void _inRoom(
    Room r,
    Member m,
    Map<String, dynamic> msg,
    void Function(String) error,
  ) {
    final host = r.hostId == m.id;
    switch (msg['t']) {
      case 'nick':
        final name = '${msg['name'] ?? ''}'.trim();
        final problem = r.checkName(name, m);
        if (problem != null) return error(problem);
        m.name = name;
        r.broadcastRoom();
      case 'setup':
        if (!host) return error('Only the host can change the game');
        if (r.match != null && !r.match!.table.isOver) {
          return error('Wait for the match to end');
        }
        final s = r.setup;
        final mode = msg['mode'] as String?;
        if (mode != null && gameModes.any((x) => x.id == mode)) s.modeId = mode;
        final bots = msg['bots'] as int?;
        if (bots != null) s.bots = bots.clamp(0, 5);
        final d = msg['difficulty'] as int?;
        if (d != null && d >= 0 && d < Difficulty.values.length) {
          s.difficulty = Difficulty.values[d];
        }
        final target = msg['target'] as int?;
        if (target != null && [0, 20, 30, 40, 50].contains(target)) {
          s.target = target;
        }
        final guess = msg['guess'] as int?;
        if (guess != null && guess >= 0 && guess < HoldGuess.values.length) {
          s.guess = HoldGuess.values[guess];
        }
        final custom = msg['custom'] as Map<String, dynamic>?;
        if (custom != null) {
          RuleSet? rules;
          try {
            rules = rulesFromJson(custom);
          } catch (_) {}
          // Only the choices the rule editor offers.
          if (rules == null ||
              ![250, 500, 1000].contains(rules.targetScore) ||
              ![null, 8].contains(rules.turnSeconds) ||
              ![null, 25].contains(rules.handLimit) ||
              (rules.teams && rules.format == MatchFormat.elimination)) {
            return error('Invalid custom rules');
          }
          s.custom = rules;
        }
        r.broadcastRoom();
      case 'start':
        if (!host) return error('Only the host can start');
        final problem = r.start();
        if (problem != null) error(problem);
      case 'act':
        if (!r.act(m, msg)) {
          m.connection?.send({'t': 'rejected'});
        }
      case 'end':
        if (!host) return error('Only the host can end the session');
        r.finished = true;
        r.broadcastRoom();
      default:
        error('Unknown message');
    }
  }
}
