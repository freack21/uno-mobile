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
  final server = await io.serve(
    createHandler(lobby),
    InternetAddress.anyIPv4,
    port,
  );
  stdout.writeln('Last Card server listening on :${server.port}');
  for (final signal in [ProcessSignal.sigterm, ProcessSignal.sigint]) {
    signal.watch().listen((_) async {
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
