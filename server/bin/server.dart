import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:last_card_server/rooms.dart';
import 'package:last_card_server/server.dart';
import 'package:shelf/shelf_io.dart' as io;

Future<void> main(List<String> args) async {
  final env = Platform.environment;
  final port = int.tryParse(env['PORT'] ?? '') ?? 8081;
  if (args.contains('--healthcheck')) exit(await _healthy(port) ? 0 : 1);
  // Overrides exist for local end-to-end testing; production uses defaults.
  final lobby = Lobby(
    config: ServerConfig(
      pace: double.tryParse(env['LC_PACE'] ?? '') ?? 1.0,
      idleMs: int.tryParse(env['LC_IDLE_MS'] ?? '') ?? 25000,
      introMs: int.tryParse(env['LC_INTRO_MS'] ?? '') ?? 8400,
    ),
  );
  // Rooms survive restarts and redeploys when a data directory is set.
  final dataDir = env['LC_DATA_DIR'];
  final store = dataDir == null || dataDir.isEmpty
      ? null
      : File('$dataDir/rooms.json');
  if (store != null && store.existsSync()) {
    try {
      final n = lobby.restore(
        jsonDecode(store.readAsStringSync()) as Map<String, dynamic>,
      );
      stdout.writeln('Restored $n room(s)');
    } catch (e) {
      stderr.writeln('Could not restore rooms: $e');
    }
  }
  var saved = '';
  void save() {
    if (store == null) return;
    final text = jsonEncode(lobby.snapshot());
    if (text == saved) return;
    try {
      // Write then rename, so a crash never leaves half a file.
      final tmp = File('${store.path}.tmp')..writeAsStringSync(text);
      tmp.renameSync(store.path);
      saved = text;
    } catch (e) {
      stderr.writeln('Could not save rooms: $e');
    }
  }

  final saver = Timer.periodic(const Duration(seconds: 5), (_) => save());
  final server = await io.serve(
    createHandler(lobby),
    InternetAddress.anyIPv4,
    port,
  );
  stdout.writeln('Last Card server listening on :${server.port}');
  for (final signal in [ProcessSignal.sigterm, ProcessSignal.sigint]) {
    signal.watch().listen((_) async {
      saver.cancel();
      save();
      lobby.close();
      await server.close(force: true);
      exit(0);
    });
  }
}

/// Container health probe (the runtime image has no curl or wget).
Future<bool> _healthy(int port) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 3);
  try {
    final req = await client.get('127.0.0.1', port, '/healthz');
    final res = await req.close();
    await res.drain<void>();
    return res.statusCode == 200;
  } catch (_) {
    return false;
  } finally {
    client.close(force: true);
  }
}
