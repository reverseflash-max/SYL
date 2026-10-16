import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/models/models.dart';
import 'package:mobile/state/library_store.dart';
import 'package:mobile/theme/syl_theme.dart';
import 'package:mobile/ui/entity_screen.dart';
import 'package:mobile/ui/home_shell.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('"I finished" moves the bookmark on a chapter, and Undo puts it back', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    const meta = EntityMeta(firstSeen: '2026-10-01', lastUpdated: '2026-10-01T10:00:00');
    final store = LibraryStore.memory(
      entities: [
        const Entity(
          id: 'aragorn',
          name: 'Aragorn',
          type: 'Character',
          book: 'LOTR',
          meta: meta,
          facts: [Fact(id: 'f1', text: 'Goes by Strider', chapter: 10, timestamp: '2026-10-01T10:00:00')],
        ),
      ],
      settings: const AppSettings(currentBook: 'LOTR', spoilerChapter: 12),
    );
    await tester.pumpWidget(ChangeNotifierProvider<LibraryStore>.value(
      value: store,
      child: MaterialApp(theme: Syl.theme(googleFonts: false), home: const HomeShell()),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('I finished ch. 12'));
    await tester.pumpAndSettle();
    expect(store.spoilerChapter, 13);
    expect(find.text('I finished ch. 13'), findsOneWidget);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(store.spoilerChapter, 12);

    // The bubble opens its entry (growing into the page on the way).
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -500));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Aragorn'));
    await tester.pumpAndSettle();
    expect(find.byType(EntityScreen), findsOneWidget);
  });
}
