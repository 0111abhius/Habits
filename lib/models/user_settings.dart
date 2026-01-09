import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class UserSettings {
  final String userId;
  final TimeOfDay sleepTime;
  final TimeOfDay wakeTime;
  final List<String> customActivities;
  final List<String> taskFolders;
  final String defaultFolderName;
  final Map<String, String> folderActivities;

  UserSettings({
    required this.userId,
    required this.sleepTime,
    required this.wakeTime,
    this.customActivities = const [],
    this.taskFolders = const [],
    this.defaultFolderName = 'Inbox',
    this.folderActivities = const {},
  });

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'sleepTime': '${sleepTime.hour.toString().padLeft(2, '0')}:${sleepTime.minute.toString().padLeft(2, '0')}',
      'wakeTime': '${wakeTime.hour.toString().padLeft(2, '0')}:${wakeTime.minute.toString().padLeft(2, '0')}',
      'customActivities': customActivities,
      'taskFolders': taskFolders,
      'defaultFolderName': defaultFolderName,
      'folderActivities': folderActivities,
    };
  }

  factory UserSettings.fromMap(Map<String, dynamic> map) {
    final sleepTimeParts = (map['sleepTime'] as String? ?? '23:00').split(':');
    final wakeTimeParts = (map['wakeTime'] as String? ?? '07:00').split(':');

    return UserSettings(
      userId: map['userId'] as String? ?? '',
      sleepTime: TimeOfDay(
        hour: int.parse(sleepTimeParts[0]),
        minute: int.parse(sleepTimeParts[1]),
      ),
      wakeTime: TimeOfDay(
        hour: int.parse(wakeTimeParts[0]),
        minute: int.parse(wakeTimeParts[1]),
      ),
      customActivities: List<String>.from(map['customActivities'] ?? []),
      taskFolders: List<String>.from(map['taskFolders'] ?? []),
      defaultFolderName: map['defaultFolderName'] ?? 'Inbox',
      folderActivities: Map<String, String>.from(map['folderActivities'] ?? {}),
    );
  }

  UserSettings copyWith({
    TimeOfDay? sleepTime,
    TimeOfDay? wakeTime,
    List<String>? customActivities,
    List<String>? taskFolders,
    String? defaultFolderName,
    Map<String, String>? folderActivities,
  }) {
    return UserSettings(
      userId: userId,
      sleepTime: sleepTime ?? this.sleepTime,
      wakeTime: wakeTime ?? this.wakeTime,
      customActivities: customActivities ?? this.customActivities,
      taskFolders: taskFolders ?? this.taskFolders,
      defaultFolderName: defaultFolderName ?? this.defaultFolderName,
      folderActivities: folderActivities ?? this.folderActivities,
    );
  }
} 