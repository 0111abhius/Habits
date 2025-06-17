import 'package:cloud_firestore/cloud_firestore.dart';

class UserSettings {
  final String userId;
  final TimeOfDay sleepTime;
  final TimeOfDay wakeTime;
  final List<String> customCategories;

  UserSettings({
    required this.userId,
    required this.sleepTime,
    required this.wakeTime,
    this.customCategories = const [],
  });

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'sleepTime': '${sleepTime.hour.toString().padLeft(2, '0')}:${sleepTime.minute.toString().padLeft(2, '0')}',
      'wakeTime': '${wakeTime.hour.toString().padLeft(2, '0')}:${wakeTime.minute.toString().padLeft(2, '0')}',
      'customCategories': customCategories,
    };
  }

  factory UserSettings.fromMap(Map<String, dynamic> map) {
    final sleepTimeParts = (map['sleepTime'] as String).split(':');
    final wakeTimeParts = (map['wakeTime'] as String).split(':');

    return UserSettings(
      userId: map['userId'] as String,
      sleepTime: TimeOfDay(
        hour: int.parse(sleepTimeParts[0]),
        minute: int.parse(sleepTimeParts[1]),
      ),
      wakeTime: TimeOfDay(
        hour: int.parse(wakeTimeParts[0]),
        minute: int.parse(wakeTimeParts[1]),
      ),
      customCategories: List<String>.from(map['customCategories'] ?? []),
    );
  }

  UserSettings copyWith({
    TimeOfDay? sleepTime,
    TimeOfDay? wakeTime,
    List<String>? customCategories,
  }) {
    return UserSettings(
      userId: userId,
      sleepTime: sleepTime ?? this.sleepTime,
      wakeTime: wakeTime ?? this.wakeTime,
      customCategories: customCategories ?? this.customCategories,
    );
  }
} 