import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/models/models.dart';
import 'package:mobile/state/library_store.dart';
import 'package:mobile/theme/syl_theme.dart';
import 'package:mobile/ui/map_screen.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('the map shows one book at a time, plus a No book choice', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    const meta = EntityMeta(firstSeen: '2026-10-01', lastUpdated: '2026-10-01T10:00:00');
    Entity e(String id, String name, String? book) => Entity(id: id, name: name, type: 'Character', book: book, meta: meta);
    final store = LibraryStore.memory(
      entities: [e('aragorn', 'Aragorn', 'The Lord of the Rings'), e('vin', 'Vin', 'Mistborn'), e('stray', 'Stray', null)],
      settings: const AppSettings(currentBook: 'Mistborn'),
    );
    await tester.pumpWidget(ChangeNotifierProvider<LibraryStore>.value(
      value: store,
      child: MaterialApp(theme: Syl.theme(googleFonts: false), home: const Scaffold(body: MapScreen())),
    ));
    await tester.pumpAndSettle();

    expect(find.text('All books'), findsNothing);
    expect(find.text('Vin'), findsWidgets); // current book first
    expect(find.text('Aragorn'), findsNothing);
    expect(find.text('Stray'), findsNothing);

    await tester.scrollUntilVisible(find.text('No book'), 120, scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('No book'));
    await tester.pumpAndSettle();
    expect(find.text('Stray'), findsWidgets);
    expect(find.text('Vin'), findsNothing);
  });

  testWidgets('a single book needs no book choices', (tester) async {
    const meta = EntityMeta(firstSeen: '2026-10-01', lastUpdated: '2026-10-01T10:00:00');
    final store = LibraryStore.memory(
      entities: [const Entity(id: 'vin', name: 'Vin', type: 'Character', book: 'Mistborn', meta: meta)],
    );
    await tester.pumpWidget(ChangeNotifierProvider<LibraryStore>.value(
      value: store,
      child: MaterialApp(theme: Syl.theme(googleFonts: false), home: const Scaffold(body: MapScreen())),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Mistborn'), findsOneWidget); // the subtitle, no pill
    expect(find.text('Vin'), findsWidgets);
  });
}
