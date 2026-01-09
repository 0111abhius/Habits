import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/task.dart';

class TaskTile extends StatelessWidget {
  final Task task;
  final VoidCallback onToggleStatus;
  final VoidCallback onDelete;
  final VoidCallback onEdit;
  final Function(bool) onToggleToday;

  const TaskTile({
    super.key,
    required this.task,
    required this.onToggleStatus,
    required this.onDelete,
    required this.onEdit,
    required this.onToggleToday,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    // Formatting
    final hours = task.estimatedMinutes / 60;
    final timeLabel = hours == hours.toInt() 
      ? '${hours.toInt()}h' 
      : '${hours.toStringAsFixed(1)}h';
      
    final isOverdue = task.scheduledDate != null && 
        task.scheduledDate!.isBefore(DateTime.now().subtract(const Duration(days: 1))) &&
        !task.isCompleted;

    return Dismissible(
      key: Key(task.id),
      background: Container(
        color: Colors.green, // Swipe Right -> Complete
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 20),
        child: const Icon(Icons.check, color: Colors.white),
      ),
      secondaryBackground: Container(
        color: Colors.red, // Swipe Left -> Delete
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.startToEnd) {
          // Complete
          onToggleStatus();
          return false; // Don't remove from tree immediately, let state update handle it
        } else {
          // Delete
          return await showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Delete Task?'),
              content: const Text('Are you sure you want to delete this task?'),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete', style: TextStyle(color: Colors.red))),
              ],
            ),
          );
        }
      },
      onDismissed: (direction) {
        if (direction == DismissDirection.endToStart) {
          onDelete();
        }
      },
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        elevation: 0,
        color: theme.colorScheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: task.isCompleted 
            ? BorderSide.none 
            : BorderSide(color: theme.dividerColor.withOpacity(0.1)),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onEdit,
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Row(
              children: [
                // Custom Checkbox
                InkWell(
                  onTap: onToggleStatus,
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: task.isCompleted ? theme.colorScheme.primary : Colors.transparent,
                      border: Border.all(
                        color: task.isCompleted ? theme.colorScheme.primary : (isOverdue ? theme.colorScheme.error : theme.hintColor),
                        width: 2,
                      ),
                    ),
                    child: task.isCompleted 
                      ? const Icon(Icons.check, size: 16, color: Colors.white)
                      : null,
                  ),
                ),
                const SizedBox(width: 12),
                
                // Content
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
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          if (task.estimatedMinutes > 0)
                            _buildChip(
                              context, 
                              label: timeLabel, 
                              icon: Icons.access_time_filled, 
                              color: theme.colorScheme.secondary,
                            ),
                          if (task.activity != null && task.activity!.isNotEmpty)
                            _buildChip(
                              context, 
                              label: task.activity!, 
                              icon: Icons.local_activity, 
                              color: Colors.blueAccent,
                            ),
                           if (task.scheduledDate != null)
                             _buildChip(
                               context, 
                               label: DateFormat('MMM d').format(task.scheduledDate!),
                               icon: Icons.event,
                               color: task.isToday ? Colors.orange : theme.colorScheme.tertiary,
                             ),
                        ],
                      ),
                    ],
                  ),
                ),
                
                // Actions
                Column(
                  children: [
                     IconButton(
                       icon: Icon(
                         task.isToday ? Icons.wb_sunny : Icons.wb_sunny_outlined,
                         color: task.isToday ? Colors.orange : theme.disabledColor,
                         size: 20,
                       ),
                       onPressed: () => onToggleToday(!task.isToday),
                       tooltip: task.isToday ? 'Planned for Today' : 'Do Today',
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

  Widget _buildChip(BuildContext context, {required String label, required IconData icon, required Color color}) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label, 
            style: theme.textTheme.labelSmall?.copyWith(
              color: color, 
              fontWeight: FontWeight.bold,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }
}
