import 'package:flutter/material.dart';
import '../dreams/models/dream_entry.dart';
import '../dreams/services/dream_service.dart';

class DreamJournalCalendarScreen extends StatefulWidget {
  const DreamJournalCalendarScreen({super.key});

  @override
  State<DreamJournalCalendarScreen> createState() =>
      _DreamJournalCalendarScreenState();
}

class _DreamJournalCalendarScreenState
    extends State<DreamJournalCalendarScreen> {
  DateTime _focusMonth = DateTime(DateTime.now().year, DateTime.now().month);
  List<DreamEntry> _dreams = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final dreams = await DreamService.instance.loadDreams();
    if (mounted)
      setState(() {
        _dreams = dreams;
        _loading = false;
      });
  }

  Map<int, List<DreamEntry>> get _byDay {
    final map = <int, List<DreamEntry>>{};
    for (final d in _dreams) {
      if (d.date.year == _focusMonth.year &&
          d.date.month == _focusMonth.month) {
        (map[d.date.day] ??= []).add(d);
      }
    }
    return map;
  }

  void _prevMonth() => setState(
      () => _focusMonth = DateTime(_focusMonth.year, _focusMonth.month - 1));
  void _nextMonth() => setState(
      () => _focusMonth = DateTime(_focusMonth.year, _focusMonth.month + 1));

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final byDay = _byDay;
    final daysInMonth =
        DateUtils.getDaysInMonth(_focusMonth.year, _focusMonth.month);
    final firstWeekday =
        DateTime(_focusMonth.year, _focusMonth.month, 1).weekday % 7;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dream Journal'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                  icon: const Icon(Icons.chevron_left), onPressed: _prevMonth),
              Text(
                ' ',
                style: tt.titleMedium,
              ),
              IconButton(
                  icon: const Icon(Icons.chevron_right), onPressed: _nextMonth),
            ],
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _WeekdayHeader(),
                Expanded(
                  child: GridView.builder(
                    padding: const EdgeInsets.all(4),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 7,
                      mainAxisSpacing: 4,
                      crossAxisSpacing: 4,
                    ),
                    itemCount: firstWeekday + daysInMonth,
                    itemBuilder: (ctx, idx) {
                      if (idx < firstWeekday) return const SizedBox.shrink();
                      final day = idx - firstWeekday + 1;
                      final entries = byDay[day] ?? [];
                      final isToday = DateTime.now().year == _focusMonth.year &&
                          DateTime.now().month == _focusMonth.month &&
                          DateTime.now().day == day;
                      return GestureDetector(
                        onTap: entries.isEmpty
                            ? null
                            : () => _showEntries(ctx, day, entries),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          decoration: BoxDecoration(
                            color: entries.isNotEmpty
                                ? cs.primaryContainer
                                : isToday
                                    ? cs.secondaryContainer
                                    : cs.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(8),
                            border: isToday
                                ? Border.all(color: cs.primary, width: 2)
                                : null,
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                '$day',
                                style: tt.bodySmall?.copyWith(
                                  fontWeight: isToday
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                  color: entries.isNotEmpty
                                      ? cs.onPrimaryContainer
                                      : cs.onSurface,
                                ),
                              ),
                              if (entries.isNotEmpty)
                                Text(
                                  ' \uD83C\uDF19',
                                  style: tt.labelSmall
                                      ?.copyWith(color: cs.onPrimaryContainer),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }

  void _showEntries(BuildContext ctx, int day, List<DreamEntry> entries) {
    showModalBottomSheet<void>(
      context: ctx,
      builder: (_) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            '$day ${_monthName(_focusMonth.month)} ${_focusMonth.year}',
            style: Theme.of(ctx).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          for (final e in entries)
            ListTile(
              leading: const Icon(Icons.nights_stay_outlined),
              title: Text(e.title.isEmpty ? 'Untitled Dream' : e.title),
              subtitle: Text(
                e.description.length > 80
                    ? '${e.description.substring(0, 80)}...'
                    : e.description,
              ),
            ),
        ],
      ),
    );
  }

  static String _monthName(int m) => const [
        '',
        'January',
        'February',
        'March',
        'April',
        'May',
        'June',
        'July',
        'August',
        'September',
        'October',
        'November',
        'December'
      ][m];
}

class _WeekdayHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    const labels = ['Su', 'Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa'];
    return Row(
      children: labels
          .map((l) => Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Text(l,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.labelSmall),
                ),
              ))
          .toList(),
    );
  }
}
