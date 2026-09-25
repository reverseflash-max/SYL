import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../state/library_store.dart';
import '../theme/syl_theme.dart';
import 'entity_screen.dart';
import 'new_entity_screen.dart';
import 'widgets/common.dart';

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
    final items = store.search(_query.text, type: _type);
    final books = store.entities.map((e) => e.book).whereType<String>().toSet().length;

    final left = <Entity>[], right = <Entity>[];
    var lh = 0.0, rh = 0.0;
    for (final e in items) {
      final h = _EntityCard.estimateHeight(e, store.spoilerChapter);
      if (lh <= rh) {
        left.add(e);
        lh += h;
      } else {
        right.add(e);
        rh += h;
      }
    }

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
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Names, facts, tags',
                ),
              ),
              const SizedBox(height: 16),
            ] else ...[
              Text('Library', style: t.displaySmall?.copyWith(fontSize: 52)),
              const SizedBox(height: 6),
              Text(
                '${store.entities.length} entries · ${store.visibleFactCount} facts · $books ${books == 1 ? 'book' : 'books'}',
                style: const TextStyle(fontSize: 15, color: Syl.muted),
              ),
              const SizedBox(height: 16),
              _ReadingCard(onTap: widget.onOpenReading),
              const SizedBox(height: 16),
            ],
            SizedBox(
              height: 40,
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
            else if (items.isEmpty)
              _EmptyState(filtered: _query.text.isNotEmpty || _type != null)
            else
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: Column(children: [for (final e in left) _EntityCard(e)])),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(children: [
                    for (final e in right) _EntityCard(e),
                    const _NewEntryTile(),
                  ]),
                ),
              ]),
          ],
        ),
      ),
    );
  }
}

class _ReadingCard extends StatelessWidget {
  const _ReadingCard({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<LibraryStore>().settings;
    return Material(
      color: Syl.ink,
      borderRadius: Syl.r24,
      child: InkWell(
        borderRadius: Syl.r24,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Reading now', style: TextStyle(fontSize: 12, color: Syl.onInkMuted)),
                const SizedBox(height: 2),
                Text(s.currentBook ?? 'Set your book',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Syl.paper)),
                const SizedBox(height: 6),
                Text(
                  s.spoilerChapter == null
                      ? 'Spoiler shield is off. Tap to set your chapter.'
                      : 'Nothing past chapter ${s.spoilerChapter} is shown or sent to the AI',
                  style: const TextStyle(fontSize: 12, color: Syl.onInkMuted),
                ),
              ]),
            ),
            const SizedBox(width: 12),
            Container(
              height: 32,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(color: s.spoilerChapter == null ? Syl.inkSoft : Syl.butter, borderRadius: BorderRadius.circular(16)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.shield_outlined, size: 15, color: s.spoilerChapter == null ? Syl.paper : Syl.ink),
                const SizedBox(width: 6),
                Text(s.spoilerChapter == null ? 'Off' : 'Ch. ${s.spoilerChapter}',
                    style: TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w700, color: s.spoilerChapter == null ? Syl.paper : Syl.ink)),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

class _EntityCard extends StatelessWidget {
  const _EntityCard(this.e);
  final Entity e;

  static double estimateHeight(Entity e, int? cap) {
    final n = e.visibleFacts(cap).length;
    return 110.0 + (n.clamp(0, 3) * 22) + (e.name.length > 12 ? 26 : 0);
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<LibraryStore>();
    final facts = e.visibleFacts(store.spoilerChapter);
    final preview = e.lore.description.isNotEmpty
        ? e.lore.description
        : facts.isNotEmpty
            ? facts.reversed.take(3).map((f) => f.text).join('. ')
            : (e.external.description.isNotEmpty ? e.external.description : 'Empty. Add a first fact.');
    final chapters = facts.isEmpty
        ? null
        : facts.first.chapter == facts.last.chapter
            ? 'Ch. ${facts.first.chapter}'
            : 'Ch. ${facts.first.chapter}–${facts.last.chapter}';

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Syl.cardColor(e.id),
        borderRadius: Syl.r24,
        child: InkWell(
          borderRadius: Syl.r24,
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => EntityScreen(entityId: e.id))),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SoftTag(e.type, dot: Syl.typeDot(e.type)),
              const SizedBox(height: 10),
              Text(e.name,
                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: -0.7, height: 1)),
              const SizedBox(height: 8),
              Text(preview, maxLines: 4, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, height: 1.35)),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                  child: Text('${facts.length} ${facts.length == 1 ? 'fact' : 'facts'}',
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
                ),
                if (chapters != null)
                  Flexible(
                    child: Text(chapters,
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
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
        decoration: BoxDecoration(
          borderRadius: Syl.r24,
          border: Border.all(color: Syl.line, width: 2),
        ),
        child: const Text('+ New entry', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: Syl.muted)),
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
      padding: const EdgeInsets.all(24),
      decoration: const BoxDecoration(color: Syl.white, borderRadius: Syl.r24),
      child: Column(children: [
        const Icon(Icons.auto_stories_outlined, size: 40, color: Syl.muted),
        const SizedBox(height: 12),
        Text(
          filtered ? 'Nothing matches. Try another word or filter.' : 'Your library is empty. Add the first character you meet.',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 15),
        ),
        if (!filtered) ...[
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NewEntityScreen())),
            child: const Text('New entry'),
          ),
        ],
      ]),
    );
  }
}
