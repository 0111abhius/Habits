import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../models/social_profile.dart';

class UserComparisonDialog extends StatelessWidget {
  final SocialProfile currentUser;
  final SocialProfile otherUser;

  const UserComparisonDialog({
    super.key,
    required this.currentUser,
    required this.otherUser,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        padding: const EdgeInsets.all(16),
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Comparison',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _buildHeaderRow(),
              const SizedBox(height: 24),
              const Text('Weekly Progress', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              SizedBox(
                height: 200,
                child: _buildComparisonChart(context),
              ),
              const SizedBox(height: 24),
              _buildStatRow('Current Streak', currentUser.currentStreak.toString(), otherUser.currentStreak.toString()),
              const Divider(),
              _buildStatRow('Weekly Avg', currentUser.weeklyScoreAvg.toStringAsFixed(1), otherUser.weeklyScoreAvg.toStringAsFixed(1)),
              const Divider(),
              // Calculate total score for last 7 days as an extra stat
              _buildStatRow('Total (7 Days)', _calculateTotal(currentUser).toString(), _calculateTotal(otherUser).toString()),
            ],
          ),
        ),
      ),
    );
  }

  int _calculateTotal(SocialProfile profile) {
    int total = 0;
    // Get last 7 days keys
    final keys = profile.recentScores.keys.toList()..sort();
    final recentKeys = keys.length > 7 ? keys.sublist(keys.length - 7) : keys;
    for (var key in recentKeys) {
      total += profile.recentScores[key] ?? 0;
    }
    return total;
  }

  Widget _buildHeaderRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        _buildUserHeader(currentUser, isMe: true),
        const Text('VS', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
        _buildUserHeader(otherUser, isMe: false),
      ],
    );
  }

  Widget _buildUserHeader(SocialProfile profile, {required bool isMe}) {
    return Column(
      children: [
        CircleAvatar(
          radius: 24,
          backgroundColor: isMe ? Colors.blue.shade100 : Colors.orange.shade100,
          child: Text(profile.displayName[0].toUpperCase()),
        ),
        const SizedBox(height: 8),
        Text(
          isMe ? 'You' : profile.displayName,
          style: const TextStyle(fontWeight: FontWeight.bold),
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  Widget _buildStatRow(String label, String value1, String value2) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(child: Center(child: Text(value1, style: const TextStyle(fontSize: 16)))),
          Expanded(child: Center(child: Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)))),
          Expanded(child: Center(child: Text(value2, style: const TextStyle(fontSize: 16)))),
        ],
      ),
    );
  }

  Widget _buildComparisonChart(BuildContext context) {
    // Merge dates from both users to get X-axis
    final allDates = {...currentUser.recentScores.keys, ...otherUser.recentScores.keys}.toList()..sort();
    // Take last 7 days
    if (allDates.length > 7) {
      allDates.removeRange(0, allDates.length - 7);
    }

    if (allDates.isEmpty) {
      return const Center(child: Text('No data to compare'));
    }

    List<FlSpot> spots1 = [];
    List<FlSpot> spots2 = [];

    for (int i = 0; i < allDates.length; i++) {
      final date = allDates[i];
      spots1.add(FlSpot(i.toDouble(), (currentUser.recentScores[date] ?? 0).toDouble()));
      spots2.add(FlSpot(i.toDouble(), (otherUser.recentScores[date] ?? 0).toDouble()));
    }

    return LineChart(
      LineChartData(
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: 20,
          getDrawingHorizontalLine: (value) => FlLine(color: Colors.grey.shade200, strokeWidth: 1),
        ),
        titlesData: FlTitlesData(
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, meta) {
                 final index = value.toInt();
                 if (index >= 0 && index < allDates.length) {
                   final date = DateTime.parse(allDates[index]);
                   return Padding(
                     padding: const EdgeInsets.only(top: 8.0),
                     child: Text('${date.day}/${date.month}', style: const TextStyle(fontSize: 10)),
                   );
                 }
                 return const Text('');
              },
              interval: 1,
            ),
          ),
          leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        borderData: FlBorderData(show: false),
        minX: 0,
        maxX: (allDates.length - 1).toDouble(),
        minY: 0,
        maxY: 100, // Assuming score is 0-100
        lineBarsData: [
          LineChartBarData(
            spots: spots1,
            isCurved: true,
            color: Colors.blue,
            barWidth: 3,
            isStrokeCapRound: true,
            dotData: const FlDotData(show: true),
          ),
          LineChartBarData(
            spots: spots2,
            isCurved: true,
            color: Colors.orange,
            barWidth: 3,
            isStrokeCapRound: true,
            dotData: const FlDotData(show: true),
          ),
        ],
      ),
    );
  }
}
