import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'rooms.dart';

class _SocketConnection implements Connection {
  _SocketConnection(this.channel);

  final WebSocketChannel channel;

  @override
  void send(Map<String, Object?> message) {
    try {
      channel.sink.add(jsonEncode(message));
    } catch (_) {
      // The socket is closing; the close handler cleans up.
    }
  }

  @override
  void close() => channel.sink.close();
}

/// HTTP handler: `/healthz` for probes, `/ws` for players.
Handler createHandler(Lobby lobby) {
  final ws = webSocketHandler((WebSocketChannel channel, String? _) {
    final handlers = lobby.connect(_SocketConnection(channel));
    channel.stream.listen(
      (data) {
        if (data is! String || data.length > 16 * 1024) return;
        Object? msg;
        try {
          msg = jsonDecode(data);
        } catch (_) {
          return;
        }
        if (msg is Map<String, dynamic>) {
          try {
            handlers.onMessage(msg);
          } catch (e) {
            // A malformed message must never take the room down.
            channel.sink.add(jsonEncode({'t': 'error', 'msg': 'Bad request'}));
          }
        }
      },
      onDone: handlers.onClose,
      onError: (_) => handlers.onClose(),
      cancelOnError: true,
    );
  }, pingInterval: const Duration(seconds: 20));

  return (Request request) {
    final path = request.url.path;
    if (path == 'healthz') return Response.ok('ok\n');
    if (path == 'ws' || path.endsWith('/ws')) return ws(request);
    return Response.notFound('Not found\n');
  };
}
