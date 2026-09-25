import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/wikidata_service.dart';
import '../state/library_store.dart';
import '../theme/syl_theme.dart';
import 'entity_screen.dart';
import 'sheets.dart';
import 'widgets/common.dart';

class NewEntityScreen extends StatefulWidget {
  const NewEntityScreen({super.key});
  @override
  State<NewEntityScreen> createState() => _NewEntityScreenState();
}

class _NewEntityScreenState extends State<NewEntityScreen> {
  final _name = TextEditingController();
  final _book = TextEditingController();
  final _chapter = TextEditingController();
  String _type = 'Character';
  WikidataInfo? _wd;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final store = context.read<LibraryStore>();
    _book.text = store.settings.currentBook ?? '';
    _chapter.text = '${store.spoilerChapter ?? 1}';
  }

  @override
  void dispose() {
    _name.dispose();
    _book.dispose();
    _chapter.dispose();
    super.dispose();
  }

  Future<void> _lookup() async {
    final q = _name.text.trim();
    if (q.isEmpty) {
      showMessage(context, 'Type a name first.');
      return;
    }
    final info = await pickFromWikidata(context, q, hint: _book.text.trim().isEmpty ? null : _book.text.trim());
    if (info == null) return;
    setState(() {
      _wd = info;
      if (info.type != 'Other') _type = info.type;
    });
  }

  Future<void> _create() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      showMessage(context, 'Give it a name.');
      return;
    }
    final store = context.read<LibraryStore>();
    if (store.byName(name) != null) {
      showMessage(context, '$name is already in your library.');
      return;
    }
    setState(() => _saving = true);
    final e = await store.createEntity(
      name: name,
      type: _type,
      book: _book.text.trim().isEmpty ? null : _book.text.trim(),
      chapter: int.tryParse(_chapter.text.trim()) ?? 1,
      wikidataInfo: _wd,
    );
    if (!mounted) return;
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => EntityScreen(entityId: e.id)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 32),
          children: [
            Row(children: [
              RoundIconButton(icon: Icons.close, tooltip: 'Cancel', onPressed: () => Navigator.pop(context)),
            ]),
            const SizedBox(height: 16),
            Text('New entry', style: Theme.of(context).textTheme.displaySmall?.copyWith(fontSize: 44)),
            const SizedBox(height: 20),
            TextField(
              controller: _name,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              onChanged: (_) {
                if (_wd != null) setState(() => _wd = null);
              },
              decoration: const InputDecoration(labelText: 'Name'),
            ),
            const SizedBox(height: 10),
            if (_wd == null)
              Align(
                alignment: Alignment.centerLeft,
                child: PillButton(label: 'Find on Wikidata', icon: Icons.travel_explore, onTap: _lookup),
              )
            else
              Container(
                padding: const EdgeInsets.all(14),
                decoration: const BoxDecoration(color: Syl.mint, borderRadius: Syl.r20),
                child: Row(children: [
                  const Icon(Icons.check_circle_outline),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${_wd!.label} · ${_wd!.id}', style: const TextStyle(fontWeight: FontWeight.w700)),
                      if (_wd!.description.isNotEmpty) Text(_wd!.description, style: const TextStyle(fontSize: 13)),
                    ]),
                  ),
                  TextButton(onPressed: () => setState(() => _wd = null), child: const Text('Remove')),
                ]),
              ),
            const SizedBox(height: 20),
            const Text('Type', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            TypePicker(value: _type, onChanged: (t) => setState(() => _type = t)),
            const SizedBox(height: 20),
            TextField(controller: _book, decoration: const InputDecoration(labelText: 'Book')),
            const SizedBox(height: 12),
            TextField(
              controller: _chapter,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'First appears in chapter'),
            ),
            const SizedBox(height: 28),
            FilledButton(
              onPressed: _saving ? null : _create,
              child: _saving
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Syl.paper))
                  : const Text('Create'),
            ),
          ],
        ),
      ),
    );
  }
}
