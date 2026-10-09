import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/models.dart';

/// Syncs with `python syl.py serve` on your PC (same Wi-Fi).
///
/// The app sends its whole library; the PC merges it with its own (see
/// syl_sync.py), saves the result and sends the merged library back.
class SyncException implements Exception {
  final String message;
  SyncException(this.message);
  @override
  String toString() => message;
}

class SyncResult {
  final List<Entity> entities;
  final List<Relationship> relationships;
  final DeletedLog deleted;
  const SyncResult(this.entities, this.relationships, this.deleted);
}

class SyncService {
  SyncService({http.Client? client}) : _client = client ?? http.Client();
  final http.Client _client;

  Uri _uri(String base, String path) {
    var b = base.trim();
    if (b.isEmpty) throw SyncException("Enter your PC's sync address first.");
    if (!b.startsWith('http')) b = 'http://$b';
    return Uri.parse('${b.replaceAll(RegExp(r'/+$'), '')}$path');
  }

  Map<String, String> _headers(String code) => {
        'X-SYL-Code': code.trim(),
        'Content-Type': 'application/json; charset=utf-8',
      };

  Never _fail(http.Response r) {
    String? msg;
    try {
      msg = (jsonDecode(utf8.decode(r.bodyBytes)) as Map)['error']?.toString();
    } catch (_) {}
    throw SyncException(msg ?? 'The PC returned HTTP ${r.statusCode}.');
  }

  String _unreachable(String base) =>
      "Can't reach SYL at $base. Is `python syl.py serve` running on the PC, and are both on the same Wi-Fi?";

  /// Number of entries in the PC's library.
  Future<int> ping(String baseUrl, String code) async {
    final http.Response r;
    try {
      r = await _client.get(_uri(baseUrl, '/ping'), headers: _headers(code)).timeout(const Duration(seconds: 6));
    } on SyncException {
      rethrow;
    } catch (_) {
      throw SyncException(_unreachable(baseUrl));
    }
    if (r.statusCode != 200) _fail(r);
    return ((jsonDecode(utf8.decode(r.bodyBytes)) as Map)['entities'] as num?)?.toInt() ?? 0;
  }

  Future<SyncResult> sync(
    String baseUrl,
    String code, {
    required List<Entity> entities,
    required List<Relationship> relationships,
    required DeletedLog deleted,
  }) async {
    final body = jsonEncode({
      'schema_version': kSchemaVersion,
      'entities': entities.map((e) => e.toJson()).toList(),
      'relationships': relationships.map((r) => r.toJson()).toList(),
      'deleted': deleted.toJson(),
    });
    final http.Response r;
    try {
      r = await _client
          .post(_uri(baseUrl, '/sync'), headers: _headers(code), body: utf8.encode(body))
          .timeout(const Duration(seconds: 30));
    } on SyncException {
      rethrow;
    } catch (_) {
      throw SyncException(_unreachable(baseUrl));
    }
    if (r.statusCode != 200) _fail(r);
    try {
      final j = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
      final ents = (j['entities'] as List)
          .whereType<Map<String, dynamic>>()
          .map((e) => Entity.fromJson(e))
          .toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      final rels = (j['relationships'] as List)
          .whereType<Map<String, dynamic>>()
          .map(Relationship.fromJson)
          .where((r) => r.source.isNotEmpty && r.target.isNotEmpty)
          .toList();
      final del = DeletedLog.fromJson((j['deleted'] as Map?)?.cast<String, dynamic>() ?? const {});
      return SyncResult(ents, rels, del);
    } catch (_) {
      throw SyncException('The PC sent back something SYL could not read. Nothing was changed.');
    }
  }
}
