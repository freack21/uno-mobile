import 'dart:js_interop';

/// Bridge defined in web/index.html.
@JS('lastCardUpdate')
external _UpdateBridge? get _bridge;

extension type _UpdateBridge(JSObject _) implements JSObject {
  external void onReady(JSFunction callback);
  external void apply();
}

void onUpdateReady(void Function() callback) => _bridge?.onReady(callback.toJS);

void applyUpdate() => _bridge?.apply();
