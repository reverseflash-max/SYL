import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mobile/models/models.dart';
import 'package:mobile/services/open_library_service.dart';
import 'package:mobile/services/sync_service.dart';
import 'package:mobile/state/library_store.dart';

const meta = EntityMeta(firstSeen: '2026-10-01', lastUpdated: '2026-10-01T10:00:00');
Fact f(String t, int ch) => Fact(id: '$t$ch', text: t, chapter: ch, timestamp: '2026-10-01T10:00:00');

void main() {
  test('an older library gets one book per title, all at the old chapter', () {
    final store = LibraryStore.memory(
      entities: [
        const Entity(id: 'vin', name: 'Vin', type: 'Character', book: 'Mistborn', meta: meta),
        const Entity(id: 'frodo', name: 'Frodo', type: 'Character', book: 'LOTR', meta: meta),
      ],
      settings: const AppSettings(currentBook: 'LOTR', spoilerChapter: 12),
    );
    expect(store.bookList.map((b) => (b.title, b.chapter)), [('LOTR', 12), ('Mistborn', 12)]);
    expect(store.spoilerChapter, 12);
  });

  test('each book shields its own entries', () async {
    final store = LibraryStore.memory(
      entities: [
        Entity(id: 'vin', name: 'Vin', type: 'Character', book: 'Mistborn', meta: meta, facts: [f('thief', 1), f('noble', 5)]),
        Entity(id: 'frodo', name: 'Frodo', type: 'Character', book: 'LOTR', meta: meta, facts: [f('ring', 1), f('blade', 12)]),
      ],
      settings: const AppSettings(currentBook: 'LOTR'),
      books: const [Book(id: 'lotr', title: 'LOTR', chapter: 12), Book(id: 'mistborn', title: 'Mistborn', chapter: 3)],
    );
    expect(store.byId('frodo')!.visibleFacts(store.capFor(store.byId('frodo')!)).length, 2);
    expect(store.byId('vin')!.visibleFacts(store.capFor(store.byId('vin')!)).length, 1);

    await store.setChapter('Mistborn', 5);
    expect(store.byId('vin')!.visibleFacts(store.capFor(store.byId('vin')!)).length, 2);
    expect(store.chapterFor('LOTR'), 12); // the other book didn't move
  });

  test('renaming a book carries its entries along; new books can be added', () async {
    final store = LibraryStore.memory(
      entities: [const Entity(id: 'frodo', name: 'Frodo', type: 'Character', book: 'LOTR', meta: meta)],
      settings: const AppSettings(currentBook: 'LOTR'),
      books: const [Book(id: 'lotr', title: 'LOTR', chapter: 12)],
    );
    await store.updateBook(store.bookByTitle('LOTR')!.copyWith(title: 'The Lord of the Rings'));
    expect(store.byId('frodo')!.book, 'The Lord of the Rings');
    expect(store.settings.currentBook, 'The Lord of the Rings');

    final b = await store.addBook(title: 'Mistborn', totalChapters: 38, chapter: 1);
    expect(store.bookList.length, 2);
    expect(b.totalChapters, 38);
    expect(store.settings.currentBook, 'The Lord of the Rings'); // the Library keeps its book
  });

  test('"mistborn" and "Mistborn" are one book, and entries follow its spelling', () async {
    final store = LibraryStore.memory(
      entities: [
        const Entity(id: 'kelsier', name: 'Kelsier', type: 'Character', book: 'Mistborn', meta: meta),
        const Entity(id: 'vin', name: 'Vin', type: 'Character', book: 'mistborn ', meta: meta),
        const Entity(id: 'ron', name: 'Ron', type: 'Character', book: 'Harry Potter', meta: meta),
      ],
      settings: const AppSettings(currentBook: 'mistborn'),
      books: const [
        Book(id: 'mistborn', title: 'mistborn', chapter: 5, updatedAt: '2026-10-02T10:00:00'),
        Book(id: 'mistborn-2', title: 'Mistborn', updatedAt: '2026-10-01T10:00:00'),
      ],
    );
    expect(store.books.length, 2); // one Mistborn, however it's spelled
    await store.tidyBooks();
    expect(store.books, ['Harry Potter', 'Mistborn']);
    expect(store.bookList.map((b) => (b.title, b.chapter)), [('Mistborn', 5), ('Harry Potter', null)]);
    expect(store.byId('vin')!.book, 'Mistborn');
    expect(store.settings.currentBook, 'Mistborn');
  });

  test('a cover you chose is remembered with the book', () {
    const b = Book(id: 'lotr', title: 'LOTR', coverId: 14627060, coverFile: 'covers/lotr-1.jpg');
    final back = Book.fromJson(b.toJson());
    expect(back.coverFile, 'covers/lotr-1.jpg');
    expect(back.coverId, 14627060); // the Open Library one stays as the fallback
    expect(back.copyWith(clearCoverFile: true).coverFile, isNull);
  });

  test('Open Library tables of contents are cleaned down to the chapters', () {
    // Shapes taken from real Open Library editions.
    expect(
      cleanChapters(['NOTE ON THE TEXT', 'FOREWORD TO THE SECOND EDITION', 'PROLOGUE Concerning Hobbits', 'BOOK ONE',
          'A Long-expected Party', 'The Shadow of the Past', '', 'BOOK TWO', 'Many Meetings']),
      ['A Long-expected Party', 'The Shadow of the Past', 'Many Meetings'],
    );
    expect(cleanChapters(['CONTENTS', 'PROLOGUE', 'PART ONE: THE SURVIVOR OF HATHSIN', 'CHAPTER 1', 'CHAPTER 2', 'EPILOGUE', 'ARS ARCANUM']),
        ['Chapter 1', 'Chapter 2']);
  });

  test('the edition with the fullest contents wins', () async {
    final client = MockClient((req) async => http.Response.bytes(
        utf8.encode(jsonEncode({
          'entries': [
            {'table_of_contents': []},
            {
              'table_of_contents': [
                {'title': 'Book One'},
                {'title': 'A Long-expected Party'},
                {'title': 'The Shadow of the Past'},
              ]
            },
            {
              'table_of_contents': [
                {'title': ''},
                {'title': ''},
              ]
            },
          ]
        })),
        200));
    final names = await OpenLibraryService(client: client).chapters('/works/OL27513W');
    expect(names, ['A Long-expected Party', 'The Shadow of the Past']);
  });

  test('books go to the PC and come back; an older PC without books keeps ours', () async {
    late Map<String, dynamic> sent;
    var pcHasBooks = true;
    final client = MockClient((req) async {
      sent = jsonDecode(utf8.decode(req.bodyBytes)) as Map<String, dynamic>;
      return http.Response.bytes(
          utf8.encode(jsonEncode({
            'entities': [],
            'relationships': [],
            'deleted': {},
            if (pcHasBooks) 'books': [const Book(id: 'lotr', title: 'LOTR', chapter: 14).toJson()],
          })),
          200);
    });
    final store = LibraryStore.memory(
      books: const [Book(id: 'lotr', title: 'LOTR', chapter: 12)],
      settings: const AppSettings(syncUrl: 'http://pc:8765', syncCode: '1'),
      sync: SyncService(client: client),
    );
    await store.syncWithPc();
    expect((sent['books'] as List).single['chapter'], 12);
    expect(store.chapterFor('LOTR'), 14);

    pcHasBooks = false;
    await store.syncWithPc();
    expect(store.chapterFor('LOTR'), 14);
  });
}
