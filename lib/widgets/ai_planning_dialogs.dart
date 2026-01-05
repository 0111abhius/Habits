import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../utils/ai_service.dart';

class AIGoalDialog extends StatelessWidget {
  final String title;
  final String promptLabel;
  final TextEditingController _controller = TextEditingController();

  AIGoalDialog({
    super.key,
    required this.title,
    this.promptLabel = 'What is your main goal?',
  });

  static Future<String?> show(BuildContext context, {required String title, String? promptLabel}) {
    return showDialog<String>(
      context: context,
      builder: (ctx) => AIGoalDialog(title: title, promptLabel: promptLabel ?? 'What is your main goal?'),
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
  final Function(Map<String, String> schedule, List<String> newActivities) onApply;

  const AIPlanReviewDialog({
    super.key,
    required this.data,
    required this.onApply,
  });

  static Future<void> show(BuildContext context, Map<String, dynamic> data, Function(Map<String, String>, List<String>) onApply) {
    return showDialog(
      context: context,
      builder: (ctx) => AIPlanReviewDialog(data: data, onApply: onApply),
    );
  }

  @override
  State<AIPlanReviewDialog> createState() => _AIPlanReviewDialogState();
}

class _AIPlanReviewDialogState extends State<AIPlanReviewDialog> {
  late Map<String, String> schedule;
  late List<String> newActs;
  late String reasoning;
  late Set<String> selectedNewActs;

  @override
  void initState() {
    super.initState();
    schedule = Map<String, String>.from(widget.data['schedule'] ?? {});
    newActs = List<String>.from(widget.data['newActivities'] ?? []);
    reasoning = widget.data['reasoning'] ?? '';
    selectedNewActs = Set.from(newActs);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('AI Review'),
      content: SizedBox(
        width: double.maxFinite,
        height: 400,
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
                    SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (reasoning.isNotEmpty) ...[
                            Padding(
                              padding: const EdgeInsets.all(8.0),
                              child: MarkdownBody(
                                data: 'Note: $reasoning',
                                styleSheet: MarkdownStyleSheet(
                                  p: const TextStyle(fontStyle: FontStyle.italic),
                                ),
                              ),
                            ),
                            const Divider(),
                          ],
                          ...schedule.entries.map((e) => ListTile(
                            dense: true,
                            title: Text(e.key),
                            subtitle: Text(e.value),
                          )),
                        ],
                      ),
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
                  onPressed: null, // Basic text field usage handled by onSubmitted for now, or users hit enter.
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
              onPressed: () {
                Navigator.pop(context);
                widget.onApply(schedule, selectedNewActs.toList());
              },
              child: const Text('Apply & Save'),
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
      // Reconstruct JSON from current state
      final currentJson = '{"schedule": ${schedule.toString()}, "newActivities": ${newActs.toString()}}';
      
      // We need existing activities list. 
      // Since it's not passed extensively, we can pass it in constructor or just utilize 
      // the known set from the previous state (newActs + schedule values).
      // Ideally, the parent widget passed everything. 
      // For now, let's just pass the activities we know of (from schedule + newActs).
      final existing = {...schedule.values, ...newActs}.toList();

      final jsonStr = await aiService.refinePlanJSON(
        currentJson: currentJson,
        userRequest: request,
        existingActivities: existing,
      );
      
      // Parse result
      // We need to import dart:convert if we use jsonDecode, but our AIService returns specific format.
      // But typically we need to create a map from the string.
      // Let's assume we can parse the string roughly or use a simple regex/helper, 
      // OR we update this file to import 'dart:convert'.
      // I'll add the import in another step or assume it exists/add it now if I can.
      
      // ... Actually, I can't easily parse JSON without dart:convert.
      // I'll update the file imports first in a separate step to be safe, or just do strictly string manipulation?
      // No, JSON parsing is better. I'll need to trigger an import update.
      // But wait, I can use a quick helper to "reload" this dialog with new data?
      // The dialog state holds the data.
      
      // Let's defer strict parsing logic to a helper or just do `Navigator.pop` (loading) -> verify -> setState.
      
      Navigator.pop(context); // close loading
      
      final Map<String, dynamic> data = jsonDecode(jsonStr);
      final newSchedule = Map<String, String>.from(data['schedule'] ?? {});
      final newNewActs = List<String>.from(data['newActivities'] ?? []);
      final newReasoning = data['reasoning'] ?? '';

      setState(() {
        schedule = newSchedule;
        newActs = newNewActs;
        reasoning = newReasoning;
        // Reset or merge selection? 
        // Logic: if an activity was previously selected and still exists in new suggestions, keep it selected.
        // If it's new, default to checked? Or unchecked? Let's default to checked as usual.
        final Set<String> updatedSelection = {};
        for (final act in newNewActs) {
             // If we already selected it, keep it. If it's brand new, select it (default).
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
