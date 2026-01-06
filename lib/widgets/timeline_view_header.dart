import 'package:flutter/material.dart';
import '../models/timeline_view_mode.dart';

class TimelineViewHeaderDelegate extends SliverPersistentHeaderDelegate {
  final TimelineViewMode currentMode;
  final ValueChanged<TimelineViewMode> onModeChanged;

  const TimelineViewHeaderDelegate({
    required this.currentMode,
    required this.onModeChanged,
  });

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
      child: Center(
        child: SegmentedButton<TimelineViewMode>(
          segments: const [
            ButtonSegment<TimelineViewMode>(
              value: TimelineViewMode.plan,
              label: Text('Plan'),
              icon: Icon(Icons.edit_calendar),
            ),
            ButtonSegment<TimelineViewMode>(
              value: TimelineViewMode.actual,
              label: Text('Actual'), 
              icon: Icon(Icons.history),
            ),
            ButtonSegment<TimelineViewMode>(
              value: TimelineViewMode.compare,
              label: Text('Compare'),
              icon: Icon(Icons.compare_arrows),
            ),
          ],
          selected: <TimelineViewMode>{currentMode},
          onSelectionChanged: (Set<TimelineViewMode> newSelection) {
            onModeChanged(newSelection.first);
          },
          style: ButtonStyle(
            visualDensity: VisualDensity.compact,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
      ),
    );
  }

  @override
  double get maxExtent => 60.0; 

  @override
  double get minExtent => 60.0;

  @override
  bool shouldRebuild(covariant TimelineViewHeaderDelegate oldDelegate) {
    return oldDelegate.currentMode != currentMode;
  }
}
