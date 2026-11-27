import 'dart:js_interop';

import 'package:web/web.dart' as web;

String? readStored(String key) {
  try {
    return web.window.localStorage.getItem(key);
  } catch (_) {
    return null;
  }
}

void writeStored(String key, String? value) {
  try {
    if (value == null) {
      web.window.localStorage.removeItem(key);
    } else {
      web.window.localStorage.setItem(key, value);
    }
  } catch (_) {
    // Private mode or blocked storage: the session just won't be resumable.
  }
}

Future<bool> shareLink({
  required String title,
  required String text,
  required String url,
}) async {
  final data = web.ShareData(title: title, text: text, url: url);
  final nav = web.window.navigator;
  try {
    if (!nav.canShare(data)) return false;
    await nav.share(data).toDart;
    return true;
  } catch (_) {
    // No share sheet, or the user closed it.
    return false;
  }
}
