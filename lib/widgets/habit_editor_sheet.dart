import 'package:flutter/material.dart';

import '../models/habit.dart';

/// Result of the habit editor; `null` when cancelled.
class HabitEditorResult {
  final String name;
  final HabitType type;
  final HabitFrequency frequency;
  final int weeklyTarget;
  final int targetCount;
  final String? reminderTime;

  const HabitEditorResult({
    required this.name,
    required this.type,
    required this.frequency,
    required this.weeklyTarget,
    required this.targetCount,
    this.reminderTime,
  });
}

/// Bottom sheet used for both creating and editing habits.
Future<HabitEditorResult?> showHabitEditor(BuildContext context, {Habit? existing}) {
  return showModalBottomSheet<HabitEditorResult>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (ctx) => _HabitEditorSheet(existing: existing),
  );
}

class _HabitEditorSheet extends StatefulWidget {
  final Habit? existing;
  const _HabitEditorSheet({this.existing});

  @override
  State<_HabitEditorSheet> createState() => _HabitEditorSheetState();
}

class _HabitEditorSheetState extends State<_HabitEditorSheet> {
  late final TextEditingController _name;
  late HabitType _type;
  late HabitFrequency _frequency;
  late int _weeklyTarget;
  late int _targetCount;
  TimeOfDay? _reminder;

  static const _suggestions = [
    'Exercise',
    'Meditate',
    'Read',
    'Drink water',
    'Sleep by 11',
    'No sugar',
    'Journal',
    'Walk',
  ];

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?.name ?? '');
    _type = e?.type ?? HabitType.binary;
    _frequency = e?.frequency ?? HabitFrequency.daily;
    _weeklyTarget = e?.weeklyTarget ?? 3;
    _targetCount = e?.targetCount ?? 1;
    if (e?.reminderTime != null) {
      final parts = e!.reminderTime!.split(':');
      if (parts.length == 2) {
        _reminder = TimeOfDay(hour: int.tryParse(parts[0]) ?? 9, minute: int.tryParse(parts[1]) ?? 0);
      }
    }
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    Navigator.pop(
      context,
      HabitEditorResult(
        name: name,
        type: _type,
        frequency: _frequency,
        weeklyTarget: _weeklyTarget,
        targetCount: _type == HabitType.counter ? _targetCount : 1,
        reminderTime: _reminder == null
            ? null
            : '${_reminder!.hour.toString().padLeft(2, '0')}:${_reminder!.minute.toString().padLeft(2, '0')}',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isEditing = widget.existing != null;
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(isEditing ? 'Edit habit' : 'New habit', style: theme.textTheme.titleLarge),
            const SizedBox(height: 16),
            TextField(
              controller: _name,
              autofocus: !isEditing,
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submit(),
              decoration: const InputDecoration(
                labelText: 'Habit',
                hintText: 'e.g. Read 20 minutes',
                border: OutlineInputBorder(),
              ),
            ),
            if (!isEditing) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: -4,
                children: _suggestions
                    .map((s) => ActionChip(
                          label: Text(s),
                          visualDensity: VisualDensity.compact,
                          onPressed: () => setState(() => _name.text = s),
                        ))
                    .toList(),
              ),
            ],
            const SizedBox(height: 16),
            Text('Type', style: theme.textTheme.labelLarge),
            const SizedBox(height: 6),
            SegmentedButton<HabitType>(
              segments: const [
                ButtonSegment(value: HabitType.binary, label: Text('Done / not done'), icon: Icon(Icons.check_circle_outline)),
                ButtonSegment(value: HabitType.counter, label: Text('Count'), icon: Icon(Icons.exposure_plus_1)),
              ],
              selected: {_type},
              onSelectionChanged: (s) => setState(() => _type = s.first),
            ),
            if (_type == HabitType.counter) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Text('Daily goal', style: theme.textTheme.labelLarge),
                  const Spacer(),
                  IconButton(
                    onPressed: _targetCount > 1 ? () => setState(() => _targetCount--) : null,
                    icon: const Icon(Icons.remove_circle_outline),
                  ),
                  Text('$_targetCount', style: theme.textTheme.titleMedium),
                  IconButton(
                    onPressed: () => setState(() => _targetCount++),
                    icon: const Icon(Icons.add_circle_outline),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 16),
            Text('How often', style: theme.textTheme.labelLarge),
            const SizedBox(height: 6),
            SegmentedButton<HabitFrequency>(
              segments: const [
                ButtonSegment(value: HabitFrequency.daily, label: Text('Every day')),
                ButtonSegment(value: HabitFrequency.weekly, label: Text('Some days a week')),
              ],
              selected: {_frequency},
              onSelectionChanged: (s) => setState(() => _frequency = s.first),
            ),
            if (_frequency == HabitFrequency.weekly) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Slider(
                      value: _weeklyTarget.toDouble(),
                      min: 1,
                      max: 6,
                      divisions: 5,
                      label: '$_weeklyTarget days / week',
                      onChanged: (v) => setState(() => _weeklyTarget = v.round()),
                    ),
                  ),
                  SizedBox(width: 90, child: Text('$_weeklyTarget days / week', style: theme.textTheme.bodyMedium)),
                ],
              ),
              Text(
                'Missing a day won\'t break your streak as long as you hit $_weeklyTarget days in the week.',
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
            const SizedBox(height: 16),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.notifications_outlined),
              title: const Text('Reminder'),
              subtitle: Text(_reminder == null ? 'Off' : _reminder!.format(context)),
              trailing: _reminder != null
                  ? IconButton(icon: const Icon(Icons.close), onPressed: () => setState(() => _reminder = null))
                  : null,
              onTap: () async {
                final picked = await showTimePicker(
                  context: context,
                  initialTime: _reminder ?? const TimeOfDay(hour: 20, minute: 0),
                );
                if (picked != null) setState(() => _reminder = picked);
              },
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: _submit,
              style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
              child: Text(isEditing ? 'Save' : 'Add habit'),
            ),
          ],
        ),
      ),
    );
  }
}
