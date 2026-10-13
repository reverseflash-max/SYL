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

  @override
  Widget build(BuildContext context) {
    final store = context.watch<LibraryStore>();
    final t = Theme.of(context).textTheme;
    final reading = store.bookList.where((b) => b.status == 'reading').toList();
    final want = store.bookList.where((b) => b.status == 'want').toList();
    final finished = store.bookList.where((b) => b.status == 'finished').toList();
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
              style: TextStyle(fontSize: 14, color: Syl.muted, height: 1.35)),
          if (store.bookList.isEmpty) ...[
            const SizedBox(height: 28),
            _EmptyShelf(onAdd: () => openNewBook(context)),
          ],
          if (reading.isNotEmpty) ...[
            _Heading('Reading', reading.length),
            for (final b in reading) _ReadingCard(book: b),
          ],
          if (want.isNotEmpty) ...[
            _Heading('Want to read', want.length),
            _Shelf(books: want),
          ],
          if (finished.isNotEmpty) ...[
            _Heading('Finished', finished.length),
            _Shelf(books: finished, showRating: true),
          ],
        ],
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.label, this.count);
  final String label;
  final int count;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(2, 26, 2, 12),
        child: Row(children: [
          Text(label.toUpperCase(),
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1.6, color: Syl.muted)),
          const SizedBox(width: 8),
          Text('$count', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Syl.muted)),
          const SizedBox(width: 10),
          Expanded(child: Container(height: 1, color: Syl.line)),
        ]),
      );
}

/// A book you're reading: title and author, your chapter (and its name),
/// progress, buttons to move on or back, and the cover on the right.
class _ReadingCard extends StatelessWidget {
  const _ReadingCard({required this.book});
  final Book book;

  @override
  Widget build(BuildContext context) {
    final store = context.read<LibraryStore>();
    final current = context.watch<LibraryStore>().settings.currentBook == book.title;
    final ch = book.chapter;
    final total = book.totalChapters;
    final name = ch == null ? null : book.chapterName(ch);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Syl.white,
        borderRadius: const BorderRadius.all(Radius.circular(26)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => showBookSheet(context, book),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 14, 14),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  if (current) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                      decoration: const BoxDecoration(color: Syl.accent, borderRadius: BorderRadius.all(Radius.circular(10))),
                      child: const Text('In the Library',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Syl.onAccent)),
                    ),
                    const SizedBox(height: 8),
                  ],
                  Text(book.title,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: Syl.serif(context, fontSize: 21, fontWeight: FontWeight.w700, color: Syl.ink, height: 1.12)),
                  if (book.author.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(book.author, style: TextStyle(fontSize: 13, color: Syl.muted)),
                  ],
                  const SizedBox(height: 14),
                  Text.rich(
                    TextSpan(children: [
                      if (ch == null)
                        const TextSpan(text: 'No chapter set')
                      else ...[
                        TextSpan(text: 'Ch. $ch', style: const TextStyle(fontWeight: FontWeight.w800)),
                        if (total != null) TextSpan(text: ' of $total', style: TextStyle(color: Syl.muted)),
                      ],
                    ]),
                    style: const TextStyle(fontSize: 15),
                  ),
                  if (name != null)
                    Text(name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Syl.serif(context, fontSize: 14, fontStyle: FontStyle.italic, color: Syl.muted)),
                  if (ch != null && total != null) ...[
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: (ch / total).clamp(0, 1).toDouble(),
                        minHeight: 7,
                        backgroundColor: Syl.line,
                        color: Syl.accent,
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  _Stepper(
                    title: book.title,
                    onBack: (ch ?? 0) <= 1 ? null : () => store.setChapter(book.title, ch! - 1),
                    onNext: total != null && (ch ?? 0) >= total ? null : () => store.setChapter(book.title, (ch ?? 0) + 1),
                  ),
                ]),
              ),
              const SizedBox(width: 14),
              BookCoverImage(book: book, width: 84),
            ]),
          ),
        ),
      ),
    );
  }
}

/// "‹  ›" for moving your chapter, in one small pill.
class _Stepper extends StatelessWidget {
  const _Stepper({required this.title, required this.onBack, required this.onNext});
  final String title;
  final VoidCallback? onBack;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    Widget button(IconData icon, String tip, VoidCallback? onTap) => IconButton(
          tooltip: '$tip of $title',
          onPressed: onTap,
          icon: Icon(icon, size: 22),
          color: Syl.ink,
          disabledColor: Syl.line,
        );
    return Container(
      decoration: BoxDecoration(color: Syl.paper.withValues(alpha: 0.55), borderRadius: BorderRadius.circular(24)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        button(Icons.remove, 'Previous chapter', onBack),
        Container(width: 1, height: 22, color: Syl.line),
        button(Icons.add, 'Next chapter', onNext),
      ]),
    );
  }
}

/// Books you want to read or have finished, as a row of covers.
class _Shelf extends StatelessWidget {
  const _Shelf({required this.books, this.showRating = false});
  final List<Book> books;
  final bool showRating;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: showRating ? 214 : 196,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: books.length,
        separatorBuilder: (_, __) => const SizedBox(width: 14),
        itemBuilder: (_, i) {
          final b = books[i];
          return SizedBox(
            width: 100,
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => showBookSheet(context, b),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                BookCoverImage(book: b, width: 100),
                const SizedBox(height: 6),
                Text(b.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, height: 1.2)),
                if (showRating && b.rating != null)
                  Text('${'★' * b.rating!}${'☆' * (5 - b.rating!)}', style: const TextStyle(fontSize: 14, color: Syl.accent)),
              ]),
            ),
          );
        },
      ),
    );
  }
}

class _EmptyShelf extends StatelessWidget {
  const _EmptyShelf({required this.onAdd});
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(color: Syl.white, borderRadius: Syl.r24),
        child: Column(children: [
          Icon(Icons.auto_stories_outlined, size: 40, color: Syl.muted),
          const SizedBox(height: 10),
          const Text('No books yet. Add the one you are reading.', textAlign: TextAlign.center, style: TextStyle(fontSize: 15)),
          const SizedBox(height: 14),
          FilledButton(onPressed: onAdd, child: const Text('Add a book')),
        ]),
      );
}

/// The book's cover from Open Library, or a cloth-bound placeholder with the
/// title while there is none (or no connection). Looks for a cover once if
/// the book has none yet.
class BookCoverImage extends StatelessWidget {
  const BookCoverImage({super.key, required this.book, this.width = 72});
  final Book book;
  final double width;

  static const _cloths = [Color(0xFF2C3B2F), Color(0xFF4A2326), Color(0xFF3B3350), Color(0xFF2D3A44)];

  @override
  Widget build(BuildContext context) {
    if (book.coverId == null) {
      final store = context.read<LibraryStore>();
      WidgetsBinding.instance.addPostFrameCallback((_) => store.findCover(book));
    }
    final h = width * 1.5;
    final placeholder = _placeholder(context, h);
    return ExcludeSemantics(
      child: Container(
        width: width,
        height: h,
        decoration: const BoxDecoration(
          borderRadius: BorderRadius.horizontal(left: Radius.circular(4), right: Radius.circular(8)),
          boxShadow: [BoxShadow(color: Color(0x66000000), blurRadius: 14, offset: Offset(0, 6))],
        ),
        clipBehavior: Clip.antiAlias,
        child: book.coverUrl == null
            ? placeholder
            : Image.network(
                book.coverUrl!,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => placeholder,
                loadingBuilder: (_, child, progress) => progress == null ? child : placeholder,
              ),
      ),
    );
  }

  Widget _placeholder(BuildContext context, double h) {
    var hash = 0;
    for (final c in book.title.codeUnits) {
      hash = (hash * 31 + c) & 0x7fffffff;
    }
    final base = _cloths[hash % _cloths.length];
    return Container(
      color: base,
      padding: const EdgeInsets.all(5),
      child: Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(border: Border.all(color: const Color(0x55E9E2CC))),
        child: Text(book.title,
            textAlign: TextAlign.center,
            maxLines: 5,
            overflow: TextOverflow.ellipsis,
            style: Syl.serif(context, fontSize: width < 80 ? 11 : 13, color: const Color(0xFFE9E2CC), height: 1.15)),
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
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: Text(widget.book.title, style: Theme.of(context).textTheme.headlineMedium)),
          const SizedBox(width: 12),
          BookCoverImage(book: store.bookList.where((b) => b.id == widget.book.id).firstOrNull ?? widget.book, width: 64),
        ]),
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
      coverId: _picked?.coverId,
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
                  leading: SizedBox(
                    width: 36,
                    height: 54,
                    child: h.coverId == null
                        ? Icon(Icons.menu_book_outlined, color: Syl.muted)
                        : Image.network('https://covers.openlibrary.org/b/id/${h.coverId}-S.jpg',
                            fit: BoxFit.cover, errorBuilder: (_, __, ___) => Icon(Icons.menu_book_outlined, color: Syl.muted)),
                  ),
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
