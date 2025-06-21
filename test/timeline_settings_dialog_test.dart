import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:habit_logger/main.dart';
import 'package:habit_logger/screens/timeline_screen.dart';
import 'helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Timeline settings dialogs', () {
    late FakeFirebaseFirestore firestore;

    setUp(() async {
      await Firebase.initializeApp();
      firestore = FakeFirebaseFirestore();
      overrideFirestoreForTests(firestore);

      // Signed-in mock so TimelineScreen renders fully.
      final user = MockUser(uid: 'test_uid', email: 'test@example.com');
      final auth = MockFirebaseAuth(mockUser: user);
      await auth.signInWithCustomToken('token');
    });

    Future<void> _openCustomizeMenu(WidgetTester tester) async {
      await tester.tap(find.byTooltip('Customize'));
      await tester.pumpAndSettle();
    }

    testWidgets('Adding custom activity is saved to Firestore', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: TimelineScreen()));
      await tester.pumpAndSettle();

      await _openCustomizeMenu(tester);
      await tester.tap(find.text('Activities'));
      await tester.pumpAndSettle();

      // Add custom activity
      const custom = 'Chess';
      await tester.enterText(find.byType(TextField).first, custom);
      await tester.tap(find.byIcon(Icons.add).first);
      await tester.pumpAndSettle();

      // Should appear in dialog list
      expect(find.text(custom), findsWidgets);

      // Close dialog
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();

      // Verify Firestore persistence
      final snap = await firestore.collection('user_settings').doc('test_uid').get();
      final List<String> customActs = List<String>.from(snap.data()?['customActivities'] ?? []);
      expect(customActs.contains(custom), isTrue);
    });

    testWidgets('Sleep time change persists to Firestore', (tester) async {
      // Seed Firestore with default settings so dialog shows times
      await firestore.collection('user_settings').doc('test_uid').set({
        'sleepTime': '23:00',
        'wakeTime': '07:00',
      });

      await tester.pumpWidget(const MaterialApp(home: TimelineScreen()));
      await tester.pumpAndSettle();

      await _openCustomizeMenu(tester);
      // select Sleep timings menu item (value "sleep")
      await tester.tap(find.text('Sleep timings'));
      await tester.pumpAndSettle();

      // Tap the Sleep Time TextButton to open time-picker
      await tester.tap(find.widgetWithText(TextButton, '23:00'));
      await tester.pumpAndSettle();

      // The native TimePicker dialog appears; simulate selecting 10:00PM by tapping OK.
      // Use tester.tap on OK button directly, skipping dial interactions.
      if (find.text('OK').evaluate().isNotEmpty) {
        await tester.tap(find.text('OK'));
        await tester.pumpAndSettle();
      } else {
        // On some platforms label is done.
        await tester.tap(find.textContaining('OK'));
        await tester.pumpAndSettle();
      }

      // Close dialog
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();

      // Verify change persisted (sleepTime updated, not default)
      final snap = await firestore.collection('user_settings').doc('test_uid').get();
      expect(snap.exists, isTrue);
      expect(snap.data()!['sleepTime'] != '23:00', isTrue);
    });
  });
}