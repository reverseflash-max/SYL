import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/models/models.dart';
import 'package:mobile/models/reading_stats.dart';
import 'package:mobile/state/library_store.dart';
import 'package:mobile/theme/syl_theme.dart';
import 'package:mobile/ui/stats_screen.dart';
import 'package:provider/provider.dart';

Book read(String id, List<String> days, {String status = 'reading', String? finishedAt, double? rating}) => Book(
      id: id,
      title: id,
      status: status,
      finishedAt: finishedAt,
      rating: rating,
      readingLog: [for (final d in days) ReadingDay(d, chapters: 1)],
    );

void main() {
  group('streak', () {
    final now = DateTime(2026, 10, 23, 9); // a Friday

    test('counts the days in the current run', () {
      final s = ReadingStats([read('a', ['2026-10-21', '2026-10-22', '2026-10-23'])], now);
      expect(s.streak, 3);
      expect(s.readToday, isTrue);
    });

    test('one missed day keeps it going, two end it', () {
      expect(ReadingStats([read('a', ['2026-10-19', '2026-10-21', '2026-10-22'])], now).streak, 3);
      expect(ReadingStats([read('a', ['2026-10-18', '2026-10-21', '2026-10-22'])], now).streak, 2);
    });

    test("doesn't drop before you've read today", () {
      expect(ReadingStats([read('a', ['2026-10-21', '2026-10-22'])], now).streak, 2);
      expect(ReadingStats([read('a', ['2026-10-21'])], now).streak, 1); // missed yesterday only
      expect(ReadingStats([read('a', ['2026-10-20'])], now).streak, 0);
      expect(ReadingStats(const [], now).streak, 0);
    });

    test('counts days, not books, and keeps the best run', () {
      final s = ReadingStats([
        read('a', ['2026-09-01', '2026-09-02', '2026-09-04', '2026-09-05']),
        read('b', ['2026-09-02', '2026-10-23']),
      ], now);
      expect(s.streak, 1);
      expect(s.bestStreak, 4);
    });

    test('this week runs Monday to Sunday', () {
      final week = ReadingStats(const [], now).thisWeek;
      expect(week.first, DateTime(2026, 10, 19));
      expect(week.last, DateTime(2026, 10, 25));
    });
  });

  test('totals for a week, month, year and all time', () {
    final s = ReadingStats([
      read('a', ['2025-12-30', '2026-10-01', '2026-10-20'], status: 'finished', finishedAt: '2026-10-20', rating: 4),
      read('b', ['2026-10-22'], status: 'finished', finishedAt: '2026-03-02', rating: 3),
      read('c', ['2026-10-22']),
    ], DateTime(2026, 10, 23));
    final week = s.totals(ReadingPeriod.week);
    expect((week.days, week.chapters, week.finished.length), (2, 3, 1));
    final month = s.totals(ReadingPeriod.month);
    expect((month.days, month.chapters), (3, 4));
    final year = s.totals(ReadingPeriod.year);
    expect(year.finished.map((b) => b.id), ['b', 'a']);
    expect(year.averageRating, 3.5);
    expect(s.totals(ReadingPeriod.all).days, 4);
    expect(s.finishedIn(2026).length, 2);
    expect(s.finishedIn(2025), isEmpty);
  });

  group('the store keeps the log', () {
    var now = DateTime(2026, 10, 23, 20);
    LibraryStore store0() => LibraryStore.memory(
          books: const [Book(id: 'lotr', title: 'LOTR', chapter: 3), Book(id: 'new', title: 'New')],
          settings: const AppSettings(currentBook: 'LOTR'),
          clock: () => now,
        );

    test('moving on a chapter notes today; undoing it leaves nothing', () async {
      final store = store0();
      await store.setChapter('LOTR', 4);
      await store.setChapter('LOTR', 5);
      expect(store.bookByTitle('LOTR')!.readingLog, [const ReadingDay('2026-10-23', chapters: 2)]);
      await store.setChapter('LOTR', 4);
      await store.setChapter('LOTR', 3);
      expect(store.bookByTitle('LOTR')!.readingLog, isEmpty);
    });

    test('setting your place for the first time is not reading', () async {
      final store = store0();
      await store.setChapter('New', 20);
      expect(store.bookByTitle('New')!.readingLog, isEmpty);
    });

    test('"I read today" counts without a chapter, and survives an undo', () async {
      final store = store0();
      await store.markReadToday(store.bookByTitle('LOTR')!);
      expect(store.readingStats.readToday, isTrue);
      await store.setChapter('LOTR', 4);
      await store.setChapter('LOTR', 3);
      expect(store.bookByTitle('LOTR')!.readingLog, [const ReadingDay('2026-10-23', marked: true)]);
    });

    test('each day gets its own entry', () async {
      final store = store0();
      await store.setChapter('LOTR', 4);
      now = DateTime(2026, 10, 24, 8);
      await store.setChapter('LOTR', 5);
      expect(store.bookByTitle('LOTR')!.readingLog.map((d) => d.date), ['2026-10-23', '2026-10-24']);
      expect(store.readingStats.streak, 2);
      now = DateTime(2026, 10, 23, 20);
    });

    test('finishing a book notes the day; un-finishing clears it', () async {
      final store = store0();
      await store.updateBook(store.bookByTitle('LOTR')!.copyWith(status: 'finished'));
      expect(store.bookByTitle('LOTR')!.finishedAt, '2026-10-23');
      now = DateTime(2026, 11, 2);
      await store.updateBook(store.bookByTitle('LOTR')!.copyWith(rating: 4)); // still finished: same day
      expect(store.bookByTitle('LOTR')!.finishedAt, '2026-10-23');
      await store.updateBook(store.bookByTitle('LOTR')!.copyWith(status: 'reading'));
      expect(store.bookByTitle('LOTR')!.finishedAt, isNull);
      now = DateTime(2026, 10, 23, 20);
    });

    test('the goal is a setting', () async {
      final store = store0();
      await store.setReadingGoal(12);
      expect(store.settings.readingGoal, 12);
      expect(AppSettings.fromJson(store.settings.toJson()).readingGoal, 12);
      await store.setReadingGoal(null);
      expect(store.settings.readingGoal, isNull);
    });
  });

  test('the log and finish day are saved with the book', () {
    const b = Book(
      id: 'lotr',
      title: 'LOTR',
      status: 'finished',
      finishedAt: '2026-10-23',
      readingLog: [ReadingDay('2026-10-22', chapters: 2), ReadingDay('2026-10-23', marked: true)],
    );
    final back = Book.fromJson(b.toJson());
    expect(back.readingLog, b.readingLog);
    expect(back.finishedAt, '2026-10-23');
    expect(Book.fromJson({'title': 'X', 'reading_log': 'nope', 'finished_at': 'soon'}).readingLog, isEmpty);
    expect(
      Book.fromJson({
        'title': 'X',
        'reading_log': [
          {'date': '2026-10-02', 'chapters': 1},
          {'date': '2026-10-01', 'chapters': 2},
          {'date': '2026-10-02', 'chapters': 3},
          {'date': 'x'},
        ],
      }).readingLog,
      [const ReadingDay('2026-10-01', chapters: 2), const ReadingDay('2026-10-02', chapters: 3)],
    );
  });

  testWidgets('the Books card and the stats page', (tester) async {
    final store = LibraryStore.memory(
      books: [
        read('Mistborn', ['2026-10-21', '2026-10-22']),
        read('The Hobbit', ['2026-10-02'], status: 'finished', finishedAt: '2026-10-02', rating: 4.5),
      ],
      settings: const AppSettings(currentBook: 'Mistborn', readingGoal: 12),
      clock: () => DateTime(2026, 10, 23, 9),
    );
    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: store,
      child: MaterialApp(theme: Syl.theme(googleFonts: false), home: const Scaffold(body: ReadingSummaryCard())),
    ));
    expect(find.text('1 of 12 books in 2026'), findsOneWidget);
    expect(find.textContaining('day streak'), findsOneWidget);

    await tester.tap(find.text('I read today'));
    await tester.pump();
    expect(find.text('You read today'), findsOneWidget);
    expect(store.readingStats.streak, 3);

    await tester.tap(find.byType(ReadingSummaryCard));
    await tester.pumpAndSettle();
    expect(find.byType(StatsScreen), findsOneWidget);
    await tester.tap(find.text('Year'));
    await tester.pump();
    expect(find.text('4.5'), findsOneWidget); // average rating
    await tester.scrollUntilVisible(find.text('October 2026'), 300, scrollable: find.byType(Scrollable).first);
    expect(find.byWidgetPredicate((w) => w is Semantics && w.properties.label == 'October 22: Mistborn'), findsOneWidget);
  });
}
