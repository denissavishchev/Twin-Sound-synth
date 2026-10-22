import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Keeps the panel settings (every slider, the wave switches, the octaves of
/// both halves) in one small JSON file in the app's documents folder, so they
/// are restored the next time the app starts.
class SettingsStore {
  /// [root] overrides the folder (tests); [enabled] = false makes load/save
  /// no-ops (widget tests, where there is no platform storage).
  // ignore: prefer_initializing_formals
  SettingsStore({Directory? root, this.enabled = true}) : _root = root;

  final bool enabled;
  Directory? _root;

  Future<File> _file() async {
    _root ??= await getApplicationDocumentsDirectory();
    return File(p.join(_root!.path, 'twin_sound_settings.json'));
  }

  /// The stored settings, or null if there are none / the file is unreadable.
  Future<Map<String, dynamic>?> load() async {
    if (!enabled) return null;
    try {
      final f = await _file();
      if (!f.existsSync()) return null;
      return Map<String, dynamic>.from(jsonDecode(await f.readAsString()) as Map);
    } catch (_) {
      return null; // corrupt file: start from the defaults
    }
  }

  /// Writes atomically (temp file + rename) so a crash can't leave half a file.
  Future<void> save(Map<String, dynamic> data) async {
    if (!enabled) return;
    try {
      final f = await _file();
      final tmp = File('${f.path}.tmp');
      await tmp.writeAsString(jsonEncode(data), flush: true);
      await tmp.rename(f.path);
    } catch (_) {
      // best effort: never break playing because storage failed
    }
  }
}
