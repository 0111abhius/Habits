import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class UserSettings {
  final String userId;
  final TimeOfDay sleepTime;
  final TimeOfDay wakeTime;
  final List<String> customActivities;
  final List<String> taskFolders;
  final String defaultFolderName;
  final String goalText;
  final Map<String, int> scoreWeights;
  final TimeOfDay planningTargetTime;
  final Map<String, String> folderActivities;

  /// Browser reminder preferences (web only for now).
  final bool remindersEnabled;
  final TimeOfDay planReminderTime;
  final TimeOfDay logReminderTime;

  /// Evening "plan tomorrow" reminder (the shutdown anchor). The morning
  /// [planReminderTime] is only a fallback when nothing is planned yet.
  final TimeOfDay planTomorrowReminderTime;

  /// How many tasks the daily focus list should hold (soft limit).
  final int topTasksLimit;

  /// Set once the first-run onboarding has been completed (or skipped).
  final bool onboardingComplete;

  UserSettings({
    required this.userId,
    required this.sleepTime,
    required this.wakeTime,
    this.customActivities = const [],
    this.taskFolders = const [],
    this.defaultFolderName = 'Inbox',
    this.folderActivities = const {},
    this.goalText = '',
    this.scoreWeights = const {
      'planning': 20,
      'retro': 20,
      'execution': 30,
      'goal': 30,
    },
    this.planningTargetTime = const TimeOfDay(hour: 10, minute: 0),
    this.remindersEnabled = false,
    this.planReminderTime = const TimeOfDay(hour: 8, minute: 30),
    this.logReminderTime = const TimeOfDay(hour: 21, minute: 0),
    this.planTomorrowReminderTime = const TimeOfDay(hour: 16, minute: 30),
    this.topTasksLimit = 3,
    this.onboardingComplete = false,
  });

  static String fmt(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  static TimeOfDay parseTime(String? s, TimeOfDay fallback) => tryParseTime(s) ?? fallback;

  static TimeOfDay? tryParseTime(String? s) {
    if (s == null) return null;
    final parts = s.split(':');
    if (parts.length != 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return null;
    return TimeOfDay(hour: h.clamp(0, 23), minute: m.clamp(0, 59));
  }

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'sleepTime': '${sleepTime.hour.toString().padLeft(2, '0')}:${sleepTime.minute.toString().padLeft(2, '0')}',
      'wakeTime': '${wakeTime.hour.toString().padLeft(2, '0')}:${wakeTime.minute.toString().padLeft(2, '0')}',
      'customActivities': customActivities,
      'taskFolders': taskFolders,
      'defaultFolderName': defaultFolderName,
      'folderActivities': folderActivities,
      'goalText': goalText,
      'scoreWeights': scoreWeights,
      'planningTargetTime': fmt(planningTargetTime),
      'remindersEnabled': remindersEnabled,
      'planReminderTime': fmt(planReminderTime),
      'logReminderTime': fmt(logReminderTime),
      'planTomorrowReminderTime': fmt(planTomorrowReminderTime),
      'topTasksLimit': topTasksLimit,
      'onboardingComplete': onboardingComplete,
    };
  }

  factory UserSettings.fromMap(Map<String, dynamic> map) {
    return UserSettings(
      userId: map['userId'] as String? ?? '',
      sleepTime: parseTime(map['sleepTime'] as String?, const TimeOfDay(hour: 23, minute: 0)),
      wakeTime: parseTime(map['wakeTime'] as String?, const TimeOfDay(hour: 7, minute: 0)),
      customActivities: List<String>.from(map['customActivities'] ?? []),
      taskFolders: List<String>.from(map['taskFolders'] ?? []),
      defaultFolderName: map['defaultFolderName'] ?? 'Inbox',
      folderActivities: Map<String, String>.from(map['folderActivities'] ?? {}),
      goalText: map['goalText'] ?? '',
      scoreWeights: Map<String, int>.from(map['scoreWeights'] ?? {
        'planning': 20,
        'retro': 20,
        'execution': 30,
        'goal': 30,
      }),
      planningTargetTime: parseTime(map['planningTargetTime'] as String?, const TimeOfDay(hour: 10, minute: 0)),
      remindersEnabled: map['remindersEnabled'] as bool? ?? false,
      planReminderTime: parseTime(map['planReminderTime'] as String?, const TimeOfDay(hour: 8, minute: 30)),
      logReminderTime: parseTime(map['logReminderTime'] as String?, const TimeOfDay(hour: 21, minute: 0)),
      planTomorrowReminderTime:
          parseTime(map['planTomorrowReminderTime'] as String?, const TimeOfDay(hour: 16, minute: 30)),
      topTasksLimit: ((map['topTasksLimit'] as num?)?.toInt() ?? 3).clamp(1, 10),
      onboardingComplete: map['onboardingComplete'] as bool? ?? false,
    );
  }

  UserSettings copyWith({
    TimeOfDay? sleepTime,
    TimeOfDay? wakeTime,
    List<String>? customActivities,
    List<String>? taskFolders,
    String? defaultFolderName,
    Map<String, String>? folderActivities,
    String? goalText,
    Map<String, int>? scoreWeights,
    TimeOfDay? planningTargetTime,
    bool? remindersEnabled,
    TimeOfDay? planReminderTime,
    TimeOfDay? logReminderTime,
    TimeOfDay? planTomorrowReminderTime,
    int? topTasksLimit,
    bool? onboardingComplete,
  }) {
    return UserSettings(
      userId: userId,
      sleepTime: sleepTime ?? this.sleepTime,
      wakeTime: wakeTime ?? this.wakeTime,
      customActivities: customActivities ?? this.customActivities,
      taskFolders: taskFolders ?? this.taskFolders,
      defaultFolderName: defaultFolderName ?? this.defaultFolderName,
      folderActivities: folderActivities ?? this.folderActivities,
      goalText: goalText ?? this.goalText,
      scoreWeights: scoreWeights ?? this.scoreWeights,
      planningTargetTime: planningTargetTime ?? this.planningTargetTime,
      remindersEnabled: remindersEnabled ?? this.remindersEnabled,
      planReminderTime: planReminderTime ?? this.planReminderTime,
      logReminderTime: logReminderTime ?? this.logReminderTime,
      planTomorrowReminderTime: planTomorrowReminderTime ?? this.planTomorrowReminderTime,
      topTasksLimit: topTasksLimit ?? this.topTasksLimit,
      onboardingComplete: onboardingComplete ?? this.onboardingComplete,
    );
  }
} 