import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:material_ui/material_ui.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'package:last_card_core/i18n.dart';

import 'browser.dart';
import 'reactions.dart';

/// The public game server the app connects to (and invite links point to);
/// override with --dart-define=LC_HOST=... for a test server.
const appHost = String.fromEnvironment(
  'LC_HOST',
  defaultValue: 'uno.refandi.my.id',
);

const _storeKey = 'lc-online';

/// The connection to the multiplayer server and the room the player is in.
///
/// Reconnects by itself (with the saved token) whenever the socket drops
/// while the player is still in a room, e.g. after the phone slept.
class OnlineSession extends ChangeNotifier {
  OnlineSession._();

  static final instance = OnlineSession._();

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _sub;
  Timer? _ping;
  Timer? _retry;
  int _attempt = 0;
  bool _stay = false;
  Completer<String?>? _pending;

  bool connected = false;
  String? roomId;
  String? password;
  String? _token;

  /// Latest room state from the server.
  Map<String, dynamic>? room;

  /// Latest match state (from this player's seat).
  Map<String, dynamic>? match;

  /// Last error for a snackbar; [errorId] changes with every new error.
  String? error;

  /// [error] in English, to tell errors apart in any language.
  String? errorKey;
  int errorId = 0;

  bool get inRoom => room != null;
  String? get myId => room?['you'] as String?;
  bool get isHost => room != null && room!['host'] == room!['you'];

  /// The saved room to come back to, as (room, password), if any.
  (String, String)? get saved {
    final raw = readStored(_storeKey);
    if (raw == null) return null;
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      return (j['room'] as String, j['pass'] as String);
    } catch (_) {
      return null;
    }
  }

  Uri get _url {
    // The app talks to the public server; the web build to its own host.
    if (!kIsWeb) return Uri.parse('wss://$appHost/ws');
    final override = Uri.base.queryParameters['ws'];
    if (override != null) return Uri.parse(override);
    final base = Uri.base;
    return Uri(
      scheme: base.scheme == 'https' ? 'wss' : 'ws',
      host: base.host,
      port: base.hasPort ? base.port : null,
      path: '/ws',
    );
  }

  /// Link that opens the app straight into this room.
  String get inviteLink {
    final base = Uri.base;
    final origin = kIsWeb
        ? '${base.scheme}://${base.host}${base.hasPort ? ':${base.port}' : ''}'
        : 'https://$appHost';
    return '$origin/join/$roomId-$password';
  }

  // --------------------------------------------------------------- rooms

  Future<String?> create() => _enter({'t': 'create'});

  /// A Quick Match table with whoever else is looking.
  Future<String?> quick() => _enter({'t': 'quick'});

  Future<String?> join(String room, String pass) {
    final saved = _savedToken(room);
    return _enter({
      't': 'join',
      'room': room.trim().toUpperCase(),
      'pass': pass.trim(),
      'token': ?saved,
    });
  }

  void setNick(String name) => _send({'t': 'nick', 'name': name});
  void setup(Map<String, Object?> setup) => _send({'t': 'setup', ...setup});
  void start() => _send({'t': 'start'});
  void endSession() => _send({'t': 'end'});
  void act(Map<String, Object?> action) => _send({'t': 'act', ...action});

  /// Reactions on screen right now, newest last.
  final reactions = ValueNotifier<List<Reaction>>(const []);
  var _reactionId = 0;

  void react(int pick) => _send({'t': 'react', 'r': pick});

  void _showReaction(String from, int pick) {
    final r = Reaction(++_reactionId, from, pick);
    reactions.value = [
      ...reactions.value.skip(reactions.value.length > 3 ? 1 : 0),
      r,
    ];
    Timer(const Duration(milliseconds: 2800), () {
      reactions.value = [
        for (final x in reactions.value)
          if (x.id != r.id) x,
      ];
    });
  }

  /// Stops offering the saved room (it no longer exists).
  void forgetSaved() => writeStored(_storeKey, null);

  /// Header label of an online match: shows when the connection dropped.
  String get statusLabel => connected ? t('Online') : t('Reconnecting…');

  void leave() {
    _send({'t': 'leave'});
    writeStored(_storeKey, null);
    _stay = false;
    room = null;
    match = null;
    roomId = null;
    password = null;
    _token = null;
    _close();
    notifyListeners();
  }

  String? _savedToken(String room) {
    final raw = readStored(_storeKey);
    if (raw == null) return null;
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      return j['room'] == room.trim().toUpperCase()
          ? j['token'] as String?
          : null;
    } catch (_) {
      return null;
    }
  }

  Future<String?> _enter(Map<String, Object?> hello) async {
    _stay = true;
    final problem = await _open();
    if (problem != null) {
      _stay = false;
      return problem;
    }
    _pending = Completer<String?>();
    _send(hello);
    final result = await _pending!.future.timeout(
      const Duration(seconds: 10),
      onTimeout: () => t('The server did not answer. Try again.'),
    );
    if (result != null) _stay = room != null;
    return result;
  }

  // ---------------------------------------------------------- transport

  Future<String?> _open() async {
    if (connected && _channel != null) return null;
    _close();
    try {
      final channel = WebSocketChannel.connect(_url);
      await channel.ready.timeout(const Duration(seconds: 8));
      _channel = channel;
    } catch (_) {
      return t('Cannot reach the game server. Check your connection.');
    }
    connected = true;
    _attempt = 0;
    _sub = _channel!.stream.listen(
      _onData,
      onDone: _onDrop,
      onError: (_) => _onDrop(),
      cancelOnError: true,
    );
    _ping = Timer.periodic(
      const Duration(seconds: 20),
      (_) => _send({'t': 'ping'}),
    );
    notifyListeners();
    return null;
  }

  void _close() {
    _ping?.cancel();
    _retry?.cancel();
    _sub?.cancel();
    _channel?.sink.close();
    _channel = null;
    connected = false;
  }

  void _send(Map<String, Object?> msg) {
    try {
      _channel?.sink.add(jsonEncode(msg));
    } catch (_) {
      // Dropped connection; the reconnect loop takes over.
    }
  }

  void _onDrop() {
    _ping?.cancel();
    connected = false;
    _channel = null;
    notifyListeners();
    if (_stay) _scheduleReconnect();
  }

  void _scheduleReconnect() {
    _retry?.cancel();
    final delay = Duration(
      milliseconds: (500 * (1 << _attempt)).clamp(500, 8000),
    );
    _attempt = (_attempt + 1).clamp(0, 6);
    _retry = Timer(delay, () async {
      if (!_stay) return;
      final problem = await _open();
      if (problem != null) return _scheduleReconnect();
      final id = roomId;
      final pass = password;
      if (id != null && pass != null) {
        _send({'t': 'join', 'room': id, 'pass': pass, 'token': _token});
      }
    });
  }

  /// Reconnects right away (e.g. when the app comes back to the front).
  void wake() {
    if (_stay && !connected) {
      _attempt = 0;
      _scheduleReconnect();
    }
  }

  void _onData(dynamic data) {
    if (data is! String) return;
    final msg = jsonDecode(data) as Map<String, dynamic>;
    switch (msg['t']) {
      case 'welcome':
        roomId = msg['room'] as String;
        password = msg['pass'] as String;
        _token = msg['token'] as String;
        writeStored(
          _storeKey,
          jsonEncode({'room': roomId, 'pass': password, 'token': _token}),
        );
      case 'room':
        room = msg;
        // Entering is done once the room itself has arrived.
        _pending?.complete(null);
        _pending = null;
        if (msg['playing'] != true && match != null) {
          // Keep the finished match for its results screen.
          match = {...match!, 'over': true};
        }
      case 'match':
        match = msg;
      case 'error':
        // Shown in the reader's language: the server sends the English
        // template and its values.
        errorKey = (msg['key'] ?? msg['msg']) as String;
        error = t(
          errorKey!,
          (msg['args'] as Map?)?.cast<String, Object?>() ?? {},
        );
        errorId++;
        if (_pending != null) {
          _pending!.complete(error);
          _pending = null;
        }
        if (msg['fatal'] == true) {
          _stay = false;
          _close();
        }
      case 'rejected':
        error = t('That move is not possible right now');
        errorId++;
      case 'left':
        room = null;
      case 'react':
        final pick = msg['r'];
        if (pick is int && pick >= 0 && pick < reactionCount) {
          _showReaction(msg['from'] as String, pick);
        }
        return;
    }
    notifyListeners();
  }
}
