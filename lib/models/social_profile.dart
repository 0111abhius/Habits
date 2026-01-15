import 'package:cloud_firestore/cloud_firestore.dart';

class SocialProfile {
  final String userId;
  final String email;
  final String displayName;
  final String? photoUrl;
  final int currentStreak;
  final double weeklyScoreAvg;
  final Map<String, int> recentScores; // Date "yyyy-MM-dd" : Score
  final DateTime lastActive;

  SocialProfile({
    required this.userId,
    required this.email,
    required this.displayName,
    this.photoUrl,
    this.currentStreak = 0,
    this.weeklyScoreAvg = 0.0,
    this.recentScores = const {},
    required this.lastActive,
  });

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'email': email,
      'displayName': displayName,
      'photoUrl': photoUrl,
      'currentStreak': currentStreak,
      'weeklyScoreAvg': weeklyScoreAvg,
      'recentScores': recentScores,
      'lastActive': FieldValue.serverTimestamp(),
    };
  }

  factory SocialProfile.fromMap(Map<String, dynamic> map) {
    return SocialProfile(
      userId: map['userId'] ?? '',
      email: map['email'] ?? '',
      displayName: map['displayName'] ?? 'Unknown',
      photoUrl: map['photoUrl'],
      currentStreak: map['currentStreak'] ?? 0,
      weeklyScoreAvg: (map['weeklyScoreAvg'] ?? 0).toDouble(),
      recentScores: Map<String, int>.from(map['recentScores'] ?? {}),
      lastActive: (map['lastActive'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }
}
