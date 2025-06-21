import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:habit_logger/main.dart';
import 'package:habit_logger/widgets/auth_gate.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupFirebaseCoreMocks();

  group('Platform UI smoke tests', () {
    for (final entry in {
      'Android': TargetPlatform.android,
      'iOS': TargetPlatform.iOS,
    }.entries) {
      testWidgets('MyApp builds on ${entry.key}', (tester) async {
        debugDefaultTargetPlatformOverride = entry.value;

        // Init firebase once
        await Firebase.initializeApp();
        // Signed-in mock so AuthGate shows Timeline instead of Login
        final mockUser = MockUser(uid: 'uid');
        final auth = MockFirebaseAuth(mockUser: mockUser);
        await auth.signInWithCustomToken('token');

        await tester.pumpWidget(const MyApp());
        await tester.pumpAndSettle();

        expect(find.byType(AuthGate), findsOneWidget);

        debugDefaultTargetPlatformOverride = null;
      });
    }
  });
}