import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../models/reading_stats.dart';
import '../state/library_store.dart';
import '../theme/syl_theme.dart';
import 'books_screen.dart';
import 'widgets/common.dart';

const _weekdays = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
const _months = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];

/// The book "I read today" is for: the one in the Library, or else the first you're reading.
Book? _readingNow(LibraryStore store) {
  final current = store.currentBook;
  if (current != null && current.status == 'reading') return current;
  return store.bookList.where((b) => b.status == 'reading').firstOrNull;
}

/// The top of the Books tab: your streak, this week, your goal for the year
/// and "I read today". Tap it for the full stats page.
class ReadingSummaryCard extends StatelessWidget {
  const ReadingSummaryCard({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<LibraryStore>();
    final stats = store.readingStats;
    final goal = store.settings.readingGoal;
    final year = stats.today.year;
    final done = stats.finishedIn(year).length;
    final book = _readingNow(store);
    final streak = stats.streak;
    return Material(
      color: Syl.white,
      borderRadius: const BorderRadius.all(Radius.circular(26)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => openStats(context),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(Icons.local_fire_department_rounded, color: streak > 0 ? Syl.accent : Syl.muted, size: 30),
              const SizedBox(width: 6),
              Expanded(
                child: Text.rich(
                  TextSpan(children: [
                    if (streak > 0) ...[
                      TextSpan(text: '$streak', style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
                      const TextSpan(text: '  day streak'),
                    ] else
                      const TextSpan(text: 'Read today to start a streak'),
                  ]),
                  style: TextStyle(fontSize: 15, color: Syl.ink),
                ),
              ),
              Icon(Icons.chevron_right, color: Syl.muted),
            ]),
            const SizedBox(height: 12),
            WeekDots(stats: stats),
            const SizedBox(height: 14),
            Text(
              goal == null ? '$done finished in $year' : '$done of $goal books in $year',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Syl.muted),
            ),
            if (goal != null) ...[
              const SizedBox(height: 6),
              _Bar(value: done / goal),
            ],
            if (book != null) ...[
              const SizedBox(height: 12),
              stats.readToday
                  ? Row(children: [
                      Icon(Icons.check_circle, size: 20, color: Syl.mint),
                      const SizedBox(width: 6),
                      Text('You read today', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Syl.ink)),
                    ])
                  : PillButton(
                      label: 'I read today',
                      icon: Icons.check,
                      dark: true,
                      onTap: () => store.markReadToday(book),
                    ),
            ],
          ]),
        ),
      ),
    );
  }
}

/// Monday to Sunday: a filled dot for each day you read, a ring round today.
class WeekDots extends StatelessWidget {
  const WeekDots({super.key, required this.stats});
  final ReadingStats stats;

  @override
  Widget build(BuildContext context) {
    final days = stats.thisWeek;
    return Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      for (var i = 0; i < 7; i++)
        Semantics(
          label: '${_months[days[i].month - 1]} ${days[i].day}: ${stats.readOn(days[i]) ? 'read' : 'not read'}',
          child: ExcludeSemantics(
            child: Column(children: [
              Text(_weekdays[i], style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Syl.muted)),
              const SizedBox(height: 4),
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: stats.readOn(days[i]) ? Syl.accent : Syl.paper,
                  border: days[i] == stats.today ? Border.all(color: Syl.ink, width: 2) : null,
                ),
                child: stats.readOn(days[i]) ? const Icon(Icons.check, size: 16, color: Syl.onAccent) : null,
              ),
            ]),
          ),
        ),
    ]);
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.value});
  final double value;

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: LinearProgressIndicator(
          value: value.clamp(0, 1).toDouble(),
          minHeight: 8,
          backgroundColor: Syl.line,
          color: Syl.accent,
        ),
      );
}

Future<void> openStats(BuildContext context) =>
    Navigator.push(context, MaterialPageRoute(builder: (_) => const StatsScreen()));

/// Your reading: streak, the year's goal, totals for a week, month, year or
/// all time, and a calendar with the cover of what you read each day.
class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key});
  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  ReadingPeriod _period = ReadingPeriod.month;
  DateTime? _month;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<LibraryStore>();
    final stats = store.readingStats;
    final month = _month ?? DateTime(stats.today.year, stats.today.month);
    final totals = stats.totals(_period);
    final goal = store.settings.readingGoal;
    final year = stats.today.year;
    final done = stats.finishedIn(year).length;
    final t = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 40),
          children: [
            Row(children: [
              RoundIconButton(icon: Icons.arrow_back, tooltip: 'Back', onPressed: () => Navigator.pop(context)),
            ]),
            const SizedBox(height: 12),
            Text('Reading', style: t.displaySmall?.copyWith(fontSize: 44)),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(child: _Tile(value: '${stats.streak}', label: 'Day streak', icon: Icons.local_fire_department_rounded)),
              const SizedBox(width: 10),
              Expanded(child: _Tile(value: '${stats.bestStreak}', label: 'Best streak')),
            ]),
            const SizedBox(height: 6),
            Text('One missed day keeps your streak going. Two in a row end it.',
                style: TextStyle(fontSize: 13, color: Syl.muted, height: 1.35)),
            const SizedBox(height: 14),
            _Panel(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(
                    child: Text(goal == null ? '$done finished in $year' : '$done of $goal books in $year',
                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                  ),
                  PillButton(
                    label: goal == null ? 'Set a goal' : 'Change',
                    onTap: () => _pickGoal(context, store, goal),
                  ),
                ]),
                if (goal != null) ...[
                  const SizedBox(height: 10),
                  _Bar(value: done / goal),
                  const SizedBox(height: 6),
                  Text(
                    done >= goal ? 'Goal reached.' : '${goal - done} to go.',
                    style: TextStyle(fontSize: 13, color: Syl.muted),
                  ),
                ],
              ]),
            ),
            const SizedBox(height: 22),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final (p, label) in const [
                (ReadingPeriod.week, 'Week'),
                (ReadingPeriod.month, 'Month'),
                (ReadingPeriod.year, 'Year'),
                (ReadingPeriod.all, 'All time'),
              ])
                FilterPill(label: label, selected: _period == p, onTap: () => setState(() => _period = p)),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: _Tile(value: '${totals.days}', label: totals.days == 1 ? 'Day read' : 'Days read')),
              const SizedBox(width: 10),
              Expanded(child: _Tile(value: '${totals.chapters}', label: totals.chapters == 1 ? 'Chapter' : 'Chapters')),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: _Tile(value: '${totals.finished.length}', label: 'Finished')),
              const SizedBox(width: 10),
              Expanded(
                child: _Tile(
                  value: totals.averageRating == null ? '–' : _stars(totals.averageRating!),
                  label: 'Average rating',
                  icon: totals.averageRating == null ? null : Icons.star_rounded,
                ),
              ),
            ]),
            if (totals.finished.isNotEmpty) ...[
              const SizedBox(height: 14),
              SizedBox(
                height: 84,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: totals.finished.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 10),
                  itemBuilder: (_, i) => Semantics(
                    label: totals.finished[i].title,
                    child: BookCoverImage(book: totals.finished[i], width: 56),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 26),
            _Calendar(
              stats: stats,
              month: month,
              onMonth: (m) => setState(() => _month = m),
            ),
          ],
        ),
      ),
    );
  }

  static String _stars(double r) {
    final rounded = (r * 10).round() / 10;
    return rounded % 1 == 0 ? '${rounded.toInt()}' : rounded.toStringAsFixed(1);
  }

  Future<void> _pickGoal(BuildContext context, LibraryStore store, int? goal) async {
    var n = goal ?? 12;
    final picked = await showDialog<int>(
      context: context,
      builder: (d) => StatefulBuilder(
        builder: (d, set) => AlertDialog(
          title: Text('Books in ${store.readingStats.today.year}'),
          content: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            IconButton(
              tooltip: 'Fewer',
              onPressed: n <= 1 ? null : () => set(() => n--),
              icon: const Icon(Icons.remove),
            ),
            SizedBox(
              width: 72,
              child: Text('$n', textAlign: TextAlign.center, style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w800)),
            ),
            IconButton(tooltip: 'More', onPressed: () => set(() => n++), icon: const Icon(Icons.add)),
          ]),
          actions: [
            if (goal != null) TextButton(onPressed: () => Navigator.pop(d, 0), child: const Text('No goal')),
            TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancel')),
            TextButton(onPressed: () => Navigator.pop(d, n), child: const Text('Save')),
          ],
        ),
      ),
    );
    if (picked != null) await store.setReadingGoal(picked == 0 ? null : picked);
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Syl.white, borderRadius: Syl.r24),
        child: child,
      );
}

class _Tile extends StatelessWidget {
  const _Tile({required this.value, required this.label, this.icon});
  final String value;
  final String label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => MergeSemantics(
        child: _Panel(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Flexible(
                child: Text(value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
              ),
              if (icon != null) ...[const SizedBox(width: 4), Icon(icon, color: Syl.accent, size: 24)],
            ]),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(fontSize: 13, color: Syl.muted)),
          ]),
        ),
      );
}

/// A month, a week to a row from Monday, with the cover of a book you read
/// on each day you read.
class _Calendar extends StatelessWidget {
  const _Calendar({required this.stats, required this.month, required this.onMonth});
  final ReadingStats stats;
  final DateTime month;
  final ValueChanged<DateTime> onMonth;

  @override
  Widget build(BuildContext context) {
    final first = DateTime(month.year, month.month);
    final days = DateTime(month.year, month.month + 1, 0).day;
    final lead = first.weekday - 1;
    final thisMonth = DateTime(stats.today.year, stats.today.month);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Expanded(
          child: Text('${_months[month.month - 1]} ${month.year}',
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
        ),
        RoundIconButton(
          icon: Icons.chevron_left,
          tooltip: 'Previous month',
          onPressed: () => onMonth(DateTime(month.year, month.month - 1)),
        ),
        const SizedBox(width: 8),
        RoundIconButton(
          icon: Icons.chevron_right,
          tooltip: 'Next month',
          onPressed: month == thisMonth ? null : () => onMonth(DateTime(month.year, month.month + 1)),
        ),
      ]),
      const SizedBox(height: 10),
      Row(children: [
        for (final d in _weekdays)
          Expanded(
            child: Text(d,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Syl.muted)),
          ),
      ]),
      const SizedBox(height: 6),
      LayoutBuilder(builder: (context, box) {
        final cell = box.maxWidth / 7;
        return Wrap(children: [
          for (var i = 0; i < lead; i++) SizedBox(width: cell, height: cell * 1.4),
          for (var d = 1; d <= days; d++) _day(context, DateTime(month.year, month.month, d), cell),
        ]);
      }),
    ]);
  }

  Widget _day(BuildContext context, DateTime day, double cell) {
    final read = stats.byDay[dayKey(day)];
    final isToday = day == stats.today;
    final number = Text('${day.day}',
        style: TextStyle(
          fontSize: 12,
          fontWeight: isToday ? FontWeight.w800 : FontWeight.w500,
          color: read != null ? Syl.onAccent : (isToday ? Syl.ink : Syl.muted),
        ));
    return Semantics(
      label: '${_months[day.month - 1]} ${day.day}${read == null ? '' : ': ${read.map((b) => b.title).join(', ')}'}',
      child: ExcludeSemantics(
        child: SizedBox(
          width: cell,
          height: cell * 1.4,
          child: Padding(
            padding: const EdgeInsets.all(2),
            child: read == null
                ? Center(child: number)
                : Stack(fit: StackFit.expand, children: [
                    FittedBox(fit: BoxFit.contain, child: BookCoverImage(book: read.first, width: cell - 4)),
                    Align(
                      alignment: Alignment.bottomRight,
                      child: Container(
                        margin: const EdgeInsets.all(2),
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                        decoration: BoxDecoration(color: Syl.accent, borderRadius: BorderRadius.circular(6)),
                        child: number,
                      ),
                    ),
                  ]),
          ),
        ),
      ),
    );
  }
}
