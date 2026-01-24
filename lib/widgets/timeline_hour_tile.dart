import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'dart:async';
import '../models/timeline_entry.dart';
import '../utils/activities.dart';
import 'activity_picker.dart';
import '../models/timeline_view_mode.dart';

class TimelineHourTile extends StatefulWidget {
  final int hour;
  final TimelineEntry entry00;
  final TimelineEntry? entry30;
  final bool isSplit;
  final TimelineViewMode viewMode;
  final VoidCallback onToggleSplit;
  final Future<void> Function(TimelineEntry entry, String activity, String notes, {bool isPlan}) onUpdateEntry;
  // We pass these down to reuse the picker logic
  final List<String> availableActivities;
  // History candidates (Yesterday/LastWeek same hour) not including general recents
  final List<String> historyActivities;
  // Live list of general recent activities
  final ValueNotifier<List<String>> recentActivitiesNotifier;
  final Future<String?> Function() onPromptCustomActivity;
  final Function(String) onUpdateRecentActivity;

  final GlobalKey? key00;
  final GlobalKey? key30;

  const TimelineHourTile({
    super.key,
    required this.hour,
    required this.entry00,
    this.entry30,
    required this.isSplit,
    required this.viewMode,
    required this.onToggleSplit,
    required this.onUpdateEntry,

    required this.availableActivities,
    required this.historyActivities,
    required this.recentActivitiesNotifier,
    required this.onPromptCustomActivity,
    required this.onUpdateRecentActivity,
    this.key00,
    this.key30,
    this.proposedActivity00,
    this.proposedActivity30,
    this.proposedReason00,
    this.proposedReason30,
    this.onAcceptProposal,
    this.onRejectProposal,
    this.proposedIsTask00 = false,
    this.proposedIsTask30 = false,
    this.proposedTaskTitle00,
    this.proposedTaskTitle30,
  });

  final String? proposedActivity00;
  final String? proposedActivity30;
  final String? proposedReason00;
  final String? proposedReason30;
  final bool proposedIsTask00;
  final bool proposedIsTask30;
  final String? proposedTaskTitle00;
  final String? proposedTaskTitle30;
  final Function(TimelineEntry, String, String?, String?)? onAcceptProposal;
  final Function(TimelineEntry)? onRejectProposal;

  @override
  State<TimelineHourTile> createState() => _TimelineHourTileState();
}

class _TimelineHourTileState extends State<TimelineHourTile> {
  // Controllers map: key '00' or '30' -> { 'retro': Ctrl, 'plan': Ctrl }
  final Map<int, TextEditingController> _retroControllers = {};
  final Map<int, TextEditingController> _planControllers = {};
  final Map<String, Timer> _debouncers = {};

  @override
  void initState() {
    super.initState();
    _initControllers(0, widget.entry00);
    if (widget.entry30 != null) {
      _initControllers(30, widget.entry30!);
    }
  }

  @override
  void didUpdateWidget(covariant TimelineHourTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncController(0, widget.entry00);
    if (widget.entry30 != null) {
      _syncController(30, widget.entry30!);
    }
  }

  @override
  void dispose() {
    for (var c in _retroControllers.values) c.dispose();
    for (var c in _planControllers.values) c.dispose();
    for (var t in _debouncers.values) t.cancel();
    super.dispose();
  }

  void _initControllers(int minute, TimelineEntry entry) {
    _retroControllers[minute] = TextEditingController(text: entry.notes);
    _planControllers[minute] = TextEditingController(text: entry.planNotes);
  }

  void _syncController(int minute, TimelineEntry entry) {
    // Ensure controllers exist
    if (!_retroControllers.containsKey(minute)) {
      _initControllers(minute, entry);
      return;
    }

    final retroCtrl = _retroControllers[minute]!;
    final planCtrl = _planControllers[minute]!;
    final debounceKeyRetro = '${minute}_retro';
    final debounceKeyPlan = '${minute}_plan';

    if (retroCtrl.text != entry.notes && !_debouncers.containsKey(debounceKeyRetro)) {
      retroCtrl.text = entry.notes;
      retroCtrl.selection = TextSelection.collapsed(offset: retroCtrl.text.length);
    }
    if (planCtrl.text != entry.planNotes && !_debouncers.containsKey(debounceKeyPlan)) {
      planCtrl.text = entry.planNotes;
      planCtrl.selection = TextSelection.collapsed(offset: planCtrl.text.length);
    }
  }

  void _onNoteChanged(int minute, String val, TimelineEntry entry, bool isPlan) {
    final key = '${minute}_${isPlan ? 'plan' : 'retro'}';
    _debouncers[key]?.cancel();
    _debouncers[key] = Timer(const Duration(milliseconds: 500), () {
      if (isPlan) {
        widget.onUpdateEntry(entry, entry.planactivity, val, isPlan: true);
      } else {
        widget.onUpdateEntry(entry, entry.activity, val, isPlan: false);
      }
      _debouncers.remove(key);
    });
  }


  String _displayLabel(String act) => displayActivity(act);

  Widget _buildGutter({required bool is30}) {
    // Determine time label
    String timeLabel;
    if (!is30) {
      // Top slot: "9 AM"
      timeLabel = DateFormat('h a').format(DateTime(2022, 1, 1, widget.hour));
    } else {
      // Bottom slot: "9:30"
      final h = widget.hour;
      final m = 30;
      timeLabel = DateFormat('h:mm').format(DateTime(2022, 1, 1, h, m));
    }

    // Determine button visibility
    // Show button in 30 slot if split (Merge)
    // Show button in 00 slot if NOT split (Split)
    final bool showButton = (is30 && widget.isSplit) || (!is30 && !widget.isSplit);

    return Container(
      width: 50,
      decoration: BoxDecoration(
        border: Border(right: BorderSide(color: Theme.of(context).colorScheme.outlineVariant.withOpacity(0.5))),
      ),
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 4.0),
            child: Text(
              timeLabel,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    fontSize: 10, // Smaller font as requested
              ),
            ),
          ),
          if (showButton)
            IconButton(
              icon: Icon(
                widget.isSplit ? Icons.remove : Icons.call_split,
                size: 16,
                color: Theme.of(context).colorScheme.outline,
              ),
              tooltip: widget.isSplit ? 'Merge' : 'Split',
              onPressed: widget.onToggleSplit,
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minHeight: 24, minWidth: 24),
            )
          else 
            const SizedBox(height: 24), // Maintain rough width/spacing if needed, or let spacer handle it
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Section Title


    final bool isSleepRow = widget.entry00.activity == 'Sleep';

    final container = Card(
      elevation: 2,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: isSleepRow ? Colors.blueGrey.withOpacity(0.05) : Theme.of(context).colorScheme.surface,
      surfaceTintColor: Theme.of(context).colorScheme.surfaceTint,
      child: Column(
        children: [
          // Slot 00
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildGutter(is30: false),
                Expanded(child: Container(key: widget.key00, child: _buildSubBlock(widget.entry00, 0))),
              ],
            ),
          ),
          
          // Slot 30 (if exists)
          if (widget.entry30 != null) ...[
             Divider(height: 1, thickness: 1, color: Theme.of(context).colorScheme.outlineVariant.withOpacity(0.5)),
             IntrinsicHeight(
               child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildGutter(is30: true),
                    Expanded(child: Container(key: widget.key30, child: _buildSubBlock(widget.entry30!, 30))),
                  ],
               ),
             ),
          ],
        ],
      ),
    );

    return container;
  }

  Widget _buildSubBlock(TimelineEntry entry, int minute) {
    // Check for proposal
    final String? proposal = minute == 0 ? widget.proposedActivity00 : widget.proposedActivity30;
    final String? reason = minute == 0 ? widget.proposedReason00 : widget.proposedReason30;
    final bool isTask = minute == 0 ? widget.proposedIsTask00 : widget.proposedIsTask30;
    final String? taskTitle = minute == 0 ? widget.proposedTaskTitle00 : widget.proposedTaskTitle30;

    // Show proposal if exists.
    // Case 1: Slot is empty -> Show "Ghost Tile"
    // Case 2: Slot is filled -> Show "Overwrite Proposal"
    // The previous logic was: if (widget.viewMode == TimelineViewMode.plan && proposal != null && proposal.isNotEmpty)
    
    if (widget.viewMode == TimelineViewMode.plan && proposal != null && proposal.isNotEmpty) {
       // Check if current is filled
       final currentAct = entry.planactivity;
       if (currentAct.isEmpty) {
          return _buildGhostTile(proposal, reason, entry, isOverlay: false, isTask: isTask, taskTitle: taskTitle);
       } else if (currentAct != proposal) {
          // Overwrite suggestion
          // We render the ghost tile ON TOP of the filled slot? Or replace it?
          // User asked for: "Show both filled value and AI suggestion value with reason"
          // Let's use a Stack or Column to show both?
          // Or a specialized GhostTile that shows "Current: X -> Proposed: Y"
          return _buildGhostTile(proposal, reason, entry, isOverlay: true, isTask: isTask, taskTitle: taskTitle);
       }
    }

    // Prepare available activities
    final available = [...widget.availableActivities];
    // Ensure current values are present
    if (entry.activity.isNotEmpty && !available.contains(entry.activity)) {
      available.add(entry.activity);
    }
    if (entry.planactivity.isNotEmpty && !available.contains(entry.planactivity)) {
      available.add(entry.planactivity);
    }

    final planCtrl = _planControllers[minute]!;
    final retroCtrl = _retroControllers[minute]!;

    Widget buildSlot({required bool isPlan, required TextEditingController ctrl}) {
      final currentAct = isPlan ? entry.planactivity : entry.activity;
      final isEmpty = currentAct.isEmpty;
      final bool isCompare = widget.viewMode == TimelineViewMode.compare;
      // In compare mode, we have very limited width (approx 50% - gutter - margins).
      // We drastically reduce items to prevent overflow.
      final int quickCount = isCompare 
          ? (MediaQuery.of(context).size.width < 600 ? 1 : 2) 
          : (MediaQuery.of(context).size.width < 400 ? 2 : 3);
      final double maxLabelWidth = isCompare ? 70.0 : 130.0;

      return Container(
        decoration: BoxDecoration(
          color: isPlan
              ? Colors.blue.withOpacity(0.05) // Plan: Blue
              : Colors.green.withOpacity(0.05), // Actual: Green (Matches Theme)
          border: Border.all(
            color: isPlan
                ? Colors.blue.withOpacity(0.2)
                : Colors.green.withOpacity(0.2),
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8), // Reduced horizontal padding
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isEmpty) ...[
              // Quick Picks Row
              ValueListenableBuilder<List<String>>(
                valueListenable: widget.recentActivitiesNotifier,
                builder: (context, recents, _) {
                  // Merge:
                  // 1. History (Yesterday/LastWeek)
                  // 2. Then fill remaining slots from Recents
                  final Set<String> candidates = {};
                  // history first
                  candidates.addAll(widget.historyActivities);
                  // then recents until we have enough
                  for (final r in recents) {
                    if (candidates.length >= 3) break;
                    if (!candidates.contains(r)) candidates.add(r);
                  }
                  
                  final suggestions = candidates.take(quickCount).toList();

                  return Row(
                    mainAxisSize: MainAxisSize.min,
                    children: suggestions.map((act) {
                      final emoji = kActivityEmoji[act];
                      // Determine max width based on screen size
                      final double screenWidth = MediaQuery.of(context).size.width;
                      final bool isWide = screenWidth > 600;
                      final double maxWidth = isWide ? 140 : 75;

                      return Padding(
                        key: ValueKey('suggestion_$act'),
                        padding: const EdgeInsets.only(right: 6, top: 2),
                        child: InkWell(
                          onTap: () {
                            widget.onUpdateRecentActivity(act);
                            widget.onUpdateEntry(entry, act, isPlan ? entry.planNotes : entry.notes, isPlan: isPlan);
                          },
                          borderRadius: BorderRadius.circular(12),
                          child: Tooltip(
                            message: act,
                            child: Container(
                              constraints: BoxConstraints(maxWidth: maxWidth),
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.surfaceContainerHigh,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                emoji != null ? '$emoji $act' : act,
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  );
                },
              ),
              
              Padding(
                padding: const EdgeInsets.only(right: 4, top: 2), // slightly tighter padding
                child: InkWell(
                  onTap: () async {
                    final picked = await showActivityPicker(
                      context: context,
                      allActivities: available,
                      recent: widget.recentActivitiesNotifier.value,
                    );
                    if (picked != null) {
                       if (picked == '__custom') {
                          final custom = await widget.onPromptCustomActivity();
                          if (custom != null && custom.isNotEmpty) {
                             widget.onUpdateRecentActivity(custom);
                             widget.onUpdateEntry(entry, custom, isPlan ? entry.planNotes : entry.notes, isPlan: isPlan);
                          }
                       } else {
                          widget.onUpdateRecentActivity(picked);
                          widget.onUpdateEntry(entry, picked, isPlan ? entry.planNotes : entry.notes, isPlan: isPlan);
                       }
                    }
                  },
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    width: isCompare ? 32 : 36, // Smaller in compare
                    height: isCompare ? 32 : 36,
                    decoration: BoxDecoration(
                       border: Border.all(color: Theme.of(context).colorScheme.outline.withOpacity(0.5)),
                       shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.add, size: isCompare ? 16 : 18),
                  ),
                ),
              ),
              
              Padding(
                padding: const EdgeInsets.only(right: 4.0, top: 6, bottom: 6),
                child: VerticalDivider(width: 1, thickness: 1, color: Theme.of(context).colorScheme.outlineVariant),
              ),
            ] else 
              Padding(
                padding: const EdgeInsets.only(top: 4, right: 4),
                child: OutlinedButton(
                  onPressed: () async {
                    final picked = await showActivityPicker(
                      context: context,
                      allActivities: available,
                      recent: widget.recentActivitiesNotifier.value,
                    );
                    if (picked == null) return;
                    if (picked == '__custom') {
                      final custom = await widget.onPromptCustomActivity();
                      if (custom != null && custom.isNotEmpty) {
                        widget.onUpdateRecentActivity(custom);
                        widget.onUpdateEntry(entry, custom, isPlan ? entry.planNotes : entry.notes, isPlan: isPlan);
                      }
                    } else {
                      widget.onUpdateRecentActivity(picked);
                      widget.onUpdateEntry(entry, picked, isPlan ? entry.planNotes : entry.notes, isPlan: isPlan);
                    }
                  },
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0), // Compact padding
                    visualDensity: VisualDensity.compact,
                  ),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: maxLabelWidth),
                    child: Text(
                      _displayLabel(currentAct),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ),
            
            Expanded(
              child: TextField(
                controller: ctrl,
                maxLines: null,
                style: isCompare ? const TextStyle(fontSize: 13) : null, // Smaller text in compare
                decoration: InputDecoration(
                  hintText: 'Notes', 
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(vertical: isCompare ? 11 : 10),
                ),
                onChanged: (val) => _onNoteChanged(minute, val, entry, isPlan),
              ),
            ),
          ],
        ),
      );
    }

    switch (widget.viewMode) {
      case TimelineViewMode.plan:
        return buildSlot(isPlan: true, ctrl: planCtrl);
      case TimelineViewMode.actual:
        return buildSlot(isPlan: false, ctrl: retroCtrl);
      case TimelineViewMode.compare:
        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: buildSlot(isPlan: true, ctrl: planCtrl)),
              
              // INLINE COPY BUTTON
              Container(
                 width: 32,
                 alignment: Alignment.center,
                 decoration: BoxDecoration(
                   color: Theme.of(context).colorScheme.surfaceContainerLow,
                   border: Border.symmetric(horizontal: BorderSide(color: Theme.of(context).colorScheme.outlineVariant.withOpacity(0.3))),
                 ),
                 child: IconButton(
                    icon: Icon(Icons.arrow_forward, size: 16, color: Theme.of(context).colorScheme.primary),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                    tooltip: 'Copy Plan to Actual',
                    onPressed: () => widget.onUpdateEntry(entry, entry.planactivity, entry.planNotes, isPlan: false),
                 ),
              ),

              Expanded(child: buildSlot(isPlan: false, ctrl: retroCtrl)),
            ],
          ),
        );
    }
  }

  Widget _buildGhostTile(String activity, String? reason, TimelineEntry entry, {required bool isOverlay, required bool isTask, String? taskTitle}) {
     final currentAct = entry.planactivity;
     final displayActivity = _displayLabel(activity);
     
     // Deduplicate reason if it matches taskTitle
     final showReason = reason != null && reason.isNotEmpty && reason != taskTitle;

     return Container(
        decoration: BoxDecoration(
          color: isOverlay ? Colors.orange.withValues(alpha: 0.1) : Colors.deepPurple.withValues(alpha: 0.08),
          border: Border.all(
            color: isOverlay ? Colors.orange.withValues(alpha: 0.5) : Colors.deepPurple.withValues(alpha: 0.5),
            style: BorderStyle.none, 
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
             Expanded(
               child: Row(
                 crossAxisAlignment: CrossAxisAlignment.start,
                 children: [
                   Padding(
                     padding: const EdgeInsets.only(top: 2),
                     child: Icon(
                       isTask ? Icons.task_alt : Icons.auto_awesome, 
                       size: 18, 
                       color: isOverlay ? Colors.orange[800] : (isTask ? Colors.blue[800] : Colors.deepPurple)
                     ),
                   ),
                   const SizedBox(width: 8),
                   Expanded(
                     child: Column(
                       crossAxisAlignment: CrossAxisAlignment.start,
                       children: [
                         // Row 1: Activity Name + Task Title
                         RichText(
                           text: TextSpan(
                             style: DefaultTextStyle.of(context).style,
                             children: [
                               if (isOverlay) ...[
                                 TextSpan(
                                   text: '$currentAct ', 
                                   style: const TextStyle(
                                     decoration: TextDecoration.lineThrough, 
                                     color: Colors.grey,
                                     fontSize: 13,
                                   )
                                 ),
                                 const TextSpan(
                                    text: '➔ ',
                                    style: TextStyle(color: Colors.grey, fontSize: 13)
                                 ),
                               ],
                               
                               // Activity Name
                               TextSpan(
                                 text: displayActivity,
                                 style: TextStyle(
                                   color: isOverlay ? Colors.orange[900] : Colors.deepPurple,
                                   fontWeight: FontWeight.w800, // Extra Bold
                                   fontSize: 14,
                                   letterSpacing: 0.5,
                                 ),
                               ),

                               // Task Title
                               if (isTask && taskTitle != null && taskTitle.isNotEmpty)
                                 TextSpan(
                                   text: '  $taskTitle',
                                   style: const TextStyle(
                                     color: Colors.black87,
                                     fontWeight: FontWeight.w400, // Normal weight
                                     fontSize: 14,
                                     fontFamily: 'Roboto', // Default but explicit for clarity
                                   ),
                                 ),
                             ],
                           ),
                           overflow: TextOverflow.ellipsis,
                           maxLines: 1,
                         ),
                         
                         // Row 2: AI Reason
                         if (showReason)
                           Padding(
                             padding: const EdgeInsets.only(top: 2),
                             child: Text(
                               reason!,
                               style: TextStyle(
                                 fontSize: 12,
                                 fontStyle: FontStyle.italic,
                                 color: Colors.grey[700],
                                 height: 1.2,
                               ),
                               maxLines: 2,
                               overflow: TextOverflow.ellipsis,
                             ),
                           ),
                       ],
                     ),
                   ),
                 ],
               ),
             ),
             
             // Actions
             Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Reject Button
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: () => widget.onRejectProposal?.call(entry),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        child: Icon(Icons.close, size: 20, color: Colors.red[300]),
                      ),
                    ),
                  ),
                  
                  const SizedBox(width: 8), 
                  
                  // Accept Button
                  Material(
                    color: Colors.green.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: () => widget.onAcceptProposal?.call(entry, activity, reason, taskTitle),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.green.withValues(alpha: 0.5)),
                        ),
                        child: Icon(Icons.check, size: 20, color: Colors.green[900]),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                ],
             ),
          ],
        ),
     );
  }
}
