import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/models/models.dart';
import 'package:mobile/state/library_store.dart';
import 'package:mobile/theme/syl_theme.dart';
import 'package:mobile/ui/home_shell.dart';
import 'package:provider/provider.dart';

LibraryStore seeded() {
  final meta = EntityMeta.fresh('test');
  Entity e(String id, String name, List<Fact> facts, {String? wd, List<String> aliases = const []}) => Entity(
        id: id,
        name: name,
        type: 'Character',
        book: 'The Lord of the Rings',
        facts: facts,
        external: ExternalData(wikidataId: wd, description: 'fictional character', aliases: aliases),
        meta: meta,
      );
  Fact f(String t, int ch) => Fact(id: '$t$ch', text: t, chapter: ch, timestamp: '2026-09-20T00:00:00');
  return LibraryStore.memory(
    entities: [
      e('Q204274', 'Galadriel', [f('She is from Lothlórien', 1), f('She offers gifts to Frodo', 3)], wd: 'Q204274'),
      e('Q180322', 'Aragorn', [f('He is the heir to the throne', 1), f('He drew his sword', 7)], wd: 'Q180322', aliases: ['Strider']),
      e('frodo-baggins', 'Frodo Baggins', []),
    ],
    relationships: [
      const Relationship(source: 'Q204274', target: 'Q180322', type: 'Mentor', createdAt: '2026-09-20T00:00:00'),
    ],
    settings: const AppSettings(currentBook: 'The Lord of the Rings', spoilerChapter: 5),
  );
}

Widget app(LibraryStore store) => ChangeNotifierProvider<LibraryStore>.value(
      value: store,
      child: MaterialApp(theme: Syl.theme(googleFonts: false), home: const HomeShell()),
    );

void main() {
  testWidgets('every screen opens and the spoiler shield holds', (tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final store = seeded();
    await tester.pumpWidget(app(store));
    await tester.pumpAndSettle();

    // Library
    expect(find.text('Library'), findsWidgets);
    expect(find.text('Galadriel'), findsOneWidget);
    expect(find.text('Aragorn'), findsOneWidget);
    expect(find.textContaining('Ch. 5'), findsWidgets);

    // Entity screen: facts, spoiler hiding, link, mention
    await tester.tap(find.text('Aragorn'));
    await tester.pumpAndSettle();
    expect(find.text('He is the heir to the throne'), findsOneWidget);
    expect(find.text('He drew his sword'), findsNothing); // chapter 7 > spoiler 5
    expect(find.textContaining('hidden by the spoiler shield'), findsOneWidget);
    expect(find.text('Galadriel'), findsOneWidget); // incoming Mentor link
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Galadriel'));
    await tester.pumpAndSettle();
    expect(find.text('Frodo Baggins'), findsOneWidget); // mentioned in a fact
    expect(find.text('Mentor of'), findsOneWidget);

    // Quick add a fact from the entity screen
    await tester.tap(find.text('Add fact'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Fact'), 'She holds Nenya');
    await tester.tap(find.text('Save fact'));
    await tester.pumpAndSettle();
    expect(find.text('She holds Nenya'), findsOneWidget);
    expect(store.byId('Q204274')!.facts.length, 3);
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();

    // Map
    await tester.tap(find.byIcon(Icons.hub_outlined));
    await tester.pumpAndSettle();
    expect(find.text('Map'), findsWidgets);
    expect(find.text('Mentor'), findsOneWidget);
    await tester.tap(find.text('Aragorn').first);
    await tester.pumpAndSettle();

    // Reading / settings
    await tester.tap(find.byIcon(Icons.menu_book_outlined));
    await tester.pumpAndSettle();
    expect(find.text('Spoiler shield'), findsOneWidget);
    expect(find.text('AI on your PC'), findsOneWidget);

    // Global quick add creates a new entity
    await tester.tap(find.byTooltip('Add a fact'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'About'), 'Samwise Gamgee');
    await tester.enterText(find.widgetWithText(TextField, 'Fact'), 'He is a gardener');
    await tester.tap(find.text('Save fact'));
    await tester.pumpAndSettle();
    expect(store.byName('Samwise Gamgee')!.facts.single.text, 'He is a gardener');
  });
}
