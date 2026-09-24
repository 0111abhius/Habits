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
    backgroundColor: Colors.transparent, // Important for DraggableScrollableSheet visual
    builder: (ctx) {
      return Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: DraggableScrollableSheet(
          initialChildSize: 0.6,
          minChildSize: 0.4,
          maxChildSize: 0.9,
          builder: (_, scrollController) => _ActivityPickerBody(
            allActivities: acts,
            recent: recent,
            scrollController: scrollController,
          ),
        ),
      );
    },
  );
}

class _ActivityPickerBody extends StatefulWidget {
  final List<String> allActivities;
  final List<String> recent;
  final ScrollController scrollController;

  const _ActivityPickerBody({
    required this.allActivities,
    required this.recent,
    required this.scrollController,
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
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 10, spreadRadius: 2)],
      ),
      child: Column(
        children: [
          // Drag Handle
          Center(
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.withOpacity(0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          
          // Search Bar (Sticky-ish)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 0),
            child: TextField(
              controller: _searchCtrl,
              autofocus: false, // Don't autofocus immediately to avoid jumping, let user tap if needed? Or true if that's preferred.
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: 'Search activity...',
                contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                filled: true,
                fillColor: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.3),
              ),
              onChanged: _applyFilter,
            ),
          ),
          const SizedBox(height: 12),

          Expanded(
            child: ListView(
              controller: widget.scrollController,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              children: [
                // Recents Section
                if (widget.recent.isNotEmpty && _searchCtrl.text.isEmpty) ...[
                  Text('Recent used', style: Theme.of(context).textTheme.labelLarge?.copyWith(color: Theme.of(context).colorScheme.primary)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: widget.recent.map((a) => _buildChip(context, a, isRecent: true)).toList(),
                  ),
                  const SizedBox(height: 24),
                ],

                // All Activities Section
                Text(
                   _searchCtrl.text.isEmpty ? 'All Activities' : 'Results', 
                   style: Theme.of(context).textTheme.labelLarge?.copyWith(color: Theme.of(context).colorScheme.primary)
                ),
                const SizedBox(height: 8),

                if (_filtered.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Center(child: Text('No matching activities')),
                  )
                else
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _filtered.map((a) => _buildChip(context, a)).toList(),
                  ),
                  
                const SizedBox(height: 40), // Bottom padding
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChip(BuildContext context, String activity, {bool isRecent = false}) {
    if (activity == '__custom') {
      return ActionChip(
        label: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.add, size: 16),
            SizedBox(width: 4),
            Text('Custom'),
          ],
        ),
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
        onPressed: () => Navigator.pop(context, activity),
      );
    }

    final fullLabel = displayActivity(activity);
    return ActionChip(
      label: Text(fullLabel),
      // Use different style for simple list?
      backgroundColor: isRecent
          ? Theme.of(context).colorScheme.tertiaryContainer.withOpacity(0.5)
          : Theme.of(context).colorScheme.secondaryContainer.withOpacity(0.3),
      side: BorderSide.none,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      onPressed: () => Navigator.pop(context, activity),
    );
  }
}