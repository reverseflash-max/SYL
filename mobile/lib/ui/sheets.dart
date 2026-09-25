import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/wikidata_service.dart';
import '../state/library_store.dart';
import '../theme/syl_theme.dart';
import 'widgets/common.dart';

Future<T?> _sheet<T>(BuildContext context, Widget child) => showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: child,
      ),
    );

// ---------------------------------------------------------------------------
// Quick add: a fact for an existing entity, or a new entity with its first fact
// ---------------------------------------------------------------------------

Future<void> showQuickAdd(BuildContext context, {Entity? entity}) =>
    _sheet(context, _QuickAddSheet(entity: entity));

class _QuickAddSheet extends StatefulWidget {
  const _QuickAddSheet({this.entity});
  final Entity? entity;
  @override
  State<_QuickAddSheet> createState() => _QuickAddSheetState();
}

class _QuickAddSheetState extends State<_QuickAddSheet> {
  final _fact = TextEditingController();
  final _chapter = TextEditingController();
  final _name = TextEditingController();
  Entity? _target;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _target = widget.entity;
    final cap = context.read<LibraryStore>().spoilerChapter;
    _chapter.text = '${cap ?? 1}';
  }

  @override
  void dispose() {
    _fact.dispose();
    _chapter.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final store = context.read<LibraryStore>();
    final text = _fact.text.trim();
    final ch = int.tryParse(_chapter.text.trim());
    if (text.isEmpty || ch == null || ch < 0) {
      showMessage(context, 'Write the fact and a chapter number.');
      return;
    }
    setState(() => _saving = true);
    var target = _target;
    if (target == null) {
      final name = _name.text.trim();
      if (name.isEmpty) {
        setState(() => _saving = false);
        showMessage(context, 'Pick who or what this fact is about.');
        return;
      }
      target = store.byName(name) ?? await store.createEntity(name: name, type: 'Other', chapter: ch);
    }
    await store.addFact(target, text, ch);
    if (!mounted) return;
    Navigator.pop(context);
    showMessage(context, 'Saved to ${target.name}');
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<LibraryStore>();
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(_target == null ? 'New fact' : 'New fact about ${_target!.name}',
            style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 16),
        if (widget.entity == null) ...[
          if (_target != null)
            Row(children: [
              SoftTag('About ${_target!.name}', dot: Syl.typeDot(_target!.type), background: Syl.white),
              const SizedBox(width: 8),
              TextButton(onPressed: () => setState(() => _target = null), child: const Text('Change')),
            ])
          else ...[
            TextField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'About',
                hintText: 'Type a name (new names become new entries)',
              ),
            ),
            if (_name.text.trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final e in store.entities
                    .where((e) => e.name.toLowerCase().contains(_name.text.trim().toLowerCase()))
                    .take(5))
                  FilterPill(label: e.name, dot: Syl.typeDot(e.type), selected: false, onTap: () => setState(() => _target = e)),
              ]),
            ],
          ],
          const SizedBox(height: 12),
        ],
        TextField(
          controller: _fact,
          autofocus: widget.entity != null,
          maxLines: 4,
          minLines: 2,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: 'Fact', hintText: 'What did you just learn?'),
        ),
        const SizedBox(height: 12),
        Row(children: [
          SizedBox(
            width: 120,
            child: TextField(
              controller: _chapter,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Chapter'),
            ),
          ),
          const Spacer(),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Syl.paper))
                : const Text('Save fact'),
          ),
        ]),
      ]),
    );
  }
}

// ---------------------------------------------------------------------------
// Link two entities
// ---------------------------------------------------------------------------

const kRelationSuggestions = [
  'Mentor', 'Ally', 'Enemy', 'Friend', 'Family', 'Rules over', 'Serves', 'Member of', 'Lives in',
  'Owns', 'Created', 'Related to',
];

Future<void> showLinkSheet(BuildContext context, Entity source) => _sheet(context, _LinkSheet(source: source));

class _LinkSheet extends StatefulWidget {
  const _LinkSheet({required this.source});
  final Entity source;
  @override
  State<_LinkSheet> createState() => _LinkSheetState();
}

class _LinkSheetState extends State<_LinkSheet> {
  Entity? _target;
  String _type = 'Ally';
  final _desc = TextEditingController();
  final _chapter = TextEditingController();

  @override
  void initState() {
    super.initState();
    final cap = context.read<LibraryStore>().spoilerChapter;
    if (cap != null) _chapter.text = '$cap';
  }

  @override
  void dispose() {
    _desc.dispose();
    _chapter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<LibraryStore>();
    final others = store.entities.where((e) => e.id != widget.source.id).toList();
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Link ${widget.source.name}', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 4),
        Text(
          _target == null
              ? 'Pick who or what they are connected to.'
              : '${widget.source.name} is $_type of ${_target!.name}',
          style: const TextStyle(color: Syl.muted),
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 44,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: others.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, i) => FilterPill(
              label: others[i].name,
              selected: _target?.id == others[i].id,
              onTap: () => setState(() => _target = others[i]),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final t in kRelationSuggestions)
            ChoiceChip(
              label: Text(t),
              selected: _type == t,
              onSelected: (_) => setState(() => _type = t),
              showCheckmark: false,
              selectedColor: Syl.butter,
              backgroundColor: Syl.white,
              side: BorderSide.none,
              shape: const StadiumBorder(),
            ),
        ]),
        const SizedBox(height: 16),
        TextField(controller: _desc, decoration: const InputDecoration(labelText: 'Note (optional)')),
        const SizedBox(height: 12),
        Row(children: [
          SizedBox(
            width: 140,
            child: TextField(
              controller: _chapter,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'From chapter'),
            ),
          ),
          const Spacer(),
          FilledButton(
            onPressed: _target == null
                ? null
                : () async {
                    await store.addLink(widget.source.id, _target!.id, _type,
                        description: _desc.text, chapter: int.tryParse(_chapter.text.trim()));
                    if (context.mounted) Navigator.pop(context);
                  },
            child: const Text('Save link'),
          ),
        ]),
      ]),
    );
  }
}

// ---------------------------------------------------------------------------
// Edit an entity's name / type / book
// ---------------------------------------------------------------------------

Future<void> showEditEntity(BuildContext context, Entity e) => _sheet(context, _EditSheet(entity: e));

class _EditSheet extends StatefulWidget {
  const _EditSheet({required this.entity});
  final Entity entity;
  @override
  State<_EditSheet> createState() => _EditSheetState();
}

class _EditSheetState extends State<_EditSheet> {
  late final _name = TextEditingController(text: widget.entity.name);
  late final _book = TextEditingController(text: widget.entity.book ?? '');
  late String _type = widget.entity.type;

  @override
  void dispose() {
    _name.dispose();
    _book.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = context.read<LibraryStore>();
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Edit', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 16),
        TextField(controller: _name, decoration: const InputDecoration(labelText: 'Name')),
        const SizedBox(height: 12),
        TypePicker(value: _type, onChanged: (t) => setState(() => _type = t)),
        const SizedBox(height: 12),
        TextField(controller: _book, decoration: const InputDecoration(labelText: 'Book')),
        const SizedBox(height: 20),
        Row(children: [
          TextButton.icon(
            onPressed: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (d) => AlertDialog(
                  title: Text('Delete ${widget.entity.name}?'),
                  content: const Text('Its facts and links go too. This cannot be undone.'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
                    TextButton(onPressed: () => Navigator.pop(d, true), child: const Text('Delete', style: TextStyle(color: Syl.danger))),
                  ],
                ),
              );
              if (ok == true && context.mounted) {
                await store.deleteEntity(widget.entity.id);
                if (!context.mounted) return;
                Navigator.of(context)
                  ..pop()
                  ..pop();
              }
            },
            icon: const Icon(Icons.delete_outline, color: Syl.danger),
            label: const Text('Delete', style: TextStyle(color: Syl.danger)),
          ),
          const Spacer(),
          FilledButton(
            onPressed: () async {
              final name = _name.text.trim();
              if (name.isEmpty) return;
              final book = _book.text.trim();
              await store.updateEntity(widget.entity.copyWith(
                name: name,
                type: _type,
                book: book.isEmpty ? null : book,
                clearBook: book.isEmpty,
              ));
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ]),
      ]),
    );
  }
}

class TypePicker extends StatelessWidget {
  const TypePicker({super.key, required this.value, required this.onChanged});
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(spacing: 8, runSpacing: 8, children: [
      for (final t in kEntityTypes)
        FilterPill(label: t, dot: Syl.typeDot(t), selected: value == t, onTap: () => onChanged(t)),
    ]);
  }
}

// ---------------------------------------------------------------------------
// Wikidata picker: search, show candidates, return the chosen item's details
// ---------------------------------------------------------------------------

Future<WikidataInfo?> pickFromWikidata(BuildContext context, String query, {String? hint}) =>
    _sheet<WikidataInfo>(context, _WikidataSheet(query: query, hint: hint));

class _WikidataSheet extends StatefulWidget {
  const _WikidataSheet({required this.query, this.hint});
  final String query;
  final String? hint;
  @override
  State<_WikidataSheet> createState() => _WikidataSheetState();
}

class _WikidataSheetState extends State<_WikidataSheet> {
  late Future<List<WikidataCandidate>> _results;
  String? _fetching;

  @override
  void initState() {
    super.initState();
    _results = context.read<LibraryStore>().wikidata.search(widget.query, hint: widget.hint);
  }

  Future<void> _choose(WikidataCandidate c) async {
    setState(() => _fetching = c.id);
    try {
      final info = await context.read<LibraryStore>().wikidata.fetch(c.id);
      if (mounted) Navigator.pop(context, info);
    } catch (e) {
      if (!mounted) return;
      setState(() => _fetching = null);
      showMessage(context, e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.75),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Wikidata', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 4),
          Text('Results for "${widget.query}". Pick the right one.', style: const TextStyle(color: Syl.muted)),
          const SizedBox(height: 12),
          Flexible(
            child: FutureBuilder<List<WikidataCandidate>>(
              future: _results,
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()));
                }
                if (snap.hasError) {
                  return Padding(padding: const EdgeInsets.all(16), child: Text(snap.error.toString()));
                }
                final items = snap.data ?? [];
                if (items.isEmpty) {
                  return const Padding(padding: EdgeInsets.all(16), child: Text('Nothing on Wikidata with that name.'));
                }
                return ListView.separated(
                  shrinkWrap: true,
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    final c = items[i];
                    return Material(
                      color: Syl.white,
                      borderRadius: Syl.r20,
                      child: ListTile(
                        shape: const RoundedRectangleBorder(borderRadius: Syl.r20),
                        title: Text(c.label, style: const TextStyle(fontWeight: FontWeight.w700)),
                        subtitle: Text(c.description.isEmpty ? c.id : '${c.description} · ${c.id}'),
                        trailing: _fetching == c.id
                            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.chevron_right),
                        onTap: _fetching == null ? () => _choose(c) : null,
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ]),
      ),
    );
  }
}
