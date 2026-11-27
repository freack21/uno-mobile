import 'browser_stub.dart'
    if (dart.library.js_interop) 'browser_web.dart'
    as impl;

/// Small browser helpers (no-ops outside the web build).

/// Loads saved settings before the app starts (device storage off the web).
Future<void> initStorage() => impl.initStorage();

String? readStored(String key) => impl.readStored(key);

void writeStored(String key, String? value) => impl.writeStored(key, value);

/// Opens the system share sheet (WhatsApp etc.). Returns false when the
/// browser has none, so the caller can copy the link instead.
Future<bool> shareLink({
  required String title,
  required String text,
  required String url,
}) => impl.shareLink(title: title, text: text, url: url);

/// Matches the browser chrome (address bar, status bar, page behind the
/// app) to the app's background.
void setPageColors({required String background, required bool dark}) =>
    impl.setPageColors(background: background, dark: dark);
