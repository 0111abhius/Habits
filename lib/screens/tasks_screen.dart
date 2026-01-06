import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/task.dart';
import '../models/user_settings.dart';
import '../main.dart'; // for getFirestore()

class TasksScreen extends StatefulWidget {
  const TasksScreen({super.key});

  @override
  State<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends State<TasksScreen> {
  final _taskController = TextEditingController();
  bool _isToday = false;
  int _estimatedMinutes = 30;
  bool _isLoading = false;
  String? _selectedFolder; // null means Default/Inbox
  List<String> _folders = [];
  bool _foldersLoaded = false;
  String _defaultFolderName = 'Inbox';
  final Map<String, bool> _folderExpansions = {}; // Track expansion state

  @override
  void initState() {
    super.initState();
    _loadFolders();
  }

  @override
  void dispose() {
    _taskController.dispose();
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

  Future<void> _addTask() async {
    final text = _taskController.text.trim();
    if (text.isEmpty) return;

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    setState(() => _isLoading = true);

    try {
      final docRef = getFirestore().collection('tasks').doc();
      final newTask = Task(
        id: docRef.id,
        userId: uid,
        title: text,
        isToday: _isToday,
        estimatedMinutes: _estimatedMinutes,
        createdAt: DateTime.now(),
        folder: _selectedFolder,
      );

      await docRef.set(newTask.toMap());

      if (mounted) {
        _taskController.clear();
        setState(() {
          _isToday = false;
          _estimatedMinutes = 30;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Task added')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error adding task: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
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
        title: const Text('Tasks'),
        actions: [
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
                        _createFolder(name);
                    }
                },
            ),
        ],
      ),
      body: Column(
        children: [
          // Input Section
          Material(
            elevation: 2,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                   Row(
                     children: [
                       Expanded(
                         child: TextField(
                           controller: _taskController,
                           decoration: const InputDecoration(
                             hintText: 'Add a new task...',
                             border: OutlineInputBorder(),
                           ),
                           onSubmitted: (_) => _addTask(),
                         ),
                       ),
                       const SizedBox(width: 8),
                       IconButton.filled(
                         onPressed: _isLoading ? null : _addTask,
                         icon: _isLoading 
                           ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) 
                           : const Icon(Icons.add),
                       ),
                     ],
                   ),
                   const SizedBox(height: 12),
                   SingleChildScrollView(
                     scrollDirection: Axis.horizontal,
                     child: Row(
                       children: [
                         // Folder Selector
                         DropdownButton<String?>(
                           value: _selectedFolder,
                           hint: Text(_defaultFolderName),
                           underline: Container(),
                           items: [
                               DropdownMenuItem(value: null, child: Text(_defaultFolderName)),
                               ..._folders.map((f) => DropdownMenuItem(value: f, child: Text(f))),
                           ],
                           onChanged: (val) {
                               setState(() => _selectedFolder = val);
                           },
                         ),
                         const SizedBox(width: 12),
                         FilterChip(
                           label: const Text('Do Today'),
                           selected: _isToday,
                           onSelected: (val) => setState(() => _isToday = val),
                         ),
                         const SizedBox(width: 12),
                         const Text('Estimate: '),
                         DropdownButton<int>(
                           value: _estimatedMinutes,
                           underline: Container(),
                           items: [30, 60, 90, 120, 150, 180, 240, 300].map((m) {
                             final hours = m / 60;
                             final label = hours == hours.toInt() 
                               ? '${hours.toInt()}h' 
                               : '${hours.toStringAsFixed(1)}h';
                             return DropdownMenuItem(value: m, child: Text(label));
                           }).toList(),
                           onChanged: (val) {
                             if (val != null) setState(() => _estimatedMinutes = val);
                           },
                         ),
                       ],
                     ),
                   ),
                ],
              ),
            ),
          ),
          
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
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

                // Group tasks
                final Map<String, List<Task>> grouped = {};
                // Initialize groups
                grouped[_defaultFolderName] = [];
                for (var f in _folders) {
                    grouped[f] = [];
                }

                for (var task in allTasks) {
                    final folder = (task.folder == null || !_folders.contains(task.folder)) ? _defaultFolderName : task.folder!;
                    if (grouped[folder] == null) grouped[folder] = []; // explicit null check mostly redundant due to init above but safe
                     grouped[folder]!.add(task);
                }

                // Sorting helper
                void sortTasks(List<Task> list) {
                    final completed = list.where((t) => t.isCompleted).toList();
                    final active = list.where((t) => !t.isCompleted).toList();
                    
                    active.sort((a, b) {
                        if (a.isToday && !b.isToday) return -1;
                        if (!a.isToday && b.isToday) return 1;
                        return b.createdAt.compareTo(a.createdAt);
                    });

                    // Hide old completed tasks? The original code hid > 7 days.
                    final now = DateTime.now();
                    final weekAgo = now.subtract(const Duration(days: 7));
                    completed.removeWhere((t) => t.completedAt != null && t.completedAt!.isBefore(weekAgo));
                    completed.sort((a, b) => b.createdAt.compareTo(a.createdAt));

                    list.clear();
                    list.addAll(active);
                    list.addAll(completed);
                }

                grouped.forEach((_, list) => sortTasks(list));

                return ListView(
                  padding: const EdgeInsets.only(bottom: 80),
                  children: [
                      // Inbox First
                      _buildFolderGroup(_defaultFolderName, grouped[_defaultFolderName]!),
                      // Then user folders
                      ..._folders.map((f) => _buildFolderGroup(f, grouped[f]!)),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFolderGroup(String folderName, List<Task> tasks) {
      final isInbox = folderName == _defaultFolderName;
      final count = tasks.where((t) => !t.isCompleted).length;
      final countStr = count > 0 ? ' ($count)' : '';
      
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
          title: Text(folderName + countStr, style: const TextStyle(fontWeight: FontWeight.bold)),
          leading: Icon(isInbox ? Icons.inbox : Icons.folder_outlined, color: isInbox ? Colors.blue : Colors.grey[700]),
          trailing: isInbox 
            ? PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert),
              onSelected: (val) async {
                  if (val == 'rename') {
                      final c = TextEditingController(text: folderName);
                      final newName = await showDialog<String>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                              title: const Text('Rename Default Folder'),
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
                  }
              },
              itemBuilder: (ctx) => [
                  const PopupMenuItem(value: 'rename', child: Text('Rename')),
              ],
            )
            : PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert),
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
              itemBuilder: (ctx) => [
                  const PopupMenuItem(value: 'rename', child: Text('Rename')),
                  const PopupMenuItem(value: 'delete', child: Text('Delete', style: TextStyle(color: Colors.red))),
              ],
          ),
          children: tasks.isEmpty 
            ? [const ListTile(title: Text('No tasks', style: TextStyle(fontStyle: FontStyle.italic, color: Colors.grey)))]
            : tasks.map((t) => _buildTaskTile(t)).toList(),
      );
  }

  Widget _buildTaskTile(Task task) {
    final hours = task.estimatedMinutes / 60;
    final timeLabel = hours == hours.toInt() ? '${hours.toInt()}h' : '${hours.toStringAsFixed(1)}h';
    final isActive = !task.isCompleted;

    return Dismissible(
        key: Key(task.id),
        direction: DismissDirection.endToStart,
        background: Container(
            color: Colors.red,
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 20),
            child: const Icon(Icons.delete, color: Colors.white),
        ),
        confirmDismiss: (dir) async {
            return await showDialog(
                context: context, 
                builder: (ctx) => AlertDialog(
                    title: const Text('Delete Task?'),
                    content: const Text('Are you sure you want to delete this task?'),
                    actions: [
                        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                        TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete', style: TextStyle(color: Colors.red))),
                    ],
                )
            );
        },
        onDismissed: (_) => _deleteTask(task.id),
        child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        elevation: 0,
        shape: RoundedRectangleBorder(
            side: BorderSide(color: Colors.grey.withOpacity(0.2)),
            borderRadius: BorderRadius.circular(8),
        ),
        child: ListTile(
            leading: Checkbox(
            value: task.isCompleted,
            onChanged: (_) => _toggleTaskStatus(task),
            ),
            title: Text(
            task.title,
            style: TextStyle(
                decoration: task.isCompleted ? TextDecoration.lineThrough : null,
                color: task.isCompleted ? Colors.grey : null,
            ),
            ),
            subtitle: Row(
            children: [
                Icon(Icons.timer_outlined, size: 14, color: Colors.grey[600]),
                const SizedBox(width: 4),
                Text(timeLabel, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
            ],
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isActive) 
                  IconButton(
                    icon: Icon(
                        task.isToday ? Icons.today : Icons.calendar_today_outlined,
                        color: task.isToday ? Colors.orange : Colors.grey,
                    ),
                    onPressed: () => _toggleToday(task),
                    tooltip: task.isToday ? 'Planned for Today' : 'Add to Today',
                ),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert),
                  onSelected: (val) {
                    if (val == 'edit') {
                      _showEditTaskDialog(task);
                    } else if (val == 'move') {
                      _showMoveTaskDialog(task);
                    } else if (val == 'delete') {
                      _deleteTaskConfirm(task);
                    }
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(value: 'edit', child: Row(children: [Icon(Icons.edit, size: 20), SizedBox(width: 8), Text('Edit')])),
                    const PopupMenuItem(value: 'move', child: Row(children: [Icon(Icons.folder_open, size: 20), SizedBox(width: 8), Text('Move Folder')])),
                    const PopupMenuItem(value: 'delete', child: Row(children: [Icon(Icons.delete, color: Colors.red, size: 20), SizedBox(width: 8), Text('Delete', style: TextStyle(color: Colors.red))])),
                  ],
                ),
              ],
            ),
        ),
        ),
    );
  }

  Future<void> _deleteTaskConfirm(Task task) async {
    final confirm = await showDialog<bool>(
        context: context, 
        builder: (ctx) => AlertDialog(
            title: const Text('Delete Task?'),
            content: const Text('Are you sure you want to delete this task?'),
            actions: [
                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete', style: TextStyle(color: Colors.red))),
            ],
        )
    );
    if (confirm == true) {
      _deleteTask(task.id);
    }
  }

  Future<void> _showEditTaskDialog(Task task) async {
    final titleController = TextEditingController(text: task.title);
    int estimatedMinutes = task.estimatedMinutes;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('Edit Task'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleController,
                  decoration: const InputDecoration(labelText: 'Task Title'),
                  textCapitalization: TextCapitalization.sentences,
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    const Text('Estimate: '),
                    const SizedBox(width: 8),
                    DropdownButton<int>(
                      value: estimatedMinutes,
                      items: [30, 60, 90, 120, 150, 180, 240, 300].map((m) {
                        final hours = m / 60;
                        final label = hours == hours.toInt() 
                          ? '${hours.toInt()}h' 
                          : '${hours.toStringAsFixed(1)}h';
                        return DropdownMenuItem(value: m, child: Text(label));
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) setDialogState(() => estimatedMinutes = val);
                      },
                    ),
                  ],
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () async {
                  final newTitle = titleController.text.trim();
                  if (newTitle.isNotEmpty) {
                    await _updateTask(task, newTitle, estimatedMinutes);
                    Navigator.pop(ctx);
                  }
                },
                child: const Text('Save'),
              ),
            ],
          );
        }
      ),
    );
  }

  Future<void> _updateTask(Task task, String newTitle, int newMinutes) async {
    try {
      await getFirestore().collection('tasks').doc(task.id).update({
        'title': newTitle,
        'estimatedMinutes': newMinutes,
      });
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error updating task: $e')));
    }
  }

  Future<void> _showMoveTaskDialog(Task task) async {
      await showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
              title: const Text('Move Task'),
              content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                      ListTile(
                          title: Text(_defaultFolderName),
                          onTap: () { Navigator.pop(ctx); _moveTask(task, null); },
                          selected: task.folder == null,
                      ),
                      ..._folders.map((f) => ListTile(
                          title: Text(f),
                          onTap: () { Navigator.pop(ctx); _moveTask(task, f); },
                          selected: task.folder == f,
                      )),
                  ],
              ),
          )
      );
  }

  Future<void> _moveTask(Task task, String? folder) async {
      if (task.folder == folder) return;
      try {
          await getFirestore().collection('tasks').doc(task.id).update({'folder': folder});
      } catch (e) {
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error moving task: $e')));
      }
  }
}
