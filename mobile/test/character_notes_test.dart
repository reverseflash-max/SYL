import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/models/models.dart';
import 'package:mobile/state/library_store.dart';
import 'package:mobile/theme/syl_theme.dart';
import 'package:mobile/ui/entity_screen.dart';
import 'package:mobile/ui/new_entity_screen.dart';
import 'package:provider/provider.dart';

const meta = EntityMeta(firstSeen: '2026-10-01', lastUpdated: '2026-10-01T10:00:00');

LibraryStore seeded() => LibraryStore.memory(
      entities: [
        const Entity(
          id: 'aragorn',
          name: 'Aragorn',
          type: 'Character',
          book: 'LOTR',
          meta: meta,
          facts: [Fact(id: 'f1', text: 'He is a ranger', chapter: 2, timestamp: '2026-10-01T10:00:00')],
        ),
        const Entity(id: 'galadriel', name: 'Galadriel', type: 'Character', book: 'LOTR', meta: meta),
        const Entity(id: 'vin', name: 'Vin', type: 'Character', book: 'Mistborn', meta: meta),
      ],
      settings: const AppSettings(currentBook: 'LOTR'),
    );

Future<void> pump(WidgetTester tester, LibraryStore store, Widget home) async {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 2.625;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ChangeNotifierProvider<LibraryStore>.value(
    value: store,
    child: MaterialApp(theme: Syl.theme(googleFonts: false), home: home),
  ));
  await tester.pumpAndSettle();
}

void main() {
  test('editing a fact keeps its id', () async {
    final store = seeded();
    await store.updateFact(store.byId('aragorn')!, 'f1', 'He is the heir of Isildur', 1);
    final facts = store.byId('aragorn')!.facts;
    expect(facts, hasLength(1));
    expect(facts.single.id, 'f1');
    expect(facts.single.text, 'He is the heir of Isildur');
    expect(facts.single.chapter, 1);
    expect(store.byId('aragorn')!.discoveryChapter, 1);
  });

  testWidgets('a note on a new entry becomes its first fact', (tester) async {
    final store = seeded();
    await pump(tester, store, const NewEntityScreen());
    await tester.enterText(find.widgetWithText(TextField, 'Name'), 'Boromir');
    await tester.enterText(find.widgetWithText(TextField, 'First appears in chapter'), '4');
    await tester.enterText(find.widgetWithText(TextField, 'Note (optional)'), 'Son of Denethor');
    await tester.ensureVisible(find.text('Create'));
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();
    final boromir = store.byName('Boromir')!;
    expect(boromir.facts.single.text, 'Son of Denethor');
    expect(boromir.facts.single.chapter, 4);
  });

  testWidgets('tap a fact to edit it', (tester) async {
    final store = seeded();
    await pump(tester, store, const EntityScreen(entityId: 'aragorn'));
    await tester.tap(find.text('He is a ranger'));
    await tester.pumpAndSettle();
    expect(find.text('Edit fact about Aragorn'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, 'Fact'), 'He is called Strider');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('He is called Strider'), findsOneWidget);
    expect(store.byId('aragorn')!.facts.single.id, 'f1');
  });

  testWidgets('linking shows only the same book, and the note becomes a fact', (tester) async {
    final store = seeded();
    await pump(tester, store, const EntityScreen(entityId: 'aragorn'));
    await tester.tap(find.byTooltip('Link to another entry'));
    await tester.pumpAndSettle();
    expect(find.text('Galadriel'), findsOneWidget);
    expect(find.text('Vin'), findsNothing); // another book
    await tester.tap(find.text('Galadriel'));
    await tester.tap(find.text('Friend'));
    await tester.enterText(find.widgetWithText(TextField, 'Note (optional)'), 'She gave him the Elfstone');
    await tester.enterText(find.widgetWithText(TextField, 'From chapter'), '6');
    await tester.tap(find.text('Save link'));
    await tester.pumpAndSettle();
    expect(store.linksFor('aragorn'), hasLength(1));
    final fact = store.byId('aragorn')!.facts.firstWhere((f) => f.text == 'She gave him the Elfstone');
    expect(fact.chapter, 6);
  });
}
