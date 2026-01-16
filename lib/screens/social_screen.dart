import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/social_profile.dart';
import '../services/social_service.dart';
import '../widgets/score_sparkline.dart';
import '../widgets/user_comparison_dialog.dart';

class SocialScreen extends StatefulWidget {
  const SocialScreen({super.key});

  @override
  State<SocialScreen> createState() => _SocialScreenState();
}

class _SocialScreenState extends State<SocialScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final SocialService _socialService = SocialService();
  
  List<SocialProfile> _leaderboard = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final list = await _socialService.getLeaderboard();
      setState(() => _leaderboard = list);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error loading social data: $e')));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Community'),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_add),
            tooltip: 'Follow User',
            onPressed: _showFollowUserDialog,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Leaderboard'),
            Tab(text: 'Following'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildLeaderboardTab(),
          _buildFollowingTab(),
        ],
      ),
    );
  }

  Widget _buildLeaderboardTab() {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_leaderboard.isEmpty) return const Center(child: Text('No community members yet.'));

    return ListView.separated(
      padding: const EdgeInsets.all(8),
      itemCount: _leaderboard.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final profile = _leaderboard[index];
        final isMe = profile.userId == FirebaseAuth.instance.currentUser?.uid;
        final rank = index + 1;

        // Prepare scores for sparkline (sorted by date)
        final dates = profile.recentScores.keys.toList()..sort();
        final scores = dates.map((d) => profile.recentScores[d]!).toList();

        return Card(
          elevation: isMe ? 4 : 1,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: isMe ? const BorderSide(color: Colors.blue, width: 2) : BorderSide.none),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: rank == 1 ? Colors.amber : Colors.grey.shade300,
              child: Text('#$rank', style: TextStyle(color: rank == 1 ? Colors.black : Colors.black87)),
            ),
            title: Text(
              isMe ? '${profile.displayName} (You)' : profile.displayName,
              style: TextStyle(fontWeight: isMe ? FontWeight.bold : FontWeight.normal),
            ),
            subtitle: Text('${profile.currentStreak} day streak'),
            trailing: SizedBox(
              width: 120,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  ScoreSparkline(scores: scores, width: 60, height: 30),
                  const SizedBox(width: 8),
                  Text(
                    profile.weeklyScoreAvg.toStringAsFixed(0),
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
            onTap: () {
               // Find current user profile for comparison
               final myProfile = _leaderboard.firstWhere(
                 (p) => p.userId == FirebaseAuth.instance.currentUser?.uid,
                 orElse: () => profile, // Fallback if not found (shouldn't happen if logged in and in list)
               );
               
               if (profile.userId != myProfile.userId) {
                 showDialog(
                   context: context,
                   builder: (context) => UserComparisonDialog(
                     currentUser: myProfile,
                     otherUser: profile,
                   ),
                 );
               } 
            },
          ),
        );
      },
    );
  }

  Widget _buildFollowingTab() {
    // Show list of people I follow. 
    // Since getLeaderboard returns everyone I follow + me, we can filter that list.
    final myUid = FirebaseAuth.instance.currentUser?.uid;
    final following = _leaderboard.where((p) => p.userId != myUid).toList();

    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (following.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.people_outline, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            const Text('You are not following anyone yet.'),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _showFollowUserDialog,
              child: const Text('Find People to Follow'),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: following.length,
      itemBuilder: (context, index) {
        final profile = following[index];
        return ListTile(
          leading: CircleAvatar(child: Text(profile.displayName[0].toUpperCase())),
          title: Text(profile.displayName),
          subtitle: Text(profile.email),
          trailing: const Icon(Icons.check, color: Colors.green), // Indicate following
        );
      },
    );
  }

  void _showFollowUserDialog() {
    final TextEditingController _emailCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Follow User'),
        content: TextField(
          controller: _emailCtrl,
          decoration: const InputDecoration(
            labelText: 'User\'s Email',
            hintText: 'user@example.com',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              _searchAndFollow(_emailCtrl.text.trim());
            },
            child: const Text('Follow'),
          ),
        ],
      ),
    );
  }

  Future<void> _searchAndFollow(String email) async {
    if (email.isEmpty) return;
    
    setState(() => _isLoading = true);
    try {
      final users = await _socialService.searchUsers(email);
      if (users.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('User not found')));
        return;
      }
      
      final target = users.first;
      await _socialService.followUser(target.userId);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Following ${target.displayName}!')));
      _loadData(); // Refresh
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      setState(() => _isLoading = false);
    }
  }
}
