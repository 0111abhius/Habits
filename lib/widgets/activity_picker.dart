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
                child: _filtered.isEmpty
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
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
} 