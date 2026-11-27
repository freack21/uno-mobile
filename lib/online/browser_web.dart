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

void setPageColors({required String background, required bool dark}) {
  try {
    final doc = web.document;
    void meta(String name, String content) {
      final el = doc.querySelector('meta[name="$name"]');
      if (el != null) (el as web.HTMLMetaElement).content = content;
    }

    meta('theme-color', background);
    meta('color-scheme', dark ? 'dark' : 'light');
    doc.documentElement?.setAttribute('style', 'background: $background');
    doc.body?.style.background = background;
  } catch (_) {
    // Cosmetic only.
  }
}
