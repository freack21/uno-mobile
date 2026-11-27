import 'dart:io';

import 'package:last_card_server/rooms.dart';
import 'package:last_card_server/server.dart';
import 'package:shelf/shelf_io.dart' as io;

Future<void> main() async {
  final port = int.tryParse(Platform.environment['PORT'] ?? '') ?? 8081;
  final lobby = Lobby();
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
