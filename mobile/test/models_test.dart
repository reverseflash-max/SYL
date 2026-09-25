import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/models/models.dart';
import 'package:mobile/services/wikidata_service.dart';

void main() {
  test('reads the old CLI snake_case format', () {
    final e = Entity.fromJson({
      'name': 'Kelsier',
      'type': 'Entity',
      'discovery_chapter': 'Chapter 1',
      'user_captured_facts': [
        {'text': 'He stole from the rich to help the poor', 'chapter': 'Chapter 5', 'timestamp': '2026-09-19 21:46:29'},
      ],
      'ai_lore_enhancement': {'description': 'x', 'biography': 'y', 'lore_tags': ['Poor']},
      'external_data': {'wikidata_id': 'Q18535363', 'description': 'fictional character'},
      'metadata': {'first_seen': '2026-09-19', 'last_updated': '2026-09-19', 'status': 'Active'},
    }, fallbackId: 'Q18535363');
    expect(e.id, 'Q18535363');
    expect(e.discoveryChapter, 1);
    expect(e.facts.single.chapter, 5);
    expect(e.type, 'Other');
    expect(e.lore.tags, ['Poor']);
  });

  test('reads the old app camelCase format', () {
    final e = Entity.fromJson({
      'name': 'Frodo Baggins',
      'type': 'Character',
      'discoveryChapter': 1,
      'userCapturedFacts': [],
      'aiLoreEnhancement': {'description': '', 'biography': '', 'loreTags': []},
      'externalData': {'wikidataId': '', 'description': ''},
      'metadata': {'firstSeen': '2026-09-22T04:07:47.626098', 'lastUpdated': '2026-09-22T04:07:47'},
      'relationships': [],
    }, fallbackId: 'Frodo Baggins');
    expect(e.id, 'frodo-baggins');
    expect(e.type, 'Character');
    expect(e.external.wikidataId, isNull);
    expect(e.meta.firstSeen, '2026-09-22');
  });

  test('round-trips v2 json', () {
    final e = Entity.create(name: 'Galadriel', type: 'character', book: 'LOTR', wikidataId: 'Q204274')
        .copyWith(facts: [Fact.create('She is from Lothlórien', 1)]);
    final back = Entity.fromJson(e.toJson());
    expect(back.id, 'Q204274');
    expect(back.type, 'Character');
    expect(back.facts.single.text, 'She is from Lothlórien');
    expect(e.toJson()['schema_version'], 2);
  });

  test('spoiler shield hides later facts', () {
    final e = Entity.create(name: 'Aragorn').copyWith(facts: [
      Fact.create('heir', 1),
      Fact.create('king', 5),
    ]);
    expect(e.visibleFacts(3).map((f) => f.text), ['heir']);
    expect(e.visibleFacts(null).length, 2);
  });

  test('guesses types from Wikidata instance-of labels', () {
    expect(guessType(['Middle-earth elf']), 'Character');
    expect(guessType(['Middle-earth locality']), 'Location');
    expect(guessType(['fictional sword']), 'Item');
    expect(guessType(['rock band']), 'Other');
  });

  test('slugify', () {
    expect(slugify('Frodo Baggins'), 'frodo-baggins');
    expect(slugify('Lothlórien'), 'lothlorien');
  });
}
