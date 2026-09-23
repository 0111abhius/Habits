import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:habit_logger/models/daily_score.dart';
import 'package:habit_logger/services/smart_coach_service.dart';

DailyScore _score({
  required int total,
  int planning = 0,
  int retro = 0,
  DateTime? date,
}) {
  return DailyScore(
    userId: 'u',
    date: date ?? DateTime(2024, 6, 1),
    totalScore: total,
    breakdown: {'planning': planning, 'retro': retro},
    computedAt: DateTime(2024, 6, 1, 22),
  );
}

Map<String, dynamic> _logDoc(String date, {DailyScore? score}) {
  return {
    'date': date,
    'complete': true,
    if (score != null) 'scoreDetails': score.toMap(),
  };
}

void main() {
  final service = SmartCoachService();

  group('parseScores', () {
    test('unwraps nested scoreDetails and skips unscored days', () {
      final scores = SmartCoachService.parseScores([
        _logDoc('2024-06-01', score: _score(total: 80, planning: 20)),
        _logDoc('2024-06-02'),
        {'scoreDetails': 'garbage'},
        _logDoc('2024-06-03', score: _score(total: 40)),
      ]);
      expect(scores.length, 2);
      expect(scores.first.totalScore, 80);
      expect(scores.first.breakdown['planning'], 20);
      expect(scores.last.totalScore, 40);
    });

    test('DailyScore.fromMap tolerates num values and string dates', () {
      final s = DailyScore.fromMap({
        'date': '2024-06-05',
        'totalScore': 72.0,
        'breakdown': {'planning': 15.0, 'retro': 5},
      });
      expect(s.date, DateTime(2024, 6, 5));
      expect(s.totalScore, 72);
      expect(s.breakdown, {'planning': 15, 'retro': 5});
    });
  });

  group('analyzeScores', () {
    test('returns null with fewer than 5 scored days', () {
      final few = List.generate(4, (i) => _score(total: 50 + i * 10, planning: i.isEven ? 20 : 0));
      expect(service.analyzeScores(few), isNull);
    });

    test('returns null when planning/retro make no difference', () {
      final flat = List.generate(8, (i) => _score(total: 60, planning: i.isEven ? 20 : 0, retro: i % 3 == 0 ? 20 : 0));
      expect(service.analyzeScores(flat), isNull);
    });

    test('detects planning impact', () {
      final scores = [
        ...List.generate(4, (_) => _score(total: 85, planning: 20)),
        ...List.generate(4, (_) => _score(total: 50, planning: 0)),
      ];
      final insight = service.analyzeScores(scores);
      expect(insight, isNotNull);
      expect(insight!.type, InsightType.planning);
      expect(insight.message, contains('35 more points'));
    });

    test('detects retro impact', () {
      final scores = [
        ...List.generate(3, (_) => _score(total: 90, retro: 20)),
        ...List.generate(3, (_) => _score(total: 60, retro: 0)),
      ];
      final insight = service.analyzeScores(scores);
      expect(insight, isNotNull);
      expect(insight!.type, InsightType.retro);
      expect(insight.message, contains('30 points higher'));
    });
  });

  group('generateInsight', () {
    test('queries by string date and reads nested scoreDetails', () async {
      final db = FakeFirebaseFirestore();
      final logs = db.collection('daily_logs').doc('u1').collection('logs');
      final today = DateTime.now();
      for (int i = 0; i < 8; i++) {
        final d = today.subtract(Duration(days: i + 1));
        final key = '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
        final planned = i.isEven;
        await logs.doc(key).set(_logDoc(
              key,
              score: _score(total: planned ? 90 : 50, planning: planned ? 20 : 0, date: d),
            ));
      }
      // Old entry outside the 30 day window should be ignored.
      await logs.doc('2000-01-01').set(_logDoc('2000-01-01', score: _score(total: 0, planning: 20)));

      final insight = await service.generateInsight('u1', firestore: db);
      expect(insight, isNotNull);
      expect(insight!.type, InsightType.planning);
    });

    test('falls back to general motivation when there is no data', () async {
      final db = FakeFirebaseFirestore();
      final insight = await service.generateInsight('nobody', firestore: db);
      expect(insight, isNotNull);
      expect(insight!.type, InsightType.general);
      expect(insight.message, isNotEmpty);
    });
  });
}
