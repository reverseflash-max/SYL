import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mobile/models/models.dart';
import 'package:mobile/services/ai_service.dart';
import 'package:mobile/services/sync_service.dart';
import 'package:mobile/state/library_store.dart';

Entity ent(String id, String name, [List<Fact> facts = const []]) => Entity(
      id: id,
      name: name,
      type: 'Character',
      facts: facts,
      meta: const EntityMeta(firstSeen: '2026-10-01', lastUpdated: '2026-10-01T10:00:00'),
    );

Fact fact(String id, String text, int ch) => Fact(id: id, text: text, chapter: ch, timestamp: '2026-10-01T09:00:00');

void main() {
  test('settings and deleted log round-trip', () {
    final s = AppSettings.fromJson(
        const AppSettings(syncUrl: 'http://10.0.0.2:8765', syncCode: '123456').toJson());
    expect(s.syncUrl, 'http://10.0.0.2:8765');
    expect(s.syncCode, '123456');
    final d = DeletedLog.fromJson(jsonDecode(jsonEncode(
        DeletedLog(entities: {'frodo': '2026-10-01T10:00:00'}, facts: {'f1': '2026-10-01T10:00:00'}).toJson())));
    expect(d.entities.keys, ['frodo']);
    expect(d.facts.keys, ['f1']);
    expect(d.relationships, isEmpty);
    expect(const Relationship(source: 'a', target: 'b', type: ' Mentor', createdAt: '').key, 'a|b|mentor');
  });

  test('deletions are recorded and sent; the PC reply replaces the library', () async {
    late Map<String, dynamic> sent;
    late Map<String, String> headers;
    final pc = MockClient((req) async {
      expect(req.url.toString(), 'http://10.0.0.2:8765/sync');
      headers = req.headers;
      sent = jsonDecode(req.body) as Map<String, dynamic>;
      return http.Response(
        jsonEncode({
          'schema_version': 2,
          'entities': [
            ent('Q204274', 'Galadriel', [fact('f1', 'She is from Lothlórien', 1)]).toJson(),
            ent('aragorn', 'Aragorn').toJson(),
          ],
          'relationships': [
            const Relationship(source: 'Q204274', target: 'aragorn', type: 'Mentor', createdAt: '2026-10-01T10:00:00')
                .toJson(),
          ],
          'deleted': sent['deleted'],
        }),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });
    final store = LibraryStore.memory(
      entities: [ent('Q204274', 'Galadriel', [fact('f1', 'She is from Lothlórien', 1), fact('f2', 'typo', 2)]), ent('frodo', 'Frodo')],
      settings: const AppSettings(syncUrl: '10.0.0.2:8765', syncCode: '123456'),
      sync: SyncService(client: pc),
    );

    await store.removeFact(store.byId('Q204274')!, 'f2');
    await store.deleteEntity('frodo');
    final msg = await store.syncWithPc();

    expect(headers['X-SYL-Code'] ?? headers['x-syl-code'], '123456');
    expect((sent['deleted'] as Map)['facts'], contains('f2'));
    expect((sent['deleted'] as Map)['entities'], contains('frodo'));
    expect((sent['entities'] as List).map((e) => e['id']), ['Q204274']);
    expect(store.entities.map((e) => e.name), ['Aragorn', 'Galadriel']);
    expect(store.relationships.single.type, 'Mentor');
    expect(msg, contains('2 entries'));
    expect(store.syncing, isFalse);
  });

  test('a wrong pairing code shows the PC\'s message and changes nothing', () async {
    final pc = MockClient((_) async => http.Response(jsonEncode({'error': 'Wrong pairing code.'}), 401));
    final store = LibraryStore.memory(
      entities: [ent('frodo', 'Frodo')],
      settings: const AppSettings(syncUrl: 'http://10.0.0.2:8765', syncCode: '1'),
      sync: SyncService(client: pc),
    );
    await expectLater(store.syncWithPc(), throwsA(isA<SyncException>().having((e) => e.message, 'message', 'Wrong pairing code.')));
    expect(store.entities.single.id, 'frodo');
    expect(store.syncing, isFalse);
  });

  test('no address set gives a clear message', () async {
    final store = LibraryStore.memory(sync: SyncService(client: MockClient((_) async => http.Response('', 500))));
    await expectLater(store.syncWithPc(), throwsA(isA<SyncException>()));
  });

  test('pointing the AI address at the sync server explains the mix-up', () async {
    final ai = AiService(client: MockClient((_) async => http.Response('{"error": "not found"}', 404)));
    await expectLater(ai.listModels('192.168.0.106:8765'),
        throwsA(isA<AiException>().having((e) => e.message, 'message', contains('port 1234'))));
  });
}
