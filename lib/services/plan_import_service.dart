import 'package:cloud_firestore/cloud_firestore.dart';

import '../main.dart';
import '../models/habit.dart';
import '../models/plan_import.dart';
import '../models/task.dart';
import '../models/template.dart';
import '../models/user_settings.dart';
import '../utils/activities.dart';
import 'habit_service.dart';
import 'template_service.dart';

enum ImportStatus { add, update, same }

/// One reviewable line in the import preview.
class ImportItem {
  final String section; // settings | activities | folders | habits | templates | tasks
  final String key;
  final String title;
  final String detail;
  final ImportStatus status;
  bool selected;

  ImportItem({
    required this.section,
    required this.key,
    required this.title,
    required this.detail,
    required this.status,
    this.selected = true,
  });
}

class ImportPreview {
  final List<ImportItem> items;
  final List<String> notes;
  const ImportPreview(this.items, this.notes);

  Iterable<ImportItem> section(String s) => items.where((i) => i.section == s);
  int get changeCount => items.where((i) => i.selected && i.status != ImportStatus.same).length;
}

class ImportSummary {
  final int settingsChanged;
  final int activitiesAdded;
  final int foldersAdded;
  final int habitsAdded;
  final int habitsUpdated;
  final int templatesAdded;
  final int templatesUpdated;
  final int tasksAdded;
  final int tasksUpdated;
  final List<String> notes;

  const ImportSummary({
    this.settingsChanged = 0,
    this.activitiesAdded = 0,
    this.foldersAdded = 0,
    this.habitsAdded = 0,
    this.habitsUpdated = 0,
    this.templatesAdded = 0,
    this.templatesUpdated = 0,
    this.tasksAdded = 0,
    this.tasksUpdated = 0,
    this.notes = const [],
  });

  List<String> lines() {
    final out = <String>[];
    if (settingsChanged > 0) out.add('Settings updated');
    if (activitiesAdded > 0) out.add('$activitiesAdded new activities');
    if (foldersAdded > 0) out.add('$foldersAdded new folders');
    if (habitsAdded + habitsUpdated > 0) out.add('Habits: $habitsAdded new, $habitsUpdated updated');
    if (templatesAdded + templatesUpdated > 0) out.add('Templates: $templatesAdded new, $templatesUpdated replaced');
    if (tasksAdded + tasksUpdated > 0) out.add('Tasks: $tasksAdded new, $tasksUpdated updated');
    out.addAll(notes);
    if (out.isEmpty) out.add('Nothing changed');
    return out;
  }
}

/// Compares a parsed [PlanImport] with the user's data and applies the
/// selected parts. Merge rules: match by name (case-insensitive), never
/// delete, unarchive matches, replace template entries wholesale.
class PlanImportService {
  final FirebaseFirestore _db;
  final HabitService _habits;
  final TemplateService _templates;

  PlanImportService({FirebaseFirestore? firestore})
      : _db = firestore ?? getFirestore(),
        _habits = HabitService(firestore: firestore),
        _templates = TemplateService(firestore: firestore);

  DocumentReference<Map<String, dynamic>> _settingsRef(String uid) => _db.collection('user_settings').doc(uid);

  static String _k(String s) => s.trim().toLowerCase();

  Future<ImportPreview> preview(String uid, PlanImport plan) async {
    final items = <ImportItem>[];
    final notes = <String>[];

    final settingsDoc = await _settingsRef(uid).get();
    final settingsMap = settingsDoc.data() ?? <String, dynamic>{};
    final settings = UserSettings.fromMap({...settingsMap, 'userId': uid});

    // Settings
    if (plan.settings != null) {
      final changes = _settingsChanges(settings, plan.settings!);
      items.add(ImportItem(
        section: 'settings',
        key: 'settings',
        title: 'Settings',
        detail: changes.isEmpty ? 'Already matches' : changes.join(' · '),
        status: changes.isEmpty ? ImportStatus.same : ImportStatus.update,
      ));
    }

    // Activities
    final custom = List<String>.from(settingsMap['customActivities'] ?? const []);
    final archived = List<String>.from(settingsMap['archivedActivities'] ?? const []);
    final knownActs = {...kDefaultActivities, ...custom}.map(_k).toSet();
    final newActs = plan.referencedActivities().where((a) => !knownActs.contains(_k(a)) || archived.contains(a)).toList()..sort();
    if (newActs.isNotEmpty) {
      items.add(ImportItem(
        section: 'activities',
        key: 'activities',
        title: 'New activities',
        detail: newActs.join(', '),
        status: ImportStatus.add,
      ));
    }

    // Folders
    final folders = List<String>.from(settingsMap['taskFolders'] ?? const []);
    final wantFolders = <String>{...plan.folders, ...plan.tasks.map((t) => t.folder).whereType<String>()};
    final newFolders = wantFolders.where((f) => !folders.map(_k).contains(_k(f))).toList()..sort();
    final fa = Map<String, String>.from(settingsMap['folderActivities'] ?? const {});
    final faChanges = plan.folderActivities.entries.where((e) => fa[e.key] != e.value).length;
    if (newFolders.isNotEmpty || faChanges > 0) {
      items.add(ImportItem(
        section: 'folders',
        key: 'folders',
        title: 'Task folders',
        detail: [
          if (newFolders.isNotEmpty) 'New: ${newFolders.join(', ')}',
          if (faChanges > 0) '$faChanges folder → activity mappings',
        ].join(' · '),
        status: newFolders.isNotEmpty ? ImportStatus.add : ImportStatus.update,
      ));
    }

    // Habits
    final existingHabits = await _habits.fetchHabits(uid);
    final habitByName = {for (final h in existingHabits) _k(h.name): h};
    for (final h in plan.habits) {
      final cur = habitByName[_k(h.name)];
      final desc = _habitDesc(h);
      if (cur == null) {
        items.add(ImportItem(section: 'habits', key: 'habit:${_k(h.name)}', title: h.name, detail: desc, status: ImportStatus.add));
      } else {
        final diff = _habitDiff(cur, h);
        items.add(ImportItem(
          section: 'habits',
          key: 'habit:${_k(h.name)}',
          title: h.name,
          detail: diff.isEmpty ? desc : diff.join(' · '),
          status: diff.isEmpty ? ImportStatus.same : ImportStatus.update,
        ));
      }
    }

    // Templates
    final existingTemplates = await _templates.fetchTemplates(uid);
    final tmplByName = {for (final t in existingTemplates) _k(t.name): t};
    final claimed = <int>{};
    for (final t in plan.templates) {
      for (final rt in TemplateSlotResolver.expand(t)) {
        final cur = tmplByName[_k(rt.name)];
        final filled = rt.slots.where((s) => !s.isEmpty).length;
        final work = rt.slots.where((s) => s.workBlock).fold<int>(0, (a, s) => a + s.durationMinutes);
        final locked = rt.slots.where((s) => s.locked).length;
        final detail = [
          rt.days.isEmpty ? 'Manual (no weekdays)' : PlanDays.label(rt.days),
          '$filled slots',
          if (work > 0) '${(work / 60).toStringAsFixed(work % 60 == 0 ? 0 : 1)}h work blocks',
          if (locked > 0) '$locked anchors',
        ].join(' · ');
        items.add(ImportItem(
          section: 'templates',
          key: 'template:${_k(rt.name)}',
          title: rt.name,
          detail: cur == null ? detail : '$detail · replaces existing',
          status: cur == null ? ImportStatus.add : ImportStatus.update,
        ));
        claimed.addAll(rt.days);
      }
    }
    if (claimed.isNotEmpty) {
      for (final t in existingTemplates) {
        final overlap = t.daysOfWeek.where(claimed.contains).toList();
        final replaced = plan.templates.any((p) => TemplateSlotResolver.expand(p).any((rt) => _k(rt.name) == _k(t.name)));
        if (overlap.isNotEmpty && !replaced) {
          notes.add('"${t.name}" will stop auto-applying on ${PlanDays.label(overlap)}');
        }
      }
    }

    // Tasks
    final taskSnap = await _db.collection('tasks').where('userId', isEqualTo: uid).where('isCompleted', isEqualTo: false).get();
    final openTasks = taskSnap.docs.map((d) => Task.fromFirestore(d)).toList();
    final taskByTitle = {for (final t in openTasks) _k(t.title): t};
    for (final t in plan.tasks) {
      final cur = taskByTitle[_k(t.title)];
      final desc = _taskDesc(t);
      if (cur == null) {
        items.add(ImportItem(section: 'tasks', key: 'task:${_k(t.title)}', title: t.title, detail: desc, status: ImportStatus.add));
      } else {
        final diff = _taskDiff(cur, t);
        items.add(ImportItem(
          section: 'tasks',
          key: 'task:${_k(t.title)}',
          title: t.title,
          detail: diff.isEmpty ? 'Already exists' : diff.join(' · '),
          status: diff.isEmpty ? ImportStatus.same : ImportStatus.update,
        ));
      }
    }

    for (final i in items) {
      if (i.status == ImportStatus.same) i.selected = false;
    }
    return ImportPreview(items, notes);
  }

  Future<ImportSummary> apply(String uid, PlanImport plan, Set<String> selected) async {
    int settingsChanged = 0, activitiesAdded = 0, foldersAdded = 0;
    int habitsAdded = 0, habitsUpdated = 0, templatesAdded = 0, templatesUpdated = 0, tasksAdded = 0, tasksUpdated = 0;
    final notes = <String>[];

    final settingsDoc = await _settingsRef(uid).get();
    final settingsMap = Map<String, dynamic>.from(settingsDoc.data() ?? {});
    final settingsUpd = <String, dynamic>{};

    if (plan.settings != null && selected.contains('settings')) {
      final s = plan.settings!;
      if (s.wakeMinutes != null) settingsUpd['wakeTime'] = PlanTime.format(s.wakeMinutes!);
      if (s.sleepMinutes != null) settingsUpd['sleepTime'] = PlanTime.format(s.sleepMinutes!);
      if (s.goal != null) settingsUpd['goalText'] = s.goal;
      if (s.topTasksLimit != null) settingsUpd['topTasksLimit'] = s.topTasksLimit;
      if (s.planTomorrowReminder != null) settingsUpd['planTomorrowReminderTime'] = PlanTime.format(s.planTomorrowReminder!);
      if (s.morningPlanReminder != null) settingsUpd['planReminderTime'] = PlanTime.format(s.morningPlanReminder!);
      if (s.eveningLogReminder != null) settingsUpd['logReminderTime'] = PlanTime.format(s.eveningLogReminder!);
      if (s.remindersEnabled != null) settingsUpd['remindersEnabled'] = s.remindersEnabled;
      if (settingsUpd.isNotEmpty) settingsChanged = 1;
    }

    if (selected.contains('activities')) {
      final custom = List<String>.from(settingsMap['customActivities'] ?? const []);
      final archived = List<String>.from(settingsMap['archivedActivities'] ?? const []);
      final known = {...kDefaultActivities, ...custom}.map(_k).toSet();
      for (final a in plan.referencedActivities()) {
        if (!known.contains(_k(a))) {
          custom.add(a);
          known.add(_k(a));
          activitiesAdded++;
        }
        if (archived.remove(a)) activitiesAdded++;
      }
      settingsUpd['customActivities'] = custom;
      settingsUpd['archivedActivities'] = archived;
    }

    if (selected.contains('folders')) {
      final folders = List<String>.from(settingsMap['taskFolders'] ?? const []);
      final want = <String>{...plan.folders, ...plan.tasks.map((t) => t.folder).whereType<String>()};
      for (final f in want) {
        if (!folders.map(_k).contains(_k(f))) {
          folders.add(f);
          foldersAdded++;
        }
      }
      final fa = Map<String, String>.from(settingsMap['folderActivities'] ?? const {});
      fa.addAll(plan.folderActivities);
      settingsUpd['taskFolders'] = folders;
      settingsUpd['folderActivities'] = fa;
    }

    if (settingsUpd.isNotEmpty) {
      settingsUpd['userId'] = uid;
      await _settingsRef(uid).set(settingsUpd, SetOptions(merge: true));
    }

    // Habits
    if (plan.habits.isNotEmpty) {
      final existing = await _habits.fetchHabits(uid);
      final byName = {for (final h in existing) _k(h.name): h};
      var order = existing.length;
      for (final h in plan.habits) {
        if (!selected.contains('habit:${_k(h.name)}')) continue;
        final cur = byName[_k(h.name)];
        final type = h.type == 'counter' ? HabitType.counter : HabitType.binary;
        final freq = h.frequency == 'weekly' ? HabitFrequency.weekly : HabitFrequency.daily;
        final reminder = h.reminderMinutes != null ? PlanTime.format(h.reminderMinutes!) : null;
        if (cur == null) {
          final created = await _habits.addHabit(
            uid: uid,
            name: h.name,
            type: type,
            frequency: freq,
            weeklyTarget: h.weeklyTarget,
            targetCount: h.targetCount,
            reminderTime: reminder,
            sortOrder: order++,
          );
          if (h.tier > 0) await _habits.updateHabit(uid, created.copyWith(tier: h.tier));
          habitsAdded++;
        } else {
          await _habits.updateHabit(
            uid,
            cur.copyWith(
              type: type,
              frequency: freq,
              weeklyTarget: h.weeklyTarget,
              targetCount: h.targetCount,
              reminderTime: reminder,
              tier: h.tier > 0 ? h.tier : cur.tier,
              archived: false,
            ),
          );
          habitsUpdated++;
        }
      }
    }

    // Templates
    if (plan.templates.isNotEmpty) {
      final existing = await _templates.fetchTemplates(uid);
      final byName = {for (final t in existing) _k(t.name): t};
      for (final t in plan.templates) {
        for (final rt in TemplateSlotResolver.expand(t)) {
          if (!selected.contains('template:${_k(rt.name)}')) continue;
          final Template? cur = byName[_k(rt.name)];
          final entries = <String, Map<String, dynamic>>{for (final s in rt.slots) s.id: s.toEntryMap()};
          final id = await _templates.upsertTemplate(
            uid,
            templateId: cur?.id,
            name: rt.name,
            daysOfWeek: rt.days,
            entries: entries,
          );
          if (cur == null) {
            templatesAdded++;
          } else {
            templatesUpdated++;
          }
          final released = await _templates.releaseDays(uid, rt.days, exceptId: id);
          for (final name in released) {
            notes.add('"$name" no longer auto-applies on ${PlanDays.label(rt.days)}');
          }
        }
      }
    }

    // Tasks
    if (plan.tasks.isNotEmpty) {
      final snap = await _db.collection('tasks').where('userId', isEqualTo: uid).where('isCompleted', isEqualTo: false).get();
      final byTitle = {for (final d in snap.docs) _k(d.data()['title'] ?? ''): Task.fromFirestore(d)};
      final batch = _db.batch();
      var i = 0;
      for (final t in plan.tasks) {
        if (!selected.contains('task:${_k(t.title)}')) continue;
        final cur = byTitle[_k(t.title)];
        if (cur == null) {
          final ref = _db.collection('tasks').doc();
          final task = Task(
            id: ref.id,
            userId: uid,
            title: t.title,
            notes: t.notes,
            estimatedMinutes: t.estimatedMinutes ?? 30,
            createdAt: DateTime.now().add(Duration(milliseconds: i++)),
            folder: t.folder,
            isToday: t.today,
            scheduledDate: t.scheduledDate,
            activity: t.activity,
            repeat: t.repeat,
          );
          batch.set(ref, task.toMap());
          tasksAdded++;
        } else {
          final upd = <String, dynamic>{};
          if (t.folder != null && t.folder != cur.folder) upd['folder'] = t.folder;
          if (t.estimatedMinutes != null && t.estimatedMinutes != cur.estimatedMinutes) upd['estimatedMinutes'] = t.estimatedMinutes;
          if (t.notes.isNotEmpty && t.notes != cur.notes) upd['notes'] = t.notes;
          if (t.repeat != null && t.repeat != cur.repeat) upd['repeat'] = t.repeat;
          if (t.today && !cur.isToday) upd['isToday'] = true;
          if (t.scheduledDate != null) upd['scheduledDate'] = Timestamp.fromDate(t.scheduledDate!);
          if (upd.isNotEmpty) {
            batch.set(_db.collection('tasks').doc(cur.id), upd, SetOptions(merge: true));
            tasksUpdated++;
          }
        }
      }
      if (tasksAdded + tasksUpdated > 0) await batch.commit();
    }

    return ImportSummary(
      settingsChanged: settingsChanged,
      activitiesAdded: activitiesAdded,
      foldersAdded: foldersAdded,
      habitsAdded: habitsAdded,
      habitsUpdated: habitsUpdated,
      templatesAdded: templatesAdded,
      templatesUpdated: templatesUpdated,
      tasksAdded: tasksAdded,
      tasksUpdated: tasksUpdated,
      notes: notes,
    );
  }

  // ---- diff helpers -------------------------------------------------------

  List<String> _settingsChanges(UserSettings cur, ImportSettings s) {
    final out = <String>[];
    String t(int m) => PlanTime.format(m);
    if (s.wakeMinutes != null && UserSettings.fmt(cur.wakeTime) != t(s.wakeMinutes!)) out.add('Wake ${t(s.wakeMinutes!)}');
    if (s.sleepMinutes != null && UserSettings.fmt(cur.sleepTime) != t(s.sleepMinutes!)) out.add('Sleep ${t(s.sleepMinutes!)}');
    if (s.goal != null && s.goal != cur.goalText) out.add('Goal');
    if (s.topTasksLimit != null && s.topTasksLimit != cur.topTasksLimit) out.add('Top ${s.topTasksLimit} tasks');
    if (s.planTomorrowReminder != null && UserSettings.fmt(cur.planTomorrowReminderTime) != t(s.planTomorrowReminder!)) {
      out.add('Plan-tomorrow reminder ${t(s.planTomorrowReminder!)}');
    }
    if (s.morningPlanReminder != null && UserSettings.fmt(cur.planReminderTime) != t(s.morningPlanReminder!)) {
      out.add('Morning reminder ${t(s.morningPlanReminder!)}');
    }
    if (s.eveningLogReminder != null && UserSettings.fmt(cur.logReminderTime) != t(s.eveningLogReminder!)) {
      out.add('Evening log reminder ${t(s.eveningLogReminder!)}');
    }
    if (s.remindersEnabled != null && s.remindersEnabled != cur.remindersEnabled) {
      out.add(s.remindersEnabled! ? 'Reminders on' : 'Reminders off');
    }
    return out;
  }

  String _habitDesc(ImportHabit h) => [
        h.frequency == 'weekly' ? '${h.weeklyTarget}x / week' : 'Every day',
        if (h.type == 'counter') 'target ${h.targetCount}',
        if (h.tier > 0) 'Tier ${h.tier}',
        if (h.reminderMinutes != null) 'reminder ${PlanTime.format(h.reminderMinutes!)}',
      ].join(' · ');

  List<String> _habitDiff(Habit cur, ImportHabit h) {
    final out = <String>[];
    final type = h.type == 'counter' ? HabitType.counter : HabitType.binary;
    final freq = h.frequency == 'weekly' ? HabitFrequency.weekly : HabitFrequency.daily;
    if (cur.type != type) out.add('type → ${h.type}');
    if (cur.frequency != freq || (freq == HabitFrequency.weekly && cur.weeklyTarget != h.weeklyTarget)) {
      out.add(freq == HabitFrequency.weekly ? '${h.weeklyTarget}x / week' : 'Every day');
    }
    if (type == HabitType.counter && cur.targetCount != h.targetCount) out.add('target ${h.targetCount}');
    if (h.tier > 0 && cur.tier != h.tier) out.add('Tier ${h.tier}');
    final reminder = h.reminderMinutes != null ? PlanTime.format(h.reminderMinutes!) : null;
    if (reminder != null && cur.reminderTime != reminder) out.add('reminder $reminder');
    if (cur.archived) out.add('unarchive');
    return out;
  }

  String _taskDesc(ImportTask t) => [
        if (t.folder != null) t.folder!,
        if (t.estimatedMinutes != null) '${t.estimatedMinutes}m',
        if (t.repeat != null) 'repeats ${t.repeat}',
        if (t.today) 'today',
      ].join(' · ');

  List<String> _taskDiff(Task cur, ImportTask t) {
    final out = <String>[];
    if (t.folder != null && t.folder != cur.folder) out.add('folder → ${t.folder}');
    if (t.estimatedMinutes != null && t.estimatedMinutes != cur.estimatedMinutes) out.add('${t.estimatedMinutes}m');
    if (t.repeat != null && t.repeat != cur.repeat) out.add('repeats ${t.repeat}');
    if (t.today && !cur.isToday) out.add('flag for today');
    return out;
  }
}
