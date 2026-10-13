import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/models/models.dart';
import 'package:mobile/state/library_store.dart';
import 'package:mobile/theme/syl_theme.dart';
import 'package:mobile/ui/home_shell.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('swipe between tabs; the map pans instead; tabs keep their state', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    const meta = EntityMeta(firstSeen: '2026-10-01', lastUpdated: '2026-10-01T10:00:00');
    final store = LibraryStore.memory(
      entities: [
        const Entity(id: 'aragorn', name: 'Aragorn', type: 'Character', book: 'LOTR', meta: meta),
        const Entity(id: 'galadriel', name: 'Galadriel', type: 'Character', book: 'LOTR', meta: meta),
      ],
      relationships: const [Relationship(source: 'galadriel', target: 'aragorn', type: 'Mentor', createdAt: '')],
      settings: const AppSettings(currentBook: 'LOTR'),
    );
    await tester.pumpWidget(ChangeNotifierProvider<LibraryStore>.value(
      value: store,
      child: MaterialApp(theme: Syl.theme(googleFonts: false), home: const HomeShell()),
    ));
    await tester.pumpAndSettle();
    final screen = tester.getSize(find.byType(HomeShell));
    bool showing(String title) => tester.getRect(find.text(title).first).overlaps(Offset.zero & screen);

    // Library -> Map
    expect(showing('Library'), isTrue);
    await tester.fling(find.text('LOTR').last, const Offset(-300, 0), 1500); // the book title in the Library header
    await tester.pumpAndSettle();
    expect(showing('Map'), isTrue);

    // A drag on the map canvas pans the map and stays on the Map tab.
    final canvas = tester.getCenter(find.byType(InteractiveViewer));
    await tester.flingFrom(canvas, const Offset(-300, 0), 1500);
    await tester.pumpAndSettle();
    expect(showing('Map'), isTrue);
    expect(find.text('Spoiler shield').hitTestable(), findsNothing);

    // A swipe on the map's title moves on to Reading.
    await tester.fling(find.text('Map').first, const Offset(-300, 0), 1500);
    await tester.pumpAndSettle();
    expect(find.text('Spoiler shield').hitTestable(), findsOneWidget);

    // Unsaved text survives swiping away and back.
    await tester.enterText(find.widgetWithText(TextField, 'Model (optional)'), 'qwen');
    await tester.fling(find.text('Spoiler shield'), const Offset(300, 0), 1500);
    await tester.pumpAndSettle();
    await tester.fling(find.text('Map').first, const Offset(-300, 0), 1500);
    await tester.pumpAndSettle();
    expect(find.text('qwen'), findsOneWidget);

    // Swipe back to the Library.
    await tester.fling(find.text('Spoiler shield'), const Offset(300, 0), 1500);
    await tester.pumpAndSettle();
    await tester.fling(find.text('Map').first, const Offset(300, 0), 1500);
    await tester.pumpAndSettle();
    expect(showing('Library'), isTrue);
  });
}
