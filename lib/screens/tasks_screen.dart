import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../models/task.dart';
import '../models/user_settings.dart';
import '../models/timeline_entry.dart';
import '../widgets/ai_scheduling_dialog.dart';
import '../widgets/activity_picker.dart';
import '../utils/activities.dart';
import '../main.dart'; // for getFirestore()
import '../widgets/task_tile.dart';

enum _TaskViewMode { folder, date }

class TasksScreen extends StatefulWidget {
  const TasksScreen({super.key});

  @override
  State<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends State<TasksScreen> {
  // _taskController removed
  bool _isToday = false;
  int _estimatedMinutes = 30;
  bool _isLoading = false;
  String? _selectedFolder; // null means Default/Inbox
  List<String> _folders = [];
  bool _foldersLoaded = false;
  String _defaultFolderName = 'Inbox';
  final Map<String, bool> _folderExpansions = {}; // Track expansion state
  _TaskViewMode _viewMode = _TaskViewMode.folder;
  final Map<String, bool> _dateExpansions = {}; 
  Map<String, String> _folderActivities = {}; 
  List<String> _allActivities = [];
  List<String> _recentActivities = []; 

  @override
  void initState() {
    super.initState();
    _loadFolders();
  }
  
  // ... (dispose, loadFolders, createFolder, deleteFolder, renameFolder, addTask, toggleTaskStatus, toggleToday, deleteTask - unchanged) ...
  // Wait, I cannot use "... unchanged ..." in replace_file_content.
  // I need to be careful with the range. 
  // The user asked me to replace up to line 466 (end of build).
  // I will target the class start and variables first.

  // ACTUALLY, I should do this in chunks.
  // Chunk 1: Enum and State Variables.
  // Chunk 2: AppBar actions.
  // Chunk 3: Build body grouping logic.

  // Let's restart the thought for tool call.




  @override
  void dispose() {
    // _taskController.dispose() removed
    super.dispose();
  }

  Future<void> _loadFolders() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    
    try {
      final doc = await getFirestore().collection('user_settings').doc(uid).get();
      if (doc.exists) {
        final settings = UserSettings.fromMap(doc.data()!);
        setState(() {
          _folders = settings.taskFolders;
          _foldersLoaded = true;
          _defaultFolderName = settings.defaultFolderName;
          _folderActivities = settings.folderActivities;
          _recentActivities = settings.customActivities; // Use user defined as recent? 
          // Actually, we usually fetch ALL predefined + custom.
          _allActivities = [...kDefaultActivities, ...settings.customActivities];
          
          // Initialize expansion states if new
          for (var f in _folders) {
            _folderExpansions.putIfAbsent(f, () => false); // collapsed by default? or true?
          }
          _folderExpansions.putIfAbsent(_defaultFolderName, () => true);
        });
      } else {
        setState(() => _foldersLoaded = true);
      }
    } catch (e) {
      print('Error loading folders: $e');
      setState(() => _foldersLoaded = true);
    }
  }

  Future<void> _createFolder(String name) async {
    if (name.isEmpty || _folders.contains(name)) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
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
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;

      try {
          final settingsRef = getFirestore().collection('user_settings').doc(uid);
          final newFolders = List<String>.from(_folders)..remove(name);
          await settingsRef.set({'taskFolders': newFolders}, SetOptions(merge: true));
          
          // Optionally move tasks to Inbox (remove folder field)
          final tasksQuery = await getFirestore().collection('tasks')
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
      
      // Special case for Default Folder
      if (oldName == _defaultFolderName) {
          if (newName == _defaultFolderName) return; // no change
          final uid = FirebaseAuth.instance.currentUser?.uid;
          if (uid == null) return;
          try {
              final settingsRef = getFirestore().collection('user_settings').doc(uid);
              await settingsRef.set({'defaultFolderName': newName}, SetOptions(merge: true));
              
              setState(() {
                  final expanded = _folderExpansions[oldName] ?? false;
                  _folderExpansions.remove(oldName);
                  _folderExpansions[newName] = expanded;
                  _defaultFolderName = newName;
              });
          } catch(e) {
               if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error renaming default folder: $e')));
          }
          return;
      }

      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;

      try {
          final settingsRef = getFirestore().collection('user_settings').doc(uid);
          int idx = _folders.indexOf(oldName);
          if (idx == -1) return;
          
          final newFolders = List<String>.from(_folders);
          newFolders[idx] = newName;
          
          await settingsRef.set({'taskFolders': newFolders}, SetOptions(merge: true));

           // Move tasks
          final tasksQuery = await getFirestore().collection('tasks')
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
              final expanded = _folderExpansions[oldName] ?? false;
              _folderExpansions.remove(oldName);
              _folderExpansions[newName] = expanded;
              if (_selectedFolder == oldName) _selectedFolder = newName;
          });
      } catch (e) {
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error renaming folder: $e')));
      }
  }

  Future<void> _setFolderActivity(String folderName) async {
      final currentActivity = _folderActivities[folderName] ?? '';
      
      // Use the reusable activity picker
      final picked = await showActivityPicker(
          context: context,
          allActivities: _allActivities,
          recent: _recentActivities,
      );

      if (picked == null) return;

      String finalActivity = picked;
      if (picked == '__custom') {
           // Prompt for custom activity
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
                      ),
                      actions: [
                          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                          TextButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('Save')),
                      ],
                  );
              }
           );
           if (custom == null || custom.isEmpty) return;
           finalActivity = custom;
           
           // Update recent/custom activities
           if (!_recentActivities.contains(custom)) {
               // Update UI
               setState(() {
                   _recentActivities.insert(0, custom);
                   if (_recentActivities.length > 10) _recentActivities.removeLast();
                   if (!_allActivities.contains(custom)) _allActivities.add(custom);
               });
               // Persist custom activity
               final uid = FirebaseAuth.instance.currentUser?.uid;
               if (uid != null) {
                   getFirestore().collection('user_settings').doc(uid).update({
                       'customActivities': FieldValue.arrayUnion([custom])
                   });
               }
           }
      }

      if (finalActivity != currentActivity) {
          final uid = FirebaseAuth.instance.currentUser?.uid;
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
              setState(() {
                  _folderActivities = newMap;
              });
          } catch (e) {
             if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error setting folder activity: $e')));
          }
      }
  }

  Future<void> _addTask({
      required String title, 
      required int estimatedMinutes, 
      required bool isToday, 
      String? folder, 
      String? activity,
      DateTime? scheduledDate,
  }) async {
    if (title.isEmpty) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    setState(() => _isLoading = true);

    try {
      final docRef = getFirestore().collection('tasks').doc();
      final newTask = Task(
        id: docRef.id,
        userId: uid,
        title: title,
        isToday: isToday,
        estimatedMinutes: estimatedMinutes,
        createdAt: DateTime.now(),
        folder: folder,
        activity: activity,
        scheduledDate: scheduledDate,
      );

      await docRef.set(newTask.toMap());
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Task added')));
        // Update recent activities logic if needed
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error adding task: $e')));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _showTaskBottomSheet({Task? taskToEdit}) async {
      final isEditing = taskToEdit != null;
      final titleController = TextEditingController(text: taskToEdit?.title ?? '');
      int estimatedMinutes = taskToEdit?.estimatedMinutes ?? 30;
      bool isToday = taskToEdit?.isToday ?? _isToday;
      String? selectedFolder = taskToEdit?.folder ?? _selectedFolder; // Default to current view's folder if any
      String? selectedActivity = taskToEdit?.activity;
      DateTime? scheduledDate = taskToEdit?.scheduledDate;

      await showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
          builder: (ctx) => StatefulBuilder(
              builder: (context, setSheetState) {
                  return Padding(
                      padding: EdgeInsets.only(
                          bottom: MediaQuery.of(context).viewInsets.bottom + 20, 
                          left: 20, 
                          right: 20, 
                          top: 20
                      ),
                      child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                              Text(
                                  isEditing ? 'Edit Task' : 'New Task', 
                                  style: Theme.of(context).textTheme.titleLarge
                              ),
                              const SizedBox(height: 16),
                              TextField(
                                  controller: titleController,
                                  autofocus: true,
                                  decoration: const InputDecoration(
                                      hintText: 'What needs to be done?',
                                      border: OutlineInputBorder(),
                                  ),
                                  textCapitalization: TextCapitalization.sentences,
                                  onSubmitted: (_) {
                                      // Trigger save
                                  },
                              ),
                              const SizedBox(height: 16),
                              SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  child: Row(
                                      children: [
                                          // Folder Selector
                                          InputChip(
                                              avatar: const Icon(Icons.folder_open, size: 16),
                                              label: Text(selectedFolder ?? _defaultFolderName),
                                              onPressed: () async {
                                                  // Show simple folder picker
                                                   final chosen = await showDialog<String>(
                                                      context: context,
                                                      builder: (c) => SimpleDialog(
                                                          title: const Text('Select Folder'),
                                                          children: [
                                                              SimpleDialogOption(
                                                                  child: Padding(padding: const EdgeInsets.all(8), child: Text(_defaultFolderName)),
                                                                  onPressed: () => Navigator.pop(c, '__INBOX__'),
                                                              ),
                                                              ..._folders.map((f) => SimpleDialogOption(
                                                                  child: Padding(padding: const EdgeInsets.all(8), child: Text(f)),
                                                                  onPressed: () => Navigator.pop(c, f),
                                                              )),
                                                          ],
                                                      )
                                                  );
                                                  
                                                  if (chosen != null) {
                                                      final newFolder = chosen == '__INBOX__' ? null : chosen;
                                                      setSheetState(() {
                                                          selectedFolder = newFolder;
                                                          // Auto-fill activity if empty and folder has default
                                                          if (newFolder != null && _folderActivities.containsKey(newFolder) && selectedActivity == null) {
                                                              selectedActivity = _folderActivities[newFolder];
                                                          }
                                                      });
                                                  }
                                              },
                                          ),
                                          const SizedBox(width: 8),
                                          
                                          // Estimate Selector
                                          InputChip(
                                              avatar: const Icon(Icons.timer_outlined, size: 16),
                                              label: Text(estimatedMinutes >= 60 ? '${(estimatedMinutes/60).toStringAsFixed(1)}h' : '${estimatedMinutes}m'),
                                              onPressed: () {
                                                  // Cycle through estimates? or show menu
                                                  // Simple toggle for now: 30 -> 60 -> 90 -> 120 -> 15 -> 30
                                                  setSheetState(() {
                                                      if (estimatedMinutes == 15) estimatedMinutes = 30;
                                                      else if (estimatedMinutes == 30) estimatedMinutes = 60;
                                                      else if (estimatedMinutes == 60) estimatedMinutes = 90;
                                                      else if (estimatedMinutes == 90) estimatedMinutes = 120;
                                                      else if (estimatedMinutes == 120) estimatedMinutes = 180;
                                                      else estimatedMinutes = 15;
                                                  });
                                              },
                                          ),
                                          const SizedBox(width: 8),
                                          
                                          // Today Toggle
                                          FilterChip(
                                              label: const Text('Today'),
                                              selected: isToday,
                                              onSelected: (val) => setSheetState(() => isToday = val),
                                              selectedColor: Colors.orange.withOpacity(0.2),
                                              checkmarkColor: Colors.orange,
                                              labelStyle: TextStyle(color: isToday ? Colors.orange[800] : null),
                                          ),
                                          const SizedBox(width: 8),

                                          // Date Picker
                                          InputChip(
                                              avatar: Icon(Icons.calendar_today, size: 16, color: scheduledDate != null ? Colors.blue : null),
                                              label: Text(scheduledDate == null ? 'Schedule' : DateFormat('MMM d').format(scheduledDate!)),
                                              onPressed: () async {
                                                  final now = DateTime.now();
                                                  final picked = await showDatePicker(
                                                      context: context,
                                                      initialDate: scheduledDate ?? now,
                                                      firstDate: now.subtract(const Duration(days: 365)),
                                                      lastDate: now.add(const Duration(days: 365)),
                                                  );
                                                  if (picked != null) {
                                                      setSheetState(() {
                                                          scheduledDate = picked;
                                                          // If picked is today, set isToday? 
                                                          // Or keep them separate? Logic in Task model implies they are separate flags but usually related.
                                                          // For now, let separate.
                                                      });
                                                  }
                                              },
                                              onDeleted: scheduledDate != null ? () => setSheetState(() => scheduledDate = null) : null,
                                          ),
                                      ],
                                  ),
                              ),
                              const SizedBox(height: 16),
                              Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                      TextButton.icon(
                                          icon: Icon(Icons.local_activity, color: selectedActivity != null ? Colors.blue : Colors.grey),
                                          label: Text(selectedActivity ?? 'Add Activity'),
                                          onPressed: () async {
                                              final picked = await showActivityPicker(
                                                  context: context,
                                                  allActivities: _allActivities,
                                                  recent: _recentActivities,
                                              );
                                              if (picked != null) {
                                                  String finalAct = picked;
                                                  if (picked == '__custom') {
                                                      // ... reuse custom logic ...
                                                  }
                                                  setSheetState(() => selectedActivity = finalAct);
                                              }
                                          },
                                      ),
                                      ElevatedButton(
                                          onPressed: () {
                                              final text = titleController.text.trim();
                                              if (text.isEmpty) return;
                                              
                                              Navigator.pop(ctx);
                                              
                                              if (isEditing) {
                                                  _updateTaskFull(taskToEdit!, text, estimatedMinutes, isToday, selectedFolder, selectedActivity, scheduledDate);
                                              } else {
                                                  _addTask(
                                                      title: text, 
                                                      estimatedMinutes: estimatedMinutes, 
                                                      isToday: isToday, 
                                                      folder: selectedFolder == '__INBOX__' ? null : selectedFolder, // Handle inbox
                                                      activity: selectedActivity,
                                                      scheduledDate: scheduledDate,
                                                  );
                                              }
                                          },
                                          child: Text(isEditing ? 'Save Changes' : 'Add Task'),
                                      )
                                  ],
                              )
                          ],
                      )
                  );
              }
          )
      );
  }

  Future<void> _updateTaskFull(Task task, String title, int mins, bool isToday, String? folder, String? activity, DateTime? scheduled) async {
       try {
          await getFirestore().collection('tasks').doc(task.id).update({
              'title': title,
              'estimatedMinutes': mins,
              'isToday': isToday,
              'folder': folder,
              'activity': activity,
              'scheduledDate': scheduled != null ? Timestamp.fromDate(scheduled) : null,
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
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error updating task: $e')),
        );
      }
    }
  }

  Future<void> _toggleToday(Task task) async {
    try {
      await getFirestore().collection('tasks').doc(task.id).update({
        'isToday': !task.isToday,
      });
    } catch (e) {
      // Handle error
    }
  }

  Future<void> _deleteTask(String taskId) async {
      try {
          await getFirestore().collection('tasks').doc(taskId).delete();
      } catch (e) {
          // Handle error
      }
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const Center(child: Text('Please log in'));

    if (!_foldersLoaded) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: SizedBox(
           height: 36,
           child: SegmentedButton<_TaskViewMode>(
              segments: const [
                  ButtonSegment<_TaskViewMode>(
                      value: _TaskViewMode.folder,
                      label: Text('Folders'),
                      icon: Icon(Icons.folder_outlined, size: 16),
                  ),
                  ButtonSegment<_TaskViewMode>(
                      value: _TaskViewMode.date,
                      label: Text('Timeline'),
                      icon: Icon(Icons.calendar_today, size: 16),
                  ),
              ],
              selected: {_viewMode},
              onSelectionChanged: (newSelection) {
                  setState(() => _viewMode = newSelection.first);
              },
              style: const ButtonStyle(
                  visualDensity: VisualDensity.compact,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
           ),
        ),
        centerTitle: true,
        actions: [
            IconButton(
              icon: const Icon(Icons.auto_awesome_motion),
              tooltip: 'AI Auto-Schedule',
              onPressed: () async {
                  final uid = FirebaseAuth.instance.currentUser?.uid;
                  if (uid == null) return;
                  
                  try {
                    final qs = await getFirestore().collection('tasks')
                      .where('userId', isEqualTo: uid)
                      .where('isCompleted', isEqualTo: false)
                      .get();
                    final tasks = qs.docs.map((d) => Task.fromFirestore(d)).toList();
                    if (mounted) _showAIAutoSchedule(tasks);
                  } catch(e) {
                    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
                  }
              },
            ),
            if (_viewMode == _TaskViewMode.folder)
              IconButton(
                  icon: const Icon(Icons.create_new_folder_outlined),
                  tooltip: 'New Folder',
                  onPressed: () async {
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
                              ),
                              actions: [
                                  TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                                  TextButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('Create')),
                              ],
                          )
                      );
                      if (name != null && name.isNotEmpty) {
                          await _createFolder(name);
                          if (mounted) {
                              // Ask for default activity?
                              final wantActivity = await showDialog<bool>(
                                  context: context,
                                  builder: (ctx) => AlertDialog(
                                      title: const Text('Set Default Activity?'),
                                      content: Text('Would you like to set a default activity for "$name"?'),
                                      actions: [
                                          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('No')),
                                          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Yes')),
                                      ],
                                  )
                              );
                              if (wantActivity == true && mounted) {
                                  await _setFolderActivity(name);
                              }
                          }
                      }
                  },
              ),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
            onPressed: () => _showTaskBottomSheet(),
            label: const Text('New Task'),
            icon: const Icon(Icons.add),
        ),
        body: StreamBuilder<QuerySnapshot>(
              stream: getFirestore()
                  .collection('tasks')
                  .where('userId', isEqualTo: uid)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(child: Text('Error: ${snapshot.error}'));
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final docs = snapshot.data!.docs;
                final allTasks = docs.map((d) => Task.fromFirestore(d)).toList();

                if (_viewMode == _TaskViewMode.folder) {
                    // --- Folder View Logic ---
                    final Map<String, List<Task>> grouped = {};
                    grouped[_defaultFolderName] = [];
                    for (var f in _folders) {
                        grouped[f] = [];
                    }

                    for (var task in allTasks) {
                        final folder = (task.folder == null || !_folders.contains(task.folder)) ? _defaultFolderName : task.folder!;
                        if (grouped[folder] == null) grouped[folder] = [];
                         grouped[folder]!.add(task);
                    }
                    grouped.forEach((_, list) => _sortTasks(list));

                    return ListView(
                      padding: const EdgeInsets.only(bottom: 80),
                      children: [
                          _buildFolderGroup(_defaultFolderName, grouped[_defaultFolderName]!),
                          ..._folders.map((f) => _buildFolderGroup(f, grouped[f]!)),
                      ],
                    );
                } else {
                    // --- Date View Logic ---
                    final Map<String, List<Task>> grouped = {};
                    
                    final now = DateTime.now();
                    final today = DateTime(now.year, now.month, now.day);
                    final tomorrow = today.add(const Duration(days: 1));

                    for (var task in allTasks) {
                        if (task.isCompleted) continue; // Hide completed in Date View
                        
                        String key = 'No Date';
                        if (task.scheduledDate != null) {
                            final d = DateTime(task.scheduledDate!.year, task.scheduledDate!.month, task.scheduledDate!.day);
                            if (d.isBefore(today)) {
                                key = "Overdue";
                            } else if (d == today) {
                                key = "Today";
                            } else if (d == tomorrow) {
                                key = "Tomorrow";
                            } else {
                                key = DateFormat('yyyy-MM-dd').format(d);
                            }
                        } else if (task.isToday) {
                            key = "Today";
                        }
                        
                        grouped.putIfAbsent(key, () => []).add(task);
                    }
                    
                    // Sort keys
                    final sortedKeys = grouped.keys.toList()..sort((a, b) {
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
                            )
                        );
                    }

                    return ListView(
                        padding: const EdgeInsets.only(bottom: 80),
                        children: sortedKeys.map((key) {
                           String title;
                            if (key == 'Overdue') title = 'Overdue';
                            else if (key == 'Today') title = 'Today';
                            else if (key == 'Tomorrow') title = 'Tomorrow';
                            else if (key == 'No Date') title = 'Unscheduled';
                            else {
                                final d = DateFormat('yyyy-MM-dd').parse(key);
                                title = DateFormat('EEE, MMM d').format(d);
                            }
                            return _buildDateGroup(title, grouped[key]!);
                        }).toList(),
                    );
                }
              },
            ),
    );
  }

   void _sortTasks(List<Task> list) {
        final completed = list.where((t) => t.isCompleted).toList();
        final active = list.where((t) => !t.isCompleted).toList();
        
        active.sort((a, b) {
            if (a.isToday && !b.isToday) return -1;
            if (!a.isToday && b.isToday) return 1;
            return b.createdAt.compareTo(a.createdAt);
        });

        // Hide old completed tasks (older than 7 days)
        final now = DateTime.now();
        final weekAgo = now.subtract(const Duration(days: 7));
        completed.removeWhere((t) => t.completedAt != null && t.completedAt!.isBefore(weekAgo));
        completed.sort((a, b) => b.createdAt.compareTo(a.createdAt));

        list.clear();
        list.addAll(active);
        list.addAll(completed);
  }

  Widget _buildFolderGroup(String folderName, List<Task> tasks) {
      final isInbox = folderName == _defaultFolderName;
      final count = tasks.where((t) => !t.isCompleted).length;
      final countStr = count > 0 ? ' ($count)' : '';
      final activity = _folderActivities[folderName];
      final activityStr = activity != null && activity.isNotEmpty ? '  [$activity]' : '';
      
      return ExpansionTile(
          key: PageStorageKey(folderName),
          initiallyExpanded: _folderExpansions[folderName] ?? false,
          onExpansionChanged: (val) {
              setState(() => _folderExpansions[folderName] = val);
              // auto-select folder when expanded? No, might be annoying.
              if (val && !isInbox && _selectedFolder != folderName) {
                  // Optional: Select this folder for new tasks if user expands it
                  setState(() => _selectedFolder = folderName);
              } else if (val && isInbox) {
                  setState(() => _selectedFolder = null);
              }
          },
          title: RichText(
            text: TextSpan(
              style: Theme.of(context).textTheme.titleMedium,
              children: [
                TextSpan(text: folderName + countStr, style: const TextStyle(fontWeight: FontWeight.bold)),
                if (activityStr.isNotEmpty)
                  TextSpan(text: activityStr, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.normal)),
              ]
            )
          ),
          leading: Icon(isInbox ? Icons.inbox : Icons.folder_outlined, color: isInbox ? Colors.blue : Colors.grey[700]),
          trailing: PopupMenuButton<String>(
              icon: Icon(Icons.settings_outlined, size: 20, color: Colors.grey[600]),
              onSelected: (val) async {
                  if (val == 'rename') {
                      final c = TextEditingController(text: folderName);
                      final newName = await showDialog<String>(
                          context: context, 
                          builder: (ctx) => AlertDialog(
                              title: const Text('Rename Folder'),
                              content: TextField(controller: c, autofocus: true, textCapitalization: TextCapitalization.sentences),
                              actions: [
                                  TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                                  TextButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('Rename')),
                              ],
                          )
                      );
                      if (newName != null && newName.isNotEmpty && newName != folderName) {
                          _renameFolder(folderName, newName);
                      }
                  } else if (val == 'activity') {
                      _setFolderActivity(folderName);
                  } else if (val == 'delete') {
                      final confirm = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                              title: const Text('Delete Folder?'),
                              content: const Text('Tasks in this folder will be moved to Inbox.'),
                              actions: [
                                  TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                                  TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete', style: TextStyle(color: Colors.red))),
                              ],
                          )
                      );
                      if (confirm == true) {
                          _deleteFolder(folderName);
                      }
                  }
              },
              itemBuilder: (ctx) {
                  final currentAct = _folderActivities[folderName];
                  return [
                    const PopupMenuItem(value: 'rename', child: Text('Rename')),
                    PopupMenuItem(
                        value: 'activity', 
                        child: Row(
                            children: [
                                const Text('Default Activity'),
                                if (currentAct != null) ...[
                                    const SizedBox(width: 8),
                                    Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                            color: Colors.blueAccent.withOpacity(0.1),
                                            borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(displayActivity(currentAct), style: const TextStyle(fontSize: 10, color: Colors.blueAccent)),
                                    )
                                ]
                            ],
                        )
                    ),
                    if (!isInbox) const PopupMenuItem(value: 'delete', child: Text('Delete', style: TextStyle(color: Colors.red))),
                  ];
              },
          ),
          children: tasks.isEmpty 
            ? [const ListTile(title: Text('No tasks', style: TextStyle(fontStyle: FontStyle.italic, color: Colors.grey)))]
            : tasks.map((t) => _buildTaskTile(t)).toList(),
      );
  }

  Widget _buildDateGroup(String title, List<Task> tasks) {
    if (_dateExpansions[title] == null) {
        // Expand Today and Tomorrow by default
        _dateExpansions[title] = (title == 'Today' || title == 'Tomorrow');
    }
    
    final count = tasks.where((t) => !t.isCompleted).length;
    final countStr = count > 0 ? ' ($count)' : '';
    Color? color;
    if (title == 'Overdue') color = Colors.red;
    else if (title == 'Today') color = Colors.orange;
    else if (title == 'Tomorrow') color = Colors.blue;

    return ExpansionTile(
       key: PageStorageKey(title),
       initiallyExpanded: _dateExpansions[title] ?? false,
       onExpansionChanged: (val) => setState(() => _dateExpansions[title] = val),
       title: Text(title + countStr, style: TextStyle(
          fontWeight: FontWeight.bold,
          color: color
       )),
       leading: Icon(Icons.calendar_today, color: color),
       children: tasks.isEmpty 
         ? [const ListTile(title: Text('No tasks', style: TextStyle(fontStyle: FontStyle.italic, color: Colors.grey)))]
         : tasks.map((t) => _buildTaskTile(t)).toList(),
    );
  }

  Widget _buildTaskTile(Task task) {
    return TaskTile(
        task: task,
        onToggleStatus: () => _toggleTaskStatus(task),
        onDelete: () => _deleteTask(task.id),
        onEdit: () => _showTaskBottomSheet(taskToEdit: task),
        onToggleToday: (_) => _toggleToday(task),
        onSchedule: () => _showScheduleDialog(task),
    );
  }

  Future<void> _showScheduleDialog(Task task) async {
      final now = DateTime.now();
      // Default to tomorrow 9am if not scheduled, or current scheduled date
      final initialDate = task.scheduledDate ?? now.add(const Duration(days: 1));
      
      final pickedDate = await showDatePicker(
          context: context, 
          initialDate: initialDate, 
          firstDate: now.subtract(const Duration(days: 365)), 
          lastDate: now.add(const Duration(days: 365)),
      );
      
      if (pickedDate != null && mounted) {
          final pickedTime = await showTimePicker(
              context: context, 
              initialTime: const TimeOfDay(hour: 9, minute: 0),
          );
          
          if (pickedTime != null) {
              final start = DateTime(
                  pickedDate.year, 
                  pickedDate.month, 
                  pickedDate.day, 
                  pickedTime.hour, 
                  pickedTime.minute
              );
              await _scheduleTaskToTimeline(task, start);
          }
      }
  }

  Future<void> _scheduleTaskToTimeline(Task task, DateTime start) async {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;
      
      final batch = getFirestore().batch();
      final entriesRef = getFirestore().collection('timeline_entries').doc(uid).collection('entries');

      int duration = task.estimatedMinutes > 0 ? task.estimatedMinutes : 60;
      int remaining = duration;
      DateTime currentStart = start;
      
      // Determine Activity
      String finalActivity = task.activity ?? '';
      if (finalActivity.isEmpty && task.folder != null && _folderActivities.containsKey(task.folder)) {
          finalActivity = _folderActivities[task.folder]!;
      }
      if (finalActivity.isEmpty) {
          finalActivity = task.title;
      }
      
      // Notes is the task title
      String finalNotes = task.title;

      while (remaining > 0) {
          int chunk = remaining;
          // Split at hour boundary logic?
          // To be perfectly safe and support visualization, we usually split at hour boundaries or simply max 60 mins.
          // Let's stick to max 60 min blocks for now to keep it simple and consistent.
          if (chunk > 60) chunk = 60;
          
          final end = currentStart.add(Duration(minutes: chunk));
          final docId = DateFormat('yyyyMMdd_HHmm').format(currentStart);
          
          batch.set(entriesRef.doc(docId), {
             'userId': uid,
             'date': DateFormat('yyyy-MM-dd').format(currentStart),
             'hour': currentStart.hour,
             'startTime': Timestamp.fromDate(currentStart),
             'endTime': Timestamp.fromDate(end),
             'planactivity': finalActivity,
             'planNotes': finalNotes,
          }, SetOptions(merge: true));
          
          currentStart = end;
          remaining -= chunk;
      }
      
      try {
          // Update Task as well
          final isToday = start.year == DateTime.now().year && start.month == DateTime.now().month && start.day == DateTime.now().day;
          batch.update(getFirestore().collection('tasks').doc(task.id), {
              'scheduledDate': Timestamp.fromDate(start),
              'isToday': isToday,
          });
          
          await batch.commit();
          if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Task scheduled on Timeline')));
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
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return '';

    // Fetch last 7 days from targetDate
    final buffer = StringBuffer();
    
    final entriesRef = getFirestore().collection('timeline_entries').doc(uid).collection('entries');
    
    // String comparison works for yyyy-MM-dd
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
      // Sort by start time
      entries.sort((a, b) => a.startTime.compareTo(b.startTime));

      if (entries.isEmpty) return "No history recorded.";

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
      print('History fetch error: $e');
      return "Error fetching history.";
    }

    return buffer.toString();
  }

  Future<String> _fetchCurrentPlan(DateTime targetDate) async {
     final uid = FirebaseAuth.instance.currentUser?.uid;
     if (uid == null) return '';
     
     final dateStr = DateFormat('yyyy-MM-dd').format(targetDate);
     final entriesRef = getFirestore().collection('timeline_entries').doc(uid).collection('entries');
     
     try {
       final snapshot = await entriesRef.where('date', isEqualTo: dateStr).get();
       final entries = snapshot.docs.map((d) => TimelineEntry.fromFirestore(d)).toList();
       if (entries.isEmpty) return "No existing plan.";
       
       entries.sort((a,b) => a.startTime.compareTo(b.startTime));
       final buffer = StringBuffer();
       for(final e in entries) {
          if (e.activity.isNotEmpty && e.activity != 'Sleep') {
             final time = DateFormat('HH:mm').format(e.startTime);
             buffer.writeln('$time - ${e.activity}');
          }
       }
       return buffer.toString();
     } catch (e) {
       return "";
     }
  }

  Future<void> _applyAISchedule(DateTime date, Map<String, String> schedule) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    
    // Batch write to timeline
    final batch = getFirestore().batch();
    final entriesRef = getFirestore().collection('timeline_entries').doc(uid).collection('entries');
    
    // Fetch active tasks for resolution
    // uid is already defined above
    
    final taskSnap = await getFirestore().collection('tasks')
        .where('userId', isEqualTo: uid)
        .where('isCompleted', isEqualTo: false)
        .get();
    final tasks = taskSnap.docs.map((d) => Task.fromFirestore(d)).toList();

    // Sort entries by time to ensure we process earliest first
    final sortedKeys = schedule.keys.toList()..sort();
    
    for (final key in sortedKeys) {
      final value = schedule[key]!;
      final timeParts = key.split(':');
      final hour = int.parse(timeParts[0]);
      final minute = int.parse(timeParts[1]);
      
      final start = DateTime(date.year, date.month, date.day, hour, minute);
      
      // Resolution Logic
      String finalActivity = value;
      String finalNotes = 'AI Scheduled';
      int durationMinutes = 60; // Default to 1 hour frame

      Task? matchingTask;
      // Find matching task by title (best effort)
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
          if (matchingTask.estimatedMinutes > 0) {
            durationMinutes = matchingTask.estimatedMinutes;
          }
          
      } catch (e) {
          // No matching task found, keep original value
      }
      
      // Calculate blocks needed based on remaining duration
      int remainingMinutes = durationMinutes;
      int offsetHours = 0;

      while (remainingMinutes > 0) {
        final blockStart = start.add(Duration(hours: offsetHours));
        final blockKey = DateFormat('HH:mm').format(blockStart);
        
        // Check for collision with explicit schedule in subsequent blocks
        if (offsetHours > 0 && schedule.containsKey(blockKey)) {
          break;
        }

        // Determine duration for this block (max 60 mins per hour slot)
        final int minutesToWrite = (remainingMinutes >= 60) ? 60 : remainingMinutes;

        final docId = DateFormat('yyyyMMdd_HHmm').format(blockStart);
        final docRef = entriesRef.doc(docId);
        
        final Map<String, dynamic> data = {
          'userId': uid,
          'date': DateFormat('yyyy-MM-dd').format(date),
          'hour': blockStart.hour,
          'startTime': Timestamp.fromDate(blockStart),
          'endTime': Timestamp.fromDate(blockStart.add(Duration(minutes: minutesToWrite))),
          'planactivity': finalActivity,
          'planNotes': finalNotes,
        };
        
        batch.set(docRef, data, SetOptions(merge: true));
        
        remainingMinutes -= 60; // Advance to next hour slot logic
        offsetHours++;
      }
    }
    
    try {
      await batch.commit();
      
      // Update task "scheduledDate" 
      final tasksQuery = await getFirestore().collection('tasks').where('userId', isEqualTo: uid).where('isCompleted', isEqualTo: false).get();
      final batchTasks = getFirestore().batch();
      bool updates = false;
      
      for (final doc in tasksQuery.docs) {
        final t = Task.fromFirestore(doc);
        if (schedule.values.any((act) => act.startsWith(t.title))) {
           final isToday = date.year == DateTime.now().year && date.month == DateTime.now().month && date.day == DateTime.now().day;
           batchTasks.update(doc.reference, {
             'scheduledDate': Timestamp.fromDate(date),
             'isToday': isToday,
           });
           updates = true;
        }
      }
      if (updates) await batchTasks.commit();
      
      if (mounted) {
        final dateStr = DateFormat('MM/dd').format(date);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Schedule applied for $dateStr!')));
      }
      
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error applying schedule: $e')));
    }
  }
}
