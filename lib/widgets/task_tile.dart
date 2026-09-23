import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/task.dart';

enum TaskTileAction { schedule, moveFolder, duplicate, delete, clearDate }

class TaskTile extends StatelessWidget {
  final Task task;
  final VoidCallback onToggleStatus;
  final VoidCallback onDelete;
  final VoidCallback onEdit;
  final Function(bool) onToggleToday;
  final VoidCallback? onSchedule;
  final VoidCallback? onMoveFolder;
  final VoidCallback? onDuplicate;
  final VoidCallback? onClearDate;

  /// When set, a drag handle is shown that starts a reorder for this index.
  final int? dragIndex;

  /// Show the folder name as a chip (used in cross-folder views).
  final String? folderLabel;

  const TaskTile({
    super.key,
    required this.task,
    required this.onToggleStatus,
    required this.onDelete,
    required this.onEdit,
    required this.onToggleToday,
    this.onSchedule,
    this.onMoveFolder,
    this.onDuplicate,
    this.onClearDate,
    this.dragIndex,
    this.folderLabel,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isOverdue = task.isOverdue;
    final isWide = MediaQuery.of(context).size.width >= 600;

    return Dismissible(
      key: Key(task.id),
      background: Container(
        color: Colors.green,
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 20),
        child: const Icon(Icons.check, color: Colors.white),
      ),
      secondaryBackground: Container(
        color: Colors.red,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.startToEnd) {
          onToggleStatus();
          return false;
        }
        return await _confirmDelete(context);
      },
      onDismissed: (direction) {
        if (direction == DismissDirection.endToStart) onDelete();
      },
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        elevation: 0,
        color: task.isCompleted
            ? theme.colorScheme.surfaceContainerLow.withValues(alpha: 0.6)
            : theme.colorScheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
            color: isOverdue
                ? theme.colorScheme.error.withValues(alpha: 0.4)
                : theme.dividerColor.withValues(alpha: 0.1),
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onEdit,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(6, 8, 4, 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (dragIndex != null)
                  ReorderableDragStartListener(
                    index: dragIndex!,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: Icon(Icons.drag_indicator, size: 18, color: theme.colorScheme.outlineVariant),
                    ),
                  )
                else
                  const SizedBox(width: 6),
                _CheckCircle(task: task, isOverdue: isOverdue, onTap: onToggleStatus),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        task.title,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          decoration: task.isCompleted ? TextDecoration.lineThrough : null,
                          color: task.isCompleted ? theme.disabledColor : theme.textTheme.bodyLarge?.color,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      if (task.notes.trim().isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          task.notes.trim().split('\n').first,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                        ),
                      ],
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          if (task.estimatedMinutes > 0)
                            _buildChip(context,
                                label: task.estimateLabel, icon: Icons.access_time_filled, color: theme.colorScheme.secondary),
                          if (task.scheduledDate != null)
                            _buildChip(
                              context,
                              label: isOverdue
                                  ? 'Overdue · ${DateFormat('MMM d').format(task.scheduledDate!)}'
                                  : DateFormat('MMM d').format(task.scheduledDate!),
                              icon: Icons.event,
                              color: isOverdue
                                  ? theme.colorScheme.error
                                  : (task.isToday ? Colors.orange : theme.colorScheme.tertiary),
                            ),
                          if (folderLabel != null)
                            _buildChip(context, label: folderLabel!, icon: Icons.folder_outlined, color: theme.colorScheme.outline),
                          if (task.isCompleted && task.completedAt != null)
                            _buildChip(context,
                                label: 'Done ${DateFormat('MMM d').format(task.completedAt!)}',
                                icon: Icons.check,
                                color: theme.colorScheme.primary),
                        ],
                      ),
                    ],
                  ),
                ),
                if (!task.isCompleted)
                  IconButton(
                    icon: Icon(
                      task.isToday ? Icons.wb_sunny : Icons.wb_sunny_outlined,
                      color: task.isToday ? Colors.orange : theme.disabledColor,
                      size: 20,
                    ),
                    onPressed: () => onToggleToday(!task.isToday),
                    tooltip: task.isToday ? 'Planned for today (click to remove)' : 'Do today',
                    visualDensity: VisualDensity.compact,
                  ),
                if (!task.isCompleted && isWide && onSchedule != null)
                  IconButton(
                    icon: Icon(Icons.schedule_send_outlined, size: 20, color: theme.colorScheme.onSurfaceVariant),
                    tooltip: 'Put on timeline',
                    onPressed: onSchedule,
                    visualDensity: VisualDensity.compact,
                  ),
                PopupMenuButton<TaskTileAction>(
                  tooltip: 'More',
                  icon: Icon(Icons.more_vert, size: 20, color: theme.colorScheme.onSurfaceVariant),
                  onSelected: (a) async {
                    switch (a) {
                      case TaskTileAction.schedule:
                        onSchedule?.call();
                        break;
                      case TaskTileAction.moveFolder:
                        onMoveFolder?.call();
                        break;
                      case TaskTileAction.duplicate:
                        onDuplicate?.call();
                        break;
                      case TaskTileAction.clearDate:
                        onClearDate?.call();
                        break;
                      case TaskTileAction.delete:
                        if (await _confirmDelete(context) == true) onDelete();
                        break;
                    }
                  },
                  itemBuilder: (ctx) => [
                    if (onSchedule != null)
                      const PopupMenuItem(
                        value: TaskTileAction.schedule,
                        child: ListTile(dense: true, leading: Icon(Icons.schedule_send_outlined), title: Text('Put on timeline')),
                      ),
                    if (onMoveFolder != null)
                      const PopupMenuItem(
                        value: TaskTileAction.moveFolder,
                        child: ListTile(dense: true, leading: Icon(Icons.drive_file_move_outline), title: Text('Move to folder')),
                      ),
                    if (onDuplicate != null)
                      const PopupMenuItem(
                        value: TaskTileAction.duplicate,
                        child: ListTile(dense: true, leading: Icon(Icons.copy_outlined), title: Text('Duplicate')),
                      ),
                    if (onClearDate != null && task.scheduledDate != null)
                      const PopupMenuItem(
                        value: TaskTileAction.clearDate,
                        child: ListTile(dense: true, leading: Icon(Icons.event_busy_outlined), title: Text('Remove date')),
                      ),
                    const PopupMenuDivider(),
                    PopupMenuItem(
                      value: TaskTileAction.delete,
                      child: ListTile(
                        dense: true,
                        leading: Icon(Icons.delete_outline, color: theme.colorScheme.error),
                        title: Text('Delete', style: TextStyle(color: theme.colorScheme.error)),
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

  Future<bool?> _confirmDelete(BuildContext context) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete task?'),
        content: Text('"${task.title}" will be permanently removed.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Widget _buildChip(BuildContext context, {required String label, required IconData icon, required Color color}) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(color: color, fontWeight: FontWeight.bold, fontSize: 10),
          ),
        ],
      ),
    );
  }
}

class _CheckCircle extends StatelessWidget {
  final Task task;
  final bool isOverdue;
  final VoidCallback onTap;
  const _CheckCircle({required this.task, required this.isOverdue, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: task.isCompleted ? theme.colorScheme.primary : Colors.transparent,
            border: Border.all(
              color: task.isCompleted
                  ? theme.colorScheme.primary
                  : (isOverdue ? theme.colorScheme.error : theme.hintColor),
              width: 2,
            ),
          ),
          child: task.isCompleted ? const Icon(Icons.check, size: 16, color: Colors.white) : null,
        ),
      ),
    );
  }
}
