import 'dart:io' show Platform;

import 'package:audioplayers/audioplayers.dart';

import '../online/browser.dart';

/// Sound effects in the app: the web sounds rendered to assets/sfx (see
/// tool/render_sfx.js). Tests and desktop runs stay silent.

const _mutedKey = 'lc-muted';
final bool _device = Platform.isAndroid || Platform.isIOS;

/// A few players in turn, so quick sounds can overlap.
final List<AudioPlayer> _players = [];
var _next = 0;

AudioPlayer _player() {
  if (_players.length < 6) {
    final p = AudioPlayer()
      ..setPlayerMode(PlayerMode.lowLatency)
      ..setReleaseMode(ReleaseMode.stop);
    _players.add(p);
    return p;
  }
  return _players[_next++ % _players.length];
}

void play(String name) {
  if (!_device) return;
  _player().play(AssetSource('sfx/$name.wav')).catchError((_) {});
}

bool isMuted() => readStored(_mutedKey) == '1';

void setMuted(bool muted) => writeStored(_mutedKey, muted ? '1' : '0');
