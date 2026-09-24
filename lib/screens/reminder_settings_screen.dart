import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../main.dart';
import '../models/habit.dart';
import '../models/user_settings.dart';
import '../services/habit_service.dart';
import '../services/reminder_service.dart';
import '../widgets/habit_editor_sheet.dart';

class ReminderSettingsScreen extends StatefulWidget {
  const ReminderSettingsScreen({super.key});

  @override
  State<ReminderSettingsScreen> createState() => _ReminderSettingsScreenState();
}

class _ReminderSettingsScreenState extends State<ReminderSettingsScreen> {
  bool _loading = true;
  bool _enabled = false;
  TimeOfDay _planTime = const TimeOfDay(hour: 8, minute: 30);
  TimeOfDay _logTime = const TimeOfDay(hour: 21, minute: 0);
  TimeOfDay _planTomorrowTime = const TimeOfDay(hour: 16, minute: 30);
  String _permission = ReminderService.permission;

  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final uid = _uid;
    if (uid == null) return;
    final doc = await getFirestore().collection('user_settings').doc(uid).get();
    if (doc.exists && doc.data() != null) {
      final s = UserSettings.fromMap(doc.data()!);
      _enabled = s.remindersEnabled;
      _planTime = s.planReminderTime;
      _logTime = s.logReminderTime;
      _planTomorrowTime = s.planTomorrowReminderTime;
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    final uid = _uid;
    if (uid == null) return;
    await ReminderService.saveSettings(uid,
        enabled: _enabled, planTime: _planTime, logTime: _logTime, planTomorrowTime: _planTomorrowTime);
  }

  Future<void> _requestPermission() async {
    final result = await ReminderService.requestPermission();
    if (mounted) setState(() => _permission = result);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final supported = kIsWeb && ReminderService.isSupported;
    final granted = _permission == 'granted';

    return Scaffold(
      appBar: AppBar(title: const Text('Reminders')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (!supported)
                  Card(
                    color: theme.colorScheme.errorContainer,
                    child: const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                        'Reminders currently use browser notifications and are only available in the web app '
                        '(Chrome desktop or an installed PWA). Mobile push is on the roadmap.',
                      ),
                    ),
                  ),
                if (supported && !granted)
                  Card(
                    color: theme.colorScheme.tertiaryContainer,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _permission == 'denied'
                                ? 'Notifications are blocked for this site. Allow them in Chrome\'s site settings (lock icon → Notifications) and reload.'
                                : 'Allow notifications so Day Coach can nudge you while the app is open or installed.',
                            style: theme.textTheme.bodyMedium,
                          ),
                          const SizedBox(height: 12),
                          if (_permission != 'denied')
                            FilledButton.icon(
                              onPressed: _requestPermission,
                              icon: const Icon(Icons.notifications_active_outlined),
                              label: const Text('Allow notifications'),
                            ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
                Card(
                  child: Column(
                    children: [
                      SwitchListTile(
                        title: const Text('Enable reminders'),
                        subtitle: const Text('Fire while Day Coach is open in a tab or installed as an app'),
                        value: _enabled,
                        onChanged: supported
                            ? (v) async {
                                setState(() => _enabled = v);
                                if (v && !granted) await _requestPermission();
                                await _save();
                              }
                            : null,
                      ),
                      const Divider(height: 1),
                      ListTile(
                        enabled: _enabled,
                        leading: const Icon(Icons.bedtime_outlined),
                        title: const Text('Plan tomorrow'),
                        subtitle: const Text('The shutdown anchor — only if tomorrow is not planned yet'),
                        trailing: Text(_planTomorrowTime.format(context), style: theme.textTheme.titleMedium),
                        onTap: () async {
                          final t = await showTimePicker(context: context, initialTime: _planTomorrowTime);
                          if (t != null) {
                            setState(() => _planTomorrowTime = t);
                            await _save();
                          }
                        },
                      ),
                      const Divider(height: 1),
                      ListTile(
                        enabled: _enabled,
                        leading: const Icon(Icons.edit_calendar_outlined),
                        title: const Text('Morning fallback'),
                        subtitle: const Text('Only if today still has no plan'),
                        trailing: Text(_planTime.format(context), style: theme.textTheme.titleMedium),
                        onTap: () async {
                          final t = await showTimePicker(context: context, initialTime: _planTime);
                          if (t != null) {
                            setState(() => _planTime = t);
                            await _save();
                          }
                        },
                      ),
                      const Divider(height: 1),
                      ListTile(
                        enabled: _enabled,
                        leading: const Icon(Icons.nightlight_outlined),
                        title: const Text('Log your day'),
                        subtitle: const Text('Only if the day is not marked as logged'),
                        trailing: Text(_logTime.format(context), style: theme.textTheme.titleMedium),
                        onTap: () async {
                          final t = await showTimePicker(context: context, initialTime: _logTime);
                          if (t != null) {
                            setState(() => _logTime = t);
                            await _save();
                          }
                        },
                      ),
                      const Divider(height: 1),
                      ListTile(
                        enabled: supported && granted,
                        leading: const Icon(Icons.send_outlined),
                        title: const Text('Send a test notification'),
                        onTap: ReminderService.showTest,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                Text('Habit reminders', style: theme.textTheme.titleMedium),
                const SizedBox(height: 4),
                Text('Set a time per habit; you are only reminded when it is not done yet.',
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                const SizedBox(height: 8),
                if (_uid != null)
                  StreamBuilder<List<Habit>>(
                    stream: HabitService().watchHabits(_uid!),
                    builder: (context, snap) {
                      final habits = (snap.data ?? const <Habit>[]).where((h) => !h.archived).toList();
                      if (habits.isEmpty) {
                        return const Card(child: ListTile(title: Text('No habits yet')));
                      }
                      return Card(
                        child: Column(
                          children: [
                            for (int i = 0; i < habits.length; i++) ...[
                              if (i > 0) const Divider(height: 1),
                              ListTile(
                                title: Text(habits[i].name),
                                subtitle: Text(habits[i].frequencyLabel),
                                trailing: Text(
                                  habits[i].reminderTime == null
                                      ? 'Off'
                                      : UserSettings.tryParseTime(habits[i].reminderTime)?.format(context) ?? 'Off',
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    color: habits[i].reminderTime == null ? theme.disabledColor : null,
                                  ),
                                ),
                                onTap: () async {
                                  final result = await showHabitEditor(context, existing: habits[i]);
                                  if (result == null || _uid == null) return;
                                  await HabitService().updateHabit(
                                    _uid!,
                                    habits[i].copyWith(
                                      name: result.name,
                                      type: result.type,
                                      frequency: result.frequency,
                                      weeklyTarget: result.weeklyTarget,
                                      targetCount: result.targetCount,
                                      reminderTime: result.reminderTime,
                                      clearReminder: result.reminderTime == null,
                                    ),
                                  );
                                },
                              ),
                            ],
                          ],
                        ),
                      );
                    },
                  ),
              ],
            ),
    );
  }
}
