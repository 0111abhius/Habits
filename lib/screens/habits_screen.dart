import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/habit.dart';
import '../services/habit_service.dart';
import '../utils/habit_stats.dart';

/// Clean, daily check-in habit tracker.
///
/// Features:
/// - Daily check-in checklist with single-tap completion.
/// - 0–100 Daily Score: Core habits (70 pts) + Bonus habits (30 pts).
/// - Frictionless inline quick-add (type name -> hit enter).
/// - Instant swipe-to-delete with undo.
/// - 1-tap star toggle between Core and Bonus.
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
  final TextEditingController _quickAddController = TextEditingController();
  final FocusNode _quickAddFocus = FocusNode();
  bool _quickAddIsCore = true;
  bool _showArchived = false;
  bool _backfillStarted = false;

  DateTime get _today => HabitStats.dayOnly(widget.today ?? DateTime.now());
  bool get _isToday => _date == _today;
  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  @override
  void dispose() {
    _quickAddController.dispose();
    _quickAddFocus.dispose();
    super.dispose();
  }

  void _shiftDate(int days) {
    final next = _date.add(Duration(days: days));
    if (next.isAfter(_today)) return;
    setState(() => _date = next);
  }

  Future<void> _submitQuickAdd() async {
    final uid = _uid;
    if (uid == null) return;
    final name = _quickAddController.text.trim();
    if (name.isEmpty) return;

    _quickAddController.clear();
    await _service.addHabit(
      uid: uid,
      name: name,
      isCore: _quickAddIsCore,
    );
  }

  Future<void> _addStarterHabit(String name, bool isCore) async {
    final uid = _uid;
    if (uid == null) return;
    await _service.addHabit(uid: uid, name: name, isCore: isCore);
  }

  Future<void> _deleteWithUndo(Habit habit) async {
    final uid = _uid;
    if (uid == null) return;

    await _service.deleteHabit(uid, habit.id);
    if (!mounted) return;

    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('"${habit.name}" removed'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () => _service.restoreHabit(uid, habit),
        ),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  Future<void> _showRenameDialog(Habit habit) async {
    final uid = _uid;
    if (uid == null) return;
    final controller = TextEditingController(text: habit.name);
    bool isCore = habit.isCore;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          final theme = Theme.of(context);
          return AlertDialog(
            title: const Text('Edit Habit'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: controller,
                  autofocus: true,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Habit Name',
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => Navigator.pop(ctx, true),
                ),
                const SizedBox(height: 16),
                Text('Habit Type:', style: theme.textTheme.labelLarge),
                const SizedBox(height: 8),
                Row(
                  children: [
                    ChoiceChip(
                      label: const Text('⭐ Core (70 pts)'),
                      selected: isCore,
                      onSelected: (val) {
                        if (val) setDialogState(() => isCore = true);
                      },
                    ),
                    const SizedBox(width: 8),
                    ChoiceChip(
                      label: const Text('✨ Bonus (30 pts)'),
                      selected: !isCore,
                      onSelected: (val) {
                        if (val) setDialogState(() => isCore = false);
                      },
                    ),
                  ],
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Save'),
              ),
            ],
          );
        },
      ),
    );

    if (confirmed == true && controller.text.trim().isNotEmpty) {
      await _service.updateHabit(
        uid,
        habit.copyWith(
          name: controller.text.trim(),
          isCore: isCore,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = _uid;
    if (uid == null) return const SizedBox.shrink();
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Habits Check-In'),
        centerTitle: false,
        actions: [
          IconButton(
            tooltip: 'Previous day',
            icon: const Icon(Icons.chevron_left),
            onPressed: () => _shiftDate(-1),
          ),
          TextButton(
            onPressed: _isToday ? null : () => setState(() => _date = _today),
            child: Text(
              _isToday ? 'Today' : DateFormat('EEE, MMM d').format(_date),
              style: TextStyle(
                fontWeight: _isToday ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Next day',
            icon: const Icon(Icons.chevron_right),
            onPressed: _isToday ? null : () => _shiftDate(1),
          ),
          const SizedBox(width: 8),
        ],
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

          if (all.isEmpty) {
            return _EmptyHabitsView(
              onAddStarter: _addStarterHabit,
              quickAddController: _quickAddController,
              quickAddFocus: _quickAddFocus,
              quickAddIsCore: _quickAddIsCore,
              onToggleIsCore: () => setState(() => _quickAddIsCore = !_quickAddIsCore),
              onSubmitQuickAdd: _submitQuickAdd,
            );
          }

          final coreHabits = active.where((h) => h.isCore).toList();
          final bonusHabits = active.where((h) => !h.isCore).toList();

          final dueCore = coreHabits.where((h) => HabitStats.isDueOn(h, _date)).toList();
          final dueBonus = bonusHabits.where((h) => HabitStats.isDueOn(h, _date)).toList();

          final doneCore = dueCore.where((h) => HabitStats.isDoneOn(h, _date)).length;
          final doneBonus = dueBonus.where((h) => HabitStats.isDoneOn(h, _date)).length;

          final dailyScore = HabitStats.habitScoreOn(active, _date);
          final avgScore = HabitStats.averageScore(active, _today, days: 7);

          return Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  children: [
                    // Top 0-100 Daily Score Card
                    _DailyScoreCard(
                      score: dailyScore,
                      avgScore: avgScore,
                      isToday: _isToday,
                      coreDone: doneCore,
                      coreTotal: dueCore.length,
                      bonusDone: doneBonus,
                      bonusTotal: dueBonus.length,
                    ),

                    const SizedBox(height: 16),

                    // Core Habits Section
                    if (coreHabits.isNotEmpty) ...[
                      _SectionHeader(
                        title: 'CORE HABITS',
                        icon: Icons.star_rounded,
                        iconColor: Colors.amber.shade700,
                        pointsLabel: bonusHabits.isEmpty ? '100 pts total' : '70 pts max',
                        doneCount: doneCore,
                        totalCount: dueCore.length,
                      ),
                      const SizedBox(height: 6),
                      ReorderableListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        buildDefaultDragHandles: false,
                        itemCount: coreHabits.length,
                        onReorder: (oldIndex, newIndex) {
                          if (newIndex > oldIndex) newIndex--;
                          final reordered = List<Habit>.from(coreHabits);
                          final item = reordered.removeAt(oldIndex);
                          reordered.insert(newIndex, item);
                          _service.saveOrder(uid, [...reordered, ...bonusHabits]);
                        },
                        itemBuilder: (context, index) {
                          final habit = coreHabits[index];
                          return _HabitCheckTile(
                            key: ValueKey(habit.id),
                            index: index,
                            habit: habit,
                            date: _date,
                            today: _today,
                            onToggleDone: () {
                              final done = HabitStats.isDoneOn(habit, _date);
                              _service.setValue(uid, habit, _date, done ? 0 : 1);
                            },
                            onToggleCore: () => _service.toggleCore(uid, habit),
                            onRename: () => _showRenameDialog(habit),
                            onDelete: () => _deleteWithUndo(habit),
                          );
                        },
                      ),
                      const SizedBox(height: 16),
                    ],

                    // Bonus Habits Section
                    if (bonusHabits.isNotEmpty) ...[
                      _SectionHeader(
                        title: 'BONUS HABITS',
                        icon: Icons.auto_awesome_rounded,
                        iconColor: theme.colorScheme.primary,
                        pointsLabel: coreHabits.isEmpty ? '100 pts total' : '30 pts max',
                        doneCount: doneBonus,
                        totalCount: dueBonus.length,
                      ),
                      const SizedBox(height: 6),
                      ReorderableListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        buildDefaultDragHandles: false,
                        itemCount: bonusHabits.length,
                        onReorder: (oldIndex, newIndex) {
                          if (newIndex > oldIndex) newIndex--;
                          final reordered = List<Habit>.from(bonusHabits);
                          final item = reordered.removeAt(oldIndex);
                          reordered.insert(newIndex, item);
                          _service.saveOrder(uid, [...coreHabits, ...reordered]);
                        },
                        itemBuilder: (context, index) {
                          final habit = bonusHabits[index];
                          return _HabitCheckTile(
                            key: ValueKey(habit.id),
                            index: index,
                            habit: habit,
                            date: _date,
                            today: _today,
                            onToggleDone: () {
                              final done = HabitStats.isDoneOn(habit, _date);
                              _service.setValue(uid, habit, _date, done ? 0 : 1);
                            },
                            onToggleCore: () => _service.toggleCore(uid, habit),
                            onRename: () => _showRenameDialog(habit),
                            onDelete: () => _deleteWithUndo(habit),
                          );
                        },
                      ),
                      const SizedBox(height: 16),
                    ],

                    // Collapsible Archived Section
                    if (archived.isNotEmpty) ...[
                      const Divider(height: 32),
                      ListTile(
                        dense: true,
                        leading: Icon(Icons.archive_outlined, color: theme.colorScheme.onSurfaceVariant),
                        title: Text('Archived (${archived.length})', style: theme.textTheme.bodyMedium),
                        trailing: Icon(_showArchived ? Icons.expand_less : Icons.expand_more),
                        onTap: () => setState(() => _showArchived = !_showArchived),
                      ),
                      if (_showArchived)
                        ...archived.map(
                          (h) => ListTile(
                            dense: true,
                            title: Text(h.name, style: TextStyle(color: theme.disabledColor)),
                            trailing: TextButton.icon(
                              icon: const Icon(Icons.unarchive, size: 16),
                              label: const Text('Restore'),
                              onPressed: () => _service.setArchived(uid, h.id, false),
                            ),
                          ),
                        ),
                    ],
                  ],
                ),
              ),

              // Persistent Quick Add Bar at the Bottom
              _QuickAddBar(
                controller: _quickAddController,
                focusNode: _quickAddFocus,
                isCore: _quickAddIsCore,
                onToggleIsCore: () => setState(() => _quickAddIsCore = !_quickAddIsCore),
                onSubmit: _submitQuickAdd,
              ),
            ],
          );
        },
      ),
    );
  }
}

/// The prominent 0–100 Daily Score Card at the top of the Habits view.
class _DailyScoreCard extends StatelessWidget {
  final int score;
  final int avgScore;
  final bool isToday;
  final int coreDone;
  final int coreTotal;
  final int bonusDone;
  final int bonusTotal;

  const _DailyScoreCard({
    required this.score,
    required this.avgScore,
    required this.isToday,
    required this.coreDone,
    required this.coreTotal,
    required this.bonusDone,
    required this.bonusTotal,
  });

  Color _scoreColor(BuildContext context) {
    if (score >= 100) return Colors.green.shade600;
    if (score >= 80) return Colors.teal.shade600;
    if (score >= 50) return Colors.amber.shade700;
    return Theme.of(context).colorScheme.primary;
  }

  String _headline() {
    if (score >= 100) return '100 / 100 · Perfect Day! 🎉';
    if (score >= 80) return '$score / 100 · Strong Day 💪';
    if (score >= 50) return '$score / 100 · Good Momentum ⚡';
    if (score > 0) return '$score / 100 · Making Progress 🌱';
    return '0 / 100 · Ready to check in?';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = _scoreColor(context);
    final totalDue = coreTotal + bonusTotal;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            accent.withValues(alpha: score >= 80 ? 0.15 : 0.08),
            theme.colorScheme.surface,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: accent.withValues(alpha: 0.3), width: 1.5),
      ),
      child: Row(
        children: [
          // Circular 0-100 Score Indicator
          SizedBox(
            width: 68,
            height: 68,
            child: Stack(
              fit: StackFit.expand,
              children: [
                CircularProgressIndicator(
                  value: totalDue == 0 ? 0 : score / 100.0,
                  strokeWidth: 7,
                  strokeCap: StrokeCap.round,
                  backgroundColor: theme.colorScheme.surfaceContainerHighest,
                  valueColor: AlwaysStoppedAnimation<Color>(accent),
                ),
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '$score',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: accent,
                          height: 1.0,
                        ),
                      ),
                      Text(
                        'pts',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(width: 16),

          // Score details & motivational text
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _headline(),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                // Breakdown text
                Text(
                  coreTotal > 0 && bonusTotal > 0
                      ? 'Core: $coreDone/$coreTotal done · Bonus: $bonusDone/$bonusTotal done'
                      : coreTotal > 0
                          ? 'Core: $coreDone/$coreTotal completed'
                          : 'Bonus: $bonusDone/$bonusTotal completed',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 6),
                // 7-day average pill
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '7-day average: $avgScore / 100',
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Section header for Core / Bonus habits
class _SectionHeader extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color iconColor;
  final String pointsLabel;
  final int doneCount;
  final int totalCount;

  const _SectionHeader({
    required this.title,
    required this.icon,
    required this.iconColor,
    required this.pointsLabel,
    required this.doneCount,
    required this.totalCount,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: iconColor),
          const SizedBox(width: 6),
          Text(
            title,
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              pointsLabel,
              style: theme.textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: iconColor,
              ),
            ),
          ),
          const Spacer(),
          Text(
            '$doneCount of $totalCount done',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// Clean check-in tile for an individual habit.
class _HabitCheckTile extends StatelessWidget {
  final int index;
  final Habit habit;
  final DateTime date;
  final DateTime today;
  final VoidCallback onToggleDone;
  final VoidCallback onToggleCore;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  const _HabitCheckTile({
    super.key,
    required this.index,
    required this.habit,
    required this.date,
    required this.today,
    required this.onToggleDone,
    required this.onToggleCore,
    required this.onRename,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final done = HabitStats.isDoneOn(habit, date);
    final streak = HabitStats.currentStreak(habit, date);

    return Dismissible(
      key: ValueKey(habit.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        margin: const EdgeInsets.symmetric(vertical: 4),
        decoration: BoxDecoration(
          color: theme.colorScheme.error,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.delete_outline, color: Colors.white, size: 22),
            SizedBox(width: 6),
            Text(
              'Delete',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
      onDismissed: (_) => onDelete(),
      child: Card(
        margin: const EdgeInsets.symmetric(vertical: 4),
        elevation: 0,
        color: done
            ? theme.colorScheme.primary.withValues(alpha: 0.06)
            : theme.colorScheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: done
                ? theme.colorScheme.primary.withValues(alpha: 0.3)
                : theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
            width: done ? 1.5 : 1.0,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onToggleDone,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
            child: Row(
              children: [
                // Drag handle
                ReorderableDragStartListener(
                  index: index,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Icon(
                      Icons.drag_indicator,
                      size: 20,
                      color: theme.colorScheme.outlineVariant,
                    ),
                  ),
                ),

                // Big Satisfying Checkbox
                Semantics(
                  button: true,
                  checked: done,
                  label: habit.name,
                  child: InkWell(
                    onTap: onToggleDone,
                    borderRadius: BorderRadius.circular(24),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: done ? theme.colorScheme.primary : Colors.transparent,
                        border: Border.all(
                          color: done ? theme.colorScheme.primary : theme.colorScheme.outline,
                          width: 2,
                        ),
                      ),
                      child: done
                          ? const Icon(Icons.check, size: 20, color: Colors.white)
                          : null,
                    ),
                  ),
                ),

                const SizedBox(width: 12),

                // Habit Title & Details
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        habit.name,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                          decoration: done ? TextDecoration.lineThrough : null,
                          color: done
                              ? theme.colorScheme.onSurfaceVariant
                              : theme.colorScheme.onSurface,
                        ),
                      ),
                      if (streak >= 2) ...[
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            const Text('🔥', style: TextStyle(fontSize: 12)),
                            const SizedBox(width: 2),
                            Text(
                              '$streak-day streak',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: Colors.orange.shade800,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),

                // Core / Bonus Star Toggle
                IconButton(
                  tooltip: habit.isCore ? 'Core habit (click to switch to Bonus)' : 'Bonus habit (click to switch to Core)',
                  icon: Icon(
                    habit.isCore ? Icons.star_rounded : Icons.star_border_rounded,
                    color: habit.isCore ? Colors.amber.shade700 : theme.colorScheme.outline,
                    size: 22,
                  ),
                  onPressed: onToggleCore,
                ),

                // 3-dots Menu for Rename / Delete
                PopupMenuButton<String>(
                  icon: Icon(Icons.more_vert, size: 20, color: theme.colorScheme.onSurfaceVariant),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  onSelected: (val) {
                    if (val == 'edit') onRename();
                    if (val == 'toggle') onToggleCore();
                    if (val == 'delete') onDelete();
                  },
                  itemBuilder: (ctx) => [
                    const PopupMenuItem(
                      value: 'edit',
                      child: Row(
                        children: [
                          Icon(Icons.edit_outlined, size: 18),
                          SizedBox(width: 8),
                          Text('Edit Name'),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'toggle',
                      child: Row(
                        children: [
                          Icon(
                            habit.isCore ? Icons.auto_awesome_rounded : Icons.star_rounded,
                            size: 18,
                          ),
                          SizedBox(width: 8),
                          Text(habit.isCore ? 'Make Bonus (30 pts)' : 'Make Core (70 pts)'),
                        ],
                      ),
                    ),
                    const PopupMenuDivider(),
                    const PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(Icons.delete_outline, size: 18, color: Colors.red),
                          SizedBox(width: 8),
                          Text('Delete', style: TextStyle(color: Colors.red)),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The inline Quick-Add bar fixed to the bottom of the screen.
class _QuickAddBar extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool isCore;
  final VoidCallback onToggleIsCore;
  final VoidCallback onSubmit;

  const _QuickAddBar({
    required this.controller,
    required this.focusNode,
    required this.isCore,
    required this.onToggleIsCore,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: EdgeInsets.fromLTRB(
        16,
        8,
        16,
        MediaQuery.of(context).viewInsets.bottom + 12,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            offset: const Offset(0, -2),
            blurRadius: 8,
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5)),
          ),
          child: Row(
            children: [
              // Core / Bonus Selector Pill
              InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: onToggleIsCore,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  decoration: BoxDecoration(
                    color: isCore
                        ? Colors.amber.withValues(alpha: 0.2)
                        : theme.colorScheme.primaryContainer.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isCore ? Colors.amber.shade700 : theme.colorScheme.primary,
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isCore ? Icons.star_rounded : Icons.auto_awesome_rounded,
                        size: 16,
                        color: isCore ? Colors.amber.shade800 : theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        isCore ? 'Core' : 'Bonus',
                        style: theme.textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: isCore ? Colors.amber.shade900 : theme.colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(width: 10),

              // Text Field
              Expanded(
                child: TextField(
                  controller: controller,
                  focusNode: focusNode,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    hintText: isCore
                        ? 'Add core habit (e.g. Workout)...'
                        : 'Add bonus habit (e.g. Read 15 mins)...',
                    hintStyle: TextStyle(
                      color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                      fontSize: 14,
                    ),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                  onSubmitted: (_) => onSubmit(),
                ),
              ),

              // Add Button
              IconButton(
                icon: const Icon(Icons.arrow_upward_rounded),
                tooltip: 'Add habit',
                style: IconButton.styleFrom(
                  backgroundColor: theme.colorScheme.primary,
                  foregroundColor: theme.colorScheme.onPrimary,
                  minimumSize: const Size(36, 36),
                ),
                onPressed: onSubmit,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Empty state when no habits exist yet, with quick starter chips.
class _EmptyHabitsView extends StatelessWidget {
  final Future<void> Function(String name, bool isCore) onAddStarter;
  final TextEditingController quickAddController;
  final FocusNode quickAddFocus;
  final bool quickAddIsCore;
  final VoidCallback onToggleIsCore;
  final VoidCallback onSubmitQuickAdd;

  const _EmptyHabitsView({
    required this.onAddStarter,
    required this.quickAddController,
    required this.quickAddFocus,
    required this.quickAddIsCore,
    required this.onToggleIsCore,
    required this.onSubmitQuickAdd,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      children: [
        Expanded(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.check_circle_outline_rounded,
                    size: 72,
                    color: theme.colorScheme.primary.withValues(alpha: 0.6),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Simple Daily Habits',
                    style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Check off daily habits and aim for a 100/100 score.\nCore habits build your foundation; bonus habits earn extra credit.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Quick Starters
                  Text(
                    'TAP TO ADD POPULAR HABITS:',
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                      color: theme.colorScheme.outline,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    alignment: WrapAlignment.center,
                    children: [
                      ActionChip(
                        avatar: const Icon(Icons.star, size: 16, color: Colors.amber),
                        label: const Text('Morning Workout (Core)'),
                        onPressed: () => onAddStarter('Morning Workout', true),
                      ),
                      ActionChip(
                        avatar: const Icon(Icons.star, size: 16, color: Colors.amber),
                        label: const Text('Drink 2L Water (Core)'),
                        onPressed: () => onAddStarter('Drink 2L Water', true),
                      ),
                      ActionChip(
                        avatar: const Icon(Icons.star, size: 16, color: Colors.amber),
                        label: const Text('Sleep by 11 PM (Core)'),
                        onPressed: () => onAddStarter('Sleep by 11 PM', true),
                      ),
                      ActionChip(
                        avatar: const Icon(Icons.auto_awesome, size: 16, color: Colors.blue),
                        label: const Text('Read 15 mins (Bonus)'),
                        onPressed: () => onAddStarter('Read 15 mins', false),
                      ),
                      ActionChip(
                        avatar: const Icon(Icons.auto_awesome, size: 16, color: Colors.blue),
                        label: const Text('10-min Meditation (Bonus)'),
                        onPressed: () => onAddStarter('10-min Meditation', false),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),

        // Quick add bar
        _QuickAddBar(
          controller: quickAddController,
          focusNode: quickAddFocus,
          isCore: quickAddIsCore,
          onToggleIsCore: onToggleIsCore,
          onSubmit: onSubmitQuickAdd,
        ),
      ],
    );
  }
}
