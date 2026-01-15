import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/user_settings.dart';

class ScoreConfigScreen extends StatefulWidget {
  const ScoreConfigScreen({super.key});

  @override
  State<ScoreConfigScreen> createState() => _ScoreConfigScreenState();
}

class _ScoreConfigScreenState extends State<ScoreConfigScreen> {
  final User? user = FirebaseAuth.instance.currentUser;
  final TextEditingController _goalController = TextEditingController();
  
  Map<String, int> _weights = {
    'planning': 20,
    'retro': 20,
    'execution': 30,
    'goal': 30,
  };
  TimeOfDay _planningTarget = const TimeOfDay(hour: 10, minute: 0);
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _goalController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    if (user == null) return;
    try {
      final doc = await FirebaseFirestore.instance.collection('user_settings').doc(user!.uid).get();
      if (doc.exists) {
        final settings = UserSettings.fromMap(doc.data()!);
        setState(() {
          _goalController.text = settings.goalText;
          _weights = Map.from(settings.scoreWeights);
          _planningTarget = settings.planningTargetTime;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error loading settings: $e')));
      }
    }
  }

  Future<void> _saveSettings() async {
    if (user == null) return;
    setState(() => _isLoading = true);
    
    // Normalize weights if needed or just warn?
    // Let's ensure they sum to 100 for sanity, or just let them be weights. 
    // Ideally sum to 100.
    int total = _weights.values.fold(0, (sum, val) => sum + val);
    if (total != 100) {
      // Allow it but maybe show warning? For V1 let's just save.
      // Logic service will likely normalize.
    }

    try {
      await FirebaseFirestore.instance.collection('user_settings').doc(user!.uid).set({
        'goalText': _goalController.text.trim(),
        'scoreWeights': _weights,
        'planningTargetTime': '${_planningTarget.hour.toString().padLeft(2, '0')}:${_planningTarget.minute.toString().padLeft(2, '0')}',
      }, SetOptions(merge: true));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Settings saved')));
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error saving: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _selectTime() async {
    final t = await showTimePicker(context: context, initialTime: _planningTarget);
    if (t != null) {
      setState(() => _planningTarget = t);
    }
  }

  @override
  Widget build(BuildContext context) {
    int totalWeight = _weights.values.fold(0, (a, b) => a + b);
    Color weightColor = totalWeight == 100 ? Colors.green : Colors.orange;

    return Scaffold(
      appBar: AppBar(title: const Text('Score Configuration')),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator())
        : ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Goal Section
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('North Star Goal', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      const Text('What is your main focus right now? The AI will use this to score your day.', style: TextStyle(color: Colors.grey)),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _goalController,
                        maxLines: 3,
                        decoration: const InputDecoration(
                          hintText: 'e.g. Become a Senior Developer, Run a Marathon...',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              
              // Planning Target
              Card(
                child: ListTile(
                  title: const Text('Planning Target Time'),
                  subtitle: const Text('Ideally plan your day before this time.'),
                  trailing: Text(
                    _planningTarget.format(context),
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  onTap: _selectTime,
                ),
              ),
              const SizedBox(height: 24),

              // Weights Section
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Score Weights', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                          Text('Total: $totalWeight%', style: TextStyle(color: weightColor, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      const Divider(),
                      _buildSlider('Planning Discipline', 'planning'),
                      _buildSlider('Retro Discipline', 'retro'),
                      _buildSlider('Execution Accuracy', 'execution'),
                      _buildSlider('Goal Alignment', 'goal'),
                      if (totalWeight != 100)
                        Padding(
                          padding: const EdgeInsets.only(top: 8.0),
                          child: Text('Note: Weights should ideally sum to 100%', style: TextStyle(color: Colors.orange[800], fontSize: 12)),
                        ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 32),
              FilledButton(
                onPressed: _saveSettings,
                child: const Text('Save Configuration'),
              ),
            ],
          ),
    );
  }

  Widget _buildSlider(String label, String key) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label),
            Text('${_weights[key]}%', style: const TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        Slider(
          value: _weights[key]!.toDouble(),
          min: 0,
          max: 100,
          divisions: 20,
          label: '${_weights[key]}%',
          onChanged: (val) {
            setState(() {
              _weights[key] = val.round();
            });
          },
        ),
      ],
    );
  }
}
