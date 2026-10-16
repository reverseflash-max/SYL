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
      settings: const AppSettings(currentBook: 'LOTR', spoilerChapter: 3),
    );
    await tester.pumpWidget(ChangeNotifierProvider<LibraryStore>.value(
      value: store,
      child: MaterialApp(theme: Syl.theme(googleFonts: false), home: const HomeShell()),
    ));
    await tester.pumpAndSettle();
    final screen = tester.getSize(find.byType(HomeShell));
    bool showing(String title) => tester.getRect(find.text(title).first).overlaps(Offset.zero & screen);
    Future<void> swipe(Finder from, double dx) async {
      await tester.fling(from, Offset(dx, 0), 1500);
      await tester.pumpAndSettle();
    }

    // Library -> Map
    expect(find.text('I finished ch. 3'), findsOneWidget);
    await swipe(find.text('LOTR').first, -300); // the book name on the Library
    expect(showing('Map'), isTrue);

    // A drag on the sky pans the map and stays on the Map tab.
    final sky = tester.getTopLeft(find.byType(InteractiveViewer)) + const Offset(200, 150);
    await tester.flingFrom(sky, const Offset(-300, 0), 1500);
    await tester.pumpAndSettle();
    expect(showing('Map'), isTrue);
    expect(find.text('New book').hitTestable(), findsNothing);

    // Below the horizon a swipe moves on to Books.
    // (beside the summary card, above the tab bar)
    final belowHorizon = Offset(screen.width - 8, screen.height - 150);
    await tester.flingFrom(belowHorizon, const Offset(-300, 0), 1500);
    await tester.pumpAndSettle();
    expect(find.text('New book').hitTestable(), findsOneWidget);

    // Books -> Settings; unsaved text survives swiping away and back.
    await swipe(find.text('Books').first, -300);
    await tester.enterText(find.widgetWithText(TextField, 'Model (optional)'), 'qwen');
    await swipe(find.text('AI on your PC'), 300);
    await swipe(find.text('Books').first, -300);
    expect(find.text('qwen'), findsOneWidget);
  });
}
