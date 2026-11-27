import 'package:material_ui/material_ui.dart';

import 'sfx_stub.dart' if (dart.library.js_interop) 'sfx_web.dart' as platform;

/// Short synthesized sound effects (web/sfx.js on the web, silent elsewhere).
enum Sfx {
  card,
  draw,
  deal,
  shuffle,
  flip,
  turn,
  start,
  skip,
  reverse,
  penalty,
  wild,
  last,
  caught,
  swap,
  knockout,
  win,
  lose,
  tick,
  nope,
}

/// Whether sound effects are on; persisted by the platform layer.
final soundOn = ValueNotifier<bool>(!platform.isMuted());

void playSfx(Sfx sound) {
  if (soundOn.value) platform.play(sound.name);
}

/// Plays a sound by its [Sfx] name (as sent in table notes); unknown names
/// are ignored.
void playSfxNamed(String name) {
  for (final s in Sfx.values) {
    if (s.name == name) return playSfx(s);
  }
}

void setSoundOn(bool on) {
  soundOn.value = on;
  platform.setMuted(!on);
  if (on) playSfx(Sfx.tick);
}
