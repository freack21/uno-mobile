{{flutter_js}}
{{flutter_build_config}}

// Flutter's own service worker is deprecated (it only unregisters itself), so
// it is not registered here; offline support comes from sw.js instead.
_flutter.loader.load();
