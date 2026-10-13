import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../state/library_store.dart';
import '../theme/syl_theme.dart';
import 'entity_screen.dart';
import 'new_entity_screen.dart';
import 'widgets/common.dart';

/// The current book's index: a cloth header with the cover and your bookmark,
/// then every entry A to Z on a page. Anything past your bookmark is counted,
/// never named.
class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key, required this.onOpenReading});
  final VoidCallback onOpenReading;

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  String? _type;
  bool _searching = false;
  final _query = TextEditingController();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  static const _filters = <(String?, String)>[
    (null, 'All'),
    ('Character', 'Characters'),
    ('Location', 'Places'),
    ('Item', 'Items'),
    ('Lore', 'Lore'),
    ('Other', 'Other'),
  ];

  @override
  Widget build(BuildContext context) {
    final store = context.watch<LibraryStore>();
    final book = store.settings.currentBook;
    final cap = store.spoilerChapter;
    bool inBook(Entity e) => book == null || e.book == null || e.book == book;
    bool pastBookmark(Entity e) => cap != null && e.discoveryChapter > cap;

    // Search looks through every book; browsing shows the current one.
    final searching = _query.text.trim().isNotEmpty;
    final matches = store.search(_query.text, type: _type).where((e) => searching || inBook(e));
    final items = matches.where((e) => !pastBookmark(e)).toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    final bookEntities = store.entities.where(inBook).toList();
    final hiddenEntries = bookEntities.where(pastBookmark).length;
    final hiddenFacts = cap == null
        ? 0
        : bookEntities.where((e) => !pastBookmark(e)).fold(0, (n, e) => n + e.facts.length - e.visibleFacts(cap).length);
    final otherBooks = store.entities.length - bookEntities.length;
    final shown = bookEntities.where((e) => !pastBookmark(e)).toList();
    final shownFacts = shown.fold(0, (n, e) => n + e.visibleFacts(cap).length);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: RefreshIndicator(
        color: Syl.ink,
        onRefresh: store.load,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 120),
          children: [
            _Header(
              book: book,
              summary: '${shown.length} ${shown.length == 1 ? 'entry' : 'entries'} · $shownFacts ${shownFacts == 1 ? 'fact' : 'facts'}',
              chapter: cap,
              searching: _searching,
              onSearch: () => setState(() {
                _searching = !_searching;
                if (!_searching) _query.clear();
              }),
              onBookmark: widget.onOpenReading,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                if (_searching) ...[
                  TextField(
                    controller: _query,
                    autofocus: true,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Who is this again?'),
                  ),
                  const SizedBox(height: 12),
                ],
                SizedBox(
                  height: 48,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _filters.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (_, i) {
                      final (type, label) = _filters[i];
                      return FilterPill(
                        label: label,
                        dot: type == null ? null : Syl.typeDot(type),
                        selected: _type == type,
                        onTap: () => setState(() => _type = type),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 18),
                Row(children: [
                  Text(searching ? 'RESULTS' : 'INDEX', style: _smallCaps),
                  const Spacer(),
                  Text('${items.length} ${items.length == 1 ? 'ENTRY' : 'ENTRIES'}', style: _smallCaps),
                ]),
                const SizedBox(height: 4),
                if (store.error != null)
                  Padding(padding: const EdgeInsets.all(16), child: Text(store.error!))
                else if (items.isEmpty && hiddenEntries == 0)
                  _EmptyState(filtered: searching || _type != null)
                else
                  for (final e in items) _IndexRow(e, cap: cap),
                if (!searching && cap != null && (hiddenEntries > 0 || hiddenFacts > 0)) ...[
                  _BookmarkLine(chapter: cap),
                  Text(
                    '${_count(hiddenFacts, 'fact')}${hiddenFacts > 0 && hiddenEntries > 0 ? ' and ' : ''}${_count(hiddenEntries, 'entry')} '
                    '${hiddenFacts + hiddenEntries == 1 ? 'is' : 'are'} past your bookmark. They show up as you read on.',
                    style: Syl.serif(context, fontSize: 15, fontStyle: FontStyle.italic, color: Syl.muted, height: 1.4),
                  ),
                ],
                const SizedBox(height: 16),
                const _NewEntryRow(),
                if (!searching && book != null && otherBooks > 0)
                  _OtherBooksRow(count: otherBooks, onTap: widget.onOpenReading),
              ]),
            ),
          ],
        ),
      ),
    );
  }

  static String _count(int n, String word) => n == 0 ? '' : '$n ${n == 1 ? word : (word == 'entry' ? 'entries' : '${word}s')}';
}

const _smallCaps = TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1.5, color: Syl.muted);

/// Navy cloth band: cover, title, and your bookmark (tap to change it).
class _Header extends StatelessWidget {
  const _Header({
    required this.book,
    required this.summary,
    required this.chapter,
    required this.searching,
    required this.onSearch,
    required this.onBookmark,
  });
  final String? book;
  final String summary;
  final int? chapter;
  final bool searching;
  final VoidCallback onSearch;
  final VoidCallback onBookmark;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Syl.cloth,
      padding: EdgeInsets.fromLTRB(20, MediaQuery.of(context).padding.top + 12, 12, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          BookCover(title: book ?? 'SYL'),
          const SizedBox(width: 16),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(book ?? 'Your library',
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: Syl.serif(context, fontSize: 26, color: Syl.onCloth, height: 1.1)),
                const SizedBox(height: 8),
                Text(summary, style: const TextStyle(fontSize: 14, color: Syl.onClothMuted)),
              ]),
            ),
          ),
          RoundIconButton(
            icon: searching ? Icons.close : Icons.search,
            tooltip: searching ? 'Close search' : 'Search',
            background: Colors.white.withValues(alpha: 0.10),
            foreground: Syl.onCloth,
            onPressed: onSearch,
          ),
        ]),
        const SizedBox(height: 10),
        Semantics(
          button: true,
          child: InkWell(
            onTap: onBookmark,
            borderRadius: BorderRadius.circular(12),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: Row(children: [
                Icon(chapter == null ? Icons.bookmark_border : Icons.bookmark, size: 20, color: Syl.onCloth),
                const SizedBox(width: 8),
                Expanded(
                  child: Text.rich(
                    chapter == null
                        ? const TextSpan(text: 'No bookmark yet, so nothing is hidden')
                        : TextSpan(children: [
                            const TextSpan(text: 'Your bookmark is at '),
                            TextSpan(text: 'ch. $chapter', style: const TextStyle(fontWeight: FontWeight.w700, color: Syl.onCloth)),
                          ]),
                    style: const TextStyle(fontSize: 14, color: Syl.onClothMuted),
                  ),
                ),
                const Text('Change', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Syl.onCloth)),
                const SizedBox(width: 8),
              ]),
            ),
          ),
        ),
      ]),
    );
  }
}

/// Placeholder cover drawn from the title until real cover art is added.
class BookCover extends StatelessWidget {
  const BookCover({super.key, required this.title, this.width = 72});
  final String title;
  final double width;

  static const _cloths = [Color(0xFF2C3B2F), Color(0xFF4A2326), Color(0xFF3B3350), Color(0xFF2D3A44)];

  @override
  Widget build(BuildContext context) {
    var h = 0;
    for (final c in title.codeUnits) {
      h = (h * 31 + c) & 0x7fffffff;
    }
    final base = _cloths[h % _cloths.length];
    return ExcludeSemantics(
      child: Container(
        width: width,
        height: width * 1.47,
        padding: const EdgeInsets.all(5),
        decoration: BoxDecoration(
          borderRadius: const BorderRadius.horizontal(left: Radius.circular(3), right: Radius.circular(6)),
          color: base,
          // a darker spine down the left edge
          border: Border(left: BorderSide(color: Color.lerp(base, Colors.black, 0.35)!, width: 4)),
          boxShadow: const [BoxShadow(color: Color(0x55000000), blurRadius: 14, offset: Offset(0, 6))],
        ),
        child: Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(border: Border.all(color: const Color(0x55E9E2CC))),
          child: Text(title,
              textAlign: TextAlign.center,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: Syl.serif(context, fontSize: 11, color: const Color(0xFFE9E2CC), height: 1.15)),
        ),
      ),
    );
  }
}

/// One index entry: "Aragorn, 10–12" and its newest fact.
class _IndexRow extends StatelessWidget {
  const _IndexRow(this.e, {required this.cap});
  final Entity e;
  final int? cap;

  static String _typeLabel(String type) => switch (type) {
        'Character' => 'Character',
        'Location' => 'Place',
        'Item' => 'Item',
        'Lore' => 'Lore',
        _ => 'Other',
      };

  @override
  Widget build(BuildContext context) {
    final facts = e.visibleFacts(cap);
    final chapters = facts.map((f) => f.chapter).toList()..sort();
    final range = chapters.isEmpty
        ? null
        : chapters.first == chapters.last
            ? '${chapters.first}'
            : '${chapters.first}–${chapters.last}';
    final latest = facts.isEmpty ? null : (facts.toList()..sort((a, b) => a.chapter.compareTo(b.chapter))).last;
    final isNew = cap != null && latest != null && latest.chapter == cap;
    final preview = latest?.text ??
        (e.lore.description.isNotEmpty
            ? e.lore.description
            : e.external.description.isNotEmpty
                ? e.external.description
                : 'Nothing noted yet');

    return InkWell(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => EntityScreen(entityId: e.id))),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Syl.line))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
            Flexible(
              child: Text(e.name, style: Syl.serif(context, fontSize: 19, fontWeight: FontWeight.w700, color: Syl.ink)),
            ),
            if (range != null) Text(', $range', style: Syl.serif(context, fontSize: 16, color: Syl.muted)),
          ]),
          const SizedBox(height: 4),
          Text.rich(
            TextSpan(children: [
              if (isNew)
                TextSpan(text: 'New in $cap', style: const TextStyle(fontWeight: FontWeight.w700, color: Syl.stamp))
              else
                TextSpan(text: _typeLabel(e.type)),
              TextSpan(text: ' · $preview'),
            ]),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 14, height: 1.35, color: Syl.muted),
          ),
        ]),
      ),
    );
  }
}

/// "—— Your bookmark · ch. 12 ——"
class _BookmarkLine extends StatelessWidget {
  const _BookmarkLine({required this.chapter});
  final int chapter;

  @override
  Widget build(BuildContext context) {
    Widget rule() => Expanded(child: Container(height: 2, color: Syl.stamp.withValues(alpha: 0.45)));
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 18, 0, 10),
      child: Row(children: [
        rule(),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Text('Your bookmark · ch. $chapter',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Syl.stamp)),
        ),
        rule(),
      ]),
    );
  }
}

class _NewEntryRow extends StatelessWidget {
  const _NewEntryRow();

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: Syl.r14,
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NewEntityScreen())),
      child: Container(
        height: 56,
        alignment: Alignment.center,
        decoration: BoxDecoration(borderRadius: Syl.r14, border: Border.all(color: Syl.line, width: 1.5)),
        child: const Text('+ New entry', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Syl.muted)),
      ),
    );
  }
}

class _OtherBooksRow extends StatelessWidget {
  const _OtherBooksRow({required this.count, required this.onTap});
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Row(children: [
          Expanded(
            child: Text('$count ${count == 1 ? 'entry is' : 'entries are'} in your other books',
                style: const TextStyle(fontSize: 14, color: Syl.muted)),
          ),
          const Text('Switch book', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Syl.ink)),
        ]),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.filtered});
  final bool filtered;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(children: [
        const Icon(Icons.auto_stories_outlined, size: 40, color: Syl.muted),
        const SizedBox(height: 12),
        Text(
          filtered ? 'Nothing matches. Try another word or filter.' : 'Your index is empty. Add the first character you meet.',
          textAlign: TextAlign.center,
          style: Syl.serif(context, fontSize: 17, color: Syl.ink, height: 1.35),
        ),
      ]),
    );
  }
}
