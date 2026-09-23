import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../main.dart';
import '../models/habit.dart';
import '../models/user_settings.dart';
import '../services/habit_service.dart';
import '../services/reminder_service.dart';

/// Three-step first-run flow: day shape, a goal sentence, starter habits.
/// Writes `user_settings` (with `onboardingComplete: true`) and creates the
/// selected habits. Designed to take under a minute.
class OnboardingScreen extends StatefulWidget {
  final VoidCallback onDone;
  final HabitService? habitService;

  const OnboardingScreen({super.key, required this.onDone, this.habitService});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pages = PageController();
  int _step = 0;
  bool _saving = false;

  TimeOfDay _wake = const TimeOfDay(hour: 7, minute: 0);
  TimeOfDay _sleep = const TimeOfDay(hour: 23, minute: 0);
  final TextEditingController _goal = TextEditingController();
  final TextEditingController _customHabit = TextEditingController();
  final Set<String> _selectedHabits = {'Exercise', 'Read'};
  bool _reminders = kIsWeb;

  static const _starterHabits = [
    'Exercise',
    'Read',
    'Meditate',
    'Drink water',
    'Walk outside',
    'Journal',
    'No phone in bed',
    'Sleep by 11',
    'Stretch',
    'Plan tomorrow',
  ];

  @override
  void dispose() {
    _pages.dispose();
    _goal.dispose();
    _customHabit.dispose();
    super.dispose();
  }

  void _next() {
    if (_step < 2) {
      setState(() => _step++);
      _pages.animateToPage(_step, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    } else {
      _finish();
    }
  }

  void _back() {
    if (_step == 0) return;
    setState(() => _step--);
    _pages.animateToPage(_step, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
  }

  Future<void> _finish({bool skipped = false}) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    setState(() => _saving = true);
    try {
      final settings = UserSettings(
        userId: uid,
        sleepTime: _sleep,
        wakeTime: _wake,
        goalText: skipped ? '' : _goal.text.trim(),
        remindersEnabled: !skipped && _reminders,
        onboardingComplete: true,
      );
      await getFirestore().collection('user_settings').doc(uid).set(settings.toMap(), SetOptions(merge: true));

      if (!skipped && _selectedHabits.isNotEmpty) {
        final service = widget.habitService ?? HabitService();
        int i = 0;
        for (final name in _selectedHabits) {
          await service.addHabit(
            uid: uid,
            name: name,
            type: HabitType.binary,
            frequency: HabitFrequency.daily,
            sortOrder: i++,
          );
        }
      }

      if (!skipped && _reminders && kIsWeb && ReminderService.permission == 'default') {
        await ReminderService.requestPermission();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not save: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
    widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 16, 16, 0),
                  child: Row(
                    children: [
                      Text('Day Coach', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                      const Spacer(),
                      TextButton(onPressed: _saving ? null : () => _finish(skipped: true), child: const Text('Skip')),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                  child: Row(
                    children: List.generate(3, (i) {
                      return Expanded(
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 250),
                          height: 4,
                          margin: EdgeInsets.only(right: i < 2 ? 6 : 0),
                          decoration: BoxDecoration(
                            color: i <= _step ? theme.colorScheme.primary : theme.colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      );
                    }),
                  ),
                ),
                Expanded(
                  child: PageView(
                    controller: _pages,
                    physics: const NeverScrollableScrollPhysics(),
                    children: [
                      _stepDayShape(theme),
                      _stepGoal(theme),
                      _stepHabits(theme),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Row(
                    children: [
                      if (_step > 0) TextButton(onPressed: _back, child: const Text('Back')),
                      const Spacer(),
                      FilledButton(
                        onPressed: _saving ? null : _next,
                        style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14)),
                        child: _saving
                            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                            : Text(_step == 2 ? 'Start' : 'Continue'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _header(ThemeData theme, String title, String subtitle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        Text(subtitle, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _stepDayShape(ThemeData theme) {
    Widget timeTile(String label, IconData icon, TimeOfDay value, ValueChanged<TimeOfDay> onPick) {
      return Card(
        child: ListTile(
          leading: Icon(icon),
          title: Text(label),
          trailing: Text(value.format(context), style: theme.textTheme.titleMedium),
          onTap: () async {
            final t = await showTimePicker(context: context, initialTime: value);
            if (t != null) onPick(t);
          },
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      children: [
        _header(theme, 'When does your day happen?',
            'The timeline auto-fills sleep and focuses on your waking hours. You can change this later in Profile.'),
        timeTile('I usually wake up at', Icons.wb_sunny_outlined, _wake, (t) => setState(() => _wake = t)),
        timeTile('I usually go to bed at', Icons.bedtime_outlined, _sleep, (t) => setState(() => _sleep = t)),
      ],
    );
  }

  Widget _stepGoal(ThemeData theme) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      children: [
        _header(theme, 'What matters most right now?',
            'One sentence. The coach scores each day against it and tells you where your time actually went.'),
        TextField(
          controller: _goal,
          maxLines: 3,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            hintText: 'e.g. Ship the side project by December while sleeping 7+ hours.',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            'Spend more deep-work time on my main project',
            'Get fitter without sacrificing sleep',
            'Be present with family in the evenings',
          ]
              .map((s) => ActionChip(label: Text(s), onPressed: () => setState(() => _goal.text = s)))
              .toList(),
        ),
        const SizedBox(height: 8),
        Text('Optional — you can skip this.', style: theme.textTheme.bodySmall?.copyWith(color: theme.disabledColor)),
      ],
    );
  }

  Widget _stepHabits(ThemeData theme) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      children: [
        _header(theme, 'Pick 2–3 habits to start',
            'Small and daily beats big and occasional. You can add counters and weekly targets later.'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ..._starterHabits.map((h) => FilterChip(
                  label: Text(h),
                  selected: _selectedHabits.contains(h),
                  onSelected: (v) => setState(() => v ? _selectedHabits.add(h) : _selectedHabits.remove(h)),
                )),
            ..._selectedHabits.where((h) => !_starterHabits.contains(h)).map((h) => InputChip(
                  label: Text(h),
                  selected: true,
                  onDeleted: () => setState(() => _selectedHabits.remove(h)),
                )),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _customHabit,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            hintText: 'Add your own…',
            border: const OutlineInputBorder(),
            isDense: true,
            suffixIcon: IconButton(
              icon: const Icon(Icons.add),
              onPressed: () {
                final v = _customHabit.text.trim();
                if (v.isEmpty) return;
                setState(() {
                  _selectedHabits.add(v);
                  _customHabit.clear();
                });
              },
            ),
          ),
          onSubmitted: (v) {
            final t = v.trim();
            if (t.isEmpty) return;
            setState(() {
              _selectedHabits.add(t);
              _customHabit.clear();
            });
          },
        ),
        if (kIsWeb) ...[
          const SizedBox(height: 20),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Remind me to plan and log my day'),
            subtitle: const Text('Browser notifications while Day Coach is open or installed'),
            value: _reminders,
            onChanged: (v) => setState(() => _reminders = v),
          ),
        ],
      ],
    );
  }
}
