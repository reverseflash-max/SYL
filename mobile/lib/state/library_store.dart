import 'package:flutter/foundation.dart';

import '../data/storage.dart';
import '../models/models.dart';
import '../services/ai_service.dart';
import '../services/wikidata_service.dart';

/// The single source of app state. Screens read it with
/// `context.watch<LibraryStore>()` and call its methods to change things;
/// every change is written straight to disk.
class LibraryStore extends ChangeNotifier {
  LibraryStore({WikidataService? wikidata, AiService? ai})
      : wikidata = wikidata ?? WikidataService(),
        ai = ai ?? AiService();

  /// In-memory store for tests and previews: nothing is written to disk.
  LibraryStore.memory({
    List<Entity> entities = const [],
    List<Relationship> relationships = const [],
    AppSettings settings = const AppSettings(),
  })  : wikidata = WikidataService(),
        ai = AiService(),
        _memoryOnly = true {
    _entities = [...entities];
    _relationships = [...relationships];
    _settings = settings;
    _loading = false;
  }

  bool _memoryOnly = false;
  final WikidataService wikidata;
  final AiService ai;
  SylStorage? _storage;

  List<Entity> _entities = [];
  List<Relationship> _relationships = [];
  AppSettings _settings = const AppSettings();
  bool _loading = true;
  String? _error;
  final Set<String> _busy = {}; // entity ids with an AI/Wikidata call in flight

  List<Entity> get entities => List.unmodifiable(_entities);
  List<Relationship> get relationships => List.unmodifiable(_relationships);
  AppSettings get settings => _settings;
  bool get loading => _loading;
  String? get error => _error;
  String get dataPath => _storage?.root.path ?? '';
  bool isBusy(String id) => _busy.contains(id);
  int? get spoilerChapter => _settings.spoilerChapter;

  Future<void> load() async {
    if (_memoryOnly) return;
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _storage ??= await SylStorage.open();
      _entities = await _storage!.loadEntities();
      _relationships = await _storage!.loadRelationships();
      _settings = await _storage!.loadSettings();
    } catch (e) {
      _error = 'Could not open the SYL library: $e';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  // ---- lookups --------------------------------------------------------------

  Entity? byId(String id) {
    for (final e in _entities) {
      if (e.id == id) return e;
    }
    return null;
  }

  Entity? byName(String name) {
    final n = name.trim().toLowerCase();
    for (final e in _entities) {
      if (e.name.toLowerCase() == n || e.external.aliases.any((a) => a.toLowerCase() == n)) return e;
    }
    return null;
  }

  List<String> get books {
    final s = <String>{
      for (final e in _entities)
        if (e.book != null) e.book!,
      if (_settings.currentBook != null) _settings.currentBook!,
    };
    return s.toList()..sort();
  }

  int get visibleFactCount => _entities.fold(0, (n, e) => n + e.visibleFacts(spoilerChapter).length);

  List<Relationship> linksFor(String id) => _relationships
      .where((r) => r.involves(id) && (spoilerChapter == null || r.chapter == null || r.chapter! <= spoilerChapter!))
      .toList();

  /// Other entities whose name or alias shows up in [e]'s visible facts.
  List<Entity> mentionsIn(Entity e) {
    final text = e.visibleFacts(spoilerChapter).map((f) => f.text).join(' ');
    if (text.isEmpty) return [];
    return _entities.where((o) {
      if (o.id == e.id) return false;
      return o.names.any((n) => RegExp('\\b${RegExp.escape(n)}\\b', caseSensitive: false).hasMatch(text));
    }).toList();
  }

  /// Entities that mention [e] in their facts (backlinks).
  List<Entity> mentionedBy(Entity e) => _entities.where((o) => o.id != e.id && mentionsIn(o).any((m) => m.id == e.id)).toList();

  List<Entity> search(String q, {String? type}) {
    final query = q.trim().toLowerCase();
    return _entities.where((e) {
      if (type != null && e.type != type) return false;
      if (query.isEmpty) return true;
      if (e.name.toLowerCase().contains(query)) return true;
      if (e.external.aliases.any((a) => a.toLowerCase().contains(query))) return true;
      if (e.lore.tags.any((t) => t.toLowerCase().contains(query))) return true;
      return e.visibleFacts(spoilerChapter).any((f) => f.text.toLowerCase().contains(query));
    }).toList();
  }

  // ---- mutations ------------------------------------------------------------

  Future<void> _put(Entity e) async {
    final updated = e.copyWith(meta: EntityMeta(
      firstSeen: e.meta.firstSeen,
      lastUpdated: nowIso(),
      status: e.meta.status,
      source: e.meta.source,
    ));
    await _storage?.saveEntity(updated);
    final i = _entities.indexWhere((x) => x.id == e.id);
    if (i >= 0) {
      _entities[i] = updated;
    } else {
      _entities.add(updated);
      _entities.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    }
    notifyListeners();
  }

  /// Creates an entity; returns the existing one if the name is taken.
  Future<Entity> createEntity({
    required String name,
    required String type,
    String? book,
    int chapter = 1,
    WikidataInfo? wikidataInfo,
  }) async {
    final existing = byName(name) ?? (wikidataInfo == null ? null : byId(wikidataInfo.id));
    if (existing != null) return existing;
    var id = wikidataInfo?.id ?? slugify(name);
    var n = 2;
    while (byId(id) != null || (_storage?.entityExists(id) ?? false)) {
      id = '${slugify(name)}-${n++}';
    }
    var e = Entity.create(
      name: name,
      type: type,
      book: book ?? _settings.currentBook,
      discoveryChapter: chapter,
      source: wikidataInfo == null ? 'manual' : 'wikidata',
    );
    e = Entity(id: id, name: e.name, type: e.type, book: e.book, discoveryChapter: e.discoveryChapter, meta: e.meta);
    if (wikidataInfo != null) e = _applyWikidata(e, wikidataInfo);
    await _put(e);
    return e;
  }

  Future<void> updateEntity(Entity e) => _put(e);

  Future<void> deleteEntity(String id) async {
    await _storage?.deleteEntity(id);
    _entities.removeWhere((e) => e.id == id);
    _relationships.removeWhere((r) => r.involves(id));
    await _storage?.saveRelationships(_relationships);
    notifyListeners();
  }

  Future<void> addFact(Entity e, String text, int chapter) async {
    final current = byId(e.id) ?? e;
    final t = text.trim();
    if (t.isEmpty) return;
    final dup = current.facts.any((f) => f.chapter == chapter && f.text.toLowerCase() == t.toLowerCase());
    if (dup) return;
    final facts = [...current.facts, Fact.create(t, chapter)]
      ..sort((a, b) => a.chapter != b.chapter ? a.chapter.compareTo(b.chapter) : a.timestamp.compareTo(b.timestamp));
    await _put(current.copyWith(
      facts: facts,
      discoveryChapter: chapter < current.discoveryChapter ? chapter : current.discoveryChapter,
    ));
  }

  Future<void> removeFact(Entity e, String factId) async {
    final current = byId(e.id) ?? e;
    await _put(current.copyWith(facts: current.facts.where((f) => f.id != factId).toList()));
  }

  Future<void> addLink(String source, String target, String type, {String description = '', int? chapter}) async {
    if (source == target) return;
    final exists = _relationships.any(
        (r) => r.source == source && r.target == target && r.type.toLowerCase() == type.toLowerCase());
    if (exists) return;
    _relationships.add(Relationship(
      source: source,
      target: target,
      type: type.trim(),
      description: description.trim(),
      chapter: chapter,
      createdAt: nowIso(),
    ));
    await _storage?.saveRelationships(_relationships);
    notifyListeners();
  }

  Future<void> removeLink(Relationship r) async {
    _relationships.removeWhere((x) => x.source == r.source && x.target == r.target && x.type == r.type);
    await _storage?.saveRelationships(_relationships);
    notifyListeners();
  }

  Future<void> updateSettings(AppSettings s) async {
    _settings = s;
    await _storage?.saveSettings(s);
    notifyListeners();
  }

  // ---- Wikidata -------------------------------------------------------------

  Entity _applyWikidata(Entity e, WikidataInfo w) => e.copyWith(
        type: e.type == 'Other' ? w.type : e.type,
        external: ExternalData(
          wikidataId: w.id,
          description: w.description,
          aliases: {...e.external.aliases, ...w.aliases}.toList()..sort(),
          instanceOf: w.instanceOf,
        ),
      );

  /// Link an existing entity to a Wikidata item; the user's facts are kept.
  Future<void> linkWikidata(Entity e, String qid) async {
    _busy.add(e.id);
    notifyListeners();
    try {
      final info = await wikidata.fetch(qid);
      await _put(_applyWikidata(byId(e.id) ?? e, info));
    } finally {
      _busy.remove(e.id);
      notifyListeners();
    }
  }

  // ---- AI -------------------------------------------------------------------

  List<String> _connectionsText(Entity e) {
    final out = <String>[];
    for (final r in linksFor(e.id)) {
      final other = byId(r.other(e.id));
      if (other == null) continue;
      out.add(r.source == e.id ? '${r.type} of ${other.name}' : '${other.name} is ${r.type} of this entity');
    }
    return out;
  }

  Future<void> generateLore(Entity e) async {
    _busy.add(e.id);
    notifyListeners();
    try {
      final current = byId(e.id) ?? e;
      final lore = await ai.generateLore(e: current, connections: _connectionsText(current), settings: _settings);
      await _put(current.copyWith(lore: lore));
    } finally {
      _busy.remove(e.id);
      notifyListeners();
    }
  }
}
