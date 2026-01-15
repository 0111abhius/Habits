import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/social_profile.dart';
import '../services/social_service.dart';
import '../widgets/score_sparkline.dart';

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
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Leaderboard'),
            Tab(text: 'Friends'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildLeaderboardTab(),
          _buildFriendsTab(),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'social_fab',
        onPressed: _showAddFriendDialog,
        child: const Icon(Icons.person_add),
      ),
    );
  }

  Widget _buildLeaderboardTab() {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_leaderboard.isEmpty) return const Center(child: Text('No friends yet. Add some to compete!'));

    return ListView.separated(
      itemCount: _leaderboard.length,
      separatorBuilder: (_, __) => const Divider(),
      itemBuilder: (context, index) {
        final profile = _leaderboard[index];
        final isMe = profile.userId == FirebaseAuth.instance.currentUser?.uid;
        final rank = index + 1;

        // Prepare scores for sparkline (sorted by date)
        final dates = profile.recentScores.keys.toList()..sort();
        final scores = dates.map((d) => profile.recentScores[d]!).toList();

        return ListTile(
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
        );
      },
    );
  }

  Widget _buildFriendsTab() {
    // For MVP, just reusing leaderboard list but filtered for "following" logic if we had it.
    // Since getLeaderboard gets everyone, we can just show list management here.
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.people_outline, size: 64, color: Colors.grey),
          const SizedBox(height: 16),
          const Text('Manage your circle'),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _showAddFriendDialog, 
            child: const Text('Find Friends'),
          ),
        ],
      ),
    );
  }

  void _showAddFriendDialog() {
    final TextEditingController _emailCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Friend'),
        content: TextField(
          controller: _emailCtrl,
          decoration: const InputDecoration(
            labelText: 'Friend\'s Email',
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
            child: const Text('Add'),
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
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Added ${target.displayName}!')));
      _loadData(); // Refresh
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      setState(() => _isLoading = false);
    }
  }
}
