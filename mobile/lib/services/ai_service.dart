import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/models.dart';

/// Talks to LM Studio on your PC (OpenAI-compatible API).
///
/// PC:    http://127.0.0.1:1234
/// Phone: `http://<your PC IP>:1234`, with "Serve on Local Network" switched on
///        in LM Studio's Developer tab, and both devices on the same Wi-Fi.
///
/// Mirrors syl_ai.py so the phone and the CLI write the same kind of lore.
class AiException implements Exception {
  final String message;
  AiException(this.message);
  @override
  String toString() => message;
}

class AiService {
  AiService({http.Client? client}) : _client = client ?? http.Client();
  final http.Client _client;

  static const systemPrompt =
      "You write short lore notes for a reader's private fantasy notebook. "
      'STRICT RULES: use ONLY the notes you are given. Do not add anything you may already '
      'know about the book, film, or character, even if you recognise the name: the reader '
      'has not read that far and outside knowledge is a spoiler. If the notes are thin, '
      'write less. Never invent events, relatives, titles or fates.';

  Uri _uri(String base, String path) {
    var b = base.trim();
    if (b.isEmpty) {
      throw AiException("Set your PC's LM Studio address in Reading & AI settings first.");
    }
    if (!b.startsWith('http')) b = 'http://$b';
    return Uri.parse('${b.replaceAll(RegExp(r'/+$'), '')}$path');
  }

  Future<List<String>> listModels(String baseUrl) async {
    try {
      final r = await _client.get(_uri(baseUrl, '/v1/models')).timeout(const Duration(seconds: 6));
      if (r.statusCode != 200) throw AiException('LM Studio returned HTTP ${r.statusCode}');
      final data = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
      return (data['data'] as List? ?? [])
          .map((m) => (m as Map)['id']?.toString() ?? '')
          .where((id) => id.isNotEmpty)
          .toList();
    } on AiException {
      rethrow;
    } catch (_) {
      throw AiException("Can't reach LM Studio at $baseUrl. Is the server running, and are you on the same Wi-Fi?");
    }
  }

  Future<String> pickModel(String baseUrl, String preferred) async {
    final models = await listModels(baseUrl);
    if (models.isEmpty) throw AiException('LM Studio is running but no model is loaded.');
    if (preferred.isNotEmpty) {
      for (final m in models) {
        if (m == preferred || m.toLowerCase().contains(preferred.toLowerCase())) return m;
      }
    }
    final chat = models.where((m) => !m.toLowerCase().contains('embed')).toList();
    return (chat.isNotEmpty ? chat : models).first;
  }

  String buildPrompt(Entity e, List<Fact> facts, List<String> connections) {
    final b = StringBuffer()
      ..writeln('Name: ${e.name}')
      ..writeln('Type: ${e.type}');
    if (e.book != null) b.writeln('Book: ${e.book}');
    b
      ..writeln()
      ..writeln("Reader's notes (chapter: note):");
    for (final f in facts) {
      b.writeln('- Ch ${f.chapter}: ${f.text}');
    }
    if (connections.isNotEmpty) {
      b
        ..writeln()
        ..writeln('Known connections:');
      for (final c in connections) {
        b.writeln('- $c');
      }
    }
    b
      ..writeln()
      ..writeln('Return ONLY a JSON object with these keys:')
      ..writeln('  "description": one sentence (max 30 words) summing up who/what this is,')
      ..writeln('  "biography": 2-4 sentences in an evocative fantasy-narrator voice, built only from the notes,')
      ..writeln('  "tags": 3-6 short tags (1-2 words each) that the notes clearly support.');
    return b.toString();
  }

  /// Returns fresh lore for [e] using only facts up to [spoilerChapter].
  Future<Lore> generateLore({
    required Entity e,
    required List<String> connections,
    required AppSettings settings,
  }) async {
    final cap = settings.spoilerChapter;
    final facts = e.visibleFacts(cap);
    if (facts.isEmpty) throw AiException('Add a fact first. The AI only writes from your notes.');
    final model = await pickModel(settings.lmStudioUrl, settings.lmModel);

    final http.Response r;
    try {
      r = await _client
          .post(
            _uri(settings.lmStudioUrl, '/v1/chat/completions'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'model': model,
              'messages': [
                {'role': 'system', 'content': systemPrompt},
                {'role': 'user', 'content': buildPrompt(e, facts, connections)},
              ],
              'temperature': 0.4,
              'max_tokens': 700,
              // Reasoning models (Qwen 3.5 etc.) otherwise spend the whole budget
              // "thinking" and return nothing. Non-reasoning models ignore this.
              'reasoning_effort': 'none',
              'stream': false,
            }),
          )
          .timeout(const Duration(minutes: 3));
    } catch (_) {
      throw AiException('LM Studio stopped responding. Try again.');
    }
    if (r.statusCode != 200) throw AiException('LM Studio returned HTTP ${r.statusCode}');

    final body = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
    final choices = body['choices'] as List? ?? const [];
    if (choices.isEmpty) throw AiException('LM Studio sent an empty reply. Try again.');
    var text = (choices.first['message']?['content'] ?? '').toString();
    if (text.trim().isEmpty && choices.first['finish_reason'] == 'length') {
      throw AiException('The model spent its whole budget thinking. Turn off reasoning for it in LM Studio, or load a non-reasoning model.');
    }
    text = text.replaceAll(RegExp(r'<think>[\s\S]*?</think>'), '').trim();
    final match = RegExp(r'\{[\s\S]*\}').firstMatch(text);
    if (match == null) throw AiException("The model didn't return JSON. Try again or pick another model.");
    final Map<String, dynamic> data;
    try {
      data = jsonDecode(match.group(0)!) as Map<String, dynamic>;
    } catch (_) {
      throw AiException('The model returned broken JSON. Try again.');
    }
    var tags = data['tags'] ?? data['lore_tags'] ?? [];
    if (tags is String) tags = tags.split(',');
    return Lore(
      description: (data['description'] ?? '').toString().trim(),
      biography: (data['biography'] ?? '').toString().trim(),
      tags: (tags as List).map((t) => t.toString().trim()).where((t) => t.isNotEmpty).take(6).toList(),
      generatedAt: nowIso(),
      model: model,
      spoilerLimitChapter: cap ?? facts.map((f) => f.chapter).reduce((a, b) => a > b ? a : b),
    );
  }
}
