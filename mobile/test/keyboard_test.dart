import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/models/models.dart';
import 'package:mobile/state/library_store.dart';
import 'package:mobile/theme/syl_theme.dart';
import 'package:mobile/ui/home_shell.dart';
import 'package:mobile/ui/new_entity_screen.dart';
import 'package:mobile/ui/widgets/keyboard.dart';
import 'package:provider/provider.dart';

Widget app(LibraryStore store, Widget home) => ChangeNotifierProvider<LibraryStore>.value(
      value: store,
      child: MaterialApp(
        theme: Syl.theme(googleFonts: false),
        navigatorObservers: [DropFocusOnPush()],
        builder: (context, child) => TapAwayToCloseKeyboard(child: child!),
        home: home,
      ),
    );

void main() {
  final store = LibraryStore.memory(
    settings: const AppSettings(currentBook: 'LOTR'),
    books: const [Book(id: 'lotr', title: 'LOTR', chapter: 3), Book(id: 'mistborn', title: 'Mistborn', chapter: 1)],
  );

  testWidgets('picking a book from a dropdown does not bring the keyboard back', (tester) async {
    await tester.pumpWidget(app(store, const NewEntityScreen()));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextField, 'Name'));
    await tester.pump();
    expect(tester.testTextInput.isVisible, isTrue);

    await tester.tap(find.text('LOTR'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mistborn').last);
    await tester.pumpAndSettle();
    expect(tester.testTextInput.isVisible, isFalse);
  });

  testWidgets('a text box on another tab lets go of the keyboard when you swipe away', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app(store, const HomeShell()));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.tune));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextField, 'Model (optional)'));
    await tester.pump();
    expect(tester.testTextInput.isVisible, isTrue);

    await tester.tap(find.byIcon(Icons.hub_outlined));
    await tester.pumpAndSettle();
    expect(tester.testTextInput.isVisible, isFalse);

    // and the Map's book list doesn't hand it back either
    await tester.tap(find.text('LOTR').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mistborn').last);
    await tester.pumpAndSettle();
    expect(tester.testTextInput.isVisible, isFalse);
  });
}
