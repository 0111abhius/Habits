import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/habit.dart';
import '../utils/habit_stats.dart';

/// Circular checkbox for binary habits or a -/+ stepper for counters.
class HabitValueControl extends StatelessWidget {
  final Habit habit;
  final DateTime date;
  final ValueChanged<int> onChanged;
  final bool compact;

  const HabitValueControl({
    super.key,
    required this.habit,
    required this.date,
    required this.onChanged,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final value = HabitStats.valueOn(habit, date);
    final done = HabitStats.isDoneOn(habit, date);
    final color = theme.colorScheme.primary;

    if (habit.type == HabitType.binary) {
      final size = compact ? 26.0 : 32.0;
      return Semantics(
        button: true,
        checked: done,
        label: habit.name,
        child: InkWell(
          onTap: () => onChanged(done ? 0 : 1),
          borderRadius: BorderRadius.circular(size),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: done ? color : Colors.transparent,
              border: Border.all(color: done ? color : theme.colorScheme.outline, width: 2),
            ),
            child: done ? Icon(Icons.check, size: size * 0.6, color: theme.colorScheme.onPrimary) : null,
          ),
        ),
      );
    }

    final btnSize = compact ? 26.0 : 32.0;
    Widget btn(IconData icon, VoidCallback? onTap) => InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(btnSize),
          child: Container(
            width: btnSize,
            height: btnSize,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: theme.colorScheme.surfaceContainerHighest,
            ),
            child: Icon(icon, size: btnSize * 0.55, color: onTap == null ? theme.disabledColor : null),
          ),
        );

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        btn(Icons.remove, value > 0 ? () => onChanged(value - 1) : null),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Text(
            '$value/${habit.targetCount}',
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.bold,
              color: done ? color : null,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
        btn(Icons.add, () => onChanged(value + 1)),
      ],
    );
  }
}

/// Seven small dots for the week ending on [endDate] (oldest first).
class HabitDotRow extends StatelessWidget {
  final Habit habit;
  final DateTime endDate;
  final int days;
  final double dotSize;
  final bool showLabels;

  const HabitDotRow({
    super.key,
    required this.habit,
    required this.endDate,
    this.days = 7,
    this.dotSize = 10,
    this.showLabels = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dates = HabitStats.lastDays(endDate, days);
    final created = HabitStats.dayOnly(habit.createdAt);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: dates.map((d) {
        final done = HabitStats.isDoneOn(habit, d);
        final beforeCreated = d.isBefore(created);
        final isEnd = d == HabitStats.dayOnly(endDate);
        final color = done
            ? theme.colorScheme.primary
            : (beforeCreated ? Colors.transparent : theme.colorScheme.outlineVariant.withValues(alpha: 0.6));
        return Padding(
          padding: EdgeInsets.symmetric(horizontal: dotSize * 0.2),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Tooltip(
                message: DateFormat('EEE, MMM d').format(d),
                child: Container(
                  width: dotSize,
                  height: dotSize,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: color,
                    border: isEnd && !done
                        ? Border.all(color: theme.colorScheme.primary, width: 1.5)
                        : null,
                  ),
                ),
              ),
              if (showLabels)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    DateFormat('E').format(d).substring(0, 1),
                    style: theme.textTheme.labelSmall?.copyWith(fontSize: 9),
                  ),
                ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

/// "🔥 12" style streak indicator. Hidden when the streak is zero unless
/// [alwaysShow] is set.
class StreakBadge extends StatelessWidget {
  final Habit habit;
  final DateTime today;
  final bool alwaysShow;

  const StreakBadge({super.key, required this.habit, required this.today, this.alwaysShow = false});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final streak = HabitStats.currentStreak(habit, today);
    if (streak == 0 && !alwaysShow) return const SizedBox.shrink();
    final unit = habit.frequency == HabitFrequency.weekly ? 'w' : 'd';
    final active = streak > 0;
    return Tooltip(
      message: habit.frequency == HabitFrequency.weekly
          ? '$streak week${streak == 1 ? '' : 's'} in a row'
          : '$streak day${streak == 1 ? '' : 's'} in a row',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: active ? Colors.orange.withValues(alpha: 0.15) : theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.local_fire_department,
                size: 14, color: active ? Colors.deepOrange : theme.disabledColor),
            const SizedBox(width: 2),
            Text(
              '$streak$unit',
              style: theme.textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: active ? Colors.deepOrange.shade700 : theme.disabledColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Small "3 / 4 this week" progress pill for weekly habits.
class WeeklyProgressPill extends StatelessWidget {
  final Habit habit;
  final DateTime date;

  const WeeklyProgressPill({super.key, required this.habit, required this.date});

  @override
  Widget build(BuildContext context) {
    if (habit.frequency != HabitFrequency.weekly) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final n = HabitStats.completionsInWeek(habit, date);
    final met = n >= habit.weeklyTarget;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: met ? theme.colorScheme.primary.withValues(alpha: 0.12) : theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        '$n/${habit.weeklyTarget} this week',
        style: theme.textTheme.labelSmall?.copyWith(
          color: met ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// GitHub-style grid of the last [weeks] weeks, columns = weeks, rows = Mon..Sun.
class HabitHeatmap extends StatelessWidget {
  final Habit habit;
  final DateTime today;
  final int weeks;

  const HabitHeatmap({super.key, required this.habit, required this.today, this.weeks = 16});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final thisWeekStart = HabitStats.weekStart(today);
    final firstWeekStart = thisWeekStart.subtract(Duration(days: 7 * (weeks - 1)));
    final created = HabitStats.dayOnly(habit.createdAt);
    final day = HabitStats.dayOnly(today);

    return LayoutBuilder(builder: (context, constraints) {
      final cell = ((constraints.maxWidth - 24) / weeks).clamp(6.0, 16.0);
      final gap = cell * 0.2;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                children: List.generate(7, (r) {
                  const labels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
                  return SizedBox(
                    height: cell + gap,
                    width: 16,
                    child: r.isEven
                        ? Text(labels[r], style: theme.textTheme.labelSmall?.copyWith(fontSize: 9))
                        : null,
                  );
                }),
              ),
              Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: List.generate(weeks, (w) {
                    final ws = firstWeekStart.add(Duration(days: 7 * w));
                    return Column(
                      children: List.generate(7, (r) {
                        final d = ws.add(Duration(days: r));
                        final future = d.isAfter(day);
                        final before = d.isBefore(created);
                        final v = HabitStats.valueOn(habit, d);
                        final done = HabitStats.isDoneOn(habit, d);
                        Color c;
                        if (future || before) {
                          c = Colors.transparent;
                        } else if (done) {
                          c = theme.colorScheme.primary;
                        } else if (v > 0) {
                          c = theme.colorScheme.primary.withValues(alpha: 0.35);
                        } else {
                          c = theme.colorScheme.surfaceContainerHighest;
                        }
                        return Padding(
                          padding: EdgeInsets.only(bottom: gap),
                          child: Tooltip(
                            message: future || before
                                ? ''
                                : '${DateFormat('MMM d').format(d)}: ${habit.type == HabitType.binary ? (done ? 'done' : 'missed') : '$v/${habit.targetCount}'}',
                            child: Container(
                              width: cell,
                              height: cell,
                              decoration: BoxDecoration(
                                color: c,
                                borderRadius: BorderRadius.circular(2),
                                border: d == day ? Border.all(color: theme.colorScheme.primary) : null,
                              ),
                            ),
                          ),
                        );
                      }),
                    );
                  }),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 16),
                child: Text(DateFormat('MMM d').format(firstWeekStart), style: theme.textTheme.labelSmall),
              ),
              Text('Today', style: theme.textTheme.labelSmall),
            ],
          ),
        ],
      );
    });
  }
}
