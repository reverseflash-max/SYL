import 'dart:convert';

import 'package:http/http.dart' as http;

/// Looks books up on Open Library (openlibrary.org) to fill in the author
/// and, when an edition lists its table of contents, the chapter count and
/// chapter names. Only popular books tend to have one; when nothing is
/// found the reader types the number of chapters.
class OpenLibraryBook {
  final String key; // e.g. /works/OL27513W
  final String title;
  final String author;
  final int? year;
  final int? coverId;
  const OpenLibraryBook(this.key, this.title, this.author, this.year, [this.coverId]);
}

class OpenLibraryException implements Exception {
  final String message;
  OpenLibraryException(this.message);
  @override
  String toString() => message;
}

class OpenLibraryService {
  OpenLibraryService({http.Client? client}) : _client = client ?? http.Client();
  final http.Client _client;

  static const _host = 'openlibrary.org';
  static const _headers = {'User-Agent': 'SYL/0.2 (personal fantasy reading companion)', 'Accept': 'application/json'};

  Future<Map<String, dynamic>> _get(Uri uri) async {
    try {
      final r = await _client.get(uri, headers: _headers).timeout(const Duration(seconds: 20));
      if (r.statusCode != 200) throw OpenLibraryException('Open Library returned HTTP ${r.statusCode}');
      return jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
    } on OpenLibraryException {
      rethrow;
    } catch (_) {
      throw OpenLibraryException("Couldn't reach Open Library. Check your connection.");
    }
  }

  Future<List<OpenLibraryBook>> search(String query) async {
    final data = await _get(Uri.https(_host, '/search.json', {
      'q': query,
      'limit': '8',
      'fields': 'key,title,author_name,first_publish_year,cover_i',
    }));
    return [
      for (final d in (data['docs'] as List? ?? []).whereType<Map<String, dynamic>>())
        if (d['key'] != null && d['title'] != null)
          OpenLibraryBook(
            d['key'].toString(),
            d['title'].toString(),
            ((d['author_name'] as List?) ?? const []).take(2).join(', '),
            (d['first_publish_year'] as num?)?.toInt(),
            (d['cover_i'] as num?)?.toInt(),
          ),
    ];
  }

  /// Chapter names from the edition with the fullest table of contents, or
  /// an empty list if no edition has one.
  Future<List<String>> chapters(String workKey) async {
    final data = await _get(Uri.https(_host, '$workKey/editions.json', {'limit': '200'}));
    var best = <String>[];
    for (final ed in (data['entries'] as List? ?? []).whereType<Map<String, dynamic>>()) {
      final toc = (ed['table_of_contents'] as List? ?? [])
          .whereType<Map>()
          .map((t) => (t['title'] ?? '').toString())
          .toList();
      final names = cleanChapters(toc);
      if (names.length > best.length) best = names;
    }
    return best;
  }
}

/// Front and back matter, and part headings, that tables of contents list
/// alongside the chapters.
final _notChapter = RegExp(
  r'^(contents|table of contents|note|note on the text|foreword|preface|prologue|epilogue|introduction|'
  r'acknowledg|dedication|maps?\b|index|glossary|appendix|appendices|about the author|also by|'
  r'title page|copyright|ars arcanum|postscript|afterword|'
  r'(book|part|volume)\s+(\d+|[ivxlc]+|one|two|three|four|five|six|seven|eight|nine|ten)\b)',
  caseSensitive: false,
);

/// The real chapters from a raw table of contents: blanks, front matter and
/// "Book One" / "Part One" headings dropped, and "CHAPTER 1" tidied to "Chapter 1".
List<String> cleanChapters(List<String> raw) {
  final out = <String>[];
  for (final r in raw) {
    final t = r.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (t.isEmpty || _notChapter.hasMatch(t)) continue;
    out.add(t == t.toUpperCase() && t.length > 3 ? _titleCase(t) : t);
  }
  return out;
}

String _titleCase(String s) =>
    s.toLowerCase().split(' ').map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1)).join(' ');
