import 'package:integration_test/integration_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:habit_logger/main.dart';
import 'package:habit_logger/screens/login_screen.dart';
import 'package:habit_logger/screens/habits_screen.dart';
import 'package:habit_logger/widgets/habit_tracker.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:habit_logger/models/habit.dart';
import 'package:intl/intl.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setupFirebaseCoreMocks();
  setupFirebaseAuthMocks();

  group('End-to-end user flows', () {
    late MockFirebaseAuth auth;
    late FakeFirebaseFirestore firestore;

    setUp(() async {
      await Firebase.initializeApp();
      firestore = FakeFirebaseFirestore();
      overrideFirestoreForTests(firestore);

      auth = MockFirebaseAuth(signedIn: false);
      // Platform registration handled by firebase_auth_mocks.
    });

    testWidgets('Full sign-in → add habit → mark done → sign-out', (tester) async {
      await tester.pumpWidget(const MyApp());
      await tester.pumpAndSettle();

      // 1) We should start on LoginScreen.
      expect(find.byType(LoginScreen), findsOneWidget);

      // Fill email/password and sign-in.
      await tester.enterText(find.byType(TextFormField).at(0), 'u@e.com');
      await tester.enterText(find.byType(TextFormField).at(1), '123456');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Sign In'));
      await tester.pumpAndSettle();

      // The mock auth registers a new MockUser automatically; after sign-in we should land on Timeline (via AuthGate).
      expect(find.text('Timeline'), findsOneWidget);

      // 2) Open popup menu → Habits screen.
      // The PopupMenuButton has tooltip 'Customize'; tap it then select 'Habits'.
      await tester.tap(find.byTooltip('Customize'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Habits'));
      await tester.pumpAndSettle();

      expect(find.byType(HabitsScreen), findsOneWidget);

      // Add new habit.
      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();
      const habitName = 'Meditate';
      await tester.enterText(find.byType(TextFormField).first, habitName);
      await tester.tap(find.widgetWithText(ElevatedButton, 'Add'));
      await tester.pumpAndSettle();

      // Habit appears in list.
      expect(find.text(habitName), findsOneWidget);

      // Back to Timeline.
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Timeline'), findsOneWidget);

      // 3) HabitTracker should show our new habit.
      await tester.pumpAndSettle(const Duration(seconds: 1)); // wait for StreamBuilder
      expect(find.text(habitName), findsOneWidget);

      // Tap checkbox to mark done (binary default).
      await tester.tap(find.byType(Checkbox).first);
      await tester.pumpAndSettle();

      // Verify Firestore log written.
      final dateId = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final habitDoc = await firestore
          .collection('habit_logs')
          .doc(auth.currentUser!.uid)
          .collection('dates')
          .doc(dateId)
          .collection('habits')
          .doc(/* habit id unknown; query any */)
          .get();
      expect(habitDoc.exists, true);

      // 4) Sign-out via popup menu.
      await tester.tap(find.byTooltip('Customize'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sign out'));
      await tester.pumpAndSettle();

      // Back to Login.
      expect(find.byType(LoginScreen), findsOneWidget);
    });
  });
}