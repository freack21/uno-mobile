// Removes the app-only sound files from the web build's offline cache list:
// the web synthesizes its sounds (web/sfx.js), so they are never needed.
import 'dart:convert';
import 'dart:io';

void main() {
  final file = File('build/web/precache_manifest.json');
  final manifest = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  final entries = manifest['entries'] as List;
  entries.removeWhere(
    (e) => (e['url'] as String).startsWith('assets/assets/sfx/'),
  );
  file.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(manifest));
}
