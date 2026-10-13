import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../state/library_store.dart';
import '../theme/syl_theme.dart';
import 'entity_screen.dart';
import 'new_entity_screen.dart';
import 'widgets/common.dart';

/// The current book's entries as bubbles, coloured by type, under a
/// "Reading now" bubble. Anything past your chapter is counted, never named.
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
    final t = Theme.of(context).textTheme;
    final book = store.settings.currentBook;
    final cap = store.spoilerChapter;
    bool inBook(Entity e) => book == null || e.book == null || e.book == book;
    bool pastBookmark(Entity e) => cap != null && e.discoveryChapter > cap;

    // Search looks through every book; browsing shows the current one.
    final searching = _query.text.trim().isNotEmpty;
    final items = store
        .search(_query.text, type: _type)
        .where((e) => (searching || inBook(e)) && !pastBookmark(e))
        .toList();

    final bookEntities = store.entities.where(inBook).toList();
    final shown = bookEntities.where((e) => !pastBookmark(e)).toList();
    final shownFacts = shown.fold(0, (n, e) => n + e.visibleFacts(cap).length);
    final hiddenEntries = bookEntities.length - shown.length;
    final hiddenFacts = cap == null ? 0 : shown.fold(0, (n, e) => n + e.facts.length - e.visibleFacts(cap).length);
    final otherBooks = store.entities.length - bookEntities.length;
    final sealed = !searching && _type == null && (hiddenFacts > 0 || hiddenEntries > 0);

    final left = <Widget>[], right = <Widget>[];
    var lh = 0.0, rh = 0.0;
    void place(Widget w, double h) {
      if (lh <= rh) {
        left.add(w);
        lh += h;
      } else {
        right.add(w);
        rh += h;
      }
    }

    for (final e in items) {
      place(_Bubble(e), _Bubble.estimateHeight(e, cap));
    }
    if (sealed) place(_SealedBubble(facts: hiddenFacts, entries: hiddenEntries), 120);
    place(const _NewEntryTile(), 88);

    return SafeArea(
      bottom: false,
      child: RefreshIndicator(
        color: Syl.ink,
        onRefresh: store.load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 120),
          children: [
            Row(children: [
              const Text('syl.', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 22, letterSpacing: -0.5)),
              const Spacer(),
              RoundIconButton(
                icon: _searching ? Icons.close : Icons.search,
                tooltip: _searching ? 'Close search' : 'Search',
                onPressed: () => setState(() {
                  _searching = !_searching;
                  if (!_searching) _query.clear();
                }),
              ),
            ]),
            const SizedBox(height: 16),
            if (_searching) ...[
              TextField(
                controller: _query,
                autofocus: true,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Who is this again?'),
              ),
              const SizedBox(height: 16),
            ] else ...[
              Text('Library', style: t.displaySmall?.copyWith(fontSize: 52)),
              const SizedBox(height: 6),
              Text(
                '${shown.length} ${shown.length == 1 ? 'entry' : 'entries'} · $shownFacts ${shownFacts == 1 ? 'fact' : 'facts'}',
                style: TextStyle(fontSize: 15, color: Syl.muted),
              ),
              const SizedBox(height: 16),
              _ReadingBubble(onTap: widget.onOpenReading),
              const SizedBox(height: 16),
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
            const SizedBox(height: 16),
            if (store.error != null)
              Padding(padding: const EdgeInsets.all(16), child: Text(store.error!))
            else ...[
              if (items.isEmpty) _EmptyState(filtered: searching || _type != null),
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: Column(children: left)),
                const SizedBox(width: 10),
                Expanded(child: Column(children: right)),
              ]),
            ],
            if (!searching && book != null && otherBooks > 0) _OtherBooksRow(count: otherBooks, onTap: widget.onOpenReading),
          ],
        ),
      ),
    );
  }
}

/// The dark "Reading now" bubble: cover, book and your chapter.
class _ReadingBubble extends StatelessWidget {
  const _ReadingBubble({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<LibraryStore>().settings;
    final book = s.currentBook;
    return Material(
      color: Syl.inverse,
      borderRadius: const BorderRadius.all(Radius.circular(28)),
      child: InkWell(
        borderRadius: const BorderRadius.all(Radius.circular(28)),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            BookCover(title: book ?? '?'),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Reading now', style: TextStyle(fontSize: 12, color: Syl.onInkMuted)),
                const SizedBox(height: 2),
                Text(book ?? 'Set your book',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Syl.dark
                        ? Syl.serif(context, fontSize: 19, color: Syl.onInverse, height: 1.15)
                        : TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Syl.onInverse)),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: const BoxDecoration(color: Syl.accent, borderRadius: BorderRadius.all(Radius.circular(16))),
                  child: Text(s.spoilerChapter == null ? 'Spoiler shield off' : 'Ch. ${s.spoilerChapter}',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Syl.onAccent)),
                ),
                const SizedBox(height: 8),
                Text(
                  s.spoilerChapter == null
                      ? 'Tap to set the chapter you\'re on'
                      : 'Nothing past chapter ${s.spoilerChapter} is shown or sent to the AI',
                  style: TextStyle(fontSize: 12, color: Syl.onInkMuted),
                ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Placeholder cover drawn from the title until real cover art is added.
class BookCover extends StatelessWidget {
  const BookCover({super.key, required this.title, this.width = 62});
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
          color: base,
          borderRadius: const BorderRadius.horizontal(left: Radius.circular(4), right: Radius.circular(10)),
          // a darker spine down the left edge
          border: Border(left: BorderSide(color: Color.lerp(base, Colors.black, 0.35)!, width: 4)),
        ),
        child: Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.all(3),
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

String typeLabel(String type) => switch (type) {
      'Character' => 'Character',
      'Location' => 'Place',
      'Item' => 'Item',
      'Lore' => 'Lore',
      _ => 'Other',
    };

/// One entry: a bubble in its type's colour, with the type's icon top right.
class _Bubble extends StatelessWidget {
  const _Bubble(this.e);
  final Entity e;

  static double estimateHeight(Entity e, int? cap) {
    final n = e.visibleFacts(cap).length;
    return 110.0 + (n.clamp(0, 3) * 22) + (e.name.length > 12 ? 26 : 0);
  }

  @override
  Widget build(BuildContext context) {
    final cap = context.watch<LibraryStore>().spoilerChapter;
    final facts = e.visibleFacts(cap).toList()..sort((a, b) => a.chapter.compareTo(b.chapter));
    final isNew = cap != null && facts.isNotEmpty && facts.last.chapter == cap;
    final preview = e.lore.description.isNotEmpty
        ? e.lore.description
        : facts.isNotEmpty
            ? facts.reversed.take(3).map((f) => f.text).join('. ')
            : (e.external.description.isNotEmpty ? e.external.description : 'Nothing noted yet.');
    final chapters = facts.isEmpty
        ? null
        : facts.first.chapter == facts.last.chapter
            ? 'Ch. ${facts.first.chapter}'
            : 'Ch. ${facts.first.chapter}–${facts.last.chapter}';

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Syl.typeColor(e.type),
        borderRadius: const BorderRadius.all(Radius.circular(26)),
        child: InkWell(
          borderRadius: const BorderRadius.all(Radius.circular(26)),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => EntityScreen(entityId: e.id))),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  child: Wrap(spacing: 6, runSpacing: 6, children: [
                    SoftTag(typeLabel(e.type)),
                    if (isNew) const _NewBadge(),
                  ]),
                ),
                const SizedBox(width: 6),
                TypeIcon(e.type),
              ]),
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Text(e.name,
                    style: Syl.dark
                        ? Syl.serif(context, fontSize: 22, fontWeight: FontWeight.w700, color: Syl.ink, height: 1.05)
                        : const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: -0.7, height: 1)),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Text(preview, maxLines: 4, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, height: 1.35)),
              ),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                  child: Text('${facts.length} ${facts.length == 1 ? 'fact' : 'facts'}',
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
                ),
                if (chapters != null)
                  Flexible(
                    child: Text(chapters,
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
                  ),
                if (!e.lore.isEmpty) ...[
                  const SizedBox(width: 6),
                  const Icon(Icons.auto_awesome, size: 14, semanticLabel: 'Has AI lore'),
                ],
              ]),
            ]),
          ),
        ),
      ),
    );
  }
}

class _NewBadge extends StatelessWidget {
  const _NewBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(color: Syl.inverse, borderRadius: const BorderRadius.all(Radius.circular(12))),
      child: Text('New', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Syl.onInverse)),
    );
  }
}

/// A small drawn icon per type: hooded figure, tower, sword, scroll.
class TypeIcon extends StatelessWidget {
  const TypeIcon(this.type, {super.key, this.size = 34});
  final String type;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: typeLabel(type),
      child: Container(
        width: size,
        height: size,
        padding: EdgeInsets.all(size * 0.2),
        decoration: BoxDecoration(color: Syl.ink.withValues(alpha: 0.08), shape: BoxShape.circle),
        child: CustomPaint(painter: _GlyphPainter(type, Syl.ink.withValues(alpha: 0.75))),
      ),
    );
  }
}

class _GlyphPainter extends CustomPainter {
  _GlyphPainter(this.type, this.color);
  final String type;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 100, size.height / 100);
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;
    final path = Path();
    switch (type) {
      case 'Character': // hooded figure
        path
          ..moveTo(50, 6)
          ..cubicTo(34, 6, 24, 20, 24, 36)
          ..cubicTo(24, 43, 26, 49, 30, 53)
          ..cubicTo(17, 61, 9, 76, 8, 94)
          ..lineTo(92, 94)
          ..cubicTo(91, 76, 83, 61, 70, 53)
          ..cubicTo(74, 49, 76, 43, 76, 36)
          ..cubicTo(76, 20, 66, 6, 50, 6)
          ..close()
          ..moveTo(37, 40)
          ..quadraticBezierTo(50, 56, 63, 40);
      case 'Location': // tower
        path
          ..moveTo(26, 94)
          ..lineTo(26, 40)
          ..lineTo(74, 40)
          ..lineTo(74, 94)
          ..close()
          ..moveTo(20, 40)
          ..lineTo(20, 14)
          ..lineTo(33, 14)
          ..lineTo(33, 24)
          ..lineTo(44, 24)
          ..lineTo(44, 14)
          ..lineTo(56, 14)
          ..lineTo(56, 24)
          ..lineTo(67, 24)
          ..lineTo(67, 14)
          ..lineTo(80, 14)
          ..lineTo(80, 40)
          ..moveTo(42, 94)
          ..lineTo(42, 74)
          ..arcToPoint(const Offset(58, 74), radius: const Radius.circular(8))
          ..lineTo(58, 94);
      case 'Item': // sword
        path
          ..moveTo(84, 8)
          ..lineTo(92, 16)
          ..lineTo(44, 66)
          ..lineTo(34, 56)
          ..close()
          ..moveTo(22, 52)
          ..lineTo(48, 78)
          ..moveTo(34, 66)
          ..lineTo(14, 86)
          ..moveTo(8, 92)
          ..lineTo(12, 88);
      case 'Lore': // scroll
        path
          ..moveTo(26, 12)
          ..lineTo(78, 12)
          ..cubicTo(86, 12, 86, 26, 78, 26)
          ..lineTo(74, 26)
          ..lineTo(74, 88)
          ..lineTo(22, 88)
          ..cubicTo(14, 88, 14, 74, 22, 74)
          ..lineTo(26, 74)
          ..close()
          ..moveTo(38, 40)
          ..lineTo(62, 40)
          ..moveTo(38, 56)
          ..lineTo(62, 56);
      default: // a simple gem
        path
          ..moveTo(50, 8)
          ..lineTo(90, 40)
          ..lineTo(50, 92)
          ..lineTo(10, 40)
          ..close()
          ..moveTo(10, 40)
          ..lineTo(90, 40);
    }
    canvas.drawPath(path, p);
  }

  @override
  bool shouldRepaint(_GlyphPainter old) => old.type != type || old.color != color;
}

/// A dashed bubble standing in for whatever is past your chapter.
class _SealedBubble extends StatelessWidget {
  const _SealedBubble({required this.facts, required this.entries});
  final int facts;
  final int entries;

  static String _n(int n, String one, String many) => '$n ${n == 1 ? one : many}';

  @override
  Widget build(BuildContext context) {
    final parts = [if (facts > 0) _n(facts, 'fact', 'facts'), if (entries > 0) _n(entries, 'entry', 'entries')];
    final total = facts + entries;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: CustomPaint(
        painter: _DashedBorder(Syl.line),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${parts.join(' and ')} ${total == 1 ? 'waits' : 'wait'}',
                style: Syl.dark
                    ? Syl.serif(context, fontSize: 18, fontWeight: FontWeight.w700, color: Syl.ink)
                    : const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: -0.4)),
            const SizedBox(height: 6),
            Text('Past your bookmark. ${total == 1 ? 'It appears' : 'They appear'} as you read on.',
                style: TextStyle(fontSize: 14, height: 1.35, color: Syl.muted)),
          ]),
        ),
      ),
    );
  }
}

class _DashedBorder extends CustomPainter {
  _DashedBorder(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final path = Path()..addRRect(RRect.fromRectAndRadius((Offset.zero & size).deflate(1), const Radius.circular(26)));
    for (final metric in path.computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += 12) {
        canvas.drawPath(metric.extractPath(d, d + 6), p);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorder old) => old.color != color;
}

class _NewEntryTile extends StatelessWidget {
  const _NewEntryTile();

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: Syl.r24,
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NewEntityScreen())),
      child: Container(
        height: 88,
        width: double.infinity,
        alignment: Alignment.center,
        decoration: BoxDecoration(borderRadius: Syl.r24, border: Border.all(color: Syl.line, width: 2)),
        child: Text('+ New entry', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: Syl.muted)),
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
                style: TextStyle(fontSize: 14, color: Syl.muted)),
          ),
          const Text('Switch book', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
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
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(color: Syl.white, borderRadius: Syl.r24),
      child: Column(children: [
        Icon(Icons.auto_stories_outlined, size: 40, color: Syl.muted),
        const SizedBox(height: 12),
        Text(
          filtered ? 'Nothing matches. Try another word or filter.' : 'Your library is empty. Add the first character you meet.',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 15),
        ),
      ]),
    );
  }
}
