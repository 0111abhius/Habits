import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/habit.dart';
import '../main.dart';

class HabitTracker extends StatelessWidget {
  final DateTime date;
  const HabitTracker({super.key, required this.date});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const SizedBox.shrink();

    final habitsStream = getFirestore()
        .collection('habits')
        .doc(user.uid)
        .collection('habits')
        .snapshots();

    return StreamBuilder<QuerySnapshot>(
      stream: habitsStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.all(8.0),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError) {
          return Padding(
            padding: const EdgeInsets.all(8.0),
            child: Text('Error: ${snapshot.error}'),
          );
        }

        final habits = snapshot.data?.docs.map((doc) => Habit.fromMap(doc.id, doc.data() as Map<String, dynamic>)).toList() ?? [];
        if (habits.isEmpty) {
          return const SizedBox.shrink();
        }

        return SizedBox(
          height: 120, // give a bit more room for taller text/checkbox on tablets
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: habits.map((h) => _HabitTile(date: date, habit: h)).toList(),
            ),
          ),
        );
      },
    );
  }
}

class _HabitTile extends StatelessWidget {
  final DateTime date;
  final Habit habit;
  const _HabitTile({required this.date, required this.habit});

  String get _dateId => '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const SizedBox.shrink();
    final logDocRef = getFirestore()
        .collection('habit_logs')
        .doc(user.uid)
        .collection('dates')
        .doc(_dateId)
        .collection('habits')
        .doc(habit.id);

    return StreamBuilder<DocumentSnapshot>(
      stream: logDocRef.snapshots(),
      builder: (context, snapshot) {
        dynamic value;
        if (snapshot.hasData && snapshot.data!.exists) {
          value = (snapshot.data!.data() as Map<String, dynamic>)['value'];
        }

        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 4),
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: habit.type == HabitType.binary
                ? _buildBinary(context, logDocRef, value == true)
                : _buildCounter(context, logDocRef, value),
          ),
        );
      },
    );
  }

  Widget _buildBinary(BuildContext context, DocumentReference logDocRef, bool isDone) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(habit.name, style: const TextStyle(fontWeight: FontWeight.bold)),
        Checkbox(
          value: isDone,
          onChanged: (val) {
            logDocRef.set({'value': val == true}, SetOptions(merge: true));
          },
        ),
      ],
    );
  }

  Widget _buildCounter(BuildContext context, DocumentReference logDocRef, dynamic rawVal) {
    final controller = TextEditingController(text: rawVal?.toString() ?? '');
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(habit.name, style: const TextStyle(fontWeight: FontWeight.bold)),
        SizedBox(
          width: 60,
          child: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              isDense: true,
              contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            ),
            onSubmitted: (value) {
              final intVal = int.tryParse(value) ?? 0;
              logDocRef.set({'value': intVal}, SetOptions(merge: true));
            },
          ),
        ),
      ],
    );
  }
} 