import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mobile/models/models.dart';
import 'package:mobile/services/wikidata_service.dart';

Map<String, dynamic> claim(String id) => {
      'mainsnak': {
        'datavalue': {
          'value': {'id': id}
        }
      }
    };

void main() {
  test('linking keeps only the spoiler-safe details', () async {
    final client = MockClient((req) async {
      if (req.url.path.contains('EntityData')) {
        return http.Response(
            jsonEncode({
              'entities': {
                'Q180322': {
                  'id': 'Q180322',
                  'labels': {
                    'en': {'value': 'Aragorn'}
                  },
                  'descriptions': {
                    'en': {'value': 'fictional character in Middle-earth'}
                  },
                  'claims': {
                    'P31': [claim('Q1')],
                    'P172': [claim('Q2')],
                    'P21': [claim('Q3')],
                    'P1080': [claim('Q4')],
                    'P26': [claim('Q90')], // spouse: a spoiler
                    'P39': [claim('Q91')], // position held: a spoiler
                  },
                },
              },
            }),
            200);
      }
      final ids = req.url.queryParameters['ids']!.split('|');
      expect(ids, isNot(contains('Q90')));
      expect(ids, isNot(contains('Q91')));
      const names = {'Q1': 'fictional human', 'Q2': 'Dúnedain', 'Q3': 'male', 'Q4': 'Middle-earth'};
      // bytes, so names like Dúnedain survive (a plain Response is Latin-1)
      return http.Response.bytes(
          utf8.encode(jsonEncode({
            'entities': {
              for (final id in ids)
                id: {
                  'labels': {
                    'en': {'value': names[id]}
                  }
                }
            }
          })),
          200);
    });

    final info = await WikidataService(client: client).fetch('Q180322');
    expect(info.safeFacts, ['People: Dúnedain', 'Gender: male', 'World: Middle-earth']);
    expect(info.type, 'Character');

    // and they survive saving and loading
    final ext = ExternalData.fromJson(ExternalData(wikidataId: 'Q180322', safeFacts: info.safeFacts).toJson());
    expect(ext.safeFacts, info.safeFacts);
  });
}
