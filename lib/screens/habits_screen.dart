import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/habit.dart';
import '../services/habit_service.dart';
import '../utils/habit_stats.dart';
import '../widgets/habit_detail_sheet.dart';
import '../widgets/habit_editor_sheet.dart';
import '../widgets/habit_widgets.dart';

/// First-class habit tracker: today's checklist, streaks, 7-day dots,
/// per-habit history, archive, and drag-to-reorder.
class HabitsScreen extends StatefulWidget {
  final HabitService? service;
  final DateTime? today;

  const HabitsScreen({super.key, this.service, this.today});

  @override
  State<HabitsScreen> createState() => _HabitsScreenState();
}

class _HabitsScreenState extends State<HabitsScreen> {
  late final HabitService _service = widget.service ?? HabitService();
  late DateTime _date = HabitStats.dayOnly(widget.today ?? DateTime.now());
  bool _showArchived = false;
  bool _backfillStarted = false;

  DateTime get _today => HabitStats.dayOnly(widget.today ?? DateTime.now());
  bool get _isToday => _date == _today;

  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  Future<void> _add() async {
    final uid = _uid;
    if (uid == null) return;
    final result = await showHabitEditor(context);
    if (result == null) return;
    await _service.addHabit(
      uid: uid,
      name: result.name,
      type: result.type,
      frequency: result.frequency,
      weeklyTarget: result.weeklyTarget,
      targetCount: result.targetCount,
      reminderTime: result.reminderTime,
    );
  }

  Future<void> _edit(Habit habit) async {
    final uid = _uid;
    if (uid == null) return;
    final result = await showHabitEditor(context, existing: habit);
    if (result == null) return;
    await _service.updateHabit(
      uid,
      habit.copyWith(
        name: result.name,
        type: result.type,
        frequency: result.frequency,
        weeklyTarget: result.weeklyTarget,
        targetCount: result.targetCount,
        reminderTime: result.reminderTime,
        clearReminder: result.reminderTime == null,
      ),
    );
  }

  Future<void> _openDetail(Habit habit) async {
    final uid = _uid;
    if (uid == null) return;
    final action = await showHabitDetail(context, habit, today: _today);
    if (!mounted || action == null) return;
    switch (action) {
      case HabitDetailAction.edit:
        await _edit(habit);
        break;
      case HabitDetailAction.archive:
        await _service.setArchived(uid, habit.id, true);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('"${habit.name}" archived'),
            action: SnackBarAction(label: 'Undo', onPressed: () => _service.setArchived(uid, habit.id, false)),
          ));
        }
        break;
      case HabitDetailAction.unarchive:
        await _service.setArchived(uid, habit.id, false);
        break;
      case HabitDetailAction.delete:
        final confirm = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Delete habit?'),
            content: Text('"${habit.name}" and its history will be removed. Consider archiving instead.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Delete'),
              ),
            ],
          ),
        );
        if (confirm == true) await _service.deleteHabit(uid, habit.id);
        break;
    }
  }

  void _shiftDate(int days) {
    final next = _date.add(Duration(days: days));
    if (next.isAfter(_today)) return;
    setState(() => _date = next);
  }

  @override
  Widget build(BuildContext context) {
    final uid = _uid;
    if (uid == null) return const SizedBox.shrink();
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Habits'),
        actions: [
          IconButton(
            tooltip: 'Previous day',
            icon: const Icon(Icons.chevron_left),
            onPressed: () => _shiftDate(-1),
          ),
          TextButton(
            onPressed: _isToday ? null : () => setState(() => _date = _today),
            child: Text(_isToday ? 'Today' : DateFormat('EEE, MMM d').format(_date)),
          ),
          IconButton(
            tooltip: 'Next day',
            icon: const Icon(Icons.chevron_right),
            onPressed: _isToday ? null : () => _shiftDate(1),
          ),
          const SizedBox(width: 8),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'habits_fab',
        onPressed: _add,
        icon: const Icon(Icons.add),
        label: const Text('New habit'),
      ),
      body: StreamBuilder<List<Habit>>(
        stream: _service.watchHabits(uid),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final all = snapshot.data!;
          if (!_backfillStarted && all.isNotEmpty) {
            _backfillStarted = true;
            _service.backfillHistoryIfNeeded(uid, all);
          }
          final active = all.where((h) => !h.archived).toList();
          final archived = all.where((h) => h.archived).toList();

          if (all.isEmpty) return _EmptyState(onAdd: _add);

          final due = active.where((h) => HabitStats.isDueOn(h, _date)).toList();
          final doneCount = due.where((h) => HabitStats.isDoneOn(h, _date)).length;

          return ListView(
            padding: const EdgeInsets.only(bottom: 96),
            children: [
              _SummaryCard(
                date: _date,
                isToday: _isToday,
                done: doneCount,
                total: due.length,
                habits: active,
              ),
              if (active.isNotEmpty)
                ReorderableListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  buildDefaultDragHandles: false,
                  itemCount: active.length,
                  onReorder: (oldIndex, newIndex) {
                    if (newIndex > oldIndex) newIndex--;
                    final reordered = List<Habit>.from(active);
                    final item = reordered.removeAt(oldIndex);
                    reordered.insert(newIndex, item);
                    _service.saveOrder(uid, reordered);
                  },
                  itemBuilder: (context, index) {
                    final habit = active[index];
                    return _HabitRow(
                      key: ValueKey(habit.id),
                      index: index,
                      habit: habit,
                      date: _date,
                      today: _today,
                      onChanged: (v) => _service.setValue(uid, habit, _date, v),
                      onTap: () => _openDetail(habit),
                    );
                  },
                ),
              if (archived.isNotEmpty) ...[
                const SizedBox(height: 8),
                ListTile(
                  dense: true,
                  leading: Icon(Icons.archive_outlined, color: theme.colorScheme.onSurfaceVariant),
                  title: Text('Archived (${archived.length})',
                      style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                  trailing: Icon(_showArchived ? Icons.expand_less : Icons.expand_more),
                  onTap: () => setState(() => _showArchived = !_showArchived),
                ),
                if (_showArchived)
                  ...archived.map((h) => ListTile(
                        dense: true,
                        title: Text(h.name, style: TextStyle(color: theme.disabledColor)),
                        subtitle: Text('${HabitStats.totalCompletions(h)} completions'),
                        trailing: TextButton(
                          onPressed: () => _service.setArchived(uid, h.id, false),
                          child: const Text('Restore'),
                        ),
                        onTap: () => _openDetail(h),
                      )),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final DateTime date;
  final bool isToday;
  final int done;
  final int total;
  final List<Habit> habits;

  const _SummaryCard({
    required this.date,
    required this.isToday,
    required this.done,
    required this.total,
    required this.habits,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pct = total == 0 ? 0.0 : done / total;
    final allDone = total > 0 && done == total;
    int bestStreak = 0;
    for (final h in habits) {
      final s = HabitStats.currentStreak(h, date);
      if (h.frequency == HabitFrequency.daily && s > bestStreak) bestStreak = s;
    }

    String headline;
    if (total == 0) {
      headline = 'Nothing due ${isToday ? 'today' : 'this day'}';
    } else if (allDone) {
      headline = isToday ? 'All done for today!' : 'All done';
    } else if (done == 0) {
      headline = isToday ? 'Let\'s get started' : '$total habits were due';
    } else {
      headline = '${total - done} to go';
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            theme.colorScheme.primaryContainer.withValues(alpha: allDone ? 0.9 : 0.5),
            theme.colorScheme.surface,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 56,
            height: 56,
            child: Stack(
              fit: StackFit.expand,
              children: [
                CircularProgressIndicator(
                  value: pct,
                  strokeWidth: 6,
                  backgroundColor: theme.colorScheme.surfaceContainerHighest,
                ),
                Center(
                  child: allDone
                      ? Icon(Icons.check, color: theme.colorScheme.primary)
                      : Text('$done/$total', style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(headline, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 2),
                Text(
                  bestStreak > 0
                      ? 'Longest active streak: $bestStreak day${bestStreak == 1 ? '' : 's'}'
                      : 'Complete a habit two days in a row to start a streak',
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HabitRow extends StatelessWidget {
  final int index;
  final Habit habit;
  final DateTime date;
  final DateTime today;
  final ValueChanged<int> onChanged;
  final VoidCallback onTap;

  const _HabitRow({
    super.key,
    required this.index,
    required this.habit,
    required this.date,
    required this.today,
    required this.onChanged,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final done = HabitStats.isDoneOn(habit, date);
    final wide = MediaQuery.of(context).size.width >= 600;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      elevation: 0,
      color: done ? theme.colorScheme.primary.withValues(alpha: 0.06) : theme.colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 10, 12, 10),
          child: Row(
            children: [
              ReorderableDragStartListener(
                index: index,
                child: Icon(Icons.drag_indicator, color: theme.colorScheme.outlineVariant),
              ),
              const SizedBox(width: 4),
              HabitValueControl(habit: habit, date: date, onChanged: onChanged),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      habit.name,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                        decoration: done ? TextDecoration.lineThrough : null,
                        color: done ? theme.colorScheme.onSurfaceVariant : null,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        StreakBadge(habit: habit, today: today),
                        WeeklyProgressPill(habit: habit, date: date),
                        if (!wide) HabitDotRow(habit: habit, endDate: date, dotSize: 8),
                      ],
                    ),
                  ],
                ),
              ),
              if (wide) ...[
                const SizedBox(width: 12),
                HabitDotRow(habit: habit, endDate: date, dotSize: 12, showLabels: true),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onAdd;
  const _EmptyState({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.self_improvement, size: 72, color: theme.colorScheme.primary.withValues(alpha: 0.6)),
            const SizedBox(height: 16),
            Text('Start with one small habit', style: theme.textTheme.titleLarge, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(
              'Pick something you can do in two minutes. Check it off daily and watch the streak grow.',
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            FilledButton.icon(onPressed: onAdd, icon: const Icon(Icons.add), label: const Text('Add a habit')),
          ],
        ),
      ),
    );
  }
}
