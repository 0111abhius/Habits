import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../main.dart';
import '../models/task.dart';

/// Checklist of the tasks that belong to [date]: tasks flagged "today" (when
/// [date] is today) plus anything scheduled on that date.
class TodayTasksPanel extends StatelessWidget {
  final DateTime date;
  final VoidCallback? onOpenTasks;

  const TodayTasksPanel({super.key, required this.date, this.onOpenTasks});

  bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final isToday = _sameDay(date, DateTime.now());

    return StreamBuilder<QuerySnapshot>(
      stream: getFirestore().collection('tasks').where('userId', isEqualTo: uid).snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox.shrink();
        final tasks = snapshot.data!.docs.map((d) => Task.fromFirestore(d)).where((t) {
          if (t.scheduledDate != null && _sameDay(t.scheduledDate!, date)) return true;
          if (isToday && t.isToday) return true;
          if (t.isCompleted && t.completedAt != null && _sameDay(t.completedAt!, date)) return true;
          return false;
        }).toList()
          ..sort((a, b) {
            if (a.isCompleted != b.isCompleted) return a.isCompleted ? 1 : -1;
            return a.sortOrder.compareTo(b.sortOrder);
          });

        final open = tasks.where((t) => !t.isCompleted).toList();
        final done = tasks.where((t) => t.isCompleted).toList();
        final totalMin = open.fold<int>(0, (s, t) => s + t.estimatedMinutes);

        if (tasks.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    isToday ? 'No tasks flagged for today.' : 'No tasks scheduled for this day.',
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ),
                if (onOpenTasks != null)
                  TextButton.icon(
                    onPressed: onOpenTasks,
                    icon: const Icon(Icons.task_alt, size: 18),
                    label: const Text('Pick tasks'),
                  ),
              ],
            ),
          );
        }

        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 8, bottom: 4),
                child: Text(
                  open.isEmpty
                      ? 'All ${done.length} done'
                      : '${open.length} open · ${(totalMin / 60).toStringAsFixed(totalMin % 60 == 0 ? 0 : 1)}h'
                          '${done.isNotEmpty ? ' · ${done.length} done' : ''}',
                  style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
              ...tasks.map((t) => _TaskRow(task: t)),
            ],
          ),
        );
      },
    );
  }
}

class _TaskRow extends StatelessWidget {
  final Task task;
  const _TaskRow({required this.task});

  Future<void> _toggle() async {
    final newStatus = !task.isCompleted;
    await getFirestore().collection('tasks').doc(task.id).update({
      'isCompleted': newStatus,
      'completedAt': newStatus ? Timestamp.fromDate(DateTime.now()) : null,
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: _toggle,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          children: [
            Icon(
              task.isCompleted ? Icons.check_circle : Icons.radio_button_unchecked,
              size: 20,
              color: task.isCompleted ? theme.colorScheme.primary : theme.colorScheme.outline,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                task.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  decoration: task.isCompleted ? TextDecoration.lineThrough : null,
                  color: task.isCompleted ? theme.disabledColor : null,
                ),
              ),
            ),
            if (task.estimatedMinutes > 0 && !task.isCompleted)
              Text(task.estimateLabel,
                  style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}
