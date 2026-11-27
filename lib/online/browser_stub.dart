import 'dart:io' show Platform;

import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The app on Android (and iOS): device storage, the system share sheet and
/// the status bar. Tests run here too, with storage kept in memory.

final _memory = <String, String>{};
SharedPreferences? _prefs;

bool get _device => Platform.isAndroid || Platform.isIOS;

Future<void> initStorage() async {
  if (!_device) return;
  try {
    _prefs = await SharedPreferences.getInstance();
  } catch (_) {
    // Storage unavailable: settings last for this run only.
  }
}

String? readStored(String key) => _prefs?.getString(key) ?? _memory[key];

void writeStored(String key, String? value) {
  if (value == null) {
    _memory.remove(key);
    _prefs?.remove(key);
  } else {
    _memory[key] = value;
    _prefs?.setString(key, value);
  }
}

Future<bool> shareLink({
  required String title,
  required String text,
  required String url,
}) async {
  if (!_device) return false;
  try {
    await SharePlus.instance.share(
      ShareParams(text: '$text $url', subject: title),
    );
    return true;
  } catch (_) {
    return false;
  }
}

void setPageColors({required String background, required bool dark}) {
  if (!_device) return;
  final ink = Color(int.parse('FF${background.substring(1)}', radix: 16));
  // Draw behind the status bar (the app keeps clear of it with SafeArea), so
  // it shows the table color instead of a grey strip on older Android.
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(
    SystemUiOverlayStyle(
      statusBarColor: const Color(0x00000000),
      statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
      statusBarBrightness: dark ? Brightness.dark : Brightness.light,
      systemNavigationBarColor: ink,
      systemNavigationBarIconBrightness: dark
          ? Brightness.light
          : Brightness.dark,
    ),
  );
}
