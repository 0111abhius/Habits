import 'package:flutter/material.dart';
import '../models/daily_score.dart';

class DayScoreDialog extends StatelessWidget {
  final DailyScore score;
  final VoidCallback? onRecalculate;

  const DayScoreDialog({super.key, required this.score, this.onRecalculate});

  static Future<void> show(BuildContext context, DailyScore score, {VoidCallback? onRecalculate}) {
    return showDialog(
      context: context,
      builder: (context) => DayScoreDialog(score: score, onRecalculate: onRecalculate),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final breakdown = score.breakdown;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header Score
            Center(
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 120,
                    height: 120,
                    child: CircularProgressIndicator(
                      value: score.totalScore / 100,
                      strokeWidth: 12,
                      backgroundColor: Colors.grey[200],
                      valueColor: AlwaysStoppedAnimation<Color>(_getScoreColor(score.totalScore)),
                    ),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${score.totalScore}',
                        style: theme.textTheme.displayMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: _getScoreColor(score.totalScore),
                        ),
                      ),
                      Text('Day Score', style: theme.textTheme.labelMedium),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
            
            // Pillar Breakdown
            _buildPillarRow(context, 'Planning', breakdown['planning'] ?? 0, Colors.blue),
            const SizedBox(height: 12),
            _buildPillarRow(context, 'Retro', breakdown['retro'] ?? 0, Colors.purple),
            const SizedBox(height: 12),
            _buildPillarRow(context, 'Execution', breakdown['execution'] ?? 0, Colors.orange),
            const SizedBox(height: 12),
            _buildPillarRow(context, 'Goal Alignment', breakdown['goal'] ?? 0, Colors.green),
            
            const SizedBox(height: 32),
            
            // AI Analysis Section
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.auto_awesome, size: 20, color: theme.primaryColor),
                      const SizedBox(width: 8),
                      const Text('Coach Insight', style: TextStyle(fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(score.aiGoalAnalysis.isNotEmpty ? score.aiGoalAnalysis : 'No analysis available.', 
                    style: const TextStyle(fontStyle: FontStyle.italic)),
                  
                  if (score.coachTip.isNotEmpty) ...[
                    const Divider(height: 24),
                    Text('Tip: ${score.coachTip}', style: const TextStyle(fontWeight: FontWeight.bold)),
                  ],
                ],
              ),
            ),
            
            const SizedBox(height: 24),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
            if (onRecalculate != null)
              TextButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  onRecalculate!();
                },
                icon: const Icon(Icons.refresh),
                label: const Text('Recalculate Score'),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPillarRow(BuildContext context, String label, int value, Color color) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 12),
        Expanded(child: Text(label, style: const TextStyle(fontWeight: FontWeight.w500))),
        SizedBox(
          width: 80,
          child: LinearProgressIndicator(
            value: value / 100,
            backgroundColor: color.withOpacity(0.1),
            valueColor: AlwaysStoppedAnimation<Color>(color),
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(width: 12),
        SizedBox(
          width: 32,
          child: Text('$value', textAlign: TextAlign.end, style: const TextStyle(fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }

  Color _getScoreColor(int score) {
    if (score >= 80) return Colors.green;
    if (score >= 60) return Colors.orange;
    return Colors.red;
  }
}
