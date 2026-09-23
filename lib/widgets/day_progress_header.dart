import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/habit.dart';
import '../models/timeline_entry.dart';
import '../services/habit_service.dart';
import '../utils/habit_stats.dart';

/// Immediate, local (no AI) feedback for the selected day: hours planned and
/// logged against the waking window, habits done, and the day-logging streak.
class DayProgressHeader extends StatelessWidget {
  final DateTime date;
  final List<TimelineEntry> entries;
  final TimeOfDay? wakeTime;
  final TimeOfDay? sleepTime;
  final int logStreak;
  final bool dayComplete;
  final VoidCallback? onFillFromPlan;
  final VoidCallback? onMarkComplete;
  final HabitService? habitService;

  const DayProgressHeader({
    super.key,
    required this.date,
    required this.entries,
    required this.wakeTime,
    required this.sleepTime,
    required this.logStreak,
    required this.dayComplete,
    this.onFillFromPlan,
    this.onMarkComplete,
    this.habitService,
  });

  /// Waking hours in the day (defaults to 16 when settings are missing).
  static int wakingHours(TimeOfDay? wake, TimeOfDay? sleep) {
    if (wake == null || sleep == null) return 16;
    int w = wake.hour;
    int s = sleep.hour;
    if (sleep.minute > 0) s += 1;
    int hours = s - w;
    if (hours <= 0) hours += 24;
    return hours.clamp(1, 24);
  }

  static bool _isSleepHour(int hour, TimeOfDay? wake, TimeOfDay? sleep) {
    if (wake == null || sleep == null) return false;
    final w = wake.hour;
    final s = sleep.hour;
    if (s > w) return hour >= s || hour < w;
    if (s < w) return hour >= s && hour < w;
    return false;
  }

  /// Count of distinct waking hours that have any actual / planned entry.
  static ({int logged, int planned}) coverage(List<TimelineEntry> entries, TimeOfDay? wake, TimeOfDay? sleep) {
    final logged = <int>{};
    final planned = <int>{};
    for (final e in entries) {
      final h = e.startTime.hour;
      if (_isSleepHour(h, wake, sleep)) continue;
      if (e.activity.isNotEmpty && e.activity != 'Sleep') logged.add(h);
      if (e.planactivity.isNotEmpty && e.planactivity != 'Sleep') planned.add(h);
    }
    return (logged: logged.length, planned: planned.length);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final total = wakingHours(wakeTime, sleepTime);
    final cov = coverage(entries, wakeTime, sleepTime);
    final loggedPct = (cov.logged / total).clamp(0.0, 1.0);
    final plannedPct = (cov.planned / total).clamp(0.0, 1.0);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(date.year, date.month, date.day);
    final isFuture = day.isAfter(today);
    final canFill = !isFuture && cov.planned > cov.logged && onFillFromPlan != null;

    Widget stat(IconData icon, String text, {Color? color, String? tooltip}) {
      final w = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color ?? theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 4),
          Text(text, style: theme.textTheme.labelMedium?.copyWith(color: color, fontWeight: FontWeight.w600)),
        ],
      );
      return tooltip == null ? w : Tooltip(message: tooltip, child: w);
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Wrap(
                  spacing: 14,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    stat(Icons.edit_calendar_outlined, 'Planned ${cov.planned}/$total h',
                        color: Colors.blue.shade700, tooltip: 'Waking hours with a plan'),
                    stat(Icons.check_circle_outline, 'Logged ${cov.logged}/$total h',
                        color: Colors.green.shade700, tooltip: 'Waking hours with an actual activity'),
                    if (uid != null)
                      StreamBuilder<List<Habit>>(
                        stream: (habitService ?? HabitService()).watchHabits(uid),
                        builder: (context, snap) {
                          final habits = (snap.data ?? const <Habit>[]).where((h) => !h.archived).toList();
                          if (habits.isEmpty) return const SizedBox.shrink();
                          final due = habits.where((h) => HabitStats.isDueOn(h, day)).toList();
                          final done = due.where((h) => HabitStats.isDoneOn(h, day)).length;
                          final all = due.isNotEmpty && done == due.length;
                          return stat(all ? Icons.emoji_events : Icons.self_improvement, 'Habits $done/${due.length}',
                              color: all ? Colors.deepOrange : theme.colorScheme.onSurfaceVariant);
                        },
                      ),
                    if (logStreak > 0)
                      stat(Icons.local_fire_department, '$logStreak-day log streak',
                          color: Colors.deepOrange, tooltip: 'Consecutive days marked as logged'),
                  ],
                ),
              ),
              if (canFill)
                Tooltip(
                  message: 'Copy the plan into the actual column for every hour you haven\'t logged yet',
                  child: TextButton.icon(
                    onPressed: onFillFromPlan,
                    icon: const Icon(Icons.done_all, size: 16),
                    label: const Text('Went as planned'),
                    style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                  ),
                ),
              if (!canFill && !dayComplete && !isFuture && cov.logged >= (total * 0.6).floor() && onMarkComplete != null)
                Tooltip(
                  message: 'Mark the day as logged to keep your streak',
                  child: FilledButton.tonalIcon(
                    onPressed: onMarkComplete,
                    icon: const Icon(Icons.flag_outlined, size: 16),
                    label: const Text('Finish day'),
                    style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: SizedBox(
              height: 6,
              child: Stack(
                children: [
                  Container(color: theme.colorScheme.surfaceContainerHighest),
                  FractionallySizedBox(
                    widthFactor: plannedPct,
                    child: Container(color: Colors.blue.withValues(alpha: 0.35)),
                  ),
                  FractionallySizedBox(
                    widthFactor: loggedPct,
                    child: Container(color: Colors.green.shade600),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
