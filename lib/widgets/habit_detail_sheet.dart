import 'package:flutter/material.dart';

import '../models/habit.dart';
import '../utils/habit_stats.dart';
import 'habit_widgets.dart';

enum HabitDetailAction { edit, archive, unarchive, delete }

/// Shows history + stats for a habit. Returns the action the user picked.
Future<HabitDetailAction?> showHabitDetail(BuildContext context, Habit habit, {DateTime? today}) {
  final now = today ?? DateTime.now();
  return showModalBottomSheet<HabitDetailAction>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (ctx) {
      final theme = Theme.of(ctx);
      final streak = HabitStats.currentStreak(habit, now);
      final best = HabitStats.bestStreak(habit);
      final rate30 = HabitStats.completionRate(habit, now, days: 30);
      final total = HabitStats.totalCompletions(habit);
      final unit = habit.frequency == HabitFrequency.weekly ? 'wk' : 'd';

      Widget stat(String label, String value) => Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  Text(value, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 2),
                  Text(label, style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                ],
              ),
            ),
          );

      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(habit.name, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                        Text(
                          '${habit.frequencyLabel}${habit.type == HabitType.counter ? ' · goal ${habit.targetCount}' : ''}${habit.tier > 0 ? ' · ${habit.tierLabel}' : ''}',
                          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Edit',
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: () => Navigator.pop(ctx, HabitDetailAction.edit),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  stat('Current streak', '$streak$unit'),
                  const SizedBox(width: 8),
                  stat('Best streak', '$best$unit'),
                  const SizedBox(width: 8),
                  stat('Last 30 days', '${(rate30 * 100).round()}%'),
                  const SizedBox(width: 8),
                  stat('Total', '$total'),
                ],
              ),
              const SizedBox(height: 20),
              Text('Last 16 weeks', style: theme.textTheme.labelLarge),
              const SizedBox(height: 8),
              HabitHeatmap(habit: habit, today: now),
              const SizedBox(height: 24),
              Row(
                children: [
                  if (!habit.archived)
                    TextButton.icon(
                      onPressed: () => Navigator.pop(ctx, HabitDetailAction.archive),
                      icon: const Icon(Icons.archive_outlined),
                      label: const Text('Archive'),
                    )
                  else
                    TextButton.icon(
                      onPressed: () => Navigator.pop(ctx, HabitDetailAction.unarchive),
                      icon: const Icon(Icons.unarchive_outlined),
                      label: const Text('Restore'),
                    ),
                  const Spacer(),
                  TextButton.icon(
                    style: TextButton.styleFrom(foregroundColor: theme.colorScheme.error),
                    onPressed: () => Navigator.pop(ctx, HabitDetailAction.delete),
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Delete'),
                  ),
                ],
              ),
              Text(
                'Archiving keeps your history and hides the habit from daily views.',
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      );
    },
  );
}
