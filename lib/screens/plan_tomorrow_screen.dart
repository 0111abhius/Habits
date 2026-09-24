import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../main.dart';
import '../models/task.dart';
import '../models/template.dart';
import '../models/timeline_entry.dart';
import '../models/user_settings.dart';
import '../services/day_plan_service.dart';
import '../services/template_service.dart';
import '../utils/task_quick_add.dart';
import '../utils/work_block_planner.dart';
import '../widgets/main_scaffold.dart';

/// The evening shutdown ritual in app form: confirm tomorrow's day shape,
/// pick the top tasks, drop them into work blocks, dump open loops, done.
class PlanTomorrowScreen extends StatefulWidget {
  final DateTime? date;
  const PlanTomorrowScreen({super.key, this.date});

  @override
  State<PlanTomorrowScreen> createState() => _PlanTomorrowScreenState();
}

class _PlanTomorrowScreenState extends State<PlanTomorrowScreen> {
  late DateTime _date;
  final _dumpCtrl = TextEditingController();
  final _dayPlan = DayPlanService();
  final _templates = TemplateService();

  UserSettings? _settings;
  List<Template> _allTemplates = const [];
  String? _appliedTemplateId;
  List<TimelineEntry> _entries = const [];
  bool _loadingDay = true;
  bool _busy = false;
  bool _planned = false;
  String? _placeSummary;
  List<Placement> _placements = const [];

  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  @override
  void initState() {
    super.initState();
    final base = widget.date ?? DateTime.now().add(const Duration(days: 1));
    _date = DateTime(base.year, base.month, base.day);
    _load();
  }

  @override
  void dispose() {
    _dumpCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final uid = _uid;
    if (uid == null) return;
    setState(() => _loadingDay = true);
    try {
      final settingsDoc = await getFirestore().collection('user_settings').doc(uid).get();
      _settings = UserSettings.fromMap({...?settingsDoc.data(), 'userId': uid});
      _allTemplates = await _templates.fetchTemplates(uid);
      _planned = await _dayPlan.isPlanned(uid, _date);

      var entries = await _dayPlan.loadEntries(uid, _date);
      final log = await getFirestore().collection('daily_logs').doc(uid).collection('logs').doc(DayPlanService.dateKey(_date)).get();
      _appliedTemplateId = log.data()?['templateId'] as String?;
      if (!DayPlanService.hasPlan(entries) && log.data()?['templateApplied'] != true) {
        final t = await _templates.templateForDate(uid, _date);
        if (t != null) {
          await _templates.applyToDate(uid, _date, templateId: t.id);
          _appliedTemplateId = t.id;
          entries = await _dayPlan.loadEntries(uid, _date);
        }
      }
      _entries = entries;
    } finally {
      if (mounted) setState(() => _loadingDay = false);
    }
  }

  Future<void> _reloadEntries() async {
    final uid = _uid;
    if (uid == null) return;
    _entries = await _dayPlan.loadEntries(uid, _date);
    if (mounted) setState(() {});
  }

  void _snack(String msg, {SnackBarAction? action}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 6), action: action));
  }

  Future<void> _switchTemplate(String? templateId) async {
    final uid = _uid;
    if (uid == null) return;
    setState(() => _busy = true);
    try {
      await _templates.clearPlan(uid, _date);
      if (templateId != null) {
        await _templates.applyToDate(uid, _date, templateId: templateId, overwrite: true);
      } else {
        await getFirestore()
            .collection('daily_logs')
            .doc(uid)
            .collection('logs')
            .doc(DayPlanService.dateKey(_date))
            .set({'templateApplied': true, 'templateId': FieldValue.delete()}, SetOptions(merge: true));
      }
      _appliedTemplateId = templateId;
      _placeSummary = null;
      _placements = const [];
      await _reloadEntries();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _place(List<Task> chosen) async {
    final uid = _uid;
    if (uid == null || chosen.isEmpty) return;
    setState(() => _busy = true);
    try {
      final outcome = await _dayPlan.placeTasks(uid, _date, chosen, folderActivities: _settings?.folderActivities ?? const {});
      _placeSummary = outcome.summary();
      _placements = outcome.result.placements;
      await _reloadEntries();
    } catch (e) {
      _snack('Could not place tasks: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _capture() async {
    final uid = _uid;
    final text = _dumpCtrl.text.trim();
    if (uid == null || text.isEmpty) return;
    setState(() => _busy = true);
    try {
      final titles = await _dayPlan.captureOpenLoops(
        uid,
        text,
        knownFolders: _settings?.taskFolders ?? const [],
      );
      _dumpCtrl.clear();
      _snack('Captured ${titles.length} open loop${titles.length == 1 ? '' : 's'} to ${_settings?.defaultFolderName ?? 'Inbox'}.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _done() async {
    final uid = _uid;
    if (uid == null) return;
    await _dayPlan.markPlanned(uid, _date);
    if (!mounted) return;
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('${DateFormat('EEEE').format(_date)} is planned. Work is parked — enjoy the evening.'),
      action: SnackBarAction(label: 'View', onPressed: () => MainScaffold.openDay(_date)),
    ));
  }

  int get _freeWorkMinutes {
    final r = WorkBlockPlanner.plan(slots: _entries.map(DayPlanService.toSlot).toList(), tasks: const []);
    return r.freeMinutesBefore;
  }

  int get _totalWorkMinutes => _entries
      .where((e) => !e.locked && WorkBlockPlanner.isWorkSlot(DayPlanService.toSlot(e)))
      .fold(0, (s, e) => s + e.duration.inMinutes);

  int get _anchorCount => _entries.where((e) => e.locked).length;

  @override
  Widget build(BuildContext context) {
    final uid = _uid;
    final theme = Theme.of(context);
    final dateLabel = DateFormat('EEEE, MMM d').format(_date);
    final isTomorrow = _date == DayPlanService.dayOnly(DateTime.now().add(const Duration(days: 1)));

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(isTomorrow ? 'Plan tomorrow' : 'Plan the day'),
            Text(dateLabel, style: theme.textTheme.bodySmall),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Pick another day',
            icon: const Icon(Icons.calendar_month_outlined),
            onPressed: () async {
              final now = DateTime.now();
              final picked = await showDatePicker(
                context: context,
                initialDate: _date,
                firstDate: DateTime(now.year, now.month, now.day),
                lastDate: now.add(const Duration(days: 60)),
              );
              if (picked != null) {
                setState(() {
                  _date = DateTime(picked.year, picked.month, picked.day);
                  _placeSummary = null;
                  _placements = const [];
                });
                await _load();
              }
            },
          ),
          IconButton(
            tooltip: 'Open in timeline',
            icon: const Icon(Icons.view_timeline_outlined),
            onPressed: () {
              Navigator.popUntil(context, (r) => r.isFirst);
              MainScaffold.openDay(_date);
            },
          ),
        ],
      ),
      body: uid == null
          ? const Center(child: Text('Sign in first.'))
          : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: getFirestore().collection('tasks').where('userId', isEqualTo: uid).snapshots(),
              builder: (context, snap) {
                final all = (snap.data?.docs ?? const []).map((d) => Task.fromFirestore(d)).toList();
                final open = all.where((t) => !t.isCompleted).toList();
                final chosen = open.where((t) => t.scheduledDate != null && DayPlanService.dayOnly(t.scheduledDate!) == _date).toList()
                  ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
                final limit = _settings?.topTasksLimit ?? 3;
                final totalMin = chosen.fold<int>(0, (s, t) => s + t.estimatedMinutes);

                return Stack(
                  children: [
                    ListView(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
                      children: [
                        _StepHeader(n: 1, title: 'Shape of the day', subtitle: 'Anchors come from your template. Work blocks are where tasks land.'),
                        _buildDayShape(theme),
                        const SizedBox(height: 20),
                        _StepHeader(
                          n: 2,
                          title: 'Top $limit for the day',
                          subtitle: 'What must move forward. Order = priority. Estimates decide how much room each gets.',
                        ),
                        _buildFocusList(theme, chosen, open, limit, totalMin),
                        const SizedBox(height: 20),
                        _StepHeader(n: 3, title: 'Place into work blocks', subtitle: 'Fills the free work blocks in priority order.'),
                        _buildPlace(theme, chosen),
                        const SizedBox(height: 20),
                        _StepHeader(n: 4, title: 'Open-loop dump', subtitle: 'One per line. Anything that would otherwise follow you home.'),
                        _buildDump(theme),
                      ],
                    ),
                    if (_busy)
                      const Positioned(top: 0, left: 0, right: 0, child: LinearProgressIndicator(minHeight: 3)),
                  ],
                );
              },
            ),
      bottomNavigationBar: uid == null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _planned ? 'Marked as planned. You can still adjust.' : 'Finish here and the day is parked.',
                        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ),
                    FilledButton.icon(
                      onPressed: _busy ? null : _done,
                      icon: Icon(_planned ? Icons.check_circle : Icons.bedtime_outlined),
                      label: Text(_planned ? 'Done' : 'Done planning'),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildDayShape(ThemeData theme) {
    if (_loadingDay) {
      return const Card(child: Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())));
    }
    final applied = _allTemplates.where((t) => t.id == _appliedTemplateId).firstOrNull;
    final hasPlan = DayPlanService.hasPlan(_entries);
    final work = _totalWorkMinutes;
    final free = _freeWorkMinutes;
    String h(int m) => m % 60 == 0 ? '${m ~/ 60}h' : '${(m / 60).toStringAsFixed(1)}h';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(hasPlan ? Icons.view_day_outlined : Icons.crop_square_outlined, color: theme.colorScheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    applied?.name ?? (hasPlan ? 'Custom plan' : 'No plan yet'),
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                if (_allTemplates.isNotEmpty)
                  PopupMenuButton<String?>(
                    tooltip: 'Use a different template',
                    icon: const Icon(Icons.swap_horiz),
                    onSelected: (id) => _switchTemplate(id == '__none__' ? null : id),
                    itemBuilder: (_) => [
                      ..._allTemplates.map((t) => PopupMenuItem<String?>(
                            value: t.id,
                            child: Row(
                              children: [
                                if (t.id == _appliedTemplateId) const Icon(Icons.check, size: 18) else const SizedBox(width: 18),
                                const SizedBox(width: 8),
                                Expanded(child: Text(t.name)),
                              ],
                            ),
                          )),
                      const PopupMenuDivider(),
                      const PopupMenuItem<String?>(value: '__none__', child: Text('Clear plan (keep Sleep)')),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                _Pill(icon: Icons.work_outline, label: work > 0 ? '${h(work)} work blocks · ${h(free)} free' : 'No work blocks'),
                _Pill(icon: Icons.anchor, label: '$_anchorCount anchor${_anchorCount == 1 ? '' : 's'}'),
                if (_appliedTemplateId == null && !hasPlan && _allTemplates.isEmpty)
                  const _Pill(icon: Icons.info_outline, label: 'Create a template in Profile → Day templates'),
              ],
            ),
            if (work == 0 && hasPlan)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'This day has no work blocks. Mark slots as "Work block" in the template, or plan Work / Deep Work hours in the timeline.',
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildFocusList(ThemeData theme, List<Task> chosen, List<Task> open, int limit, int totalMin) {
    final overCap = chosen.length > limit;
    final free = _freeWorkMinutes;
    return Card(
      child: Column(
        children: [
          if (chosen.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Nothing picked yet. Add the one outcome that matters, then up to ${limit - 1} more.',
                style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            )
          else
            ReorderableListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              buildDefaultDragHandles: false,
              itemCount: chosen.length,
              onReorder: (oldIndex, newIndex) async {
                if (newIndex > oldIndex) newIndex--;
                final list = List<Task>.from(chosen);
                final item = list.removeAt(oldIndex);
                list.insert(newIndex, item);
                final batch = getFirestore().batch();
                for (var i = 0; i < list.length; i++) {
                  batch.set(getFirestore().collection('tasks').doc(list[i].id), {'sortOrder': i}, SetOptions(merge: true));
                }
                await batch.commit();
              },
              itemBuilder: (context, i) {
                final t = chosen[i];
                final placedAt = _placements.where((p) => p.task.id == t.id).firstOrNull;
                return ListTile(
                  key: ValueKey('focus_${t.id}'),
                  dense: true,
                  leading: ReorderableDragStartListener(
                    index: i,
                    child: CircleAvatar(
                      radius: 13,
                      backgroundColor: i == 0 ? theme.colorScheme.primary : theme.colorScheme.surfaceContainerHighest,
                      child: Text('${i + 1}',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: i == 0 ? theme.colorScheme.onPrimary : theme.colorScheme.onSurface)),
                    ),
                  ),
                  title: Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text([
                    if (t.folder != null) t.folder!,
                    if (placedAt != null) '→ ${DateFormat('H:mm').format(placedAt.start)}',
                  ].join(' · ')),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ActionChip(
                        label: Text(t.estimateLabel.isEmpty ? '30m' : t.estimateLabel),
                        avatar: const Icon(Icons.timer_outlined, size: 14),
                        visualDensity: VisualDensity.compact,
                        onPressed: () {
                          const steps = [15, 30, 45, 60, 90, 120, 180, 240];
                          final idx = steps.indexOf(t.estimatedMinutes);
                          final next = steps[(idx + 1) % steps.length];
                          getFirestore().collection('tasks').doc(t.id).update({'estimatedMinutes': next});
                        },
                      ),
                      IconButton(
                        tooltip: 'Remove from this day',
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () => getFirestore().collection('tasks').doc(t.id).update({
                          'scheduledDate': null,
                          if (DayPlanService.dayOnly(DateTime.now()) == _date) 'isToday': false,
                        }),
                      ),
                    ],
                  ),
                );
              },
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
            child: Row(
              children: [
                OutlinedButton.icon(
                  onPressed: _busy ? null : () => _showTaskPicker(open, chosen),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add task'),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    chosen.isEmpty
                        ? ''
                        : '${chosen.length}${overCap ? '/$limit' : ''} · ${_h(totalMin)} planned · ${_h(free)} free'
                            '${overCap ? ' · over your top $limit' : ''}'
                            '${totalMin > free && free > 0 ? ' · more than fits' : ''}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: (overCap || totalMin > free) ? theme.colorScheme.error : theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _h(int m) => m % 60 == 0 ? '${m ~/ 60}h' : '${(m / 60).toStringAsFixed(1)}h';

  Widget _buildPlace(ThemeData theme, List<Task> chosen) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                FilledButton.tonalIcon(
                  onPressed: _busy || chosen.isEmpty || _totalWorkMinutes == 0 ? null : () => _place(chosen),
                  icon: const Icon(Icons.schedule_send_outlined, size: 18),
                  label: const Text('Place into work blocks'),
                ),
                const SizedBox(width: 10),
                if (_placements.isNotEmpty)
                  TextButton(
                    onPressed: () {
                      Navigator.popUntil(context, (r) => r.isFirst);
                      MainScaffold.openDay(_date);
                    },
                    child: const Text('See timeline'),
                  ),
              ],
            ),
            if (_placeSummary != null) ...[
              const SizedBox(height: 8),
              Text(_placeSummary!, style: theme.textTheme.bodySmall),
            ],
            if (_placements.isNotEmpty) ...[
              const SizedBox(height: 8),
              ..._placements.map((p) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 92,
                          child: Text(
                            '${DateFormat('H:mm').format(p.slots.first.start)}–${DateFormat('H:mm').format(p.slots.last.end)}',
                            style: theme.textTheme.bodySmall?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
                          ),
                        ),
                        Expanded(child: Text(p.task.title, maxLines: 1, overflow: TextOverflow.ellipsis)),
                        if (p.minutes < p.task.estimatedMinutes)
                          Text(' short', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error)),
                      ],
                    ),
                  )),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDump(ThemeData theme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _dumpCtrl,
              minLines: 3,
              maxLines: 8,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'Reply to Sam about the offsite\nRenew passport #"Life admin"\nIdea: weekly metrics dashboard 1h',
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Quick-add syntax works: #Folder, 30m, tomorrow, @fri.',
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ),
                FilledButton.tonal(
                  onPressed: _busy || _dumpCtrl.text.trim().isEmpty ? null : _capture,
                  child: const Text('Capture'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showTaskPicker(List<Task> open, List<Task> chosen) async {
    final uid = _uid;
    if (uid == null) return;
    final chosenIds = chosen.map((t) => t.id).toSet();
    final candidates = open.where((t) => !chosenIds.contains(t.id)).toList()
      ..sort((a, b) {
        // Overdue and today-flagged first, then by folder order/sortOrder.
        int rank(Task t) => t.isOverdue ? 0 : (t.isToday ? 1 : (t.scheduledDate == null ? 2 : 3));
        final r = rank(a).compareTo(rank(b));
        return r != 0 ? r : a.sortOrder.compareTo(b.sortOrder);
      });
    final searchCtrl = TextEditingController();
    final quickCtrl = TextEditingController();

    Future<void> choose(Task t) async {
      await getFirestore().collection('tasks').doc(t.id).set(
        {
          'scheduledDate': Timestamp.fromDate(_date),
          'sortOrder': chosen.length,
          if (DayPlanService.dayOnly(DateTime.now()) == _date) 'isToday': true,
        },
        SetOptions(merge: true),
      );
    }

    Future<void> quickAdd(String raw) async {
      final text = raw.trim();
      if (text.isEmpty) return;
      final parsed = TaskQuickAdd.parse(text, knownFolders: _settings?.taskFolders ?? const []);
      final ref = getFirestore().collection('tasks').doc();
      final task = Task(
        id: ref.id,
        userId: uid,
        title: parsed.title,
        estimatedMinutes: parsed.estimatedMinutes ?? 30,
        createdAt: DateTime.now(),
        folder: parsed.folder,
        scheduledDate: _date,
        isToday: DayPlanService.dayOnly(DateTime.now()) == _date,
        sortOrder: chosen.length,
      );
      await ref.set(task.toMap());
      quickCtrl.clear();
    }

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          final q = searchCtrl.text.trim().toLowerCase();
          final shown = q.isEmpty ? candidates : candidates.where((t) => t.title.toLowerCase().contains(q)).toList();
          return Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
            child: SizedBox(
              height: MediaQuery.of(ctx).size.height * 0.75,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: TextField(
                      controller: quickCtrl,
                      autofocus: true,
                      decoration: InputDecoration(
                        hintText: 'New task for this day…  e.g. Draft design note 45m #work',
                        prefixIcon: const Icon(Icons.add),
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.keyboard_return),
                          onPressed: () async {
                            await quickAdd(quickCtrl.text);
                            if (ctx.mounted) Navigator.pop(ctx);
                          },
                        ),
                      ),
                      onSubmitted: (v) async {
                        await quickAdd(v);
                        if (ctx.mounted) Navigator.pop(ctx);
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: TextField(
                      controller: searchCtrl,
                      decoration: const InputDecoration(
                        hintText: 'Search open tasks',
                        prefixIcon: Icon(Icons.search),
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (_) => setSheet(() {}),
                    ),
                  ),
                  Expanded(
                    child: shown.isEmpty
                        ? const Center(child: Text('No open tasks match.'))
                        : ListView.builder(
                            itemCount: shown.length,
                            itemBuilder: (_, i) {
                              final t = shown[i];
                              return ListTile(
                                dense: true,
                                leading: Icon(
                                  t.isOverdue ? Icons.warning_amber_rounded : Icons.radio_button_unchecked,
                                  color: t.isOverdue ? Theme.of(ctx).colorScheme.error : null,
                                  size: 20,
                                ),
                                title: Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                                subtitle: Text([
                                  if (t.folder != null) t.folder!,
                                  t.estimateLabel,
                                  if (t.isOverdue) 'overdue',
                                  if (t.isToday) 'today',
                                ].where((s) => s.isNotEmpty).join(' · ')),
                                trailing: const Icon(Icons.add_circle_outline),
                                onTap: () async {
                                  await choose(t);
                                  if (ctx.mounted) Navigator.pop(ctx);
                                },
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _StepHeader extends StatelessWidget {
  final int n;
  final String title;
  final String subtitle;
  const _StepHeader({required this.n, required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 12,
            backgroundColor: theme.colorScheme.primaryContainer,
            child: Text('$n', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: theme.colorScheme.onPrimaryContainer)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleMedium),
                Text(subtitle, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final IconData icon;
  final String label;
  const _Pill({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 6),
          Text(label, style: theme.textTheme.labelMedium),
        ],
      ),
    );
  }
}
