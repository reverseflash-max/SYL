import 'dart:convert';

import 'package:http/http.dart' as http;

/// Same logic as syl_wikidata.py: search, fetch the few fields SYL keeps,
/// guess a type from "instance of". It never touches the user's facts.

class WikidataCandidate {
  final String id;
  final String label;
  final String description;
  const WikidataCandidate(this.id, this.label, this.description);
}

class WikidataInfo {
  final String id;
  final String label;
  final String description;
  final List<String> aliases;
  final List<String> instanceOf;
  final String type;

  /// Spoiler-safe details, as "Label: value" lines (see [safeProperties]).
  final List<String> safeFacts;
  const WikidataInfo({
    required this.id,
    required this.label,
    required this.description,
    required this.aliases,
    required this.instanceOf,
    required this.type,
    this.safeFacts = const [],
  });
}

/// Wikidata properties that describe who or what something is without
/// giving the story away. Anything that changes as the story goes on
/// (titles, spouse, children, allies, enemies, what they come to own, which
/// later books they appear in) is left out on purpose.
const safeProperties = <(String, String)>[
  ('P172', 'People'), // ethnic group: Dúnedain, Hobbits
  ('P21', 'Gender'),
  ('P1080', 'World'), // from narrative universe: Middle-earth
  ('P4584', 'First appears in'),
  ('P1412', 'Speaks'),
  ('P170', 'Created by'),
];

class WikidataException implements Exception {
  final String message;
  WikidataException(this.message);
  @override
  String toString() => message;
}

const _typeKeywords = <String, List<String>>{
  'Character': ['character', 'human', 'person', 'elf', 'dwarf', 'hobbit', 'wizard', 'deity', 'god',
    'being', 'creature', 'orc', 'dragon', 'mistborn', 'hero', 'king', 'queen'],
  'Location': ['location', 'locality', 'city', 'town', 'village', 'realm', 'kingdom', 'country',
    'region', 'place', 'fortress', 'castle', 'forest', 'mountain', 'river', 'continent', 'world',
    'planet', 'capital', 'island', 'tower', 'sea', 'lake', 'valley', 'land'],
  'Item': ['item', 'object', 'weapon', 'sword', 'artifact', 'artefact', 'ring', 'jewel', 'gem',
    'book', 'armour', 'armor', 'staff', 'ship', 'vehicle'],
  'Lore': ['organization', 'organisation', 'group', 'order', 'language', 'event', 'war', 'battle',
    'religion', 'magic', 'race', 'species', 'people'],
};

String guessType(List<String> labels) {
  final text = ' ${labels.join(' ').toLowerCase()}';
  for (final entry in _typeKeywords.entries) {
    for (final w in entry.value) {
      if (text.contains(' $w')) return entry.key;
    }
  }
  return 'Other';
}

class WikidataService {
  WikidataService({http.Client? client}) : _client = client ?? http.Client();
  final http.Client _client;

  static const _api = 'www.wikidata.org';
  static const _headers = {
    'User-Agent': 'SYL/0.2 (personal fantasy reading companion)',
    'Accept': 'application/json',
  };
  static const _fictionHints = ['fictional', 'character', 'legendarium', 'middle-earth', 'novel',
    'fantasy', 'series', 'saga', 'book'];
  // Adaptations share names with the book version; prefer the literary one.
  static const _adaptationHints = ['musical', 'film', 'television', 'tv series', 'video game', 'opera',
    'stage', 'actor', 'actress', 'band', 'album', 'song'];

  Future<Map<String, dynamic>> _get(Uri uri) async {
    try {
      final r = await _client.get(uri, headers: _headers).timeout(const Duration(seconds: 20));
      if (r.statusCode != 200) throw WikidataException('Wikidata returned HTTP ${r.statusCode}');
      return jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
    } on WikidataException {
      rethrow;
    } catch (e) {
      throw WikidataException("Couldn't reach Wikidata. Check your connection.");
    }
  }

  /// Fiction-looking results (and ones matching [hint], e.g. the book) come first.
  Future<List<WikidataCandidate>> search(String name, {String? hint}) async {
    final data = await _get(Uri.https(_api, '/w/api.php', {
      'action': 'wbsearchentities',
      'search': name,
      'language': 'en',
      'uselang': 'en',
      'type': 'item',
      'limit': '7',
      'format': 'json',
    }));
    final hits = (data['search'] as List? ?? []).whereType<Map<String, dynamic>>().toList();
    final hintWords = (hint ?? '').toLowerCase().split(' ').where((w) => w.length > 3).toList();
    final scored = <(int, int, WikidataCandidate)>[];
    for (var i = 0; i < hits.length; i++) {
      final h = hits[i];
      final desc = (h['description'] ?? '').toString();
      final low = desc.toLowerCase();
      var score = 0;
      if (_fictionHints.any(low.contains)) score += 2;
      if (_adaptationHints.any(low.contains)) score -= 3;
      if (hintWords.any(low.contains)) score += 1;
      if ((h['label'] ?? '').toString().toLowerCase() == name.toLowerCase()) score += 1;
      scored.add((score, i, WikidataCandidate(h['id'].toString(), (h['label'] ?? '').toString(), desc)));
    }
    scored.sort((a, b) => a.$1 != b.$1 ? b.$1.compareTo(a.$1) : a.$2.compareTo(b.$2));
    return scored.map((s) => s.$3).toList();
  }

  Future<WikidataInfo> fetch(String qid) async {
    final data = await _get(Uri.https(_api, '/wiki/Special:EntityData/$qid.json'));
    final ents = (data['entities'] as Map<String, dynamic>? ?? {});
    final ent = (ents[qid] ?? (ents.isNotEmpty ? ents.values.first : null)) as Map<String, dynamic>?;
    if (ent == null) throw WikidataException('$qid not found on Wikidata');
    final realId = (ent['id'] ?? qid).toString();
    String label = realId;
    final labels = ent['labels'] as Map<String, dynamic>? ?? {};
    if (labels['en'] != null) {
      label = labels['en']['value'].toString();
    } else if (labels.isNotEmpty) {
      label = (labels.values.first as Map)['value'].toString();
    }
    final desc = ((ent['descriptions'] as Map<String, dynamic>? ?? {})['en']?['value'] ?? '').toString();
    final aliases = ((ent['aliases'] as Map<String, dynamic>? ?? {})['en'] as List? ?? [])
        .map((a) => (a as Map)['value'].toString())
        .toList();
    final claims = ent['claims'] as Map<String, dynamic>? ?? {};
    List<String> ids(String prop) => [
          for (final c in (claims[prop] as List? ?? []))
            if ((c as Map)['mainsnak']?['datavalue']?['value'] case {'id': final id}) id.toString(),
        ];
    final p31 = ids('P31');
    final safe = {for (final (prop, _) in safeProperties) prop: ids(prop)};
    // One lookup for every label we need.
    final names = await _labelMap([...p31, for (final v in safe.values) ...v]);
    final instanceLabels = [for (final id in p31) names[id] ?? id];
    return WikidataInfo(
      id: realId,
      label: label,
      description: desc,
      aliases: aliases,
      instanceOf: instanceLabels,
      type: guessType(instanceLabels),
      safeFacts: [
        for (final (prop, name) in safeProperties)
          if (safe[prop]!.isNotEmpty) '$name: ${safe[prop]!.map((id) => names[id] ?? id).join(', ')}',
      ],
    );
  }

  Future<Map<String, String>> _labelMap(List<String> ids) async {
    if (ids.isEmpty) return {};
    final data = await _get(Uri.https(_api, '/w/api.php', {
      'action': 'wbgetentities',
      'ids': ids.take(50).join('|'),
      'props': 'labels',
      'languages': 'en',
      'format': 'json',
    }));
    final ents = data['entities'] as Map<String, dynamic>? ?? {};
    return {
      for (final id in ids)
        if (ents.containsKey(id)) id: ((ents[id] as Map)['labels']?['en']?['value'] ?? id).toString(),
    };
  }
}
