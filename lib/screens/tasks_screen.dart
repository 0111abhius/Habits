import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../models/task.dart';
import '../models/user_settings.dart';
import '../services/day_plan_service.dart';
import '../utils/task_repeat.dart';
import 'plan_tomorrow_screen.dart';
import '../widgets/main_scaffold.dart';
import '../models/timeline_entry.dart';
import '../widgets/ai_scheduling_dialog.dart';
import '../widgets/activity_picker.dart';
import '../utils/activities.dart';
import '../utils/task_quick_add.dart';
import '../main.dart'; // for getFirestore()
import '../widgets/task_tile.dart';

enum _TaskViewMode { folder, date }

const String _kInboxSentinel = '__INBOX__';

class TasksScreen extends StatefulWidget {
  const TasksScreen({super.key});

  @override
  State<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends State<TasksScreen> {
  String? _selectedFolder; // null means Default/Inbox
  List<String> _folders = [];
  bool _foldersLoaded = false;
  String _defaultFolderName = 'Inbox';
  final Map<String, bool> _folderExpansions = {};
  final Map<String, bool> _showCompleted = {};
  _TaskViewMode _viewMode = _TaskViewMode.folder;
  final Map<String, bool> _dateExpansions = {};
  Map<String, String> _folderActivities = {};
  int _topTasksLimit = 3;
  bool _placing = false;
  List<String> _allActivities = [];
  List<String> _recentActivities = [];
  bool _todayExpanded = true;

  final TextEditingController _quickAddController = TextEditingController();
  final FocusNode _quickAddFocus = FocusNode();
  final TextEditingController _searchController = TextEditingController();
  String _search = '';
  bool _searching = false;

  @override
  void initState() {
    super.initState();
    _loadFolders();
    _searchController.addListener(() {
      final v = _searchController.text.trim().toLowerCase();
      if (v != _search) setState(() => _search = v);
    });
  }

  @override
  void dispose() {
    _quickAddController.dispose();
    _quickAddFocus.dispose();
    _searchController.dispose();
    super.dispose();
  }

  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  List<String> get _allFolderNames => [_defaultFolderName, ..._folders];

  Future<void> _loadFolders() async {
    final uid = _uid;
    if (uid == null) return;

    try {
      final doc = await getFirestore().collection('user_settings').doc(uid).get();
      if (doc.exists) {
        final settings = UserSettings.fromMap(doc.data()!);
        if (mounted) {
          setState(() {
            _folders = settings.taskFolders;
            _foldersLoaded = true;
            _defaultFolderName = settings.defaultFolderName;
            _folderActivities = settings.folderActivities;
            _topTasksLimit = settings.topTasksLimit;
            _recentActivities = settings.customActivities;
            _allActivities = [...kDefaultActivities, ...settings.customActivities];
            for (var f in _folders) {
              _folderExpansions.putIfAbsent(f, () => true);
            }
            _folderExpansions.putIfAbsent(_defaultFolderName, () => true);
          });
        }
      } else {
        if (mounted) setState(() => _foldersLoaded = true);
      }
    } catch (e) {
      debugPrint('Error loading folders: $e');
      if (mounted) setState(() => _foldersLoaded = true);
    }
  }

  // ---------------------------------------------------------------------------
  // Folders
  // ---------------------------------------------------------------------------

  Future<void> _createFolder(String name) async {
    if (name.isEmpty || _folders.contains(name)) return;
    final uid = _uid;
    if (uid == null) return;

    try {
      final settingsRef = getFirestore().collection('user_settings').doc(uid);
      final newFolders = [..._folders, name];
      await settingsRef.set({'taskFolders': newFolders}, SetOptions(merge: true));
      setState(() {
        _folders = newFolders;
        _folderExpansions[name] = true;
      });
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error creating folder: $e')));
    }
  }

  Future<void> _deleteFolder(String name) async {
    final uid = _uid;
    if (uid == null) return;

    try {
      final settingsRef = getFirestore().collection('user_settings').doc(uid);
      final newFolders = List<String>.from(_folders)..remove(name);
      await settingsRef.set({'taskFolders': newFolders}, SetOptions(merge: true));

      final tasksQuery = await getFirestore()
          .collection('tasks')
          .where('userId', isEqualTo: uid)
          .where('folder', isEqualTo: name)
          .get();

      final batch = getFirestore().batch();
      for (var doc in tasksQuery.docs) {
        batch.update(doc.reference, {'folder': null});
      }
      await batch.commit();

      setState(() {
        _folders = newFolders;
        _folderExpansions.remove(name);
        if (_selectedFolder == name) _selectedFolder = null;
      });
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error deleting folder: $e')));
    }
  }

  Future<void> _renameFolder(String oldName, String newName) async {
    if (newName.isEmpty || _folders.contains(newName)) return;
    final uid = _uid;
    if (uid == null) return;

    if (oldName == _defaultFolderName) {
      if (newName == _defaultFolderName) return;
      try {
        final settingsRef = getFirestore().collection('user_settings').doc(uid);
        await settingsRef.set({'defaultFolderName': newName}, SetOptions(merge: true));
        setState(() {
          final expanded = _folderExpansions[oldName] ?? true;
          _folderExpansions.remove(oldName);
          _folderExpansions[newName] = expanded;
          _defaultFolderName = newName;
        });
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error renaming default folder: $e')));
      }
      return;
    }

    try {
      final settingsRef = getFirestore().collection('user_settings').doc(uid);
      int idx = _folders.indexOf(oldName);
      if (idx == -1) return;

      final newFolders = List<String>.from(_folders);
      newFolders[idx] = newName;
      await settingsRef.set({'taskFolders': newFolders}, SetOptions(merge: true));

      final tasksQuery = await getFirestore()
          .collection('tasks')
          .where('userId', isEqualTo: uid)
          .where('folder', isEqualTo: oldName)
          .get();

      final batch = getFirestore().batch();
      for (var doc in tasksQuery.docs) {
        batch.update(doc.reference, {'folder': newName});
      }
      await batch.commit();

      setState(() {
        _folders = newFolders;
        final expanded = _folderExpansions[oldName] ?? true;
        _folderExpansions.remove(oldName);
        _folderExpansions[newName] = expanded;
        if (_selectedFolder == oldName) _selectedFolder = newName;
      });
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error renaming folder: $e')));
    }
  }

  Future<String?> _promptCustomActivity() async {
    final custom = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final c = TextEditingController();
        return AlertDialog(
          title: const Text('Custom Activity'),
          content: TextField(
            controller: c,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(hintText: 'Activity Name'),
            onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            TextButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('Save')),
          ],
        );
      },
    );
    if (custom == null || custom.isEmpty) return null;

    if (!_recentActivities.contains(custom)) {
      setState(() {
        _recentActivities.insert(0, custom);
        if (_recentActivities.length > 10) _recentActivities.removeLast();
        if (!_allActivities.contains(custom)) _allActivities.add(custom);
      });
      final uid = _uid;
      if (uid != null) {
        getFirestore().collection('user_settings').doc(uid).set({
          'customActivities': FieldValue.arrayUnion([custom])
        }, SetOptions(merge: true));
      }
    }
    return custom;
  }

  Future<void> _setFolderActivity(String folderName, {String? explicitActivity}) async {
    final currentActivity = _folderActivities[folderName] ?? '';

    final picked = explicitActivity ??
        await showActivityPicker(
          context: context,
          allActivities: _allActivities,
          recent: _recentActivities,
        );
    if (picked == null) return;

    String finalActivity = picked;
    if (picked == '__custom') {
      final custom = await _promptCustomActivity();
      if (custom == null) return;
      finalActivity = custom;
    }

    if (finalActivity != currentActivity) {
      final uid = _uid;
      if (uid == null) return;
      try {
        final settingsRef = getFirestore().collection('user_settings').doc(uid);
        final newMap = Map<String, String>.from(_folderActivities);
        if (finalActivity.isEmpty) {
          newMap.remove(folderName);
        } else {
          newMap[folderName] = finalActivity;
        }
        await settingsRef.set({'folderActivities': newMap}, SetOptions(merge: true));
        setState(() => _folderActivities = newMap);
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error setting folder activity: $e')));
      }
    }
  }

  Future<void> _newFolderFlow() async {
    final c = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New Folder'),
        content: TextField(
          controller: c,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Folder Name'),
          textCapitalization: TextCapitalization.sentences,
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('Next')),
        ],
      ),
    );
    if (name == null || name.isEmpty || !mounted) return;

    final pickedActivity = await showActivityPicker(
      context: context,
      allActivities: _allActivities,
      recent: _recentActivities,
    );
    if (pickedActivity == null) return;

    String finalActivity = pickedActivity;
    if (pickedActivity == '__custom') {
      if (!mounted) return;
      final custom = await _promptCustomActivity();
      if (custom == null) return;
      finalActivity = custom;
    }

    await _createFolder(name);
    if (mounted) await _setFolderActivity(name, explicitActivity: finalActivity);
  }

  // ---------------------------------------------------------------------------
  // Tasks CRUD
  // ---------------------------------------------------------------------------

  String? _activityForFolder(String? folder) => _folderActivities[folder ?? _defaultFolderName];

  Future<void> _addTask({
    required String title,
    required int estimatedMinutes,
    required bool isToday,
    String? folder,
    String? activity,
    DateTime? scheduledDate,
    String notes = '',
    String? repeat,
  }) async {
    if (title.isEmpty) return;
    final uid = _uid;
    if (uid == null) return;

    try {
      final docRef = getFirestore().collection('tasks').doc();
      final now = DateTime.now();
      final newTask = Task(
        id: docRef.id,
        userId: uid,
        title: title,
        notes: notes,
        isToday: isToday,
        estimatedMinutes: estimatedMinutes,
        createdAt: now,
        folder: folder,
        activity: activity,
        scheduledDate: scheduledDate,
        repeat: repeat,
        // Negative so new tasks land at the top of their folder.
        sortOrder: -now.millisecondsSinceEpoch,
      );
      await docRef.set(newTask.toMap());
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error adding task: $e')));
    }
  }

  Future<void> _quickAdd() async {
    final raw = _quickAddController.text.trim();
    if (raw.isEmpty) return;
    final parsed = TaskQuickAdd.parse(raw, knownFolders: _allFolderNames);
    String? folder = parsed.folder;
    if (folder == null) {
      folder = _selectedFolder;
    } else if (folder == _defaultFolderName) {
      folder = null;
    }
    await _addTask(
      title: parsed.title,
      estimatedMinutes: parsed.estimatedMinutes ?? 30,
      isToday: parsed.isToday,
      folder: folder,
      activity: _activityForFolder(folder),
      scheduledDate: parsed.scheduledDate,
    );
    _quickAddController.clear();
    _quickAddFocus.requestFocus();
  }

  Future<void> _showTaskBottomSheet({Task? taskToEdit}) async {
    final isEditing = taskToEdit != null;
    final titleController = TextEditingController(text: taskToEdit?.title ?? '');
    final notesController = TextEditingController(text: taskToEdit?.notes ?? '');
    int estimatedMinutes = taskToEdit?.estimatedMinutes ?? 30;
    bool isToday = taskToEdit?.isToday ?? false;
    String? selectedFolder = taskToEdit?.folder ?? _selectedFolder;
    DateTime? scheduledDate = taskToEdit?.scheduledDate;
    String? repeat = taskToEdit?.repeat;

    void submit(BuildContext ctx) {
      final text = titleController.text.trim();
      if (text.isEmpty) return;
      final derivedActivity = _activityForFolder(selectedFolder);
      Navigator.pop(ctx);
      if (isEditing) {
        _updateTaskFull(taskToEdit, text, notesController.text.trim(), estimatedMinutes, isToday, selectedFolder,
            derivedActivity, scheduledDate, repeat);
      } else {
        _addTask(
          title: text,
          notes: notesController.text.trim(),
          estimatedMinutes: estimatedMinutes,
          isToday: isToday,
          folder: selectedFolder,
          activity: derivedActivity,
          scheduledDate: scheduledDate,
          repeat: repeat,
        );
      }
    }

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setSheetState) {
          final theme = Theme.of(context);
          return Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom + 20, left: 20, right: 20, top: 20),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Text(isEditing ? 'Edit Task' : 'New Task', style: theme.textTheme.titleLarge),
                      const Spacer(),
                      if (isEditing)
                        Text('Created ${DateFormat('MMM d').format(taskToEdit.createdAt)}',
                            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: titleController,
                    autofocus: true,
                    decoration: const InputDecoration(hintText: 'What needs to be done?', border: OutlineInputBorder()),
                    textCapitalization: TextCapitalization.sentences,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => submit(ctx),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: notesController,
                    minLines: 2,
                    maxLines: 6,
                    decoration: const InputDecoration(
                      hintText: 'Notes, links, sub-steps…',
                      border: OutlineInputBorder(),
                      alignLabelWithHint: true,
                    ),
                    textCapitalization: TextCapitalization.sentences,
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      InputChip(
                        avatar: const Icon(Icons.folder_open, size: 16),
                        label: Text(selectedFolder ?? _defaultFolderName),
                        onPressed: () async {
                          final chosen = await _pickFolder(context, current: selectedFolder);
                          if (chosen != null) {
                            setSheetState(() => selectedFolder = chosen == _kInboxSentinel ? null : chosen);
                          }
                        },
                      ),
                      InputChip(
                        avatar: const Icon(Icons.timer_outlined, size: 16),
                        label: Text(estimatedMinutes >= 60
                            ? '${(estimatedMinutes / 60).toStringAsFixed(estimatedMinutes % 60 == 0 ? 0 : 1)}h'
                            : '${estimatedMinutes}m'),
                        tooltip: 'Click to cycle estimate',
                        onPressed: () {
                          setSheetState(() {
                            const steps = [15, 30, 45, 60, 90, 120, 180, 240];
                            final idx = steps.indexOf(estimatedMinutes);
                            estimatedMinutes = steps[(idx + 1) % steps.length];
                          });
                        },
                      ),
                      FilterChip(
                        label: const Text('Today'),
                        avatar: isToday ? null : const Icon(Icons.wb_sunny_outlined, size: 16),
                        selected: isToday,
                        onSelected: (val) => setSheetState(() => isToday = val),
                        selectedColor: Colors.orange.withValues(alpha: 0.2),
                        checkmarkColor: Colors.orange,
                        labelStyle: TextStyle(color: isToday ? Colors.orange[800] : null),
                      ),
                      InputChip(
                        avatar: Icon(Icons.calendar_today, size: 16, color: scheduledDate != null ? Colors.blue : null),
                        label: Text(scheduledDate == null ? 'Schedule' : DateFormat('EEE, MMM d').format(scheduledDate!)),
                        onPressed: () async {
                          final now = DateTime.now();
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: scheduledDate ?? now,
                            firstDate: now.subtract(const Duration(days: 365)),
                            lastDate: now.add(const Duration(days: 365)),
                          );
                          if (picked != null) setSheetState(() => scheduledDate = picked);
                        },
                        onDeleted: scheduledDate != null ? () => setSheetState(() => scheduledDate = null) : null,
                      ),
                      InputChip(
                        avatar: Icon(Icons.repeat, size: 16, color: repeat != null ? Colors.teal : null),
                        label: Text(repeat == null ? 'Repeat' : TaskRepeat.label(repeat)),
                        onPressed: () async {
                          final picked = await _pickRepeat(context, current: repeat);
                          if (picked != null) setSheetState(() => repeat = picked.isEmpty ? null : picked);
                        },
                        onDeleted: repeat != null ? () => setSheetState(() => repeat = null) : null,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      if (isEditing)
                        TextButton.icon(
                          style: TextButton.styleFrom(foregroundColor: theme.colorScheme.error),
                          onPressed: () async {
                            Navigator.pop(ctx);
                            await _deleteTask(taskToEdit.id);
                          },
                          icon: const Icon(Icons.delete_outline),
                          label: const Text('Delete'),
                        ),
                      const Spacer(),
                      FilledButton(
                        onPressed: () => submit(ctx),
                        child: Text(isEditing ? 'Save Changes' : 'Add Task'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// Returns the chosen rule, '' for "no repeat", or null when cancelled.
  Future<String?> _pickRepeat(BuildContext context, {String? current}) {
    const options = <String, String>{
      '': 'Does not repeat',
      'daily': 'Every day',
      'weekdays': 'Weekdays',
      'weekly:mon': 'Every Monday',
      'weekly:fri': 'Every Friday',
      'weekly:sat': 'Every Saturday',
      'weekly:sun': 'Every Sunday',
      'monthly:1': 'Monthly on the 1st',
    };
    return showDialog<String>(
      context: context,
      builder: (c) => SimpleDialog(
        title: const Text('Repeat'),
        children: [
          ...options.entries.map((e) => SimpleDialogOption(
                onPressed: () => Navigator.pop(c, e.key),
                child: Text(e.value,
                    style: TextStyle(fontWeight: (current ?? '') == e.key ? FontWeight.bold : null)),
              )),
          SimpleDialogOption(
            onPressed: () async {
              final ctrl = TextEditingController(text: current ?? '');
              final custom = await showDialog<String>(
                context: c,
                builder: (d) => AlertDialog(
                  title: const Text('Custom rule'),
                  content: TextField(
                    controller: ctrl,
                    autofocus: true,
                    decoration: const InputDecoration(hintText: 'weekly:mon,wed  ·  monthly:15'),
                    onSubmitted: (v) => Navigator.pop(d, v),
                  ),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancel')),
                    FilledButton(onPressed: () => Navigator.pop(d, ctrl.text), child: const Text('OK')),
                  ],
                ),
              );
              if (custom == null) return;
              final norm = TaskRepeat.normalize(custom);
              if (norm == null && custom.trim().isNotEmpty) {
                if (c.mounted) {
                  ScaffoldMessenger.of(c).showSnackBar(const SnackBar(content: Text('Could not understand that rule.')));
                }
                return;
              }
              if (c.mounted) Navigator.pop(c, norm ?? '');
            },
            child: const Text('Custom…'),
          ),
        ],
      ),
    );
  }

  Future<String?> _pickFolder(BuildContext context, {String? current}) {
    return showDialog<String>(
      context: context,
      builder: (c) => SimpleDialog(
        title: const Text('Select Folder'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(c, _kInboxSentinel),
            child: Row(children: [
              const Icon(Icons.inbox, size: 18),
              const SizedBox(width: 8),
              Text(_defaultFolderName, style: TextStyle(fontWeight: current == null ? FontWeight.bold : null)),
            ]),
          ),
          ..._folders.map((f) => SimpleDialogOption(
                onPressed: () => Navigator.pop(c, f),
                child: Row(children: [
                  const Icon(Icons.folder_outlined, size: 18),
                  const SizedBox(width: 8),
                  Text(f, style: TextStyle(fontWeight: current == f ? FontWeight.bold : null)),
                ]),
              )),
        ],
      ),
    );
  }

  Future<void> _updateTaskFull(Task task, String title, String notes, int mins, bool isToday, String? folder,
      String? activity, DateTime? scheduled, String? repeat) async {
    try {
      await getFirestore().collection('tasks').doc(task.id).update({
        'title': title,
        'notes': notes,
        'estimatedMinutes': mins,
        'isToday': isToday,
        'folder': folder,
        'activity': activity,
        'scheduledDate': scheduled != null ? Timestamp.fromDate(scheduled) : null,
        'repeat': repeat,
      });
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error updating task: $e')));
    }
  }

  Future<void> _toggleTaskStatus(Task task) async {
    final newStatus = !task.isCompleted;
    try {
      await getFirestore().collection('tasks').doc(task.id).update({
        'isCompleted': newStatus,
        'completedAt': newStatus ? Timestamp.fromDate(DateTime.now()) : null,
        if (newStatus) 'isToday': false,
      });
      String? rolledId;
      if (newStatus && task.isRepeating) {
        rolledId = await DayPlanService().rollRepeatingTask(task);
      }
      if (newStatus && mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Done: ${task.title}'),
          duration: const Duration(seconds: 3),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () {
              getFirestore().collection('tasks').doc(task.id).update({
                'isCompleted': false,
                'completedAt': null,
                'isToday': task.isToday,
              });
              if (rolledId != null) getFirestore().collection('tasks').doc(rolledId).delete();
            },
          ),
        ));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error updating task: $e')));
    }
  }

  Future<void> _setToday(Task task, bool value) async {
    try {
      await getFirestore().collection('tasks').doc(task.id).update({'isToday': value});
    } catch (_) {}
  }

  Future<void> _deleteTask(String taskId) async {
    try {
      await getFirestore().collection('tasks').doc(taskId).delete();
    } catch (_) {}
  }

  Future<void> _moveTaskToFolder(Task task) async {
    final chosen = await _pickFolder(context, current: task.folder);
    if (chosen == null) return;
    final folder = chosen == _kInboxSentinel ? null : chosen;
    try {
      await getFirestore().collection('tasks').doc(task.id).update({
        'folder': folder,
        'activity': _activityForFolder(folder),
      });
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error moving task: $e')));
    }
  }

  Future<void> _duplicateTask(Task task) async {
    await _addTask(
      title: task.title,
      notes: task.notes,
      estimatedMinutes: task.estimatedMinutes,
      isToday: false,
      folder: task.folder,
      activity: task.activity,
    );
  }

  Future<void> _clearDate(Task task) async {
    try {
      await getFirestore().collection('tasks').doc(task.id).update({'scheduledDate': null});
    } catch (_) {}
  }

  Future<void> _moveAllToToday(List<Task> tasks) async {
    final batch = getFirestore().batch();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    for (final t in tasks) {
      batch.update(getFirestore().collection('tasks').doc(t.id), {
        'isToday': true,
        'scheduledDate': Timestamp.fromDate(today),
      });
    }
    try {
      await batch.commit();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Future<void> _clearTodayFlags(List<Task> tasks) async {
    final batch = getFirestore().batch();
    for (final t in tasks) {
      batch.update(getFirestore().collection('tasks').doc(t.id), {'isToday': false});
    }
    try {
      await batch.commit();
    } catch (_) {}
  }

  Future<void> _persistOrder(List<Task> ordered) async {
    final batch = getFirestore().batch();
    for (int i = 0; i < ordered.length; i++) {
      if (ordered[i].sortOrder != i) {
        batch.update(getFirestore().collection('tasks').doc(ordered[i].id), {'sortOrder': i});
      }
    }
    try {
      await batch.commit();
    } catch (_) {}
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final uid = _uid;
    if (uid == null) return const Center(child: Text('Please log in'));
    if (!_foldersLoaded) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: _searching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                decoration: const InputDecoration(hintText: 'Search tasks…', border: InputBorder.none),
              )
            : SizedBox(
                height: 36,
                child: SegmentedButton<_TaskViewMode>(
                  segments: const [
                    ButtonSegment<_TaskViewMode>(
                        value: _TaskViewMode.folder, label: Text('Folders'), icon: Icon(Icons.folder_outlined, size: 16)),
                    ButtonSegment<_TaskViewMode>(
                        value: _TaskViewMode.date, label: Text('Schedule'), icon: Icon(Icons.calendar_today, size: 16)),
                  ],
                  selected: {_viewMode},
                  onSelectionChanged: (newSelection) => setState(() => _viewMode = newSelection.first),
                  style: const ButtonStyle(visualDensity: VisualDensity.compact, tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                ),
              ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: Icon(_searching ? Icons.close : Icons.search),
            tooltip: _searching ? 'Close search' : 'Search',
            onPressed: () => setState(() {
              _searching = !_searching;
              if (!_searching) _searchController.clear();
            }),
          ),
          IconButton(
            icon: const Icon(Icons.auto_awesome_motion),
            tooltip: 'AI Auto-Schedule',
            onPressed: () async {
              try {
                final qs = await getFirestore()
                    .collection('tasks')
                    .where('userId', isEqualTo: uid)
                    .where('isCompleted', isEqualTo: false)
                    .get();
                final tasks = qs.docs.map((d) => Task.fromFirestore(d)).toList();
                if (mounted) _showAIAutoSchedule(tasks);
              } catch (e) {
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
              }
            },
          ),
          if (_viewMode == _TaskViewMode.folder)
            IconButton(icon: const Icon(Icons.create_new_folder_outlined), tooltip: 'New Folder', onPressed: _newFolderFlow),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'tasks_fab',
        onPressed: () => _showTaskBottomSheet(),
        label: const Text('New Task'),
        icon: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          _buildQuickAdd(theme),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: getFirestore().collection('tasks').where('userId', isEqualTo: uid).snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) return Center(child: Text('Error: ${snapshot.error}'));
                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

                var allTasks = snapshot.data!.docs.map((d) => Task.fromFirestore(d)).toList();
                if (_search.isNotEmpty) {
                  allTasks = allTasks
                      .where((t) => t.title.toLowerCase().contains(_search) || t.notes.toLowerCase().contains(_search))
                      .toList();
                }

                if (_viewMode == _TaskViewMode.folder) return _buildFolderView(allTasks);
                return _buildDateView(allTasks);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickAdd(ThemeData theme) {
    final target = _selectedFolder ?? _defaultFolderName;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): () {
            _quickAddController.clear();
            _quickAddFocus.unfocus();
          },
        },
        child: TextField(
          controller: _quickAddController,
          focusNode: _quickAddFocus,
          textInputAction: TextInputAction.done,
          textCapitalization: TextCapitalization.sentences,
          onSubmitted: (_) => _quickAdd(),
          decoration: InputDecoration(
            hintText: 'Add to $target…  try "Call bank 30m today" or "#Work review PR tmr"',
            prefixIcon: const Icon(Icons.add),
            suffixIcon: ValueListenableBuilder<TextEditingValue>(
              valueListenable: _quickAddController,
              builder: (_, v, __) => v.text.trim().isEmpty
                  ? Tooltip(
                      message: 'Shortcuts: #folder · 30m / 1h · today · tomorrow · @fri',
                      child: Icon(Icons.info_outline, size: 18, color: theme.colorScheme.outline),
                    )
                  : IconButton(icon: const Icon(Icons.keyboard_return), tooltip: 'Add (Enter)', onPressed: _quickAdd),
            ),
            filled: true,
            fillColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          ),
        ),
      ),
    );
  }

  Widget _buildFolderView(List<Task> allTasks) {
    final Map<String, List<Task>> grouped = {_defaultFolderName: []};
    for (var f in _folders) {
      grouped[f] = [];
    }
    for (var task in allTasks) {
      final folder = (task.folder == null || !_folders.contains(task.folder)) ? _defaultFolderName : task.folder!;
      grouped.putIfAbsent(folder, () => []).add(task);
    }

    final todayDate = DateTime.now();
    final todayTasks = allTasks.where((t) => !t.isCompleted && t.isFocusOn(todayDate)).toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    final doneToday = allTasks.where((t) {
      if (!t.isCompleted || t.completedAt == null) return false;
      final n = DateTime.now();
      final c = t.completedAt!;
      return c.year == n.year && c.month == n.month && c.day == n.day;
    }).length;

    return ListView(
      padding: const EdgeInsets.only(bottom: 96),
      children: [
        if (_search.isEmpty) _buildTodaySection(todayTasks, doneToday),
        _buildFolderGroup(_defaultFolderName, grouped[_defaultFolderName]!),
        ..._folders.map((f) => _buildFolderGroup(f, grouped[f]!)),
      ],
    );
  }

  Widget _buildTodaySection(List<Task> todayTasks, int doneToday) {
    final theme = Theme.of(context);
    final totalMin = todayTasks.fold<int>(0, (s, t) => s + t.estimatedMinutes);
    final hours = totalMin / 60;
    final overCap = todayTasks.length > _topTasksLimit;
    final summary = todayTasks.isEmpty
        ? (doneToday > 0 ? '$doneToday done today' : 'Nothing planned — flag tasks with the sun icon')
        : '${todayTasks.length}${overCap ? '/$_topTasksLimit' : ''} task${todayTasks.length == 1 ? '' : 's'} · ${hours == hours.roundToDouble() ? hours.toInt() : hours.toStringAsFixed(1)}h'
            '${doneToday > 0 ? ' · $doneToday done' : ''}'
            '${overCap ? ' · more than your top $_topTasksLimit' : ''}';

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.orange.withValues(alpha: 0.25)),
      ),
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.wb_sunny, color: Colors.orange),
            title: Text('Today', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            subtitle: Text(summary),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'Plan tomorrow',
                  icon: const Icon(Icons.nightlight_outlined),
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const PlanTomorrowScreen()),
                  ),
                ),
                if (todayTasks.isNotEmpty)
                  TextButton(
                    onPressed: () => _clearTodayFlags(todayTasks),
                    child: const Text('Clear'),
                  ),
                Icon(_todayExpanded ? Icons.expand_less : Icons.expand_more),
              ],
            ),
            onTap: () => setState(() => _todayExpanded = !_todayExpanded),
          ),
          if (_todayExpanded && todayTasks.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: Row(
                children: [
                  FilledButton.tonalIcon(
                    onPressed: _placing ? null : () => _placeInWorkBlocks(todayTasks),
                    icon: _placing
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.schedule_send_outlined, size: 18),
                    label: const Text('Place in work blocks'),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Fills today\'s remaining work blocks in this order.',
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      maxLines: 2,
                    ),
                  ),
                ],
              ),
            ),
          if (_todayExpanded && todayTasks.isNotEmpty)
            ReorderableListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              buildDefaultDragHandles: false,
              itemCount: todayTasks.length,
              onReorder: (oldIndex, newIndex) {
                if (newIndex > oldIndex) newIndex--;
                final list = List<Task>.from(todayTasks);
                final item = list.removeAt(oldIndex);
                list.insert(newIndex, item);
                _persistOrder(list);
              },
              itemBuilder: (context, i) {
                final t = todayTasks[i];
                return KeyedSubtree(
                  key: ValueKey('today_${t.id}'),
                  child: _buildTaskTile(t, dragIndex: i, showFolder: true),
                );
              },
            ),
          if (_todayExpanded && todayTasks.isNotEmpty) const SizedBox(height: 8),
        ],
      ),
    );
  }

  Future<void> _placeInWorkBlocks(List<Task> todayTasks) async {
    final uid = _uid;
    if (uid == null || todayTasks.isEmpty) return;
    setState(() => _placing = true);
    try {
      final outcome = await DayPlanService().placeTasks(
        uid,
        DateTime.now(),
        todayTasks,
        folderActivities: _folderActivities,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text(outcome.summary()),
          duration: const Duration(seconds: 6),
          action: outcome.result.placements.isEmpty
              ? null
              : SnackBarAction(label: 'Today', onPressed: () => MainScaffold.selectTab(MainTab.today)),
        ));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not place tasks: $e')));
    } finally {
      if (mounted) setState(() => _placing = false);
    }
  }

  Widget _buildDateView(List<Task> allTasks) {
    final Map<String, List<Task>> grouped = {};
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));

    for (var task in allTasks) {
      if (task.isCompleted) continue;
      String key = 'No Date';
      if (task.scheduledDate != null) {
        final d = DateTime(task.scheduledDate!.year, task.scheduledDate!.month, task.scheduledDate!.day);
        if (d.isBefore(today)) {
          key = 'Overdue';
        } else if (d == today) {
          key = 'Today';
        } else if (d == tomorrow) {
          key = 'Tomorrow';
        } else {
          key = DateFormat('yyyy-MM-dd').format(d);
        }
      } else if (task.isToday) {
        key = 'Today';
      }
      grouped.putIfAbsent(key, () => []).add(task);
    }
    grouped.forEach((_, list) => list.sort((a, b) => a.sortOrder.compareTo(b.sortOrder)));

    final sortedKeys = grouped.keys.toList()
      ..sort((a, b) {
        int score(String k) {
          if (k == 'Overdue') return 0;
          if (k == 'Today') return 1;
          if (k == 'Tomorrow') return 2;
          if (k == 'No Date') return 999;
          return 3;
        }

        final sa = score(a);
        final sb = score(b);
        if (sa != sb) return sa.compareTo(sb);
        return a.compareTo(b);
      });

    if (sortedKeys.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.event_available, size: 64, color: Colors.grey[300]),
            const SizedBox(height: 16),
            Text('No scheduled tasks', style: TextStyle(color: Colors.grey[500], fontSize: 16)),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: 96),
      children: sortedKeys.map((key) {
        String title;
        if (key == 'Overdue') {
          title = 'Overdue';
        } else if (key == 'Today') {
          title = 'Today';
        } else if (key == 'Tomorrow') {
          title = 'Tomorrow';
        } else if (key == 'No Date') {
          title = 'Unscheduled';
        } else {
          final d = DateFormat('yyyy-MM-dd').parse(key);
          title = DateFormat('EEE, MMM d').format(d);
        }
        return _buildDateGroup(title, grouped[key]!);
      }).toList(),
    );
  }

  void _sortTasks(List<Task> list) {
    list.sort((a, b) {
      if (a.isCompleted != b.isCompleted) return a.isCompleted ? 1 : -1;
      if (a.isCompleted) {
        final ca = a.completedAt ?? a.createdAt;
        final cb = b.completedAt ?? b.createdAt;
        return cb.compareTo(ca);
      }
      return a.sortOrder.compareTo(b.sortOrder);
    });
  }

  Widget _buildFolderGroup(String folderName, List<Task> tasks) {
    final theme = Theme.of(context);
    final isInbox = folderName == _defaultFolderName;
    _sortTasks(tasks);
    final active = tasks.where((t) => !t.isCompleted).toList();
    final weekAgo = DateTime.now().subtract(const Duration(days: 14));
    final completed = tasks
        .where((t) => t.isCompleted && (t.completedAt == null || t.completedAt!.isAfter(weekAgo)))
        .toList();
    final showCompleted = _showCompleted[folderName] ?? false;
    final activity = _folderActivities[folderName];
    final totalMin = active.fold<int>(0, (s, t) => s + t.estimatedMinutes);

    return ExpansionTile(
      key: PageStorageKey('folder_$folderName'),
      initiallyExpanded: _folderExpansions[folderName] ?? true,
      onExpansionChanged: (val) {
        setState(() {
          _folderExpansions[folderName] = val;
          if (val) _selectedFolder = isInbox ? null : folderName;
        });
      },
      title: Row(
        children: [
          Flexible(
            child: Text(
              folderName,
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (active.isNotEmpty) ...[
            const SizedBox(width: 8),
            Text('${active.length} · ${(totalMin / 60).toStringAsFixed(totalMin % 60 == 0 ? 0 : 1)}h',
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ],
          if (activity != null && activity.isNotEmpty) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.blueAccent.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Colors.blueAccent.withValues(alpha: 0.2)),
              ),
              child: Text(displayActivity(activity),
                  style: const TextStyle(fontSize: 10, color: Colors.blueAccent, fontWeight: FontWeight.bold)),
            ),
          ],
        ],
      ),
      leading: Icon(isInbox ? Icons.inbox : Icons.folder_outlined, color: isInbox ? Colors.blue : Colors.grey[700]),
      trailing: PopupMenuButton<String>(
        icon: Icon(Icons.more_horiz, size: 20, color: Colors.grey[600]),
        onSelected: (val) async {
          if (val == 'add') {
            setState(() => _selectedFolder = isInbox ? null : folderName);
            _quickAddFocus.requestFocus();
          } else if (val == 'rename') {
            final c = TextEditingController(text: folderName);
            final newName = await showDialog<String>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('Rename Folder'),
                content: TextField(
                  controller: c,
                  autofocus: true,
                  textCapitalization: TextCapitalization.sentences,
                  onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
                ),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                  TextButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('Rename')),
                ],
              ),
            );
            if (newName != null && newName.isNotEmpty && newName != folderName) _renameFolder(folderName, newName);
          } else if (val == 'activity') {
            _setFolderActivity(folderName);
          } else if (val == 'today_all') {
            _moveAllToToday(active);
          } else if (val == 'delete') {
            final confirm = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('Delete Folder?'),
                content: const Text('Tasks in this folder will be moved to Inbox.'),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                  TextButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Delete', style: TextStyle(color: Colors.red))),
                ],
              ),
            );
            if (confirm == true) _deleteFolder(folderName);
          }
        },
        itemBuilder: (ctx) => [
          const PopupMenuItem(value: 'add', child: Text('Add task here')),
          if (active.isNotEmpty) const PopupMenuItem(value: 'today_all', child: Text('Move all to Today')),
          const PopupMenuItem(value: 'rename', child: Text('Rename')),
          PopupMenuItem(
            value: 'activity',
            child: Text(activity == null ? 'Set default activity' : 'Default activity: ${displayActivity(activity)}'),
          ),
          if (!isInbox) const PopupMenuItem(value: 'delete', child: Text('Delete', style: TextStyle(color: Colors.red))),
        ],
      ),
      children: [
        if (active.isEmpty && completed.isEmpty)
          const ListTile(
            dense: true,
            title: Text('No tasks — type above and press Enter', style: TextStyle(fontStyle: FontStyle.italic, color: Colors.grey)),
          ),
        if (active.isNotEmpty)
          ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            itemCount: active.length,
            onReorder: (oldIndex, newIndex) {
              if (newIndex > oldIndex) newIndex--;
              final list = List<Task>.from(active);
              final item = list.removeAt(oldIndex);
              list.insert(newIndex, item);
              _persistOrder(list);
            },
            itemBuilder: (context, i) => KeyedSubtree(
              key: ValueKey('f_${active[i].id}'),
              child: _buildTaskTile(active[i], dragIndex: i),
            ),
          ),
        if (completed.isNotEmpty)
          TextButton.icon(
            onPressed: () => setState(() => _showCompleted[folderName] = !showCompleted),
            icon: Icon(showCompleted ? Icons.expand_less : Icons.expand_more, size: 18),
            label: Text('${showCompleted ? 'Hide' : 'Show'} ${completed.length} completed'),
          ),
        if (completed.isNotEmpty && showCompleted) ...completed.map((t) => _buildTaskTile(t)),
        const SizedBox(height: 4),
      ],
    );
  }

  Widget _buildDateGroup(String title, List<Task> tasks) {
    _dateExpansions[title] ??= (title == 'Overdue' || title == 'Today' || title == 'Tomorrow');
    final count = tasks.where((t) => !t.isCompleted).length;
    Color? color;
    if (title == 'Overdue') {
      color = Colors.red;
    } else if (title == 'Today') {
      color = Colors.orange;
    } else if (title == 'Tomorrow') {
      color = Colors.blue;
    }

    return ExpansionTile(
      key: PageStorageKey('date_$title'),
      initiallyExpanded: _dateExpansions[title] ?? false,
      onExpansionChanged: (val) => setState(() => _dateExpansions[title] = val),
      title: Text('$title${count > 0 ? ' ($count)' : ''}', style: TextStyle(fontWeight: FontWeight.bold, color: color)),
      leading: Icon(Icons.calendar_today, color: color),
      trailing: title == 'Overdue'
          ? TextButton(onPressed: () => _moveAllToToday(tasks), child: const Text('Move all to today'))
          : null,
      children: tasks.isEmpty
          ? [const ListTile(title: Text('No tasks', style: TextStyle(fontStyle: FontStyle.italic, color: Colors.grey)))]
          : tasks.map((t) => _buildTaskTile(t, showFolder: true)).toList(),
    );
  }

  Widget _buildTaskTile(Task task, {int? dragIndex, bool showFolder = false}) {
    final folderLabel = showFolder ? (task.folder != null && _folders.contains(task.folder) ? task.folder : _defaultFolderName) : null;
    return TaskTile(
      key: ValueKey(task.id),
      task: task,
      dragIndex: dragIndex,
      folderLabel: folderLabel,
      onToggleStatus: () => _toggleTaskStatus(task),
      onDelete: () => _deleteTask(task.id),
      onEdit: () => _showTaskBottomSheet(taskToEdit: task),
      onToggleToday: (v) => _setToday(task, v),
      onSchedule: () => _showScheduleDialog(task),
      onMoveFolder: () => _moveTaskToFolder(task),
      onDuplicate: () => _duplicateTask(task),
      onClearDate: () => _clearDate(task),
    );
  }

  // ---------------------------------------------------------------------------
  // Timeline scheduling
  // ---------------------------------------------------------------------------

  Future<void> _showScheduleDialog(Task task) async {
    final now = DateTime.now();
    final initialDate = task.scheduledDate ?? now;

    final pickedDate = await showDatePicker(
      context: context,
      initialDate: initialDate.isBefore(now.subtract(const Duration(days: 365))) ? now : initialDate,
      firstDate: now.subtract(const Duration(days: 365)),
      lastDate: now.add(const Duration(days: 365)),
      helpText: 'Which day?',
    );
    if (pickedDate == null || !mounted) return;

    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: (now.hour + 1).clamp(6, 22), minute: 0),
      helpText: 'Start time on the timeline',
    );
    if (pickedTime == null) return;

    final start = DateTime(pickedDate.year, pickedDate.month, pickedDate.day, pickedTime.hour, pickedTime.minute);
    await _scheduleTaskToTimeline(task, start);
  }

  Future<void> _scheduleTaskToTimeline(Task task, DateTime start) async {
    final uid = _uid;
    if (uid == null) return;

    final batch = getFirestore().batch();
    final entriesRef = getFirestore().collection('timeline_entries').doc(uid).collection('entries');

    int duration = task.estimatedMinutes > 0 ? task.estimatedMinutes : 60;
    int remaining = duration;
    DateTime currentStart = start;

    String finalActivity = task.activity ?? '';
    if (finalActivity.isEmpty && task.folder != null && _folderActivities.containsKey(task.folder)) {
      finalActivity = _folderActivities[task.folder]!;
    }
    if (finalActivity.isEmpty) finalActivity = task.title;
    final String finalNotes = task.title;

    while (remaining > 0) {
      int chunk = remaining > 60 ? 60 : remaining;
      final end = currentStart.add(Duration(minutes: chunk));
      final docId = DateFormat('yyyyMMdd_HHmm').format(currentStart);

      batch.set(
          entriesRef.doc(docId),
          {
            'userId': uid,
            'date': DateFormat('yyyy-MM-dd').format(currentStart),
            'hour': currentStart.hour,
            'startTime': Timestamp.fromDate(currentStart),
            'endTime': Timestamp.fromDate(end),
            'planactivity': finalActivity,
            'planNotes': finalNotes,
          },
          SetOptions(merge: true));

      currentStart = end;
      remaining -= chunk;
    }

    try {
      final n = DateTime.now();
      final isToday = start.year == n.year && start.month == n.month && start.day == n.day;
      batch.update(getFirestore().collection('tasks').doc(task.id), {
        'scheduledDate': Timestamp.fromDate(start),
        'isToday': isToday,
      });
      await batch.commit();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Scheduled "${task.title}" at ${DateFormat('EEE h:mm a').format(start)}'),
        ));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error scheduling: $e')));
    }
  }

  Future<void> _showAIAutoSchedule(List<Task> availableTasks) async {
    if (availableTasks.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No active tasks to schedule.')));
      return;
    }
    await AIAutoScheduleDialog.show(
      context,
      tasks: availableTasks,
      folderActivities: _folderActivities,
      onGetHistory: _fetchHistory,
      onGetCurrentPlan: _fetchCurrentPlan,
      onScheduleGenerated: _applyAISchedule,
    );
  }

  Future<String> _fetchHistory(DateTime targetDate) async {
    final uid = _uid;
    if (uid == null) return '';

    final buffer = StringBuffer();
    final entriesRef = getFirestore().collection('timeline_entries').doc(uid).collection('entries');
    final endDate = targetDate.subtract(const Duration(days: 1));
    final startDate = endDate.subtract(const Duration(days: 7));
    final startStr = DateFormat('yyyy-MM-dd').format(startDate);
    final endStr = DateFormat('yyyy-MM-dd').format(endDate);

    try {
      final snapshot = await entriesRef
          .where('date', isGreaterThanOrEqualTo: startStr)
          .where('date', isLessThanOrEqualTo: endStr)
          .get();

      final entries = snapshot.docs.map((d) => TimelineEntry.fromFirestore(d)).toList();
      entries.sort((a, b) => a.startTime.compareTo(b.startTime));
      if (entries.isEmpty) return 'No history recorded.';

      String currentDay = '';
      for (final e in entries) {
        final dayStr = DateFormat('yyyy-MM-dd').format(e.startTime);
        if (dayStr != currentDay) {
          buffer.writeln('\nDate: $dayStr');
          currentDay = dayStr;
        }
        if (e.activity.isNotEmpty && e.activity != 'Sleep') {
          final time = DateFormat('HH:mm').format(e.startTime);
          buffer.writeln('  $time - ${e.activity}');
        }
      }
    } catch (e) {
      debugPrint('History fetch error: $e');
      return 'Error fetching history.';
    }
    return buffer.toString();
  }

  Future<String> _fetchCurrentPlan(DateTime targetDate) async {
    final uid = _uid;
    if (uid == null) return '';

    final dateStr = DateFormat('yyyy-MM-dd').format(targetDate);
    final entriesRef = getFirestore().collection('timeline_entries').doc(uid).collection('entries');

    try {
      final snapshot = await entriesRef.where('date', isEqualTo: dateStr).get();
      final entries = snapshot.docs.map((d) => TimelineEntry.fromFirestore(d)).toList();
      if (entries.isEmpty) return 'No existing plan.';

      entries.sort((a, b) => a.startTime.compareTo(b.startTime));
      final buffer = StringBuffer();
      for (final e in entries) {
        if (e.activity.isNotEmpty && e.activity != 'Sleep') {
          final time = DateFormat('HH:mm').format(e.startTime);
          buffer.writeln('$time - ${e.activity}');
        }
      }
      return buffer.toString();
    } catch (e) {
      return '';
    }
  }

  Future<void> _applyAISchedule(DateTime date, Map<String, String> schedule) async {
    final uid = _uid;
    if (uid == null) return;

    final batch = getFirestore().batch();
    final entriesRef = getFirestore().collection('timeline_entries').doc(uid).collection('entries');

    final taskSnap = await getFirestore()
        .collection('tasks')
        .where('userId', isEqualTo: uid)
        .where('isCompleted', isEqualTo: false)
        .get();
    final tasks = taskSnap.docs.map((d) => Task.fromFirestore(d)).toList();

    final sortedKeys = schedule.keys.toList()..sort();

    for (final key in sortedKeys) {
      final value = schedule[key]!;
      final timeParts = key.split(':');
      final hour = int.parse(timeParts[0]);
      final minute = int.parse(timeParts[1]);
      final start = DateTime(date.year, date.month, date.day, hour, minute);

      String finalActivity = value;
      String finalNotes = 'AI Scheduled';
      int durationMinutes = 60;

      Task? matchingTask;
      try {
        matchingTask = tasks.firstWhere((t) => t.title.toLowerCase() == value.toLowerCase());
        if (matchingTask.activity != null && matchingTask.activity!.isNotEmpty) {
          finalActivity = matchingTask.activity!;
        } else if (matchingTask.folder != null && _folderActivities.containsKey(matchingTask.folder)) {
          finalActivity = _folderActivities[matchingTask.folder]!;
        } else {
          finalActivity = matchingTask.title;
        }
        finalNotes = '${matchingTask.title} (AI Scheduled)';
        if (matchingTask.estimatedMinutes > 0) durationMinutes = matchingTask.estimatedMinutes;
      } catch (_) {}

      int remainingMinutes = durationMinutes;
      int offsetHours = 0;
      while (remainingMinutes > 0) {
        final blockStart = start.add(Duration(hours: offsetHours));
        final blockKey = DateFormat('HH:mm').format(blockStart);
        if (offsetHours > 0 && schedule.containsKey(blockKey)) break;

        final int minutesToWrite = (remainingMinutes >= 60) ? 60 : remainingMinutes;
        final docId = DateFormat('yyyyMMdd_HHmm').format(blockStart);
        batch.set(
            entriesRef.doc(docId),
            {
              'userId': uid,
              'date': DateFormat('yyyy-MM-dd').format(date),
              'hour': blockStart.hour,
              'startTime': Timestamp.fromDate(blockStart),
              'endTime': Timestamp.fromDate(blockStart.add(Duration(minutes: minutesToWrite))),
              'planactivity': finalActivity,
              'planNotes': finalNotes,
            },
            SetOptions(merge: true));

        remainingMinutes -= 60;
        offsetHours++;
      }
    }

    try {
      await batch.commit();

      final tasksQuery = await getFirestore()
          .collection('tasks')
          .where('userId', isEqualTo: uid)
          .where('isCompleted', isEqualTo: false)
          .get();
      final batchTasks = getFirestore().batch();
      bool updates = false;
      for (final doc in tasksQuery.docs) {
        final t = Task.fromFirestore(doc);
        if (schedule.values.any((act) => act.startsWith(t.title))) {
          final n = DateTime.now();
          final isToday = date.year == n.year && date.month == n.month && date.day == n.day;
          batchTasks.update(doc.reference, {'scheduledDate': Timestamp.fromDate(date), 'isToday': isToday});
          updates = true;
        }
      }
      if (updates) await batchTasks.commit();

      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Schedule applied for ${DateFormat('MM/dd').format(date)}!')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error applying schedule: $e')));
    }
  }
}
