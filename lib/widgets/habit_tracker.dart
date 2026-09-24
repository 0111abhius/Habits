import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/habit.dart';
import '../services/habit_service.dart';
import '../utils/habit_stats.dart';
import 'habit_widgets.dart';

/// Compact habit strip shown on the timeline for the selected [date].
class HabitTracker extends StatefulWidget {
  final DateTime date;
  final HabitService? service;
  final VoidCallback? onOpenHabits;

  const HabitTracker({super.key, required this.date, this.service, this.onOpenHabits});

  @override
  State<HabitTracker> createState() => _HabitTrackerState();
}

class _HabitTrackerState extends State<HabitTracker> {
  late final HabitService _service = widget.service ?? HabitService();

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final today = HabitStats.dayOnly(DateTime.now());
    final date = HabitStats.dayOnly(widget.date);

    return StreamBuilder<List<Habit>>(
      stream: _service.watchHabits(user.uid),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Padding(padding: const EdgeInsets.all(8), child: Text('Error: ${snapshot.error}'));
        }
        if (!snapshot.hasData) {
          return const SizedBox(height: 48, child: Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))));
        }
        final habits = snapshot.data!.where((h) => !h.archived).toList();
        if (habits.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: Text('No habits yet.', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                ),
                TextButton.icon(
                  onPressed: widget.onOpenHabits,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add habit'),
                ),
              ],
            ),
          );
        }

        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: habits.map((h) {
              final done = HabitStats.isDoneOn(h, date);
              final due = HabitStats.isDueOn(h, date);
              final streak = HabitStats.currentStreak(h, today);
              final value = HabitStats.valueOn(h, date);
              final isCounter = h.type == HabitType.counter;

              return Material(
                color: done
                    ? theme.colorScheme.primary.withValues(alpha: 0.12)
                    : theme.colorScheme.surfaceContainerHighest.withValues(alpha: due ? 0.7 : 0.3),
                borderRadius: BorderRadius.circular(20),
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: isCounter ? () => _service.increment(user.uid, h, date) : () => _service.toggle(user.uid, h, date),
                  onLongPress: isCounter && value > 0 ? () => _service.setValue(user.uid, h, date, value - 1) : widget.onOpenHabits,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          done ? Icons.check_circle : (isCounter ? Icons.add_circle_outline : Icons.radio_button_unchecked),
                          size: 18,
                          color: done ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          isCounter ? '${h.name} $value/${h.targetCount}' : h.name,
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: done ? theme.colorScheme.primary : null,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (streak > 0) ...[
                          const SizedBox(width: 6),
                          Icon(Icons.local_fire_department, size: 14, color: Colors.deepOrange.shade400),
                          Text('$streak', style: theme.textTheme.labelSmall?.copyWith(color: Colors.deepOrange.shade700, fontWeight: FontWeight.bold)),
                        ],
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        );
      },
    );
  }
}
