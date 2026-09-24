import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/task.dart';
import '../utils/ai_service.dart';
import 'ai_planning_dialogs.dart'; // Reuse AIPlanReviewDialog
import 'dart:convert';

enum ScheduleMode { single, range }

class AIAutoScheduleDialog extends StatefulWidget {
  // ... (unchanged)
  final List<Task> availableTasks;
  final Map<String, String> folderActivities;
  final Function(DateTime date, Map<String, String> schedule) onScheduleGenerated;
  final Future<String> Function(DateTime date) onGetHistory;
  final Future<String> Function(DateTime date) onGetCurrentPlan;

  const AIAutoScheduleDialog({
    super.key,
    required this.availableTasks,
    required this.folderActivities,
    required this.onScheduleGenerated,
    required this.onGetHistory,
    required this.onGetCurrentPlan,
  });
  
  static Future<void> show(
    BuildContext context, {
    required List<Task> tasks,
    required Map<String, String> folderActivities,
    required Function(DateTime date, Map<String, String> schedule) onScheduleGenerated,
    required Future<String> Function(DateTime date) onGetHistory,
    required Future<String> Function(DateTime date) onGetCurrentPlan,
  }) {
    return showDialog(
      context: context,
      builder: (ctx) => AIAutoScheduleDialog(
        availableTasks: tasks,
        folderActivities: folderActivities,
        onScheduleGenerated: onScheduleGenerated,
        onGetHistory: onGetHistory,
        onGetCurrentPlan: onGetCurrentPlan,
      ),
    );
  }

  @override
  State<AIAutoScheduleDialog> createState() => _AIAutoScheduleDialogState();
}

class _AIAutoScheduleDialogState extends State<AIAutoScheduleDialog> {
  ScheduleMode _mode = ScheduleMode.single;
  DateTime _selectedDate = DateTime.now();
  DateTimeRange? _selectedRange;
  final Set<String> _selectedTaskIds = {};
  bool _isLoading = false;
  String? _statusMessage;

  Map<String, String> _calculateActivityHints() {
     final Map<String, String> hints = {};
     for (var t in widget.availableTasks) {
        if (t.activity != null && t.activity!.isNotEmpty) {
            hints[t.title] = t.activity!;
        } else if (t.folder != null && widget.folderActivities.containsKey(t.folder)) {
            hints[t.title] = widget.folderActivities[t.folder]!;
        }
     }
     return hints;
  }

  @override
  void initState() {
    super.initState();
    // Default range: Today + 6 days
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    _selectedRange = DateTimeRange(start: today, end: today.add(const Duration(days: 6)));
    _updateSelection();
  }

  void _updateSelection() {
    _selectedTaskIds.clear();
    // Default select tasks that are explicitly scheduled for this date (or range)
    for (var t in widget.availableTasks) {
      if (_mode == ScheduleMode.single) {
        if (_isScheduledForDate(t, _selectedDate)) {
          _selectedTaskIds.add(t.id);
        }
      } else {
        // Range mode: Select tasks in range
        if (_isScheduledForRange(t, _selectedRange!)) {
          _selectedTaskIds.add(t.id);
        }
      }
    }
  }

  bool _isScheduledForDate(Task t, DateTime date) {
    if (t.scheduledDate == null) return false;
    return t.scheduledDate!.year == date.year &&
           t.scheduledDate!.month == date.month &&
           t.scheduledDate!.day == date.day;
  }

  bool _isScheduledForRange(Task t, DateTimeRange range) {
      if (t.scheduledDate == null) return false;
      final d = t.scheduledDate!;
      // Simple range check (inclusive start, inclusive end for day granularity)
      final day = DateTime(d.year, d.month, d.day);
      return !day.isBefore(range.start) && !day.isAfter(range.end);
  }

  Future<void> _selectDate(BuildContext context) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    
    if (_mode == ScheduleMode.single) {
        final picked = await showDatePicker(
        context: context,
        initialDate: _selectedDate,
        firstDate: today, 
        lastDate: today.add(const Duration(days: 365)),
        );
        if (picked != null && picked != _selectedDate) {
        setState(() {
            _selectedDate = picked;
            _updateSelection();
        });
        }
    } else {
        final picked = await showDateRangePicker(
            context: context, 
            firstDate: today, 
            lastDate: today.add(const Duration(days: 365)),
            initialDateRange: _selectedRange,
        );
        if (picked != null && picked != _selectedRange) {
            setState(() {
                _selectedRange = picked;
                _updateSelection();
            });
        }
    }
  }

  Future<void> _generateSchedule() async {
    // Shared validation
    if (_mode == ScheduleMode.single && _selectedTaskIds.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Select at least one task')));
        return;
    }

    setState(() {
      _isLoading = true;
      _statusMessage = 'Initializing...';
    });

    try {
      if (_mode == ScheduleMode.single) {
          await _generateSingleDay();
      } else {
          await _generateBatchRange();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _statusMessage = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _generateSingleDay() async {
    final tasksToSchedule = widget.availableTasks
        .where((t) => _selectedTaskIds.contains(t.id))
        .toList();
    
    // ... (Existing Single Day Logic, but slightly refactored to use variables explicitly if needed, but keeping implementation clean)
    setState(() => _statusMessage = 'Fetching history...');
    final historyLogs = await widget.onGetHistory(_selectedDate);
    final currentPlan = await widget.onGetCurrentPlan(_selectedDate);

    if (!mounted) return;
    setState(() => _statusMessage = 'Generating Schedule...');
    
    // Format tasks
    final taskStrings = tasksToSchedule.map((t) => "${t.title} (${t.estimatedMinutes}m)").toList();

    final aiService = AIService();
    final jsonStr = await aiService.scheduleTasks(
      tasks: taskStrings,
      historyLogs: historyLogs,
      targetDate: _selectedDate,
      currentPlan: currentPlan,
    );
    
    final Map<String, dynamic> data = jsonDecode(jsonStr);

    if (!mounted) return;
    setState(() {
        _isLoading = false;
        _statusMessage = null;
    });

    if (data.containsKey('error')) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('AI Error: ${data['error']}')));
        return;
    }

    final dateStr = DateFormat('EEE, MMM d').format(_selectedDate);
    data['reasoning'] = "Target Date: $dateStr\n\n${data['reasoning'] ?? ''}";

    // Pre-calculate activity names for tasks
    final hints = _calculateActivityHints();

    await AIPlanReviewDialog.show(context, data, (schedule, newActs) async {
        await widget.onScheduleGenerated(_selectedDate, schedule);
        if (mounted) Navigator.pop(context);
    }, taskActivities: hints);
  }

  Future<void> _generateBatchRange() async {
      final start = _selectedRange!.start;
      final end = _selectedRange!.end;
      final days = end.difference(start).inDays + 1;
      
      final Map<DateTime, Map<String, dynamic>> results = {};
      final aiService = AIService();

      for (int i = 0; i < days; i++) {
          final date = start.add(Duration(days: i));
          if (!mounted) return;
          setState(() => _statusMessage = 'Processing ${DateFormat('MMM d').format(date)} (Day ${i+1} of $days)...');

          // 1. Filter tasks for this specific date
          final tasksForDate = widget.availableTasks.where((t) {
              // Only include tasks explicitly scheduled for this date
              // (Ignoring global "selection" set for simplicity in Batch Mode, 
              // assuming user wants to schedule what is assigned)
              return _isScheduledForDate(t, date);
          }).toList();
          
          // If no tasks, skip? Or generate empty schedule to be safe? 
          // If no tasks, AI might just return free time. Let's skip to save tokens if empty.
          if (tasksForDate.isEmpty) {
              results[date] = {'schedule': <String, String>{}, 'reasoning': 'No tasks assigned.'};
              continue;
          }

          // 2. Fetch Context
          final history = await widget.onGetHistory(date);
          final plan = await widget.onGetCurrentPlan(date);
          final taskStrings = tasksForDate.map((t) => "${t.title} (${t.estimatedMinutes}m)").toList();

          // 3. Call AI
          final jsonStr = await aiService.scheduleTasks(
            tasks: taskStrings,
            historyLogs: history,
            targetDate: date,
            currentPlan: plan,
          );
          
          final data = jsonDecode(jsonStr);
          if (data.containsKey('error')) {
               results[date] = {'schedule': <String, String>{}, 'reasoning': 'Error: ${data['error']}'};
          } else {
               results[date] = Map<String, dynamic>.from(data);
          }
      }

      if (!mounted) return;
      setState(() {
          _isLoading = false;
          _statusMessage = null;
      });

      // Show Multi-Day Review
      final hints = _calculateActivityHints();
      
      await AIMultiDayReviewDialog.show(context, results, (finalSchedules) async {
          // Apply all
          for (final entry in finalSchedules.entries) {
              final date = entry.key;
              final schedule = entry.value;
              if (schedule.isNotEmpty) {
                  // We cast to dynamic or assume async is supported by whatever onScheduleGenerated is
                  // TasksScreen signature: Future<void> _applyAISchedule
                  await widget.onScheduleGenerated(date, schedule);
              }
          }
          if (mounted) Navigator.pop(context); // Pop AIAutoScheduleDialog
      }, taskActivities: hints);
  }

  @override
  Widget build(BuildContext context) {
    // Filter tasks
    final visibleTasks = widget.availableTasks.where((t) {
      if (t.scheduledDate == null) return true; // Always show backlog? Or filter backlog too?
      // For now, show backlog + relevant scheduled tasks
      if (_mode == ScheduleMode.single) {
          return _isScheduledForDate(t, _selectedDate);
      } else {
          return _isScheduledForRange(t, _selectedRange!);
      }
    }).toList();
    
    visibleTasks.sort((a, b) {
       final aPinned = a.scheduledDate != null;
       final bPinned = b.scheduledDate != null;
       if (aPinned && !bPinned) return -1;
       if (!aPinned && bPinned) return 1;
       // sub-sort by date?
       if (aPinned && bPinned) return a.scheduledDate!.compareTo(b.scheduledDate!);
       return 0;
    });

    if (_isLoading) {
      return AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(_statusMessage ?? 'Please wait...'),
          ],
        ),
      );
    }

    String dateLabel = '';
    if (_mode == ScheduleMode.single) {
        dateLabel = DateFormat('EEE, MMM d, yyyy').format(_selectedDate);
    } else {
        final start = DateFormat('MMM d').format(_selectedRange!.start);
        final end = DateFormat('MMM d').format(_selectedRange!.end);
        dateLabel = '$start - $end';
    }

    return AlertDialog(
      title: const Text('AI Auto-Schedule'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
             // Mode Toggle
             Center(
                 child: SegmentedButton<ScheduleMode>(
                     segments: const [
                         ButtonSegment(value: ScheduleMode.single, label: Text('Single Day')),
                         ButtonSegment(value: ScheduleMode.range, label: Text('Batch Range')),
                     ],
                     selected: {_mode},
                     onSelectionChanged: (Set<ScheduleMode> newSelection) {
                         setState(() {
                             _mode = newSelection.first;
                             _updateSelection();
                         });
                     },
                 ),
             ),
            const SizedBox(height: 16),
            const Text('1. Select Target:'),
            ListTile(
              title: Text(dateLabel),
              trailing: const Icon(Icons.calendar_today),
              onTap: () => _selectDate(context),
              shape: RoundedRectangleBorder(
                side: const BorderSide(color: Colors.grey),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(height: 16),
            Text('2. Select Tasks (${visibleTasks.length}):'),
            const SizedBox(height: 8),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.withOpacity(0.3)),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: visibleTasks.isEmpty
                    ? const Center(child: Text('No active tasks available for selection.'))
                    : ListView.builder(
                        itemCount: visibleTasks.length,
                        itemBuilder: (context, index) {
                          final task = visibleTasks[index];
                          final isSelected = _selectedTaskIds.contains(task.id);
                          final isScheduled = task.scheduledDate != null;
                          
                          String sub = '${task.estimatedMinutes} min';
                          if (isScheduled) {
                              sub = 'Scheduled ${DateFormat('MM/dd').format(task.scheduledDate!)} • $sub';
                          } else {
                              sub = 'Unscheduled • $sub';
                          }

                          return CheckboxListTile(
                            value: isSelected,
                            onChanged: (val) {
                              setState(() {
                                if (val == true) {
                                  _selectedTaskIds.add(task.id);
                                } else {
                                  _selectedTaskIds.remove(task.id);
                                }
                              });
                            },
                            title: Text(
                              task.title,
                              style: TextStyle(
                                fontWeight: isScheduled ? FontWeight.bold : FontWeight.normal,
                              ),
                            ),
                            subtitle: Text(
                              sub,
                              style: TextStyle(
                                color: isScheduled ? Colors.green : Colors.grey,
                              ),
                            ),
                            dense: true,
                            secondary: isScheduled ? const Icon(Icons.push_pin, size: 16) : null,
                          );
                        },
                      ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: _selectedTaskIds.isEmpty ? null : _generateSchedule,
          icon: const Icon(Icons.auto_awesome),
          label: Text(_mode == ScheduleMode.single ? 'Generate Schedule' : 'Batch Schedule'),
        ),
      ],
    );
  }
}
