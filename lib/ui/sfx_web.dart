import 'dart:js_interop';

/// Sound engine defined in web/sfx.js.
@JS('lastCardSfx')
external _Sfx? get _sfx;

extension type _Sfx(JSObject _) implements JSObject {
  external void play(String name);
  external bool isMuted();
  external void setMuted(bool muted);
}

void play(String name) => _sfx?.play(name);

bool isMuted() => _sfx?.isMuted() ?? false;

void setMuted(bool muted) => _sfx?.setMuted(muted);
