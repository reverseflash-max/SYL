import 'models.dart';

enum ReadingPeriod { week, month, year, all }

/// What you read in one [ReadingPeriod].
class PeriodTotals {
  const PeriodTotals({this.days = 0, this.chapters = 0, this.finished = const [], this.averageRating});

  /// Days you read anything.
  final int days;
  final int chapters;

  /// Books you marked finished in the period.
  final List<Book> finished;

  /// Of those, the average of the ones you rated.
  final double? averageRating;
}

/// Your reading habit, worked out from every book's reading log: the streak,
/// the yearly goal, the calendar and the totals on the stats page.
class ReadingStats {
  ReadingStats(List<Book> books, DateTime now)
      : books = List.unmodifiable(books),
        today = DateTime(now.year, now.month, now.day);

  final List<Book> books;
  final DateTime today;

  /// For each day you read, the books you read that day.
  late final Map<String, List<Book>> byDay = () {
    final out = <String, List<Book>>{};
    for (final b in books) {
      for (final d in b.readingLog) {
        (out[d.date] ??= []).add(b);
      }
    }
    return out;
  }();

  static DateTime _day(DateTime d, [int plus = 0]) => DateTime(d.year, d.month, d.day + plus);

  bool readOn(DateTime d) => byDay.containsKey(dayKey(d));

  bool get readToday => readOn(today);

  /// Days read in the current run. One missed day doesn't break it; two in a
  /// row do. Today only counts once you've read, so the streak doesn't drop
  /// in the morning before you've had the chance.
  int get streak {
    var d = readToday ? today : _day(today, -1);
    var count = 0, missed = 0;
    while (missed < 2) {
      if (readOn(d)) {
        count++;
        missed = 0;
      } else {
        missed++;
      }
      d = _day(d, -1);
    }
    return count;
  }

  /// The longest run ever, by the same rule as [streak].
  int get bestStreak {
    final days = byDay.keys.map(DateTime.parse).toList()..sort();
    var best = 0, run = 0;
    DateTime? last;
    for (final d in days) {
      run = last != null && d.difference(last).inHours <= 50 ? run + 1 : 1; // 50: a DST day is 23 or 25 hours
      if (run > best) best = run;
      last = d;
    }
    return best;
  }

  /// Monday of this week, then the six days after it.
  List<DateTime> get thisWeek {
    final monday = _day(today, -(today.weekday - 1));
    return [for (var i = 0; i < 7; i++) _day(monday, i)];
  }

  /// Books you finished in [year].
  List<Book> finishedIn(int year) =>
      books.where((b) => b.status == 'finished' && b.finishedAt != null && b.finishedAt!.startsWith('$year-')).toList();

  /// The first day of [p] (null for all time).
  DateTime? startOf(ReadingPeriod p) => switch (p) {
        ReadingPeriod.week => thisWeek.first,
        ReadingPeriod.month => DateTime(today.year, today.month),
        ReadingPeriod.year => DateTime(today.year),
        ReadingPeriod.all => null,
      };

  PeriodTotals totals(ReadingPeriod p) {
    final from = startOf(p);
    final fromKey = from == null ? '' : dayKey(from);
    var days = 0, chapters = 0;
    for (final e in byDay.entries) {
      if (e.key.compareTo(fromKey) < 0) continue;
      days++;
      for (final b in e.value) {
        chapters += b.readOn(e.key)?.chapters ?? 0;
      }
    }
    final finished = books
        .where((b) => b.status == 'finished' && b.finishedAt != null && b.finishedAt!.compareTo(fromKey) >= 0)
        .toList()
      ..sort((a, b) => a.finishedAt!.compareTo(b.finishedAt!));
    final rated = [for (final b in finished) ?b.rating];
    return PeriodTotals(
      days: days,
      chapters: chapters,
      finished: finished,
      averageRating: rated.isEmpty ? null : rated.reduce((a, b) => a + b) / rated.length,
    );
  }
}
