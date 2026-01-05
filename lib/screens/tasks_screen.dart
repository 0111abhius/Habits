import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/task.dart';
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

  @override
  void dispose() {
    _taskController.dispose();
    super.dispose();
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

    return Scaffold(
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

                final activeTasks = allTasks.where((t) => !t.isCompleted).toList();
                
                // Sort active: Today first, then date
                activeTasks.sort((a, b) {
                    if (a.isToday && !b.isToday) return -1;
                    if (!a.isToday && b.isToday) return 1;
                    return b.createdAt.compareTo(a.createdAt);
                });

                final now = DateTime.now();
                final weekAgo = now.subtract(const Duration(days: 7));
                final completedTasks = allTasks.where((t) => 
                  t.isCompleted && 
                  (t.completedAt == null || t.completedAt!.isAfter(weekAgo))
                ).toList()
                ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

                if (allTasks.isEmpty) {
                  return const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.task_alt, size: 64, color: Colors.grey),
                        SizedBox(height: 16),
                        Text('No tasks yet!', style: TextStyle(color: Colors.grey)),
                      ],
                    ),
                  );
                }

                return ListView(
                  padding: const EdgeInsets.only(bottom: 80),
                  children: [
                    if (activeTasks.isNotEmpty) ...[
                      const Padding(
                        padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                        child: Text('Active Tasks', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
                      ),
                      ...activeTasks.map((task) => _buildTaskTile(task, isActive: true)),
                    ],
                    
                    if (completedTasks.isNotEmpty) ...[
                      const Padding(
                        padding: EdgeInsets.fromLTRB(16, 24, 16, 8),
                        child: Text('Completed (Last 7 Days)', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
                      ),
                      ...completedTasks.map((task) => _buildTaskTile(task, isActive: false)),
                    ],
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTaskTile(Task task, {required bool isActive}) {
    final hours = task.estimatedMinutes / 60;
    final timeLabel = hours == hours.toInt() ? '${hours.toInt()}h' : '${hours.toStringAsFixed(1)}h';

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
            trailing: isActive ? IconButton(
                icon: Icon(
                    task.isToday ? Icons.today : Icons.calendar_today_outlined,
                    color: task.isToday ? Colors.orange : Colors.grey,
                ),
                onPressed: () => _toggleToday(task),
                tooltip: task.isToday ? 'Planned for Today' : 'Add to Today',
            ) : null,
        ),
        ),
    );
  }
}
