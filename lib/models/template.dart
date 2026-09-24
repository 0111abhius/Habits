import 'package:cloud_firestore/cloud_firestore.dart';

class Template {
  final String id;
  final String name;
  final List<int> daysOfWeek; // 1=Mon, 7=Sun
  final bool isDefault;

  Template({
    required this.id,
    required this.name,
    required this.daysOfWeek,
    this.isDefault = false,
  });

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'daysOfWeek': daysOfWeek,
      'isDefault': isDefault,
    };
  }

  factory Template.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Template(
      id: doc.id,
      name: data['name'] ?? '',
      daysOfWeek: List<int>.from(data['daysOfWeek'] ?? []),
      isDefault: data['isDefault'] ?? false,
    );
  }
}
