// SYL data models. The JSON shape is shared with the Python tools
// (see syl_core.py in the project root): snake_case keys, schema_version 2.
//
// Parsing is deliberately forgiving: it also reads the older camelCase files
// the first version of this app wrote, so nothing silently disappears.

const int kSchemaVersion = 2;
const List<String> kEntityTypes = ['Character', 'Location', 'Item', 'Lore', 'Other'];

T? _pick<T>(Map<String, dynamic> j, List<String> keys) {
  for (final k in keys) {
    final v = j[k];
    if (v != null && v is T) return v;
  }
  return null;
}

String _str(Map<String, dynamic> j, List<String> keys, [String fallback = '']) {
  for (final k in keys) {
    final v = j[k];
    if (v != null) return v.toString();
  }
  return fallback;
}

/// "Chapter 3", "3", 3, null -> int
int parseChapter(Object? v, [int fallback = 1]) {
  if (v is int) return v;
  if (v is double) return v.toInt();
  if (v is String) {
    final m = RegExp(r'\d+').firstMatch(v);
    if (m != null) return int.parse(m.group(0)!);
  }
  return fallback;
}

String normalizeType(Object? v) {
  if (v is! String || v.trim().isEmpty) return 'Other';
  final s = v.trim().toLowerCase();
  for (final t in kEntityTypes) {
    if (s == t.toLowerCase() || s == '${t.toLowerCase()}s') return t;
  }
  if (s == 'place' || s == 'places') return 'Location';
  return 'Other';
}

String nowIso() {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day, n.hour, n.minute, n.second).toIso8601String().split('.').first;
}

String slugify(String name) {
  final s = name
      .toLowerCase()
      .replaceAll(RegExp(r'[àáâãäå]'), 'a')
      .replaceAll(RegExp(r'[èéêë]'), 'e')
      .replaceAll(RegExp(r'[ìíîï]'), 'i')
      .replaceAll(RegExp(r'[òóôõö]'), 'o')
      .replaceAll(RegExp(r'[ùúûü]'), 'u')
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  return s.isEmpty ? 'entity' : s;
}

bool isQid(String? v) => v != null && RegExp(r'^Q\d+$').hasMatch(v.trim());

class Fact {
  final String id;
  final String text;
  final int chapter;
  final String timestamp;
  final String source;

  const Fact({
    required this.id,
    required this.text,
    required this.chapter,
    required this.timestamp,
    this.source = 'user',
  });

  factory Fact.create(String text, int chapter) => Fact(
        id: 'f_${DateTime.now().microsecondsSinceEpoch.toRadixString(16)}',
        text: text.trim(),
        chapter: chapter,
        timestamp: nowIso(),
      );

  factory Fact.fromJson(Map<String, dynamic> j) => Fact(
        id: _str(j, ['id'], 'f_${j.hashCode.toRadixString(16)}'),
        text: _str(j, ['text']).trim(),
        chapter: parseChapter(j['chapter']),
        timestamp: _str(j, ['timestamp'], nowIso()).replaceFirst(' ', 'T'),
        source: _str(j, ['source'], 'user'),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'text': text,
        'chapter': chapter,
        'timestamp': timestamp,
        'source': source,
      };
}

class Lore {
  final String description;
  final String biography;
  final List<String> tags;
  final String? generatedAt;
  final String? model;
  final int? spoilerLimitChapter;

  const Lore({
    this.description = '',
    this.biography = '',
    this.tags = const [],
    this.generatedAt,
    this.model,
    this.spoilerLimitChapter,
  });

  bool get isEmpty => biography.trim().isEmpty && description.trim().isEmpty;

  factory Lore.fromJson(Map<String, dynamic>? j) {
    if (j == null) return const Lore();
    final rawTags = _pick<List>(j, ['lore_tags', 'loreTags']) ?? const [];
    return Lore(
      description: _str(j, ['description']),
      biography: _str(j, ['biography']),
      tags: rawTags.map((e) => e.toString()).toList(),
      generatedAt: _pick<String>(j, ['generated_at']),
      model: _pick<String>(j, ['model']),
      spoilerLimitChapter: j['spoiler_limit_chapter'] == null ? null : parseChapter(j['spoiler_limit_chapter']),
    );
  }

  Map<String, dynamic> toJson() => {
        'description': description,
        'biography': biography,
        'lore_tags': tags,
        'generated_at': generatedAt,
        'model': model,
        'spoiler_limit_chapter': spoilerLimitChapter,
      };
}

class ExternalData {
  final String? wikidataId;
  final String description;
  final List<String> aliases;
  final List<String> instanceOf;

  const ExternalData({
    this.wikidataId,
    this.description = '',
    this.aliases = const [],
    this.instanceOf = const [],
  });

  factory ExternalData.fromJson(Map<String, dynamic>? j) {
    if (j == null) return const ExternalData();
    final id = _pick<String>(j, ['wikidata_id', 'wikidataId']);
    return ExternalData(
      wikidataId: isQid(id) ? id : null,
      description: _str(j, ['description']),
      aliases: (_pick<List>(j, ['aliases']) ?? const []).map((e) => e.toString()).toList(),
      instanceOf: (_pick<List>(j, ['instance_of']) ?? const []).map((e) => e.toString()).toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'wikidata_id': wikidataId,
        'description': description,
        'aliases': aliases,
        'instance_of': instanceOf,
      };
}

class EntityMeta {
  final String firstSeen;
  final String lastUpdated;
  final String status;
  final String source;

  const EntityMeta({
    required this.firstSeen,
    required this.lastUpdated,
    this.status = 'active',
    this.source = 'manual',
  });

  factory EntityMeta.fresh(String source) {
    final now = nowIso();
    return EntityMeta(firstSeen: now.substring(0, 10), lastUpdated: now, source: source);
  }

  factory EntityMeta.fromJson(Map<String, dynamic>? j) {
    if (j == null) return EntityMeta.fresh('manual');
    final first = _str(j, ['first_seen', 'firstSeen'], nowIso());
    return EntityMeta(
      firstSeen: first.length >= 10 ? first.substring(0, 10) : first,
      lastUpdated: _str(j, ['last_updated', 'lastUpdated'], nowIso()),
      status: _str(j, ['status'], 'active').toLowerCase(),
      source: _str(j, ['source'], 'manual'),
    );
  }

  Map<String, dynamic> toJson() => {
        'first_seen': firstSeen,
        'last_updated': lastUpdated,
        'status': status,
        'source': source,
      };
}

class Entity {
  final String id;
  final String name;
  final String type;
  final String? book;
  final int discoveryChapter;
  final List<Fact> facts;
  final Lore lore;
  final ExternalData external;
  final EntityMeta meta;

  const Entity({
    required this.id,
    required this.name,
    required this.type,
    this.book,
    this.discoveryChapter = 1,
    this.facts = const [],
    this.lore = const Lore(),
    this.external = const ExternalData(),
    required this.meta,
  });

  factory Entity.create({
    required String name,
    String type = 'Other',
    String? book,
    int discoveryChapter = 1,
    String? wikidataId,
    String source = 'manual',
  }) {
    return Entity(
      id: wikidataId ?? slugify(name),
      name: name.trim(),
      type: normalizeType(type),
      book: (book == null || book.trim().isEmpty) ? null : book.trim(),
      discoveryChapter: discoveryChapter,
      external: ExternalData(wikidataId: wikidataId),
      meta: EntityMeta.fresh(source),
    );
  }

  factory Entity.fromJson(Map<String, dynamic> j, {String? fallbackId}) {
    final ext = ExternalData.fromJson(_pick<Map<String, dynamic>>(j, ['external_data', 'externalData']));
    final name = _str(j, ['name'], fallbackId ?? 'Unnamed').trim();
    final factsRaw = _pick<List>(j, ['user_captured_facts', 'userCapturedFacts']) ?? const [];
    final facts = factsRaw
        .whereType<Map<String, dynamic>>()
        .map(Fact.fromJson)
        .where((f) => f.text.isNotEmpty)
        .toList()
      ..sort((a, b) => a.chapter != b.chapter ? a.chapter.compareTo(b.chapter) : a.timestamp.compareTo(b.timestamp));
    return Entity(
      id: _pick<String>(j, ['id']) ?? ext.wikidataId ?? (isQid(fallbackId) ? fallbackId! : slugify(name)),
      name: name,
      type: normalizeType(j['type']),
      book: _pick<String>(j, ['book']),
      discoveryChapter: parseChapter(j['discovery_chapter'] ?? j['discoveryChapter']),
      facts: facts,
      lore: Lore.fromJson(_pick<Map<String, dynamic>>(j, ['ai_lore_enhancement', 'aiLoreEnhancement'])),
      external: ext,
      meta: EntityMeta.fromJson(_pick<Map<String, dynamic>>(j, ['metadata'])),
    );
  }

  Map<String, dynamic> toJson() => {
        'schema_version': kSchemaVersion,
        'id': id,
        'name': name,
        'type': type,
        'book': book,
        'discovery_chapter': discoveryChapter,
        'user_captured_facts': facts.map((f) => f.toJson()).toList(),
        'ai_lore_enhancement': lore.toJson(),
        'external_data': external.toJson(),
        'metadata': meta.toJson(),
      };

  Entity copyWith({
    String? name,
    String? type,
    String? book,
    bool clearBook = false,
    int? discoveryChapter,
    List<Fact>? facts,
    Lore? lore,
    ExternalData? external,
    EntityMeta? meta,
  }) {
    return Entity(
      id: id,
      name: name ?? this.name,
      type: type ?? this.type,
      book: clearBook ? null : (book ?? this.book),
      discoveryChapter: discoveryChapter ?? this.discoveryChapter,
      facts: facts ?? this.facts,
      lore: lore ?? this.lore,
      external: external ?? this.external,
      meta: meta ?? this.meta,
    );
  }

  /// Facts the reader is allowed to see with the spoiler shield at [cap].
  List<Fact> visibleFacts(int? cap) => cap == null ? facts : facts.where((f) => f.chapter <= cap).toList();

  /// Every name this entity is known by (for finding mentions in facts).
  List<String> get names => [name, name.split(' ').first, ...external.aliases].where((n) => n.length >= 3).toList();

  String get initial => name.isEmpty ? '?' : String.fromCharCode(name.runes.first).toUpperCase();
}

class Relationship {
  final String source;
  final String target;
  final String type;
  final String description;
  final int? chapter;
  final String createdAt;

  const Relationship({
    required this.source,
    required this.target,
    required this.type,
    this.description = '',
    this.chapter,
    required this.createdAt,
  });

  factory Relationship.fromJson(Map<String, dynamic> j) => Relationship(
        source: _str(j, ['source', 'sourceEntityId']),
        target: _str(j, ['target', 'targetEntityId']),
        type: _str(j, ['type', 'relationType'], 'Related to'),
        description: _str(j, ['description']),
        chapter: j['chapter'] == null ? null : parseChapter(j['chapter']),
        createdAt: _str(j, ['created_at'], nowIso()).replaceFirst(' ', 'T'),
      );

  Map<String, dynamic> toJson() => {
        'source': source,
        'target': target,
        'type': type,
        'description': description,
        'chapter': chapter,
        'created_at': createdAt,
      };

  bool involves(String id) => source == id || target == id;
  String other(String id) => source == id ? target : source;
}

class AppSettings {
  final String? currentBook;
  final int? spoilerChapter;
  final String lmStudioUrl;
  final String lmModel;

  const AppSettings({
    this.currentBook,
    this.spoilerChapter,
    this.lmStudioUrl = 'http://127.0.0.1:1234',
    this.lmModel = '',
  });

  factory AppSettings.fromJson(Map<String, dynamic> j) => AppSettings(
        currentBook: _pick<String>(j, ['current_book']),
        spoilerChapter: j['spoiler_chapter'] == null ? null : parseChapter(j['spoiler_chapter']),
        lmStudioUrl: _str(j, ['lm_studio_url'], 'http://127.0.0.1:1234'),
        lmModel: _str(j, ['lm_model']),
      );

  Map<String, dynamic> toJson() => {
        'current_book': currentBook,
        'spoiler_chapter': spoilerChapter,
        'lm_studio_url': lmStudioUrl,
        'lm_model': lmModel,
      };

  AppSettings copyWith({
    String? currentBook,
    bool clearBook = false,
    int? spoilerChapter,
    bool clearSpoiler = false,
    String? lmStudioUrl,
    String? lmModel,
  }) =>
      AppSettings(
        currentBook: clearBook ? null : (currentBook ?? this.currentBook),
        spoilerChapter: clearSpoiler ? null : (spoilerChapter ?? this.spoilerChapter),
        lmStudioUrl: lmStudioUrl ?? this.lmStudioUrl,
        lmModel: lmModel ?? this.lmModel,
      );
}
