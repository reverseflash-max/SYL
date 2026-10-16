import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/models/models.dart';
import 'package:mobile/state/library_store.dart';
import 'package:mobile/theme/syl_theme.dart';
import 'package:mobile/ui/books_screen.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets("saving a book's sheet keeps a cover chosen while it was open", (tester) async {
    final store = LibraryStore.memory(books: const [Book(id: 'hobbit', title: 'The Hobbit', status: 'finished', coverId: 1)]);
    await tester.pumpWidget(ChangeNotifierProvider<LibraryStore>.value(
      value: store,
      child: MaterialApp(
        theme: Syl.theme(googleFonts: false),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(onPressed: () => showBookSheet(context, store.bookList.single), child: const Text('open')),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // A photo picked from the sheet's cover button (or a cover found) lands in the store...
    await store.updateBook(store.bookList.single.copyWith(coverFile: 'covers/hobbit-1.jpg', coverId: 2));
    await tester.pump();

    // ...and pressing Save must not put the old cover back.
    final save = find.text('Save');
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(store.bookList.single.coverFile, 'covers/hobbit-1.jpg');
    expect(store.bookList.single.coverId, 2);
  });
}
