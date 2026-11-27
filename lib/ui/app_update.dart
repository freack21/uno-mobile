import 'package:material_ui/material_ui.dart';

import 'app_update_stub.dart'
    if (dart.library.js_interop) 'app_update_web.dart'
    as platform;

/// True once a newer version of the web app is downloaded and waiting.
final updateReady = ValueNotifier<bool>(false);

/// Starts listening for app updates (no-op outside the web build).
void watchForUpdates() =>
    platform.onUpdateReady(() => updateReady.value = true);

/// Activates the waiting version and reloads the app.
void applyUpdate() => platform.applyUpdate();
