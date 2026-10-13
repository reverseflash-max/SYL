import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/open_library_service.dart';
import '../state/library_store.dart';
import '../theme/syl_theme.dart';
import 'widgets/common.dart';

/// Your books: what you're reading (each with its own chapter, which is that
/// book's spoiler shield), what you want to read, and what you've finished.
class BooksScreen extends StatelessWidget {
  const BooksScreen({super.key});

  static const _sections = [('reading', 'Reading'), ('want', 'Want to read'), ('finished', 'Finished')];

  @override
  Widget build(BuildContext context) {
    final store = context.watch<LibraryStore>();
    final t = Theme.of(context).textTheme;
    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 120),
        children: [
          Row(children: [
            Expanded(child: Text('Books', style: t.displaySmall?.copyWith(fontSize: 44))),
            PillButton(label: 'New book', icon: Icons.add, onTap: () => openNewBook(context)),
          ]),
          const SizedBox(height: 6),
          Text('Each book keeps its own chapter. Nothing past it is shown or sent to the AI.',
              style: TextStyle(fontSize: 14, color: Syl.muted)),
          if (store.bookList.isEmpty) ...[
            const SizedBox(height: 24),
            Text('No books yet. Add the one you are reading.', style: TextStyle(fontSize: 15, color: Syl.muted)),
          ],
          for (final (status, label) in _sections)
            if (store.bookList.any((b) => b.status == status)) ...[
              const SizedBox(height: 22),
              Text(label, style: t.titleLarge),
              const SizedBox(height: 10),
              for (final b in store.bookList.where((b) => b.status == status)) _BookCard(book: b),
            ],
        ],
      ),
    );
  }
}

class _BookCard extends StatelessWidget {
  const _BookCard({required this.book});
  final Book book;

  @override
  Widget build(BuildContext context) {
    final store = context.read<LibraryStore>();
    final current = context.watch<LibraryStore>().settings.currentBook == book.title;
    final ch = book.chapter;
    final total = book.totalChapters;
    final name = ch == null ? null : book.chapterName(ch);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Syl.white,
        borderRadius: Syl.r24,
        child: InkWell(
          borderRadius: Syl.r24,
          onTap: () => showBookSheet(context, book),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 10, 14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(book.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                    if (book.author.isNotEmpty) Text(book.author, style: TextStyle(fontSize: 13, color: Syl.muted)),
                  ]),
                ),
                if (current) SoftTag('In the Library', background: Syl.butter),
              ]),
              if (book.status == 'finished' && book.rating != null) ...[
                const SizedBox(height: 6),
                Text('${'★' * book.rating!}${'☆' * (5 - book.rating!)}', style: const TextStyle(fontSize: 16, color: Syl.accent)),
              ],
              if (book.status == 'reading') ...[
                const SizedBox(height: 10),
                Row(children: [
                  RoundIconButton(
                    icon: Icons.remove,
                    tooltip: 'Previous chapter of ${book.title}',
                    onPressed: (ch ?? 0) <= 1 ? null : () => store.setChapter(book.title, ch! - 1),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(
                        ch == null ? 'No chapter set: nothing hidden' : 'Ch. $ch${total != null ? ' of $total' : ''}',
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                      ),
                      if (name != null)
                        Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: Syl.muted)),
                      if (ch != null && total != null) ...[
                        const SizedBox(height: 6),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(3),
                          child: LinearProgressIndicator(
                            value: (ch / total).clamp(0, 1).toDouble(),
                            minHeight: 6,
                            backgroundColor: Syl.line,
                            color: Syl.accent,
                          ),
                        ),
                      ],
                    ]),
                  ),
                  const SizedBox(width: 10),
                  RoundIconButton(
                    icon: Icons.add,
                    tooltip: 'Next chapter of ${book.title}',
                    onPressed: total != null && (ch ?? 0) >= total ? null : () => store.setChapter(book.title, (ch ?? 0) + 1),
                  ),
                ]),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// One book: chapter, total, status, rating, show it in the Library, delete
// ---------------------------------------------------------------------------

Future<void> showBookSheet(BuildContext context, Book book) => showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: _BookSheet(book: book),
      ),
    );

class _BookSheet extends StatefulWidget {
  const _BookSheet({required this.book});
  final Book book;
  @override
  State<_BookSheet> createState() => _BookSheetState();
}

class _BookSheetState extends State<_BookSheet> {
  late final _title = TextEditingController(text: widget.book.title);
  late final _author = TextEditingController(text: widget.book.author);
  late final _chapter = TextEditingController(text: widget.book.chapter?.toString() ?? '');
  late final _total = TextEditingController(text: widget.book.totalChapters?.toString() ?? '');
  late String _status = widget.book.status;
  late int? _rating = widget.book.rating;
  bool _looking = false;
  late List<String> _names = widget.book.chapterNames;

  @override
  void dispose() {
    _title.dispose();
    _author.dispose();
    _chapter.dispose();
    _total.dispose();
    super.dispose();
  }

  Future<void> _lookUp() async {
    final key = widget.book.openLibraryKey;
    final store = context.read<LibraryStore>();
    setState(() => _looking = true);
    try {
      var k = key;
      if (k == null) {
        final hits = await store.openLibrary.search(_title.text.trim());
        if (hits.isEmpty) throw OpenLibraryException('Open Library has no book by that name.');
        k = hits.first.key;
      }
      final names = await store.openLibrary.chapters(k);
      if (!mounted) return;
      if (names.isEmpty) {
        showMessage(context, 'Open Library has no chapter list for this book. Type the number of chapters.');
      } else {
        setState(() {
          _names = names;
          _total.text = '${names.length}';
        });
      }
    } catch (e) {
      if (mounted) showMessage(context, e.toString());
    } finally {
      if (mounted) setState(() => _looking = false);
    }
  }

  Future<void> _save() async {
    final store = context.read<LibraryStore>();
    final title = _title.text.trim();
    if (title.isEmpty) {
      showMessage(context, 'A book needs a title.');
      return;
    }
    final ch = int.tryParse(_chapter.text.trim());
    final total = int.tryParse(_total.text.trim());
    await store.updateBook(widget.book.copyWith(
      title: title,
      author: _author.text.trim(),
      chapter: ch != null && ch > 0 ? ch : null,
      clearChapter: ch == null || ch <= 0,
      totalChapters: total != null && total > 0 ? total : null,
      clearTotal: total == null || total <= 0,
      chapterNames: _names,
      status: _status,
      rating: _rating,
      clearRating: _rating == null,
    ));
    if (mounted) Navigator.pop(context);
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text('Remove ${widget.book.title}?'),
        content: const Text('Its entries stay in your library.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Keep')),
          TextButton(onPressed: () => Navigator.pop(d, true), child: Text('Remove', style: TextStyle(color: Syl.danger))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await context.read<LibraryStore>().deleteBook(widget.book.id);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<LibraryStore>();
    final current = store.settings.currentBook == widget.book.title;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(widget.book.title, style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 14),
        TextField(controller: _title, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Title')),
        const SizedBox(height: 10),
        TextField(controller: _author, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Author')),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: TextField(
              controller: _chapter,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: "I've read up to chapter", hintText: 'Empty = no shield'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _total,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Chapters in the book'),
            ),
          ),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: Text(
              _names.isEmpty ? 'No chapter names yet.' : '${_names.length} chapter names from Open Library.',
              style: TextStyle(fontSize: 13, color: Syl.muted),
            ),
          ),
          TextButton(
            onPressed: _looking ? null : _lookUp,
            child: Text(_looking ? 'Looking...' : 'Look up chapters'),
          ),
        ]),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final (s, label) in const [('reading', 'Reading'), ('want', 'Want to read'), ('finished', 'Finished')])
            FilterPill(label: label, selected: _status == s, onTap: () => setState(() => _status = s)),
        ]),
        if (_status == 'finished') ...[
          const SizedBox(height: 12),
          Row(children: [
            Text('Your rating', style: TextStyle(color: Syl.muted)),
            const SizedBox(width: 6),
            for (var i = 1; i <= 5; i++)
              IconButton(
                tooltip: '$i ${i == 1 ? 'star' : 'stars'}',
                onPressed: () => setState(() => _rating = _rating == i ? null : i),
                icon: Icon(i <= (_rating ?? 0) ? Icons.star_rounded : Icons.star_outline_rounded, color: Syl.accent),
              ),
          ]),
        ],
        const SizedBox(height: 16),
        if (!current)
          OutlinedButton(
            onPressed: () async {
              await store.setCurrentBook(widget.book.title);
              if (context.mounted) showMessage(context, 'The Library now shows ${widget.book.title}');
            },
            child: const Text('Show this book in the Library'),
          ),
        const SizedBox(height: 8),
        FilledButton(onPressed: _save, child: const Text('Save')),
        const SizedBox(height: 4),
        TextButton(onPressed: _delete, child: Text('Remove book', style: TextStyle(color: Syl.danger))),
      ]),
    );
  }
}

// ---------------------------------------------------------------------------
// New book: look it up on Open Library, or type it in
// ---------------------------------------------------------------------------

Future<void> openNewBook(BuildContext context) =>
    Navigator.push(context, MaterialPageRoute(builder: (_) => const NewBookScreen()));

class NewBookScreen extends StatefulWidget {
  const NewBookScreen({super.key});
  @override
  State<NewBookScreen> createState() => _NewBookScreenState();
}

class _NewBookScreenState extends State<NewBookScreen> {
  final _title = TextEditingController();
  final _author = TextEditingController();
  final _chapter = TextEditingController(text: '1');
  final _total = TextEditingController();
  String _status = 'reading';
  List<OpenLibraryBook>? _hits;
  OpenLibraryBook? _picked;
  List<String> _names = [];
  bool _busy = false;

  @override
  void dispose() {
    _title.dispose();
    _author.dispose();
    _chapter.dispose();
    _total.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final q = _title.text.trim();
    if (q.isEmpty) {
      showMessage(context, 'Type the title first.');
      return;
    }
    setState(() => _busy = true);
    try {
      final hits = await context.read<LibraryStore>().openLibrary.search(q);
      if (mounted) setState(() => _hits = hits);
      if (hits.isEmpty && mounted) showMessage(context, 'Nothing found. You can still add it yourself.');
    } catch (e) {
      if (mounted) showMessage(context, e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pick(OpenLibraryBook b) async {
    setState(() {
      _picked = b;
      _hits = null;
      _title.text = b.title;
      _author.text = b.author;
      _busy = true;
    });
    try {
      final names = await context.read<LibraryStore>().openLibrary.chapters(b.key);
      if (!mounted) return;
      setState(() {
        _names = names;
        if (names.isNotEmpty) _total.text = '${names.length}';
      });
    } catch (e) {
      if (mounted) showMessage(context, e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    if (title.isEmpty) {
      showMessage(context, 'A book needs a title.');
      return;
    }
    final store = context.read<LibraryStore>();
    if (store.bookByTitle(title) != null) {
      showMessage(context, '$title is already in your books.');
      return;
    }
    final ch = int.tryParse(_chapter.text.trim());
    final total = int.tryParse(_total.text.trim());
    await store.addBook(
      title: title,
      author: _author.text.trim(),
      totalChapters: total != null && total > 0 ? total : null,
      chapterNames: _names,
      chapter: _status == 'want' ? null : (ch != null && ch > 0 ? ch : null),
      status: _status,
      openLibraryKey: _picked?.key,
    );
    if (!mounted) return;
    Navigator.pop(context);
    showMessage(context, 'Added $title');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 32),
          children: [
            Row(children: [RoundIconButton(icon: Icons.close, tooltip: 'Cancel', onPressed: () => Navigator.pop(context))]),
            const SizedBox(height: 16),
            Text('New book', style: Theme.of(context).textTheme.displaySmall?.copyWith(fontSize: 44)),
            const SizedBox(height: 20),
            TextField(
              controller: _title,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              onSubmitted: (_) => _search(),
              decoration: const InputDecoration(labelText: 'Title'),
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: PillButton(
                label: _busy ? 'Looking...' : 'Find on Open Library',
                icon: Icons.travel_explore,
                onTap: _busy ? null : _search,
              ),
            ),
            if (_hits != null)
              for (final h in _hits!)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(h.title),
                  subtitle: Text([h.author, if (h.year != null) '${h.year}'].where((s) => s.isNotEmpty).join(' · ')),
                  onTap: () => _pick(h),
                ),
            if (_picked != null) ...[
              const SizedBox(height: 10),
              Text(
                _names.isEmpty
                    ? (_busy ? 'Looking for its chapters...' : 'No chapter list on Open Library. Type the number of chapters below.')
                    : 'Found ${_names.length} chapters: ${_names.take(3).join(', ')}${_names.length > 3 ? '...' : ''}',
                style: TextStyle(fontSize: 13, color: Syl.muted),
              ),
            ],
            const SizedBox(height: 16),
            TextField(controller: _author, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Author')),
            const SizedBox(height: 10),
            TextField(
              controller: _total,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Chapters in the book', hintText: 'Optional'),
            ),
            const SizedBox(height: 16),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final (s, label) in const [('reading', 'Reading now'), ('want', 'Want to read'), ('finished', 'Finished')])
                FilterPill(label: label, selected: _status == s, onTap: () => setState(() => _status = s)),
            ]),
            if (_status != 'want') ...[
              const SizedBox(height: 12),
              TextField(
                controller: _chapter,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: "I've read up to chapter"),
              ),
            ],
            const SizedBox(height: 24),
            FilledButton(onPressed: _busy ? null : _save, child: const Text('Add book')),
          ],
        ),
      ),
    );
  }
}

/// A dropdown of your books (plus "No book"), for new entries and facts.
class BookPicker extends StatelessWidget {
  const BookPicker({super.key, required this.value, required this.onChanged});
  final String? value;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final titles = context.watch<LibraryStore>().books;
    final v = value != null && titles.contains(value) ? value : null;
    return DropdownButtonFormField<String?>(
      initialValue: v,
      isExpanded: true,
      dropdownColor: Syl.white,
      decoration: const InputDecoration(labelText: 'Book'),
      items: [
        for (final t in titles) DropdownMenuItem(value: t, child: Text(t, overflow: TextOverflow.ellipsis)),
        const DropdownMenuItem(value: null, child: Text('No book')),
      ],
      onChanged: onChanged,
    );
  }
}
