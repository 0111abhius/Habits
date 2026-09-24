import 'package:flutter/material.dart';
import '../services/smart_coach_service.dart';

class CoachCard extends StatelessWidget {
  final CoachInsight insight;
  final VoidCallback onDismiss;

  const CoachCard({
    super.key,
    required this.insight,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    // Different visual styles based on insight type to keep it fresh
    final isPlanning = insight.type == InsightType.planning;
    final isRetro = insight.type == InsightType.retro;
    final isGeneral = insight.type == InsightType.general;

    final Color badgeColor = isPlanning 
        ? Colors.blue.shade100 
        : (isRetro ? Colors.orange.shade100 : Colors.green.shade100);
    
    final Color badgeTextColor = isPlanning 
        ? Colors.blue.shade900 
        : (isRetro ? Colors.orange.shade900 : Colors.green.shade900);

    final String badgeText = isPlanning 
        ? "SMART PLANNER" 
        : (isRetro ? "RETRO INSIGHT" : "DAILY COACH");

    final IconData icon = isPlanning 
        ? Icons.auto_graph 
        : (isRetro ? Icons.psychology : Icons.lightbulb_outline);

    return Dismissible(
      key: ValueKey(insight.message.hashCode),
      onDismissed: (_) => onDismiss(),
      direction: DismissDirection.horizontal,
      background: Container(color: Colors.transparent), // fade out effect basically
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          gradient: LinearGradient(
              colors: [
                  Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.5),
                  Theme.of(context).colorScheme.surface,
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: Theme.of(context).colorScheme.outlineVariant.withOpacity(0.5),
          ),
          boxShadow: [
              BoxShadow(
                  color: Colors.black.withOpacity(0.03),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
              ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                   Container(
                     padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                     decoration: BoxDecoration(
                       color: badgeColor,
                       borderRadius: BorderRadius.circular(8),
                     ),
                     child: Row(
                       mainAxisSize: MainAxisSize.min,
                       children: [
                         Icon(icon, size: 14, color: badgeTextColor),
                         const SizedBox(width: 4),
                         Text(
                           badgeText,
                           style: TextStyle(
                             color: badgeTextColor,
                             fontSize: 10,
                             fontWeight: FontWeight.w800,
                             letterSpacing: 0.5,
                           ),
                         ),
                       ],
                     ),
                   ),
                   const Spacer(),
                   IconButton(
                     icon: const Icon(Icons.close, size: 18), 
                     padding: EdgeInsets.zero,
                     constraints: const BoxConstraints(),
                     onPressed: onDismiss
                   ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                insight.message,
                style: const TextStyle(
                  fontSize: 14,
                  height: 1.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
