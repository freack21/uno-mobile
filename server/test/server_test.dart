import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:last_card_server/rooms.dart';
import 'package:last_card_server/server.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:test/test.dart';

/// A player connected over a real WebSocket.
class Client {
  Client._(this.socket) {
    socket.listen((data) {
      final msg = jsonDecode(data as String) as Map<String, dynamic>;
      inbox.add(msg);
      for (final w in List.of(_waiters)) {
        if (w.$1(msg)) {
          _waiters.remove(w);
          w.$2.complete(msg);
        }
      }
    });
  }

  static Future<Client> connect(int port) async =>
      Client._(await WebSocket.connect('ws://127.0.0.1:$port/ws'));

  final WebSocket socket;
  final inbox = <Map<String, dynamic>>[];
  final _waiters =
      <
        (bool Function(Map<String, dynamic>), Completer<Map<String, dynamic>>)
      >[];

  void send(Map<String, Object?> msg) => socket.add(jsonEncode(msg));

  /// The next message matching [test] (or one already received after [from]).
  Future<Map<String, dynamic>> next(
    bool Function(Map<String, dynamic>) test, {
    int from = 0,
  }) {
    for (final m in inbox.skip(from)) {
      if (test(m)) return Future.value(m);
    }
    final c = Completer<Map<String, dynamic>>();
    _waiters.add((test, c));
    return c.future.timeout(const Duration(seconds: 20));
  }

  Future<Map<String, dynamic>> latestRoom() =>
      next((m) => m['t'] == 'room', from: inbox.length);

  Future<void> close() => socket.close();
}

bool isType(Map<String, dynamic> m, String t) => m['t'] == t;

void main() {
  late HttpServer server;
  late Lobby lobby;
  late int port;

  setUp(() async {
    lobby = Lobby(
      config: const ServerConfig(pace: 0.0005, idleMs: 40, introMs: 0),
    );
    server = await io.serve(
      createHandler(lobby),
      InternetAddress.loopbackIPv4,
      0,
    );
    port = server.port;
  });

  tearDown(() async {
    lobby.close();
    await server.close(force: true);
  });

  /// Host creates a room; [guests] join it. Returns (clients, room, pass).
  Future<(List<Client>, String, String)> room(int guests) async {
    final host = await Client.connect(port);
    host.send({'t': 'create'});
    final w = await host.next((m) => isType(m, 'welcome'));
    final clients = [host];
    for (var i = 0; i < guests; i++) {
      final g = await Client.connect(port);
      g.send({'t': 'join', 'room': w['room'], 'pass': w['pass']});
      await g.next((m) => isType(m, 'welcome'));
      clients.add(g);
    }
    return (clients, w['room'] as String, w['pass'] as String);
  }

  test('health check', () async {
    final client = HttpClient();
    final req = await client.get('127.0.0.1', port, '/healthz');
    final res = await req.close();
    expect(res.statusCode, 200);
    expect(await res.transform(utf8.decoder).join(), 'ok\n');
    client.close();
  });

  test('create gives a room id, password and a random unique name', () async {
    final (cs, id, pass) = await room(1);
    expect(id, matches(RegExp(r'^[A-Z2-9]{6}$')));
    expect(pass, matches(RegExp(r'^\d{4}$')));
    final view = await cs[1].next(
      (m) => isType(m, 'room') && (m['members'] as List).length == 2,
    );
    final names = [for (final x in view['members'] as List) x['name']];
    expect(names.toSet().length, 2);
    expect(view['host'], (view['members'] as List).first['id']);
    for (final c in cs) {
      await c.close();
    }
  });

  test('wrong password is refused', () async {
    final (cs, id, _) = await room(0);
    final g = await Client.connect(port);
    g.send({'t': 'join', 'room': id, 'pass': '0000x'});
    final e = await g.next((m) => isType(m, 'error'));
    expect(e['msg'], contains('Wrong'));
    await g.close();
    await cs.first.close();
  });

  test('nicknames must be unique within the room', () async {
    final (cs, _, _) = await room(1);
    cs[0].send({'t': 'nick', 'name': 'Budi'});
    await cs[1].next(
      (m) =>
          isType(m, 'room') &&
          (m['members'] as List).any((x) => x['name'] == 'Budi'),
    );
    cs[1].send({'t': 'nick', 'name': 'Budi'});
    final e = await cs[1].next((m) => isType(m, 'error'));
    expect(e['msg'], contains('already taken'));
    cs[1].send({'t': 'nick', 'name': 'budi'});
    await cs[0].next(
      (m) =>
          isType(m, 'room') &&
          (m['members'] as List).any((x) => x['name'] == 'budi'),
    );
    for (final c in cs) {
      await c.close();
    }
  });

  test('only the host sets up and starts', () async {
    final (cs, _, _) = await room(1);
    cs[1].send({'t': 'setup', 'mode': 'speed'});
    expect(
      (await cs[1].next((m) => isType(m, 'error')))['msg'],
      contains('host'),
    );
    cs[1].send({'t': 'start'});
    expect(
      (await cs[1].next((m) => isType(m, 'error')))['msg'],
      contains('host'),
    );
    cs[0].send({'t': 'setup', 'mode': 'teams'});
    await cs[0].next((m) => isType(m, 'room') && m['setup']['mode'] == 'teams');
    cs[0].send({'t': 'start'});
    expect(
      (await cs[0].next((m) => isType(m, 'error')))['msg'],
      contains('at least 4'),
    );
    for (final c in cs) {
      await c.close();
    }
  });

  for (final (mode, bots) in [
    ('classic', 1),
    ('exact_score', 1),
    ('hold_card', 2),
  ]) {
    test('$mode: a full match is played and scored', () async {
      final (cs, _, _) = await room(1);
      cs[0].send({'t': 'nick', 'name': 'Ana'});
      cs[1].send({'t': 'nick', 'name': 'Budi'});
      await cs[0].next((m) {
        if (!isType(m, 'room')) return false;
        final names = {for (final x in m['members'] as List) x['name']};
        return names.containsAll(['Ana', 'Budi']);
      });
      cs[0].send({'t': 'setup', 'mode': mode, 'bots': bots, 'target': 20});
      await cs[0].next((m) => isType(m, 'room') && m['setup']['mode'] == mode);
      cs[0].send({'t': 'start'});

      // Each player sees the match from their own seat.
      final a = await cs[0].next((m) => isType(m, 'match'));
      final b = await cs[1].next((m) => isType(m, 'match'));
      expect((a['view']['players'] as List).first['name'], 'Ana');
      expect((b['view']['players'] as List).first['name'], 'Budi');
      expect((a['view']['players'] as List).length, 2 + bots);

      // Everyone keeps their lobby color, the same on every screen.
      final lobby = cs[0].inbox.lastWhere((m) => isType(m, 'room'));
      final lobbyColors = [
        for (final x in lobby['members'] as List) x['color'] as int,
      ];
      final ca = (a['colors'] as List).cast<int>();
      final cb = (b['colors'] as List).cast<int>();
      expect(ca.take(2), lobbyColors);
      expect(ca.toSet().length, 2 + bots, reason: 'bots get free colors');
      expect([...cb.skip(cb.length - 1), ...cb.take(cb.length - 1)], ca);

      // Nobody acts: idle turns are played for them until the end.
      final done = await cs[0].next(
        (m) => isType(m, 'room') && (m['history'] as List).isNotEmpty,
      );
      final ranks = (done['history'] as List).first['ranks'] as List;
      expect(ranks.length, 2 + bots);
      expect(ranks.first['place'], 1);
      expect(ranks.first['points'], 10);
      final total = [
        for (final x in done['members'] as List) x['points'] as int,
      ].fold(0, (s, x) => s + x);
      final human = ranks
          .where((r) => r['bot'] == false)
          .fold<int>(0, (s, r) => s + (r['points'] as int));
      expect(total, human);
      expect(done['playing'], isFalse);
      for (final c in cs) {
        await c.close();
      }
    });
  }

  test('custom rules are checked and used for the match', () async {
    final (cs, _, _) = await room(1);
    Map<String, Object?> rules({
      bool teams = false,
      int format = 0,
      int? turnSeconds,
    }) => {
      'deck': 1,
      'format': format,
      'target': 500,
      'stack': 1,
      'sevenZero': true,
      'jumpIn': false,
      'drawUntil': false,
      'challenge': true,
      'combos': true,
      'teams': teams,
      'turnSeconds': turnSeconds,
      'handLimit': null,
    };
    cs[0].send({
      't': 'setup',
      'mode': 'custom',
      'custom': rules(turnSeconds: 1),
    });
    expect(
      (await cs[0].next((m) => isType(m, 'error')))['msg'],
      contains('Invalid'),
    );
    cs[0].send({'t': 'setup', 'custom': rules(teams: true, format: 2)});
    await cs[0].next((m) => isType(m, 'error'), from: cs[0].inbox.length);
    cs[0].send({'t': 'setup', 'custom': rules(turnSeconds: 8), 'bots': 1});
    await cs[0].next(
      (m) =>
          isType(m, 'room') &&
          m['setup']['mode'] == 'custom' &&
          m['setup']['custom']['turnSeconds'] == 8,
    );
    cs[0].send({'t': 'start'});
    final b = await cs[1].next((m) => isType(m, 'match'));
    final r = b['view']['rules'] as Map<String, dynamic>;
    expect(r['deck'], 1);
    expect(r['combos'], isTrue);
    expect(r['turnSeconds'], 8);
    for (final c in cs) {
      await c.close();
    }
  });

  test('reconnecting with the token returns to the same seat', () async {
    final (cs, id, pass) = await room(1);
    final w = cs[1].inbox.firstWhere((m) => isType(m, 'welcome'));
    final before = await cs[1].next((m) => isType(m, 'room'));
    await cs[1].close();
    await cs[0].next(
      (m) =>
          isType(m, 'room') &&
          (m['members'] as List).any((x) => x['online'] == false),
    );
    final again = await Client.connect(port);
    again.send({'t': 'join', 'room': id, 'pass': pass, 'token': w['token']});
    final view = await again.next((m) => isType(m, 'room'));
    expect(view['you'], before['you']);
    expect((view['members'] as List).length, 2);
    await again.close();
    await cs[0].close();
  });

  test('rooms and a running match survive a restart', () async {
    // A slower table, so the save lands in the middle of the match.
    lobby.close();
    await server.close(force: true);
    lobby = Lobby(
      config: const ServerConfig(pace: 0.05, idleMs: 400, introMs: 0),
    );
    server = await io.serve(
      createHandler(lobby),
      InternetAddress.loopbackIPv4,
      0,
    );
    port = server.port;

    final (cs, id, pass) = await room(1);
    final token = cs[1].inbox.firstWhere((m) => isType(m, 'welcome'))['token'];
    cs[0].send({'t': 'nick', 'name': 'Ana'});
    cs[0].send({'t': 'setup', 'mode': 'classic', 'bots': 1});
    await cs[1].next(
      (m) =>
          isType(m, 'room') &&
          m['setup']['bots'] == 1 &&
          (m['members'] as List).any((x) => x['name'] == 'Ana'),
    );
    cs[0].send({'t': 'start'});
    final before = await cs[1].next((m) => isType(m, 'match'));
    await Future<void>.delayed(const Duration(milliseconds: 300));

    // The old process saves and stops; a new one loads the file.
    final saved = jsonDecode(jsonEncode(lobby.snapshot())) as Map;
    final savedRoom = (saved['rooms'] as List).single as Map;
    expect(savedRoom['match'], isNotNull, reason: 'saved mid-match');
    final g = savedRoom['match']['table']['game'] as Map;
    int total(Map v, int pile) =>
        (v['players'] as List).fold<int>(
          0,
          (s, p) => s + (p['hand'] as List).length,
        ) +
        pile +
        (v['discard'] as List).length;
    final cards = total(g, (g['pile'] as List).length);
    for (final c in cs) {
      await c.close();
    }
    lobby.close();
    await server.close(force: true);
    lobby = Lobby(
      config: const ServerConfig(pace: 0.0005, idleMs: 40, introMs: 0),
    );
    expect(lobby.restore(saved.cast<String, dynamic>()), 1);
    server = await io.serve(
      createHandler(lobby),
      InternetAddress.loopbackIPv4,
      0,
    );

    final back = await Client.connect(server.port);
    back.send({'t': 'join', 'room': id, 'pass': pass, 'token': token});
    final view = await back.next((m) => isType(m, 'room'));
    expect(view['you'], (view['members'] as List)[1]['id']);
    expect(view['interrupted'], isNull);
    expect(view['matchId'], before['id']);
    expect([
      for (final x in view['members'] as List) x['name'],
    ], contains('Ana'));
    // The same match carries on from the same cards, and gets scored.
    final again = await back.next((m) => isType(m, 'match'));
    expect(again['id'], before['id']);
    final v = again['view'] as Map;
    expect(
      total(v, v['draw'] as int),
      cards,
      reason: 'same deck, no card lost',
    );
    final done = await back.next(
      (m) => isType(m, 'room') && (m['history'] as List).isNotEmpty,
    );
    expect(done['playing'], isFalse);
    expect((done['history'] as List).single['mode'], 'Classic');
    await back.close();
  });

  test('a save that cannot be read is reported in the lobby', () async {
    final (cs, id, pass) = await room(0);
    final token = cs[0].inbox.firstWhere((m) => isType(m, 'welcome'))['token'];
    final saved = jsonDecode(jsonEncode(lobby.snapshot())) as Map;
    ((saved['rooms'] as List).single as Map)['match'] = {
      'id': 1,
      'mode': 'speed',
      'table': {'kind': 'unknown'},
    };
    await cs[0].close();
    lobby.close();
    lobby = Lobby(
      config: const ServerConfig(pace: 0.0005, idleMs: 40, introMs: 0),
    );
    lobby.restore(saved.cast<String, dynamic>());
    await server.close(force: true);
    server = await io.serve(
      createHandler(lobby),
      InternetAddress.loopbackIPv4,
      0,
    );
    final back = await Client.connect(server.port);
    back.send({'t': 'join', 'room': id, 'pass': pass, 'token': token});
    final view = await back.next((m) => isType(m, 'room'));
    expect(view['interrupted'], 'Speed');
    expect(view['playing'], isFalse);
    await back.close();
  });

  test('Quick Match fills with people, then bots after the wait', () async {
    lobby.close();
    await server.close(force: true);
    lobby = Lobby(
      config: const ServerConfig(
        pace: 0.0005,
        idleMs: 40,
        introMs: 0,
        quickWait: Duration(milliseconds: 300),
      ),
    );
    server = await io.serve(
      createHandler(lobby),
      InternetAddress.loopbackIPv4,
      0,
    );
    final a = await Client.connect(server.port);
    final b = await Client.connect(server.port);
    a.send({'t': 'quick'});
    final first = await a.next((m) => isType(m, 'room'));
    expect(first['quickInMs'], isNotNull);
    b.send({'t': 'quick'});
    final second = await b.next((m) => isType(m, 'room'));
    expect(second['id'], first['id'], reason: 'same table');
    // Nobody else comes: two bots take the empty seats.
    final match = await a.next((m) => isType(m, 'match'));
    expect((match['view']['players'] as List).length, quickSize);
    expect(match['mode'], 'classic');
    // The next Quick Match gets a new table.
    final c = await Client.connect(server.port);
    c.send({'t': 'quick'});
    final third = await c.next((m) => isType(m, 'room'));
    expect(third['id'], isNot(first['id']));
    for (final x in [a, b, c]) {
      await x.close();
    }
  });

  test('reactions reach everyone, from a fixed list, rate limited', () async {
    final (cs, _, _) = await room(1);
    final me = (await cs[0].next((m) => isType(m, 'room')))['you'];
    cs[0].send({'t': 'react', 'r': 3});
    final got = await cs[1].next((m) => isType(m, 'react'));
    expect(got['from'], me);
    expect(got['r'], 3);
    // Too soon, out of range or not a number: dropped.
    cs[0].send({'t': 'react', 'r': 4});
    cs[1].send({'t': 'react', 'r': 99});
    cs[1].send({'t': 'react', 'r': 'lol'});
    cs[1].send({'t': 'react', 'r': 1});
    final next = await cs[0].next((m) => isType(m, 'react') && m['from'] != me);
    expect(next['r'], 1);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(
      cs[1].inbox.where((m) => isType(m, 'react') && m['r'] == 4),
      isEmpty,
    );
    for (final c in cs) {
      await c.close();
    }
  });

  test('leaving hands the host role on', () async {
    final (cs, _, _) = await room(1);
    final guestView = await cs[1].next((m) => isType(m, 'room'));
    cs[0].send({'t': 'leave'});
    await cs[0].next((m) => isType(m, 'left'));
    final after = await cs[1].next(
      (m) => isType(m, 'room') && (m['members'] as List).length == 1,
    );
    expect(after['host'], guestView['you']);
    for (final c in cs) {
      await c.close();
    }
  });

  test('moves out of turn are rejected', () async {
    final (cs, _, _) = await room(1);
    cs[0].send({'t': 'setup', 'mode': 'classic'});
    cs[0].send({'t': 'start'});
    final a = await cs[0].next((m) => isType(m, 'match'));
    final mine = (a['view']['current'] as int) == 0;
    final idle = mine ? cs[1] : cs[0];
    idle.send({'t': 'act', 'a': 'draw'});
    await idle.next((m) => isType(m, 'rejected'));
    for (final c in cs) {
      await c.close();
    }
  });
}
