import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:habit_logger/models/habit.dart';
import '../main.dart';  // Import for getFirestore()

class HabitsScreen extends StatefulWidget {
  const HabitsScreen({super.key});

  @override
  State<HabitsScreen> createState() => _HabitsScreenState();
}

class _HabitsScreenState extends State<HabitsScreen> {
  final FirebaseFirestore _firestore = getFirestore();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  HabitType _selectedType = HabitType.binary;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _addHabit() async {
    if (!_formKey.currentState!.validate()) return;

    final user = _auth.currentUser;
    if (user == null) return;

    final docRef = _firestore
        .collection('habits')
        .doc(user.uid)
        .collection('habits')
        .doc();
    
    final habit = Habit(
      id: docRef.id,
      name: _nameController.text,
      type: _selectedType,
      frequency: HabitFrequency.daily,
      userId: user.uid,
      completedDates: [],
      createdAt: DateTime.now(),
    );

    try {
      await docRef.set(habit.toMap());
      _nameController.clear();
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Habit added successfully')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error adding habit: $e')),
        );
      }
    }
  }

  Future<void> _deleteHabit(Habit habit) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Habit'),
        content: Text('Are you sure you want to delete "${habit.name}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirm != true) return;

    final user = _auth.currentUser;
    if (user == null) return;
    try {
      await _firestore
          .collection('habits')
          .doc(user.uid)
          .collection('habits')
          .doc(habit.id)
          .delete();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Habit deleted')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error deleting habit: $e')),
      );
    }
  }

  void _showAddHabitDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add New Habit'),
        content: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Habit Name',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter a habit name';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<HabitType>(
                value: _selectedType,
                decoration: const InputDecoration(
                  labelText: 'Habit Type',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: HabitType.binary, child: Text('Binary (Done / Not)')),
                  DropdownMenuItem(value: HabitType.counter, child: Text('Counter (Number)')),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setState(() {
                      _selectedType = value;
                    });
                  }
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: _addHabit,
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = _auth.currentUser;
    if (user == null) return const SizedBox.shrink();

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Habits'),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: _firestore
            .collection('habits')
            .doc(user.uid)
            .collection('habits')
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }

          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final habits = snapshot.data!.docs.map((doc) {
            return Habit.fromMap(doc.id, doc.data() as Map<String, dynamic>);
          }).toList();

          if (habits.isEmpty) {
            return const Center(
              child: Text('No habits yet. Add your first habit!'),
            );
          }

          return ListView.builder(
            itemCount: habits.length,
            itemBuilder: (context, index) {
              final habit = habits[index];
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: ListTile(
                  title: Text(habit.name),
                  subtitle: Text(habit.type == HabitType.binary ? 'Binary' : 'Counter'),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete),
                    onPressed: () => _deleteHabit(habit),
                  ),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddHabitDialog,
        child: const Icon(Icons.add),
      ),
    );
  }
} 