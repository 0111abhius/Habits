import 'package:flutter/material.dart';

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
                              child: Text('Note: $reasoning', style: const TextStyle(fontStyle: FontStyle.italic)),
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
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            Navigator.pop(context);
            widget.onApply(schedule, selectedNewActs.toList());
          },
          child: const Text('Apply & Save'),
        ),
      ],
    );
  }
}
