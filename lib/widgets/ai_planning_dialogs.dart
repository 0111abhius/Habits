import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:intl/intl.dart';
import '../utils/ai_service.dart';

class AIGoalDialog extends StatelessWidget {
  final String title;
  final String promptLabel;
  final String? initialGoal;
  final TextEditingController _controller;

  AIGoalDialog({
    super.key,
    required this.title,
    this.promptLabel = 'What is your main goal?',
    this.initialGoal,
  }) : _controller = TextEditingController(text: initialGoal);

  static Future<String?> show(BuildContext context, {required String title, String? promptLabel, String? initialGoal}) {
    return showDialog<String>(
      context: context,
      builder: (ctx) => AIGoalDialog(
        title: title, 
        promptLabel: promptLabel ?? 'What is your main goal?',
        initialGoal: initialGoal,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(promptLabel),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            decoration: const InputDecoration(
              labelText: 'Goal (e.g., "Deep work", "Recovery")',
              border: OutlineInputBorder(),
            ),
            maxLines: 2,
            autofocus: true,
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            Navigator.pop(context, _controller.text.trim());
          },
          child: const Text('Get Suggestions'),
        ),
      ],
    );
  }
}

class AIPlanReviewDialog extends StatefulWidget {
  final Map<String, dynamic> data;
  final Future<void> Function(Map<String, String> schedule, List<String> newActivities) onApply;
  final Map<String, String>? taskActivities;
  final Map<String, String> originalSchedule;

  const AIPlanReviewDialog({
    super.key,
    required this.data,
    required this.onApply,
    this.taskActivities,
    this.originalSchedule = const {},
  });

  static Future<void> show(BuildContext context, Map<String, dynamic> data, Future<void> Function(Map<String, String>, List<String>) onApply, {Map<String, String>? taskActivities, Map<String, String> originalSchedule = const {}}) {
    return showDialog(
      context: context,
      builder: (ctx) => AIPlanReviewDialog(data: data, onApply: onApply, taskActivities: taskActivities, originalSchedule: originalSchedule),
    );
  }

  @override
  State<AIPlanReviewDialog> createState() => _AIPlanReviewDialogState();
}

class _ScheduleItem {
  TextEditingController timeCtrl;
  TextEditingController activityCtrl;
  String? originalActivity;

  _ScheduleItem(String time, String activity, {this.originalActivity}) 
    : timeCtrl = TextEditingController(text: time),
      activityCtrl = TextEditingController(text: activity);
  
  void dispose() {
    timeCtrl.dispose();
    activityCtrl.dispose();
  }
}

class _AIPlanReviewDialogState extends State<AIPlanReviewDialog> {
  // late Map<String, String> schedule; // Replaced by _items
  late List<_ScheduleItem> _items;
  late List<String> newActs;
  late String reasoning;
  late Set<String> selectedNewActs;
  bool _showAll = false;

  @override
  void initState() {
    super.initState();
    final initialSchedule = Map<String, String>.from(widget.data['schedule'] ?? {});
    _items = initialSchedule.entries.map((e) {
        final original = widget.originalSchedule[e.key];
        return _ScheduleItem(e.key, e.value, originalActivity: original);
    }).toList();
    
    newActs = List<String>.from(widget.data['newActivities'] ?? []);
    reasoning = widget.data['reasoning'] ?? '';
    selectedNewActs = Set.from(newActs);
  }

  @override
  void dispose() {
    for (var i in _items) {
      i.dispose();
    }
    super.dispose();
  }

  void _addItem() {
    setState(() {
      _items.add(_ScheduleItem("", ""));
    });
  }

  void _removeItem(int index) {
    setState(() {
      _items[index].dispose();
      _items.removeAt(index);
    });
  }

  @override
  Widget build(BuildContext context) {
    // Filter items based on _showAll
    final visibleItems = _items.where((item) {
        if (_showAll) return true;
        // Show if modified (different from original) OR original was empty
        if (item.originalActivity == null || item.originalActivity != item.activityCtrl.text) return true;
        return false;
    }).toList();

    return AlertDialog(
      title: const Text('AI Review'),
      content: SizedBox(
        width: double.maxFinite,
        height: 500, // Increased height
        child: DefaultTabController(
          length: 2,
          child: Column(
            children: [
              const TabBar(
                labelColor: Colors.blue,
                tabs: [Tab(text: 'Schedule'), Tab(text: 'New Activities')],
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    // Schedule Tab
                    Column(
                      children: [
                        if (reasoning.isNotEmpty) ...[
                          Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: SizedBox(
                              height: 60,
                              child: SingleChildScrollView(
                                child: MarkdownBody(
                                  data: 'Note: $reasoning',
                                  styleSheet: MarkdownStyleSheet(
                                    p: const TextStyle(fontStyle: FontStyle.italic, fontSize: 12),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const Divider(),
                        ],
                        // Toggle Show All
                        if (widget.originalSchedule.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8.0),
                            child: Row(
                              children: [
                                Text('${visibleItems.length} changes shown'),
                                const Spacer(),
                                const Text('Show All'),
                                Switch(value: _showAll, onChanged: (v) => setState(() => _showAll = v)),
                              ],
                            ),
                          ),
                        Expanded(
                          child: ListView.builder(
                            itemCount: _items.length + 1, // +1 for Add Button
                            itemBuilder: (ctx, i) {
                              if (i == _items.length) {
                                return TextButton.icon(
                                  onPressed: _addItem, 
                                  icon: const Icon(Icons.add),
                                  label: const Text('Add Slot'),
                                );
                              }
                              
                              final item = _items[i];
                              
                              // Check visibility locally to maintain index integrity for removal?
                              // Actually for ListView.builder we usually want exact indices.
                              // So better to filter the list and use that index?
                              // But removing item requires original index.
                              // Let's iterate original list but return SizedBox.shrink for hidden items if we simply hide them
                              // OR use the filtered list for rendering.
                              // Using logic:
                              final isVisible = _showAll || (item.originalActivity == null || item.originalActivity != item.activityCtrl.text);
                              if (!isVisible) return const SizedBox.shrink();

                              return Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                child: Row(
                                  children: [
                                    // Time
                                    SizedBox(
                                      width: 80,
                                      child: TextField(
                                        controller: item.timeCtrl,
                                        decoration: const InputDecoration(
                                          hintText: 'Time',
                                          isDense: true,
                                          contentPadding: EdgeInsets.all(8),
                                          border: OutlineInputBorder(),
                                        ),
                                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    // Activity
                                    Expanded(
                                      child: TextField(
                                        controller: item.activityCtrl,
                                        decoration: InputDecoration(
                                          hintText: 'Activity',
                                          isDense: true,
                                          contentPadding: const EdgeInsets.all(8),
                                          border: const OutlineInputBorder(),
                                          suffixIcon: Builder(
                                            builder: (context) {
                                              final val = item.activityCtrl.text;
                                              if (widget.taskActivities != null && widget.taskActivities!.containsKey(val)) {
                                                 return Padding(
                                                   padding: const EdgeInsets.only(right: 8.0),
                                                   child: Chip(
                                                     label: Text(widget.taskActivities![val]!, style: const TextStyle(fontSize: 10)),
                                                     visualDensity: VisualDensity.compact,
                                                     materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                                   ),
                                                 );
                                              }
                                              return const SizedBox.shrink();
                                            }
                                          ),
                                        ),
                                        style: const TextStyle(fontSize: 13),
                                        onChanged: (_) => setState(() {}),
                                      ),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.close, color: Colors.grey, size: 20),
                                      onPressed: () => _removeItem(i), // Removing by original index is correct here? Yes loop is over _items
                                      tooltip: 'Remove',
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                    // New Activities Tab
                    newActs.isEmpty
                        ? const Center(child: Text('No new activities suggested.'))
                        : Column(
                            children: [
                              const Padding(
                                padding: EdgeInsets.all(8.0),
                                child: Text(
                                  'Uncheck to keep as one-off (won\'t be saved to your list).',
                                  style: TextStyle(fontSize: 12, color: Colors.grey),
                                ),
                              ),
                              Expanded(
                                child: ListView(
                                  children: newActs.map((act) => CheckboxListTile(
                                    title: Text(act),
                                    value: selectedNewActs.contains(act),
                                    onChanged: (val) {
                                      setState(() {
                                        if (val == true) selectedNewActs.add(act);
                                        else selectedNewActs.remove(act);
                                      });
                                    },
                                  )).toList(),
                                ),
                              ),
                            ],
                          ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        // Refinement Input
        SizedBox(
          width: double.maxFinite,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                     decoration: const InputDecoration(
                       hintText: 'Refine (e.g. "Move gym to 5pm")', 
                       border: OutlineInputBorder(),
                       contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                     ),
                     onSubmitted: (val) => _refinePlan(val),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.send),
                  onPressed: null, // Basic text field usage handled by onSubmitted for now
                  tooltip: 'Type and press Enter to refine',
                ),
              ],
            ),
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: () async {
                // Reconstruct Map
                final Map<String, String> finalSchedule = {};
                for (var item in _items) {
                    if (item.timeCtrl.text.isNotEmpty && item.activityCtrl.text.isNotEmpty) {
                        finalSchedule[item.timeCtrl.text] = item.activityCtrl.text;
                    }
                }
                
                // Show saving indicator
            showDialog(
                context: context, 
                barrierDismissible: false,
                builder: (ctx) => const Center(child: CircularProgressIndicator())
            );

            await widget.onApply(finalSchedule, selectedNewActs.toList());
            
            if (context.mounted) {
              Navigator.pop(context); // Pop loading
              Navigator.pop(context); // Pop Dialog
            }
          },
          child: const Text('Apply Plan'),
        ),
            const SizedBox(width: 16),
          ],
        ),
      ],
    );
  }

  Future<void> _refinePlan(String request) async {
    if (request.trim().isEmpty) return;
    
    // Show loading
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final aiService = AIService();
      // Reconstruct schedule for context
      final Map<String, String> currentSchedule = {};
      for (var item in _items) {
          if (item.timeCtrl.text.isNotEmpty) {
              currentSchedule[item.timeCtrl.text] = item.activityCtrl.text;
          }
      }

      final currentJson = '{"schedule": ${currentSchedule.toString()}, "newActivities": ${newActs.toString()}}';
      final existing = {...currentSchedule.values, ...newActs}.toList();

      final jsonStr = await aiService.refinePlanJSON(
        currentJson: currentJson,
        userRequest: request,
        existingActivities: existing,
      );
      
      Navigator.pop(context); // close loading
      
      final Map<String, dynamic> data = jsonDecode(jsonStr);
      final newSchedule = Map<String, String>.from(data['schedule'] ?? {});
      final newNewActs = List<String>.from(data['newActivities'] ?? []);
      final newReasoning = data['reasoning'] ?? '';

      setState(() {
        // Dispose old items
        for (var i in _items) { i.dispose(); }
        // Create new items
        // RETAIN ORIGINAL INFO?
        // If refined, it's basically a new plan, so diffing against original probably still makes sense?
        // Or should we reset original?
        // Let's keep original to show what changed from start.
        _items = newSchedule.entries.map((e) {
             final original = widget.originalSchedule[e.key];
             return _ScheduleItem(e.key, e.value, originalActivity: original);
        }).toList();
        
        newActs = newNewActs;
        reasoning = newReasoning;
        
        final Set<String> updatedSelection = {};
        for (final act in newNewActs) {
             if (selectedNewActs.contains(act) || !existing.contains(act)) {
               updatedSelection.add(act);
             }
        }
        selectedNewActs = updatedSelection;
      });
      
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Plan refined.')));

    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // close loading
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error refining: $e')));
      }
    }
  }
}

class AIMultiDayReviewDialog extends StatefulWidget {
  final Map<DateTime, Map<String, dynamic>> dailyResults;
  final Future<void> Function(Map<DateTime, Map<String, String>> finalSchedules) onApply;
  final Map<String, String>? taskActivities;

  const AIMultiDayReviewDialog({
    super.key,
    required this.dailyResults,
    required this.onApply,
    this.taskActivities,
  });

  static Future<void> show(
    BuildContext context, 
    Map<DateTime, Map<String, dynamic>> dailyResults, 
    Future<void> Function(Map<DateTime, Map<String, String>>) onApply,
    {Map<String, String>? taskActivities}
  ) {
    return showDialog(
      context: context,
      builder: (ctx) => AIMultiDayReviewDialog(dailyResults: dailyResults, onApply: onApply, taskActivities: taskActivities),
    );
  }

  @override
  State<AIMultiDayReviewDialog> createState() => _AIMultiDayReviewDialogState();
}
// ... (State class logic for building UI unchanged) ...

// But I need to update the build method's onPressed action.
// Since replace_file_content replaces a chunk, I need to include the build method actions or target specifically.
// I'll replace the class definition and the actions part.

// Actually I can just target the class definition and confirm signature change.
// And target the onPressed logic separately?
// Let's do huge replacement of the class to be safe and clean.


class _AIMultiDayReviewDialogState extends State<AIMultiDayReviewDialog> with TickerProviderStateMixin {
  late Map<DateTime, List<_ScheduleItem>> _editableSchedules;
  late TabController _tabController;
  late List<DateTime> _sortedDates;

  @override
  void initState() {
    super.initState();
    _sortedDates = widget.dailyResults.keys.toList()..sort();
    
    // Initialize editable schedules
    _editableSchedules = {};
    for (var date in _sortedDates) {
        final result = widget.dailyResults[date]!;
        final scheduleMap = Map<String, String>.from(result['schedule'] ?? {});
        
        _editableSchedules[date] = scheduleMap.entries
            .map((e) => _ScheduleItem(e.key, e.value))
            .toList();
    }

    _tabController = TabController(length: _sortedDates.length, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    for (var list in _editableSchedules.values) {
        for (var item in list) {
            item.dispose();
        }
    }
    super.dispose();
  }

  void _addItem(DateTime date) {
      if (!_editableSchedules.containsKey(date)) return;
      setState(() {
          _editableSchedules[date]!.add(_ScheduleItem("", ""));
      });
  }

  void _removeItem(DateTime date, int index) {
      if (!_editableSchedules.containsKey(date)) return;
      setState(() {
          _editableSchedules[date]![index].dispose();
          _editableSchedules[date]!.removeAt(index);
      });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Batch Schedule Review'),
      content: SizedBox(
        width: double.maxFinite,
        height: 500,
        child: Column(
          children: [
            TabBar(
              controller: _tabController,
              isScrollable: true,
              labelColor: Colors.blue,
              tabs: _sortedDates.map((d) => Tab(text: DateFormat('E, MMM d').format(d))).toList(),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: _sortedDates.map((date) {
                    final items = _editableSchedules[date] ?? [];
                    final result = widget.dailyResults[date]!;
                    final reasoning = result['reasoning'] ?? '';

                    return Column(
                        children: [
                            if (reasoning.isNotEmpty) ...[
                                Container(
                                    padding: const EdgeInsets.all(8),
                                    color: Colors.grey[100],
                                    width: double.infinity,
                                    child: ConstrainedBox(
                                        constraints: const BoxConstraints(maxHeight: 60),
                                        child: SingleChildScrollView(
                                            child: MarkdownBody(
                                                data: reasoning, 
                                                styleSheet: MarkdownStyleSheet(
                                                    p: const TextStyle(fontSize: 12),
                                                ),
                                            ),
                                        ),
                                    ),
                                ),
                                const Divider(),
                            ],
                            Expanded(
                                child: ListView.builder(
                                    itemCount: items.length + 1,
                                    itemBuilder: (ctx, i) {
                                        if (i == items.length) {
                                            return TextButton.icon(
                                                onPressed: () => _addItem(date),
                                                icon: const Icon(Icons.add),
                                                label: const Text('Add Slot'),
                                            );
                                        }

                                        final item = items[i];
                                        return Padding(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                            child: Row(
                                                children: [
                                                    // Time
                                                    SizedBox(
                                                        width: 80,
                                                        child: TextField(
                                                            controller: item.timeCtrl,
                                                            decoration: const InputDecoration(
                                                                hintText: 'Time',
                                                                isDense: true,
                                                                contentPadding: EdgeInsets.all(8),
                                                                border: OutlineInputBorder(),
                                                            ),
                                                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                                                        ),
                                                    ),
                                                    const SizedBox(width: 8),
                                                    // Activity
                                                    Expanded(
                                                        child: TextField(
                                                            controller: item.activityCtrl,
                                                            decoration: InputDecoration(
                                                                hintText: 'Activity',
                                                                isDense: true,
                                                                contentPadding: const EdgeInsets.all(8),
                                                                border: const OutlineInputBorder(),
                                                                suffixIcon: Builder(
                                                                  builder: (context) {
                                                                    final val = item.activityCtrl.text;
                                                                    if (widget.taskActivities != null && widget.taskActivities!.containsKey(val)) {
                                                                       return Padding(
                                                                         padding: const EdgeInsets.only(right: 8.0),
                                                                         child: Chip(
                                                                           label: Text(widget.taskActivities![val]!, style: const TextStyle(fontSize: 10)),
                                                                           visualDensity: VisualDensity.compact,
                                                                           materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                                                         ),
                                                                       );
                                                                    }
                                                                    return const SizedBox.shrink();
                                                                  }
                                                                ),
                                                            ),
                                                            style: const TextStyle(fontSize: 13),
                                                            onChanged: (_) => setState(() {}),
                                                        ),
                                                    ),
                                                    IconButton(
                                                        icon: const Icon(Icons.close, color: Colors.grey, size: 20),
                                                        onPressed: () => _removeItem(date, i),
                                                        tooltip: 'Remove',
                                                    ),
                                                ],
                                            ),
                                        );
                                    },
                                ),
                            ),
                        ],
                    );
                }).toList(),
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
        FilledButton(
          onPressed: () async {
            // Reconstruct all schedules
            final Map<DateTime, Map<String, String>> finalSchedules = {};
            
            for (var date in _sortedDates) {
                final Map<String, String> schedule = {};
                final items = _editableSchedules[date] ?? [];
                
                for (var item in items) {
                     if (item.timeCtrl.text.isNotEmpty && item.activityCtrl.text.isNotEmpty) {
                         schedule[item.timeCtrl.text] = item.activityCtrl.text;
                     }
                }
                
                if (schedule.isNotEmpty) {
                    finalSchedules[date] = schedule;
                }
            }

            // Show saving indicator?
            showDialog(
                context: context, 
                barrierDismissible: false,
                builder: (ctx) => const Center(child: CircularProgressIndicator())
            );

            await widget.onApply(finalSchedules);
            
            if (context.mounted) {
                Navigator.pop(context); // Pop loading
                Navigator.pop(context); // Pop Review Dialog
            }
          },
          child: const Text('Apply All'),
        ),
      ],
    );
  }
}
