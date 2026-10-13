import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../state/library_store.dart';
import '../theme/syl_theme.dart';
import 'entity_screen.dart';
import 'new_entity_screen.dart';
import 'widgets/common.dart';

/// "Night watch": the Library as a night drawing in over the book. Your
/// chapter is the moon, the last few chapters are the moons before it, and
/// the entries are bubbles in jewel tones. Anything past your chapter is
/// counted, never named. The night is the Library's own world, so it stays
/// dark in light mode too.
class _Night {
  static const ground = Color(0xFF1B2240);
  static const deep = Color(0xFF121830);
  static const hill = Color(0xFF2A3360);
  static const ink = Color(0xFFF2EEE6);
  static const muted = Color(0xFFA9B0CC);
  static const faint = Color(0xFF5A6289);
  static const teal = Color(0xFF86D6C6);
  static const pill = Color(0xFF262E52);

  /// Bubble colour per type: sapphire, emerald, amethyst, garnet, slate.
  static Color type(String t) => switch (t) {
        'Character' => const Color(0xFF34509A),
        'Location' => const Color(0xFF235A43),
        'Item' => const Color(0xFF55387E),
        'Lore' => const Color(0xFF74293A),
        _ => const Color(0xFF34405A),
      };

  /// Filter dots, light enough to read on the night.
  static Color dot(String t) => switch (t) {
        'Character' => const Color(0xFF8FB0F5),
        'Location' => const Color(0xFF6FD39A),
        'Item' => const Color(0xFFB9A3F0),
        'Lore' => const Color(0xFFF59A8B),
        _ => muted,
      };
}

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

  /// Moves your bookmark on a chapter, with a way back.
  Future<void> _finishChapter(LibraryStore store, int cap) async {
    final before = store.settings;
    await store.updateSettings(before.copyWith(spoilerChapter: cap + 1));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text('Bookmark moved to ch. ${cap + 1}'),
        action: SnackBarAction(label: 'Undo', onPressed: () => store.updateSettings(before)),
      ));
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<LibraryStore>();
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
    final hiddenEntries = bookEntities.length - shown.length;
    final hiddenFacts = cap == null ? 0 : shown.fold(0, (n, e) => n + e.facts.length - e.visibleFacts(cap).length);
    final newTonight = cap == null ? 0 : shown.where((e) => e.visibleFacts(cap).any((f) => f.chapter == cap)).length;
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

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: ColoredBox(
        color: _Night.ground,
        child: DefaultTextStyle.merge(
          style: const TextStyle(color: _Night.ink),
          child: IconTheme.merge(
            data: const IconThemeData(color: _Night.ink),
            child: SafeArea(
              bottom: false,
              child: RefreshIndicator(
                color: _Night.ground,
                onRefresh: store.load,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(0, 8, 0, 120),
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(22, 0, 12, 0),
                      child: Row(children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: widget.onOpenReading,
                            child: Text(book ?? 'No book set',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 14, color: _Night.muted)),
                          ),
                        ),
                        RoundIconButton(
                          icon: _searching ? Icons.close : Icons.search,
                          tooltip: _searching ? 'Close search' : 'Search',
                          background: Colors.white.withValues(alpha: 0.08),
                          foreground: _Night.ink,
                          onPressed: () => setState(() {
                            _searching = !_searching;
                            if (!_searching) _query.clear();
                          }),
                        ),
                      ]),
                    ),
                    if (_searching)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(18, 12, 18, 16),
                        child: TextField(
                          controller: _query,
                          autofocus: true,
                          onChanged: (_) => setState(() {}),
                          decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Who is this again?'),
                        ),
                      )
                    else
                      _Sky(
                        chapter: cap,
                        newTonight: newTonight,
                        onFinished: cap == null ? widget.onOpenReading : () => _finishChapter(store, cap),
                      ),
                    SizedBox(
                      height: 48,
                      child: ListView.separated(
                        padding: const EdgeInsets.symmetric(horizontal: 18),
                        scrollDirection: Axis.horizontal,
                        itemCount: _filters.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 8),
                        itemBuilder: (_, i) {
                          final (type, label) = _filters[i];
                          return _NightPill(
                            label: label,
                            dot: type == null ? null : _Night.dot(type),
                            selected: _type == type,
                            onTap: () => setState(() => _type = type),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 14),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                      child: Column(children: [
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
                        if (!searching && book != null && otherBooks > 0)
                          _OtherBooksRow(count: otherBooks, onTap: widget.onOpenReading),
                      ]),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The hero: "ch. 12" big, the moons of the last few chapters, a hillside
/// with a lit tower window, and the button that moves you on a chapter.
class _Sky extends StatelessWidget {
  const _Sky({required this.chapter, required this.newTonight, required this.onFinished});
  final int? chapter;
  final int newTonight;
  final VoidCallback onFinished;

  @override
  Widget build(BuildContext context) {
    final cap = chapter;
    final line = cap == null
        ? 'Set the chapter you\'re on, and nothing past it will reach you.'
        : '${newTonight == 0 ? 'Nothing new yet tonight' : newTonight == 1 ? 'One new face tonight' : '$newTonight new faces tonight'}. '
            'Nothing past here can reach you.';
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(22, 2, 22, 0),
        child: cap == null
            ? Text('No chapter set', style: Syl.serif(context, fontSize: 40, color: _Night.ink, height: 1.1))
            : Text.rich(
                TextSpan(children: [
                  TextSpan(text: 'ch. ', style: Syl.serif(context, fontSize: 28, color: _Night.muted)),
                  TextSpan(text: '$cap', style: Syl.serif(context, fontSize: 84, color: _Night.ink, height: 1, letterSpacing: -2)),
                ]),
              ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(22, 6, 22, 0),
        child: Text(line, style: const TextStyle(fontSize: 15, height: 1.35, color: Color(0xFFC9CEE2))),
      ),
      if (cap != null) _Moons(chapter: cap),
      const SizedBox(height: 150, child: CustomPaint(painter: _HillsPainter())),
      Transform.translate(
        offset: const Offset(0, -8),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 10),
          child: SizedBox(
            height: 52,
            child: FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Syl.accent, foregroundColor: Syl.onAccent),
              onPressed: onFinished,
              child: Text(cap == null ? 'Set my chapter' : 'I finished ch. $cap'),
            ),
          ),
        ),
      ),
    ]);
  }
}

/// The last few chapters as full moons, yours in gold, the next one still dark.
class _Moons extends StatelessWidget {
  const _Moons({required this.chapter});
  final int chapter;

  @override
  Widget build(BuildContext context) {
    final first = (chapter - 3).clamp(1, chapter);
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 18, 22, 0),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        for (var c = first; c <= chapter + 1; c++)
          Column(children: [
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: c > chapter ? null : (c == chapter ? Syl.accent : _Night.ink),
                border: c > chapter ? Border.all(color: _Night.faint, width: 1.5) : null,
              ),
            ),
            const SizedBox(height: 4),
            Text(c == chapter ? '$c, you' : '$c',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: c == chapter ? FontWeight.w700 : FontWeight.w500,
                    color: c == chapter ? Syl.accent : _Night.muted)),
          ]),
      ]),
    );
  }
}

/// Stars, two hills and a tower with one lit window.
class _HillsPainter extends CustomPainter {
  const _HillsPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final p = Paint();
    var s = 11;
    double rnd() => (s = (s * 16807) % 2147483647) / 2147483647;
    for (var i = 0; i < 26; i++) {
      p.color = _Night.ink.withValues(alpha: 0.25 + rnd() * 0.5);
      canvas.drawCircle(Offset(rnd() * w, rnd() * h * 0.5), 0.6 + rnd() * 0.8, p);
    }
    // a small constellation
    final a = Offset(w * 0.69, h * 0.27), b = Offset(w * 0.8, h * 0.4), c = Offset(w * 0.61, h * 0.47);
    final line = Paint()
      ..color = _Night.teal.withValues(alpha: 0.7)
      ..strokeWidth = 1;
    canvas
      ..drawLine(a, b, line)
      ..drawLine(a, c, line);
    p.color = _Night.ink;
    canvas
      ..drawCircle(a, 3.5, p)
      ..drawCircle(b, 2.5, p)
      ..drawCircle(c, 2.5, p);

    final far = Path()
      ..moveTo(0, h * 0.73)
      ..cubicTo(w * 0.17, h * 0.53, w * 0.3, h * 0.67, w * 0.44, h * 0.6)
      ..cubicTo(w * 0.6, h * 0.53, w * 0.75, h * 0.45, w, h * 0.63)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(far, Paint()..color = _Night.hill);

    final deep = Paint()..color = _Night.deep;
    // tower: body, roof, battlements
    final tx = w * 0.2;
    canvas.drawRect(Rect.fromLTWH(tx, h * 0.48, 22, h * 0.36), deep);
    canvas.drawPath(
        Path()
          ..moveTo(tx - 4, h * 0.48)
          ..lineTo(tx + 26, h * 0.48)
          ..lineTo(tx + 22, h * 0.43)
          ..lineTo(tx, h * 0.43)
          ..close(),
        deep);
    for (var i = 0; i < 4; i++) {
      canvas.drawRect(Rect.fromLTWH(tx - 4 + i * 8.5, h * 0.37, 5, h * 0.06), deep);
    }
    canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(tx + 7, h * 0.57, 8, 11), const Radius.circular(4)), Paint()..color = Syl.accent);
    // trees
    for (final (x, size) in [(0.5, 20.0), (0.55, 16.0), (0.84, 16.0)]) {
      canvas.drawPath(
          Path()
            ..moveTo(w * x, h * 0.82)
            ..lineTo(w * x + size / 2, h * 0.82 - size * 1.4)
            ..lineTo(w * x + size, h * 0.82)
            ..close(),
          deep);
    }
    final near = Path()
      ..moveTo(0, h * 0.85)
      ..cubicTo(w * 0.2, h * 0.73, w * 0.4, h * 0.88, w * 0.61, h * 0.79)
      ..cubicTo(w * 0.8, h * 0.74, w * 0.9, h * 0.78, w, h * 0.8)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(near, deep);
  }

  @override
  bool shouldRepaint(_HillsPainter old) => false;
}

class _NightPill extends StatelessWidget {
  const _NightPill({required this.label, required this.selected, required this.onTap, this.dot});
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color? dot;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? _Night.ink : _Night.pill,
      shape: const StadiumBorder(),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (dot != null) ...[
              Container(width: 8, height: 8, decoration: BoxDecoration(color: dot, shape: BoxShape.circle)),
              const SizedBox(width: 6),
            ],
            Text(label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected ? _Night.ground : _Night.ink,
                )),
          ]),
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

/// One entry: a jewel-toned bubble with its type's icon top right.
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
        color: _Night.type(e.type),
        borderRadius: const BorderRadius.all(Radius.circular(24)),
        child: InkWell(
          borderRadius: const BorderRadius.all(Radius.circular(24)),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => EntityScreen(entityId: e.id))),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 10, 14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  child: Wrap(spacing: 6, runSpacing: 6, children: [
                    SoftTag(typeLabel(e.type), background: Colors.white.withValues(alpha: 0.14), foreground: _Night.ink),
                    if (isNew) const _NewBadge(),
                  ]),
                ),
                const SizedBox(width: 6),
                TypeIcon(e.type),
              ]),
              const SizedBox(height: 10),
              Text(e.name, style: Syl.serif(context, fontSize: 21, fontWeight: FontWeight.w700, color: _Night.ink, height: 1.05)),
              const SizedBox(height: 7),
              Text(preview,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13.5, height: 1.35, color: _Night.ink.withValues(alpha: 0.88))),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                  child: Text('${facts.length} ${facts.length == 1 ? 'fact' : 'facts'}',
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: _Night.ink)),
                ),
                if (chapters != null)
                  Flexible(
                    child: Text(chapters,
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: _Night.ink)),
                  ),
                if (!e.lore.isEmpty) ...[
                  const SizedBox(width: 6),
                  const Icon(Icons.auto_awesome, size: 14, color: _Night.ink, semanticLabel: 'Has AI lore'),
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
      decoration: const BoxDecoration(color: Syl.accent, borderRadius: BorderRadius.all(Radius.circular(12))),
      child: const Text('New', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Syl.onAccent)),
    );
  }
}

/// A small drawn icon per type: hooded figure, tower, sword, scroll.
class TypeIcon extends StatelessWidget {
  const TypeIcon(this.type, {super.key, this.size = 32, this.color = _Night.ink});
  final String type;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: typeLabel(type),
      child: Container(
        width: size,
        height: size,
        padding: EdgeInsets.all(size * 0.22),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.12), shape: BoxShape.circle),
        child: CustomPaint(painter: _GlyphPainter(type, color.withValues(alpha: 0.85))),
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
        painter: const _DashedBorder(_Night.faint),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${parts.join(' and ')} ${total == 1 ? 'waits' : 'wait'}',
                style: Syl.serif(context, fontSize: 18, fontWeight: FontWeight.w700, color: _Night.ink)),
            const SizedBox(height: 6),
            Text('Below the horizon. ${total == 1 ? 'It rises' : 'They rise'} as you read on.',
                style: const TextStyle(fontSize: 13.5, height: 1.35, color: _Night.muted)),
          ]),
        ),
      ),
    );
  }
}

class _DashedBorder extends CustomPainter {
  const _DashedBorder(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final path = Path()..addRRect(RRect.fromRectAndRadius((Offset.zero & size).deflate(1), const Radius.circular(24)));
    for (final metric in path.computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += 10) {
        canvas.drawPath(metric.extractPath(d, d + 5), p);
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
      borderRadius: const BorderRadius.all(Radius.circular(24)),
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NewEntityScreen())),
      child: Container(
        height: 88,
        width: double.infinity,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: const BorderRadius.all(Radius.circular(24)),
          border: Border.all(color: _Night.pill, width: 2),
        ),
        child: const Text('+ New entry', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: _Night.muted)),
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
                style: const TextStyle(fontSize: 14, color: _Night.muted)),
          ),
          const Text('Switch book', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: _Night.ink)),
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
      decoration: const BoxDecoration(color: _Night.pill, borderRadius: BorderRadius.all(Radius.circular(24))),
      child: Column(children: [
        const Icon(Icons.auto_stories_outlined, size: 40, color: _Night.muted),
        const SizedBox(height: 12),
        Text(
          filtered ? 'Nothing matches. Try another word or filter.' : 'Your library is empty. Add the first character you meet.',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 15, color: _Night.ink),
        ),
      ]),
    );
  }
}
