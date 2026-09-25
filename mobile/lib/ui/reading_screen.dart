import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/library_store.dart';
import '../theme/syl_theme.dart';
import 'widgets/common.dart';

/// Reading progress (spoiler shield) and the LM Studio connection.
class ReadingScreen extends StatefulWidget {
  const ReadingScreen({super.key});
  @override
  State<ReadingScreen> createState() => _ReadingScreenState();
}

class _ReadingScreenState extends State<ReadingScreen> {
  late final TextEditingController _book;
  late final TextEditingController _chapter;
  late final TextEditingController _url;
  late final TextEditingController _model;
  String? _status;
  bool _testing = false;

  @override
  void initState() {
    super.initState();
    final s = context.read<LibraryStore>().settings;
    _book = TextEditingController(text: s.currentBook ?? '');
    _chapter = TextEditingController(text: s.spoilerChapter?.toString() ?? '');
    _url = TextEditingController(text: s.lmStudioUrl);
    _model = TextEditingController(text: s.lmModel);
  }

  @override
  void dispose() {
    _book.dispose();
    _chapter.dispose();
    _url.dispose();
    _model.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final store = context.read<LibraryStore>();
    final ch = int.tryParse(_chapter.text.trim());
    final book = _book.text.trim();
    await store.updateSettings(store.settings.copyWith(
      currentBook: book.isEmpty ? null : book,
      clearBook: book.isEmpty,
      spoilerChapter: ch != null && ch > 0 ? ch : null,
      clearSpoiler: ch == null || ch <= 0,
      lmStudioUrl: _url.text.trim(),
      lmModel: _model.text.trim(),
    ));
    if (mounted) showMessage(context, 'Saved');
  }

  Future<void> _test() async {
    setState(() {
      _testing = true;
      _status = null;
    });
    final ai = context.read<LibraryStore>().ai;
    try {
      final models = await ai.listModels(_url.text.trim());
      final chosen = await ai.pickModel(_url.text.trim(), _model.text.trim());
      _status = 'Connected. Loaded: ${models.join(', ')}\nSYL will use: $chosen';
    } catch (e) {
      _status = e.toString();
    }
    if (mounted) setState(() => _testing = false);
  }

  void _bump(int d) {
    final ch = (int.tryParse(_chapter.text.trim()) ?? 0) + d;
    setState(() => _chapter.text = ch <= 0 ? '' : '$ch');
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<LibraryStore>();
    final t = Theme.of(context).textTheme;
    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 120),
        children: [
          Text('Reading', style: t.displaySmall?.copyWith(fontSize: 44)),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(color: Syl.butter, borderRadius: Syl.r24),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Text('Spoiler shield', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              const Text('Facts and links from later chapters are hidden everywhere, and never sent to the AI.',
                  style: TextStyle(fontSize: 13)),
              const SizedBox(height: 14),
              TextField(
                controller: _book,
                decoration: const InputDecoration(labelText: 'Current book'),
              ),
              if (store.books.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final b in store.books)
                    FilterPill(label: b, selected: _book.text == b, onTap: () => setState(() => _book.text = b)),
                ]),
              ],
              const SizedBox(height: 12),
              Row(children: [
                RoundIconButton(icon: Icons.remove, tooltip: 'Previous chapter', onPressed: () => _bump(-1)),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _chapter,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    decoration: const InputDecoration(labelText: "I've read up to chapter", hintText: 'Empty = off'),
                  ),
                ),
                const SizedBox(width: 8),
                RoundIconButton(icon: Icons.add, tooltip: 'Next chapter', onPressed: () => _bump(1)),
              ]),
            ]),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(color: Syl.white, borderRadius: Syl.r24),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Text('AI on your PC', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              const Text(
                'SYL uses the model loaded in LM Studio. On the PC use http://127.0.0.1:1234. '
                'On your phone use your PC\'s Wi-Fi address (e.g. http://192.168.0.109:1234) and turn on '
                '"Serve on Local Network" in LM Studio.',
                style: TextStyle(fontSize: 13, color: Syl.muted),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _url,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(labelText: 'LM Studio address'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _model,
                decoration: const InputDecoration(labelText: 'Model (optional)', hintText: 'Blank = whatever is loaded'),
              ),
              const SizedBox(height: 12),
              Row(children: [
                PillButton(label: _testing ? 'Testing...' : 'Test connection', icon: Icons.wifi_tethering, onTap: _testing ? null : _test),
              ]),
              if (_status != null) ...[
                const SizedBox(height: 10),
                Text(_status!, style: const TextStyle(fontSize: 13)),
              ],
            ]),
          ),
          const SizedBox(height: 18),
          FilledButton(onPressed: _save, child: const Text('Save')),
          const SizedBox(height: 18),
          Text('Library folder: ${store.dataPath}', style: const TextStyle(fontSize: 12, color: Syl.muted)),
        ],
      ),
    );
  }
}
