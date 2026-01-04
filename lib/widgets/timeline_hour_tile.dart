import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'dart:async';
import '../models/timeline_entry.dart';
import '../utils/activities.dart';
import 'activity_picker.dart';

class TimelineHourTile extends StatefulWidget {
  final int hour;
  final TimelineEntry entry00;
  final TimelineEntry? entry30;
  final bool isSplit;
  final bool showRetro;
  final VoidCallback onToggleSplit;
  final Future<void> Function(TimelineEntry entry, String activity, String notes, {bool isPlan}) onUpdateEntry;
  // We pass these down to reuse the picker logic
  final List<String> availableActivities;
  final List<String> recentActivities;
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
    required this.showRetro,
    required this.onToggleSplit,
    required this.onUpdateEntry,
    required this.availableActivities,
    required this.recentActivities,
    required this.onPromptCustomActivity,
    required this.onUpdateRecentActivity,
    this.key00,
    this.key30,
  });

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

  Color _planBg(BuildContext context) => Color.alphaBlend(Colors.indigo.withOpacity(0.04), Theme.of(context).colorScheme.surface);
  Color _retroBg(BuildContext context) => Color.alphaBlend(Colors.orange.withOpacity(0.04), Theme.of(context).colorScheme.surface);

  String _displayLabel(String act) => displayActivity(act);

  @override
  Widget build(BuildContext context) {
    // Section Title
    String? sectionTitle;
    if (widget.hour == 6) sectionTitle = 'Morning';
    if (widget.hour == 12) sectionTitle = 'Afternoon';
    if (widget.hour == 18) sectionTitle = 'Evening';

    final bool isSleepRow = widget.entry00.activity == 'Sleep';

    final container = Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: isSleepRow ? Colors.blueGrey.withOpacity(0.04) : Theme.of(context).colorScheme.surfaceVariant,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))],
      ),
      child: Column(
            children: [
              ListTile(
                title: Text(DateFormat('h a').format(DateTime(2022,1,1,widget.hour)), style: Theme.of(context).textTheme.titleSmall),
                trailing: IconButton(
                  icon: Icon(widget.isSplit ? Icons.remove : Icons.call_split, color: Theme.of(context).colorScheme.primary),
                  onPressed: widget.onToggleSplit,
                ),
              ),
              Container(key: widget.key00, child: _buildSubBlock(widget.entry00, 0)),
              if (widget.entry30 != null) 
                Container(key: widget.key30, child: _buildSubBlock(widget.entry30!, 30)),
            ],
      ),
    );

    if (sectionTitle == null) {
      return container;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(sectionTitle,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
        ),
        container,
      ],
    );
  }

  Widget _buildSubBlock(TimelineEntry entry, int minute) {
    // Prepare available activities
    final available = [...widget.availableActivities];
    // Ensure current values are present
    if (entry.activity.isNotEmpty && !available.contains(entry.activity)) {
      available.add(entry.activity);
    }
    if (entry.planactivity.isNotEmpty && !available.contains(entry.planactivity)) {
      available.add(entry.planactivity);
    }

    final dropdownValue = (entry.activity.isNotEmpty && available.contains(entry.activity)) ? entry.activity : null;

    final planCtrl = _planControllers[minute]!;
    final retroCtrl = _retroControllers[minute]!;

    // Plan Column
    Widget planColumn = Expanded(
      child: Container(
        decoration: BoxDecoration(
          color: _planBg(context),
          borderRadius: widget.showRetro
              ? const BorderRadius.only(topLeft: Radius.circular(8), bottomLeft: Radius.circular(8))
              : BorderRadius.circular(8),
        ),
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            OutlinedButton(
              onPressed: () async {
                final picked = await showActivityPicker(
                  context: context,
                  allActivities: available,
                  recent: widget.recentActivities,
                );
                if (picked == null) return;
                if (picked == '__custom') {
                  final custom = await widget.onPromptCustomActivity();
                  if (custom != null && custom.isNotEmpty) {
                    widget.onUpdateRecentActivity(custom);
                    widget.onUpdateEntry(entry, custom, entry.planNotes, isPlan: true);
                  }
                } else {
                  widget.onUpdateRecentActivity(picked);
                  widget.onUpdateEntry(entry, picked, entry.planNotes, isPlan: true);
                }
              },
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
              ),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  entry.planactivity.isEmpty ? 'Plan' : _displayLabel(entry.planactivity),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            TextField(
              controller: planCtrl,
              maxLines: null,
              decoration: const InputDecoration(hintText: 'Notes', border: InputBorder.none),
              onChanged: (val) => _onNoteChanged(minute, val, entry, true),
            ),
          ],
        ),
      ),
    );

    // Retro Column
    Widget retroColumn = Container(
      decoration: BoxDecoration(
        color: _retroBg(context),
        borderRadius: const BorderRadius.only(topRight: Radius.circular(8), bottomRight: Radius.circular(8)),
      ),
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          OutlinedButton(
            onPressed: () async {
              final picked = await showActivityPicker(
                context: context,
                allActivities: available,
                recent: widget.recentActivities,
              );
              if (picked == null) return;
              if (picked == '__custom') {
                final custom = await widget.onPromptCustomActivity();
                if (custom != null && custom.isNotEmpty) {
                  widget.onUpdateRecentActivity(custom);
                  widget.onUpdateEntry(entry, custom, entry.notes, isPlan: false);
                }
              } else {
                widget.onUpdateRecentActivity(picked);
                widget.onUpdateEntry(entry, picked, entry.notes, isPlan: false);
              }
            },
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
            ),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                dropdownValue == null ? 'Retro' : _displayLabel(dropdownValue),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          TextField(
            controller: retroCtrl,
            maxLines: null,
            decoration: const InputDecoration(hintText: 'Notes', border: InputBorder.none),
            onChanged: (val) => _onNoteChanged(minute, val, entry, false),
          ),
        ],
      ),
    );

    // Combine
    final retroWithCopy = Stack(
      children: [
        retroColumn,
        if (entry.planNotes.isNotEmpty || entry.planactivity.isNotEmpty)
          Positioned(
            top: 4,
            right: 4,
            child: InkWell(
              onTap: () => widget.onUpdateEntry(entry, entry.planactivity, entry.planNotes, isPlan: false),
              child: Icon(Icons.copy_all, size: 16, color: Theme.of(context).colorScheme.primary),
            ),
          ),
      ],
    );

    Widget innerRow;
    if (!widget.showRetro) {
      innerRow = Row(children: [planColumn]);
    } else {
      innerRow = Row(
        children: [
          planColumn,
          const SizedBox(width: 4),
          Expanded(child: retroWithCopy),
        ],
      );
    }

    if (minute == 0) return innerRow;

    final String label = DateFormat('h:mm a').format(entry.startTime);
    final TextStyle labelStyle = Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ) ??
        const TextStyle(fontSize: 13, fontWeight: FontWeight.w600);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 16.0, top: 8, bottom: 6),
          child: Text(label, style: labelStyle),
        ),
        innerRow,
      ],
    );
  }
}
