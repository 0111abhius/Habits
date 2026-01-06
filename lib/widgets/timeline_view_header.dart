import 'package:flutter/material.dart';
import '../models/timeline_view_mode.dart';

class TimelineViewHeaderDelegate extends SliverPersistentHeaderDelegate {
  final TimelineViewMode currentMode;
  final ValueChanged<TimelineViewMode> onModeChanged;
  final VoidCallback onJumpToNow;

  const TimelineViewHeaderDelegate({
    required this.currentMode,
    required this.onModeChanged,
    required this.onJumpToNow,
  });

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
      child: Stack(
        children: [
          Center(
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
          Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            child: IconButton(
              onPressed: onJumpToNow,
              icon: const Icon(Icons.access_time),
              tooltip: 'Jump to Now',
            ),
          ),
        ],
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
