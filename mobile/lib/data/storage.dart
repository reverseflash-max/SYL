import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/models.dart';

/// Reads and writes the SYL data folder. Same layout as the Python tools:
///
///   `data/entities/<id>.json`
///   data/relationships.json
///   data/settings.json
///
/// Where the folder lives:
///  1. the SYL_DATA_DIR environment variable, if set (desktop);
///  2. on Windows, the project's own data folder if it exists, so the app and
///     the `python syl.py ...` tools share one library;
///  3. otherwise a private folder inside the app's documents directory
///     (Android/iOS: data on the phone is separate from the PC copy).
class SylStorage {
  SylStorage._(this.root);

  final Directory root;

  static const String windowsProjectData = r'C:\Users\V\SYL_Project\data';

  static Future<SylStorage> open() async {
    final env = Platform.environment['SYL_DATA_DIR'];
    Directory dir;
    if (env != null && env.isNotEmpty) {
      dir = Directory(env);
    } else if (Platform.isWindows && Directory(windowsProjectData).existsSync()) {
      dir = Directory(windowsProjectData);
    } else {
      final docs = await getApplicationDocumentsDirectory();
      dir = Directory('${docs.path}${Platform.pathSeparator}syl_data');
    }
    final s = SylStorage._(dir);
    await s._entitiesDir.create(recursive: true);
    await s._migrateLooseFiles();
    return s;
  }

  Directory get _entitiesDir => Directory(_join(root.path, 'entities'));
  File get _relationshipsFile => File(_join(root.path, 'relationships.json'));
  File get _settingsFile => File(_join(root.path, 'settings.json'));

  static String _join(String a, String b) =>
      a.endsWith(Platform.pathSeparator) ? '$a$b' : '$a${Platform.pathSeparator}$b';

  File _entityFile(String id) {
    if (!RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(id)) {
      throw ArgumentError('Bad entity id: $id');
    }
    return File(_join(_entitiesDir.path, '$id.json'));
  }

  // ---- entities -----------------------------------------------------------

  Future<List<Entity>> loadEntities() async {
    final out = <Entity>[];
    if (!await _entitiesDir.exists()) return out;
    await for (final f in _entitiesDir.list()) {
      if (f is! File || !f.path.endsWith('.json')) continue;
      final id = f.uri.pathSegments.last.replaceAll('.json', '');
      try {
        final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
        out.add(Entity.fromJson(j, fallbackId: id));
      } catch (e) {
        // One bad file shouldn't hide the whole library.
        // ignore: avoid_print
        print('SYL: could not read ${f.path}: $e');
      }
    }
    out.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return out;
  }

  Future<void> saveEntity(Entity e) async {
    await _writeJson(_entityFile(e.id), e.toJson());
  }

  Future<void> deleteEntity(String id) async {
    final f = _entityFile(id);
    if (await f.exists()) await f.delete();
  }

  bool entityExists(String id) => _entityFile(id).existsSync();

  // ---- relationships ------------------------------------------------------

  Future<List<Relationship>> loadRelationships() async {
    if (!await _relationshipsFile.exists()) return [];
    try {
      final list = jsonDecode(await _relationshipsFile.readAsString()) as List;
      return list
          .whereType<Map<String, dynamic>>()
          .map(Relationship.fromJson)
          .where((r) => r.source.isNotEmpty && r.target.isNotEmpty)
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveRelationships(List<Relationship> rels) =>
      _writeJson(_relationshipsFile, rels.map((r) => r.toJson()).toList());

  // ---- settings -----------------------------------------------------------

  Future<AppSettings> loadSettings() async {
    if (!await _settingsFile.exists()) {
      return AppSettings(
        // On a phone, 127.0.0.1 is the phone itself; the PC's address must be set.
        lmStudioUrl: Platform.isAndroid || Platform.isIOS ? '' : 'http://127.0.0.1:1234',
      );
    }
    try {
      return AppSettings.fromJson(jsonDecode(await _settingsFile.readAsString()) as Map<String, dynamic>);
    } catch (_) {
      return const AppSettings();
    }
  }

  Future<void> saveSettings(AppSettings s) => _writeJson(_settingsFile, s.toJson());

  // ---- helpers ------------------------------------------------------------

  Future<void> _writeJson(File f, Object data) async {
    await f.parent.create(recursive: true);
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(const JsonEncoder.withIndent('  ').convert(data));
    await tmp.rename(f.path);
  }

  /// Files the first app version wrote straight into data/ (e.g. "Frodo Baggins.json")
  /// are moved into entities/ under a proper id. The Python `migrate_data.py`
  /// does the full merge on the PC; this only makes sure nothing is lost on a phone.
  Future<void> _migrateLooseFiles() async {
    if (!await root.exists()) return;
    final backup = Directory(_join(root.path, '_old_v1'));
    await for (final f in root.list()) {
      if (f is! File || !f.path.endsWith('.json')) continue;
      final name = f.uri.pathSegments.last;
      if (name == 'relationships.json' || name == 'settings.json') continue;
      try {
        final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
        final e = Entity.fromJson(j, fallbackId: name.replaceAll('.json', ''));
        if (!entityExists(e.id)) await saveEntity(e);
        await backup.create(recursive: true);
        await f.rename(_join(backup.path, name));
      } catch (_) {
        // leave anything unreadable where it is
      }
    }
  }
}
