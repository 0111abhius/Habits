import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';

class ScoreSparkline extends StatelessWidget {
  final List<int> scores;
  final double height;
  final double width;
  final Color color;

  const ScoreSparkline({
    super.key,
    required this.scores,
    this.height = 30,
    this.width = 60,
    this.color = Colors.green,
  });

  @override
  Widget build(BuildContext context) {
    if (scores.isEmpty) return SizedBox(height: height, width: width);

    final spots = <FlSpot>[];
    for (int i = 0; i < scores.length; i++) {
      spots.add(FlSpot(i.toDouble(), scores[i].toDouble()));
    }

    return SizedBox(
      height: height,
      width: width,
      child: LineChart(
        LineChartData(
          gridData: const FlGridData(show: false),
          titlesData: const FlTitlesData(show: false),
          borderData: FlBorderData(show: false),
          minX: 0,
          maxX: (scores.length - 1).toDouble(),
          minY: 0,
          maxY: 100,
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              color: color,
              barWidth: 2,
              isStrokeCapRound: true,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(show: false),
            ),
          ],
        ),
      ),
    );
  }
}
