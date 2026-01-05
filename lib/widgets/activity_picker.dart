import 'package:flutter/material.dart';
import '../utils/activities.dart';

/// Shows a bottom-sheet picker that lets the user select an activity from [allActivities].
///
/// [recent] will be rendered as chips at the top for one-tap selection.
/// Returns the picked activity or `null` if the sheet was dismissed.
Future<String?> showActivityPicker({
  required BuildContext context,
  required List<String> allActivities,
  required List<String> recent,
}) {
  final List<String> acts = List<String>.from(allActivities);
  if (!acts.contains('__custom')) acts.add('__custom');

  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) {
      return _ActivityPickerBody(
        allActivities: acts,
        recent: recent,
      );
    },
  );
}

class _ActivityPickerBody extends StatefulWidget {
  final List<String> allActivities;
  final List<String> recent;

  const _ActivityPickerBody({
    required this.allActivities,
    required this.recent,
  });

  @override
  State<_ActivityPickerBody> createState() => _ActivityPickerBodyState();
}

class _ActivityPickerBodyState extends State<_ActivityPickerBody> {
  late TextEditingController _searchCtrl;
  late List<String> _filtered;

  @override
  void initState() {
    super.initState();
    _searchCtrl = TextEditingController();
    _filtered = List.from(widget.allActivities);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _applyFilter(String query) {
    final q = query.toLowerCase();
    setState(() {
      _filtered = widget.allActivities
          .where((a) => a.toLowerCase().contains(q))
          .toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    final double height = MediaQuery.of(context).size.height * 0.6;
    return SafeArea(
      child: SizedBox(
        height: height,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.recent.isNotEmpty) ...[
                const Text('Recent', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: widget.recent
                      .map((a) => ActionChip(
                            label: Text(displayActivity(a)),
                            onPressed: () => Navigator.pop(context, a),
                          ))
                      .toList(),
                ),
                const SizedBox(height: 16),
              ],
              TextField(
                controller: _searchCtrl,
                autofocus: true,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Type to search…',
                  border: OutlineInputBorder(),
                ),
                onChanged: _applyFilter,
              ),
              const SizedBox(height: 16),
              Expanded(
                child: _searchCtrl.text.isNotEmpty
                    ? _filtered.isEmpty
                        ? const Center(child: Text('No match'))
                        : ListView.builder(
                            itemCount: _filtered.length,
                            itemBuilder: (ctx, i) {
                              final act = _filtered[i];
                              final label = act == '__custom' ? 'Custom…' : displayActivity(act);
                              return ListTile(
                                title: Text(label),
                                onTap: () => Navigator.pop(context, act),
                              );
                            },
                          )
                    : GridView.builder(
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          childAspectRatio: 1.2,
                          crossAxisSpacing: 10,
                          mainAxisSpacing: 10,
                        ),
                        itemCount: _filtered.length,
                        itemBuilder: (ctx, i) {
                          final act = _filtered[i];
                          if (act == '__custom') {
                            return InkWell(
                              onTap: () => Navigator.pop(context, act),
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                decoration: BoxDecoration(
                                  border: Border.all(color: Theme.of(context).colorScheme.outline),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.add, size: 32, color: Theme.of(context).colorScheme.primary),
                                    const SizedBox(height: 4),
                                    const Text('Custom', style: TextStyle(fontWeight: FontWeight.w500)),
                                  ],
                                ),
                              ),
                            );
                          }

                          // Split emoji and name for nicer layout
                          final full = displayActivity(act);
                          // displayActivity returns "Emoji Name" or just "Name".
                          // Let's try to parse if possible, else just show full center.
                          return Card(
                            elevation: 0,
                            color: Theme.of(context).colorScheme.secondaryContainer.withOpacity(0.3),
                            shape: RoundedRectangleBorder(
                              side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            margin: EdgeInsets.zero,
                            child: InkWell(
                              onTap: () => Navigator.pop(context, act),
                              borderRadius: BorderRadius.circular(12),
                              child: Center(
                                child: Text(
                                  full,
                                  textAlign: TextAlign.center,
                                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
} 