import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/social_profile.dart';
import '../models/daily_score.dart';

class SocialService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // --- Profile Management ---

  Future<void> updateSocialStats(DailyScore newScore) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;



    // FIX: Using 'profile' collection to match the CollectionGroup query and Index
    final docRef = _firestore.collection('users').doc(user.uid).collection('profile').doc('stats');
    
    // Check if profile exists
    final docSnap = await docRef.get();
    
    Map<String, int> recent = {};
    int streak = 0;
    
    if (docSnap.exists) {
      final data = docSnap.data()!;
      recent = Map<String, int>.from(data['recentScores'] ?? {});
      streak = data['currentStreak'] ?? 0;
    }

    // Update recent scores
    final dateKey = newScore.date.toIso8601String().split('T')[0];
    recent[dateKey] = newScore.totalScore;
    
    // Keep only last 7 days
    final keys = recent.keys.toList()..sort();
    if (keys.length > 7) {
      final toRemove = keys.sublist(0, keys.length - 7);
      for (var k in toRemove) recent.remove(k);
    }

    // Calculate Average
    double avg = 0;
    if (recent.isNotEmpty) {
      avg = recent.values.reduce((a, b) => a + b) / recent.length;
    }
    
    streak = _calculateStreak(recent);

    final emailLower = (user.email ?? '').toLowerCase();


    final profile = SocialProfile(
      userId: user.uid,
      email: emailLower,
      displayName: user.displayName ?? 'User',
      photoUrl: user.photoURL,
      currentStreak: streak,
      weeklyScoreAvg: avg,
      recentScores: recent,
      lastActive: DateTime.now(),
    );

    await docRef.set(profile.toMap(), SetOptions(merge: true));

  }

  int _calculateStreak(Map<String, int> scores) {
     final sortedDates = scores.keys.toList()..sort();
     if (sortedDates.isEmpty) return 0;
     
     // Check if today or yesterday is present
     final today = DateTime.now().toIso8601String().split('T')[0];
     final yesterday = DateTime.now().subtract(const Duration(days: 1)).toIso8601String().split('T')[0];
     
     if (!sortedDates.contains(today) && !sortedDates.contains(yesterday)) {
       return 0; // Streak broken
     }
     
     int streak = 0;
     DateTime current = DateTime.now();
     // If today not logged, start check from yesterday
     if (!sortedDates.contains(today)) {
       current = current.subtract(const Duration(days: 1));
     }

     while (true) {
       final dateStr = current.toIso8601String().split('T')[0];
       if (scores.containsKey(dateStr)) {
         streak++;
         current = current.subtract(const Duration(days: 1));
       } else {
         break;
       }
     }
     return streak;
  }

  Future<List<SocialProfile>> searchUsers(String emailQuery) async {
    final query = emailQuery.toLowerCase();

    
    final snap = await _firestore.collectionGroup('profile')
        .where('email', isEqualTo: query)
        .limit(1)
        .get();
        

    return snap.docs.map((d) => SocialProfile.fromMap(d.data())).toList();
  }

  Future<void> followUser(String targetUid) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    // Add to 'following' subcollection
    await _firestore.collection('users').doc(user.uid).collection('following').doc(targetUid).set({
      'followedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<List<SocialProfile>> getLeaderboard() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return [];

    // Get following list
    final followingSnap = await _firestore.collection('users').doc(user.uid).collection('following').get();
    final followingUids = followingSnap.docs.map((d) => d.id).toList();
    
    // Add self
    followingUids.add(user.uid);

    List<SocialProfile> leaderboard = [];
    
    // Fetch profiles (batch or individual)
    // Firestore 'in' query supports up to 10
    // For scalability we'd loop chunks.
    
    for (var chunk in _chunkList(followingUids, 10)) {
       final snap = await _firestore.collectionGroup('profile')
           .where('userId', whereIn: chunk)
           .get();
       leaderboard.addAll(snap.docs.map((d) => SocialProfile.fromMap(d.data())));
    }
    
    // Sort by Weekly Avg Descending
    leaderboard.sort((a, b) => b.weeklyScoreAvg.compareTo(a.weeklyScoreAvg));
    
    return leaderboard;
  }

  List<List<T>> _chunkList<T>(List<T> list, int chunkSize) {
    List<List<T>> chunks = [];
    for (var i = 0; i < list.length; i += chunkSize) {
      chunks.add(list.sublist(i, i + chunkSize > list.length ? list.length : i + chunkSize));
    }
    return chunks;
  }
}
