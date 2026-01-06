import 'package:intl/intl.dart';

class MockEntry {
  final DateTime startTime;
  final DateTime endTime;
  final String activity;

  MockEntry(this.startTime, this.endTime, this.activity);
}

void main() {
  print('--- Analytics Logic Verification ---');

  // Scenario: Split Hour
  // Usage: User has filled 10:00 - 11:00 with "Work" (defaults to 1h).
  // Then user adds 10:30 - 11:00 with "Break".
  // Firestore likely has:
  // 1. 10:00 "Work", end: 11:00 (Duration 1h)
  // 2. 10:30 "Break", end: 11:00 (Duration 0.5h)
  // Total Sum currently: 1.5h. 
  // Desired: "Work" counts as 0.5h, "Break" counts as 0.5h. Total 1.0h.

  final entries = [
    MockEntry(DateTime(2025, 1, 1, 10, 0), DateTime(2025, 1, 1, 11, 0), 'Work'),
    MockEntry(DateTime(2025, 1, 1, 10, 30), DateTime(2025, 1, 1, 11, 0), 'Break'),
  ];

  // 1. Current Logic (Naive Sum)
  double naiveSum = 0;
  Map<String, double> naiveTotals = {};
  for (final e in entries) {
    double dur = e.endTime.difference(e.startTime).inMinutes / 60.0;
    naiveSum += dur;
    naiveTotals[e.activity] = (naiveTotals[e.activity] ?? 0) + dur;
  }
  print('Current Logic Total: $naiveSum hours (Expected > 1.0)');
  print('Current Totals: $naiveTotals');

  // 2. Fixed Logic (Clip 00 if 30 exists)
  // We need to sort by startTime first.
  entries.sort((a, b) => a.startTime.compareTo(b.startTime));

  double fixedSum = 0;
  Map<String, double> fixedTotals = {};

  for (int i = 0; i < entries.length; i++) {
    final current = entries[i];
    DateTime effectiveEnd = current.endTime;

    // Check if next entry overlaps specifically in the way we want to handle (split hour)
    // Or just generally clip to next start time? 
    // Generally clipping to next start time is safer for "Total Time", 
    // but for specific activities, we only really support 00/30 splits currently.
    // Let's implement "Clip to next.startTime if next.startTime < current.endTime"
    
    if (i + 1 < entries.length) {
      final next = entries[i + 1];
      if (next.startTime.isBefore(effectiveEnd) && next.startTime.isAfter(current.startTime)) {
         effectiveEnd = next.startTime;
      }
    }

    double dur = effectiveEnd.difference(current.startTime).inMinutes / 60.0;
    if (dur < 0) dur = 0; // Should not happen if sorted
    
    fixedSum += dur;
    fixedTotals[current.activity] = (fixedTotals[current.activity] ?? 0) + dur;
  }

  print('Fixed Logic Total: $fixedSum hours (Expected 1.0)');
  print('Fixed Totals: $fixedTotals (Expected Work: 0.5, Break: 0.5)');
}
